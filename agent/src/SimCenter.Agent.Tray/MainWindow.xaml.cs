using System.ComponentModel;
using System.Reflection;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Serilog;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Pairing;
using SimCenter.Agent.Infrastructure.Upload;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace SimCenter.Agent.Tray;

/// <summary>
/// 게임 연결 상태 창. <see cref="GameConnectionMonitor"/>를 DispatcherTimer로 폴링해 신호등·지표·수신 그래프를 갱신한다.
/// 닫기는 트레이 최소화(<see cref="AllowExit"/>가 true일 때만 실제 종료).
/// "계정 연결" 영역은 연결 코드 입력·이 PC 연결 끊기와 업로드 상태 표시를 맡는다(docs/11 §6.3).
/// </summary>
public partial class MainWindow : Window
{
    private static readonly Brush RedBrush = Freeze(0xDC, 0x35, 0x45);
    private static readonly Brush AmberBrush = Freeze(0xFF, 0xC1, 0x07);
    private static readonly Brush GreenBrush = Freeze(0x28, 0xA7, 0x45);

    private const double IntervalMs = 500;
    private const int Capacity = 120;          // 500ms × 120 ≈ 최근 60초
    private const double MinScale = 10;        // Y축 최소 상한(pkt/s) — 저트래픽에서도 바닥에 붙게

    private static readonly string DeviceName = Environment.MachineName;

    private readonly GameConnectionMonitor _monitor;
    private readonly AgentOptions _options;
    private readonly IAgentPairingClient _pairingClient;
    private readonly IDeviceCredentialStore _credentials;
    private readonly UploadStatusTracker _uploadStatus;
    private readonly GameEditionDetector _edition;
    private readonly DispatcherTimer _timer;
    private readonly CancellationTokenSource _lifetime = new();

    private readonly List<double> _rates = new(Capacity);
    private long _lastTotal;
    private bool _hasLastTotal;
    private bool _isPairing;

    /// <summary>트레이 "종료"에서만 true로 세팅 → 실제 창 종료 허용.</summary>
    public bool AllowExit { get; set; }

    public MainWindow(
        GameConnectionMonitor monitor,
        AgentOptions options,
        IAgentPairingClient pairingClient,
        IDeviceCredentialStore credentials,
        UploadStatusTracker uploadStatus,
        GameEditionDetector edition)
    {
        _monitor = monitor;
        _options = options;
        _pairingClient = pairingClient;
        _credentials = credentials;
        _uploadStatus = uploadStatus;
        _edition = edition;
        InitializeComponent();

        PortValue.Text = _options.UdpPort.ToString();
        FooterText.Text = $"창을 닫아도 트레이에서 계속 실행됩니다. · 버전 {AgentVersion()}";

        // 업로더가 아직 Disabled일 수 있으니 현재 상태를 한 번 읽어 그리고, 이후 변화는 이벤트로 받는다.
        _uploadStatus.StateChanged += OnUploadStateChanged;
        RenderAccountAreaSafely();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(IntervalMs) };
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
        Refresh();
    }

    /// <summary>
    /// 배포 스크립트(publish-agent.ps1)가 넣은 버전(InformationalVersion, 예: <c>37d2230-20261020</c>).
    /// 개발 빌드에서 SDK가 붙이는 <c>+커밋</c> 꼬리는 뗀다.
    /// </summary>
    private static string AgentVersion()
    {
        var version = typeof(MainWindow).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "?";
        var plus = version.IndexOf('+');
        return plus < 0 ? version : version[..plus];
    }

    private void Refresh()
    {
        var snapshot = _monitor.GetSnapshot();

        StatusText.Text = ConnectionStatusText.Describe(snapshot.State);
        (StatusDot.Fill, StatusHint.Text) = snapshot.State switch
        {
            ConnectionState.Connected => (GreenBrush, "실시간 텔레메트리 수신 중"),
            ConnectionState.Waiting => (AmberBrush, "게임 텔레메트리 수신을 기다리는 중…"),
            _ => (RedBrush, "게임이 실행 중인지, UDP 포트 설정을 확인하세요"),
        };

        PacketsValue.Text = snapshot.TotalDatagrams.ToString("N0");

        LastSeenValue.Text = snapshot.SecondsSinceLast is { } secs
            ? secs < 1 ? "방금" : $"{secs:F1}초 전"
            : "—";

        // 패킷 포맷 옆에 지금 세션의 게임(F1 25 / 2026 시즌팩 = F1 26)을 함께 보인다.
        PacketFormatValue.Text = snapshot.DetectedPacketFormat is { } fmt
            ? (fmt == _options.ExpectedPacketFormat ? fmt.ToString() : $"{fmt} (기대 {_options.ExpectedPacketFormat})")
              + $" · {GameEditions.DisplayName(_edition.GameCode)}"
            : "—";

        if (snapshot.ListenerError is { } error)
        {
            ErrorText.Text = error;
            ErrorBox.Visibility = Visibility.Visible;
        }
        else
        {
            ErrorBox.Visibility = Visibility.Collapsed;
        }

        UpdateRate(snapshot.TotalDatagrams);
    }

    /// <summary>누적 수신 카운트의 증분으로 초당 수신율을 계산해 롤링 버퍼에 넣고 그래프를 다시 그린다.</summary>
    private void UpdateRate(long total)
    {
        if (_hasLastTotal)
        {
            var delta = Math.Max(0, total - _lastTotal);
            var perSecond = delta * (1000.0 / IntervalMs);

            _rates.Add(perSecond);
            if (_rates.Count > Capacity)
            {
                _rates.RemoveAt(0);
            }

            RateValue.Text = Math.Round(perSecond).ToString("N0");
        }

        _lastTotal = total;
        _hasLastTotal = true;

        DrawChart();
    }

    private void DrawChart()
    {
        var width = ChartArea.ActualWidth;
        var height = ChartArea.ActualHeight;

        if (width <= 0 || height <= 0 || _rates.Count < 2)
        {
            RateLine.Points = null;
            RateFill.Points = null;
            return;
        }

        var max = MinScale;
        foreach (var rate in _rates)
        {
            if (rate > max)
            {
                max = rate;
            }
        }

        max *= 1.15; // 상단 여유

        var line = new PointCollection(_rates.Count);
        var step = width / (_rates.Count - 1);
        for (var i = 0; i < _rates.Count; i++)
        {
            var x = i * step;
            var y = height - (_rates[i] / max * height);
            line.Add(new Point(x, y));
        }

        RateLine.Points = line;

        // 면적 채움: 라인 아래를 바닥까지 닫는다.
        var fill = new PointCollection(line) { new Point(width, height), new Point(0, height) };
        RateFill.Points = fill;
    }

    private void ChartArea_SizeChanged(object sender, SizeChangedEventArgs e) => DrawChart();

    /// <summary>
    /// 업로드 루프 스레드에서 동기 호출된다. 여기서 예외가 새면 업로드 BackgroundService가 죽어 에이전트 전체가 멈추므로
    /// UI는 건드리지 않고 Dispatcher에 비동기로(BeginInvoke — Invoke는 루프를 UI 스레드에 묶는다) 넘기며 예외를 모두 흡수한다.
    /// </summary>
    private void OnUploadStateChanged(object? sender, EventArgs e)
    {
        try
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(RenderAccountAreaSafely));
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "업로드 상태 변경을 UI로 전달하지 못했습니다");
        }
    }

    private void RenderAccountAreaSafely()
    {
        try
        {
            RenderAccountArea();
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "계정 연결 영역을 갱신하지 못했습니다");
        }
    }

    private void RenderAccountArea()
    {
        var hasKey = _credentials.Load() is not null;
        var state = _uploadStatus.State;

        // 업로드 루프가 키 삭제를 반영하기 전(전송 중 등)에도 방금 끊은 PC가 "연결됨"으로 남지 않게 키 유무를 함께 본다.
        if (!hasKey && UploadStateText.IsLinked(state))
        {
            state = UploadState.Unpaired;
        }

        AccountStatusText.Text = UploadStateText.Describe(state, DeviceName);

        var issues = UploadStateText.DescribeIssues(_uploadStatus.DeferredCount, _uploadStatus.DeadLetterCount);
        UploadIssueText.Text = issues ?? string.Empty;
        UploadIssueText.Visibility = issues is null ? Visibility.Collapsed : Visibility.Visible;

        PairingCodeBox.IsEnabled = !_isPairing;
        PairButton.IsEnabled = !_isPairing;
        PairButton.Content = _isPairing ? "연결 중…" : "연결";
        UnlinkButton.IsEnabled = hasKey && !_isPairing;
    }

    private void SetAccountError(string? message)
    {
        AccountErrorText.Text = message ?? string.Empty;
        AccountErrorText.Visibility = string.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
    }

    // async void: WPF 이벤트 핸들러라 예외가 새면 앱(=에이전트)이 죽는다. 그래서 모든 경로를 여기서 처리한다.
    private async void PairButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isPairing)
        {
            return;
        }

        // 연결 코드는 1회용 비밀 — 화면 입력값만 다듬고, 로그·오류 문구에는 싣지 않는다.
        var code = PairingCodeBox.Text.Trim();

        SetAccountError(null);
        _isPairing = true;
        RenderAccountAreaSafely();

        try
        {
            var outcome = await _pairingClient.PairAsync(code, DeviceName, _lifetime.Token);
            if (outcome.Succeeded)
            {
                // 키는 이미 저장됐고 Changed가 업로더를 깨운다. 상태 문구는 StateChanged가 갱신한다.
                PairingCodeBox.Clear();
            }
            else
            {
                SetAccountError(outcome.Message);
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
            // 창 종료 중 — 정상. 표시할 것이 없다.
        }
        catch (Exception ex)
        {
            Log.Error(ex, "계정 연결 중 예기치 않은 오류가 발생했습니다");
            SetAccountError("연결 중 예기치 않은 오류가 발생했습니다. 잠시 후 다시 시도하세요.");
        }
        finally
        {
            _isPairing = false;
            RenderAccountAreaSafely();
        }
    }

    private void UnlinkButton_Click(object sender, RoutedEventArgs e)
    {
        SetAccountError(null);

        try
        {
            // 로컬 키만 지운다. 서버 쪽 장치 해제는 웹에서 한다(docs/11 §6.3).
            _credentials.Clear();
        }
        catch (Exception ex)
        {
            Log.Error(ex, "장치 키를 지우지 못했습니다");
            SetAccountError("이 PC의 연결 정보를 지우지 못했습니다. 다른 프로그램이 파일을 사용 중이거나 권한이 없을 수 있습니다.");
        }

        RenderAccountAreaSafely();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!AllowExit)
        {
            // 트레이 상주: 닫기는 숨김으로 대체.
            e.Cancel = true;
            Hide();
            return;
        }

        _timer.Stop();
        _uploadStatus.StateChanged -= OnUploadStateChanged;
        _lifetime.Cancel();
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _lifetime.Dispose();
        base.OnClosed(e);
    }

    private static Brush Freeze(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
