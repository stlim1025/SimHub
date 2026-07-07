using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Infrastructure.Configuration;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;

namespace SimCenter.Agent.Tray;

/// <summary>
/// 게임 연결 상태 창. <see cref="GameConnectionMonitor"/>를 DispatcherTimer로 폴링해 신호등·지표를 갱신한다.
/// 닫기는 트레이 최소화(<see cref="AllowExit"/>가 true일 때만 실제 종료).
/// </summary>
public partial class MainWindow : Window
{
    private static readonly Brush RedBrush = Freeze(0xDC, 0x35, 0x45);
    private static readonly Brush AmberBrush = Freeze(0xFF, 0xC1, 0x07);
    private static readonly Brush GreenBrush = Freeze(0x28, 0xA7, 0x45);

    private readonly GameConnectionMonitor _monitor;
    private readonly AgentOptions _options;
    private readonly DispatcherTimer _timer;

    /// <summary>트레이 "종료"에서만 true로 세팅 → 실제 창 종료 허용.</summary>
    public bool AllowExit { get; set; }

    public MainWindow(GameConnectionMonitor monitor, AgentOptions options)
    {
        _monitor = monitor;
        _options = options;
        InitializeComponent();

        PortValue.Text = _options.UdpPort.ToString();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
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
        base.OnClosing(e);
    }

    private static Brush Freeze(byte r, byte g, byte b)
    {
        var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
        brush.Freeze();
        return brush;
    }
}
