using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Infrastructure.Configuration;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace SimCenter.Agent.Tray;

/// <summary>
/// 게임 연결 상태 창. <see cref="GameConnectionMonitor"/>를 DispatcherTimer로 폴링해 신호등·지표·수신 그래프를 갱신한다.
/// 닫기는 트레이 최소화(<see cref="AllowExit"/>가 true일 때만 실제 종료).
/// </summary>
public partial class MainWindow : Window
{
    private static readonly Brush RedBrush = Freeze(0xDC, 0x35, 0x45);
    private static readonly Brush AmberBrush = Freeze(0xFF, 0xC1, 0x07);
    private static readonly Brush GreenBrush = Freeze(0x28, 0xA7, 0x45);

    private const double IntervalMs = 500;
    private const int Capacity = 120;          // 500ms × 120 ≈ 최근 60초
    private const double MinScale = 10;        // Y축 최소 상한(pkt/s) — 저트래픽에서도 바닥에 붙게

    private readonly GameConnectionMonitor _monitor;
    private readonly AgentOptions _options;
    private readonly DispatcherTimer _timer;

    private readonly List<double> _rates = new(Capacity);
    private long _lastTotal;
    private bool _hasLastTotal;

    /// <summary>트레이 "종료"에서만 true로 세팅 → 실제 창 종료 허용.</summary>
    public bool AllowExit { get; set; }

    public MainWindow(GameConnectionMonitor monitor, AgentOptions options)
    {
        _monitor = monitor;
        _options = options;
        InitializeComponent();

        PortValue.Text = _options.UdpPort.ToString();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(IntervalMs) };
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
        Refresh();
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

        PacketFormatValue.Text = snapshot.DetectedPacketFormat is { } fmt
            ? fmt == _options.ExpectedPacketFormat ? fmt.ToString() : $"{fmt} (기대 {_options.ExpectedPacketFormat})"
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
        base.OnClosing(e);
    }

    private static Brush Freeze(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
