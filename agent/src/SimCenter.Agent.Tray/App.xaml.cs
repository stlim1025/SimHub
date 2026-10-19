using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Serilog;
using SimCenter.Agent.Core.Connection;
using SimCenter.Agent.Infrastructure;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Credentials;
using SimCenter.Agent.Infrastructure.Hosting;
using SimCenter.Agent.Infrastructure.Pairing;
using SimCenter.Agent.Infrastructure.Upload;
using Application = System.Windows.Application;

namespace SimCenter.Agent.Tray;

/// <summary>
/// Tray 앱 진입점. Cli와 동일한 Generic Host를 조립해 텔레메트리 파이프라인을 백그라운드로 돌리고,
/// 트레이 아이콘(신호등)으로 게임 연결 상태를 노출한다. 닫기 = 트레이 최소화, 종료 = 트레이 메뉴.
/// </summary>
public partial class App : Application
{
    /// <summary>트레이 툴팁·창 제목에 보이는 이름(웹 서비스 이름 SimHub와 맞춘다).</summary>
    internal const string DisplayName = "SimHub Agent";

    /// <summary>csproj의 EmbeddedResource LogicalName.</summary>
    private const string LogoResourceName = "SimCenter.Agent.Tray.simhub.ico";

    private const int WindowIconSize = 32;

    /// <summary>트레이 아이콘 한 변 대비 상태 점 지름·테두리 두께 비율.</summary>
    private const double StatusDotRatio = 0.5;
    private const double StatusRingRatio = 0.08;

    /// <summary>상태 점 테두리 색(앱 다크 배경 #12141C).</summary>
    private static readonly Color StatusRingColor = Color.FromArgb(18, 20, 28);

    private IHost? _host;
    private GameConnectionMonitor? _monitor;
    private System.Windows.Forms.NotifyIcon? _notifyIcon;
    private DispatcherTimer? _trayTimer;
    private MainWindow? _window;

    private readonly Dictionary<ConnectionState, Icon> _stateIcons = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var builder = Host.CreateApplicationBuilder(e.Args);

        builder.Services.AddSerilog((services, config) =>
            config.ReadFrom.Configuration(builder.Configuration)
                .Enrich.FromLogContext()
                .WriteTo.Console());

        builder.Services.AddAgentInfrastructure(builder.Configuration);
        builder.Services.AddHostedService<TelemetryHostedService>();

        _host = builder.Build();
        _host.Start();

        _monitor = _host.Services.GetRequiredService<GameConnectionMonitor>();
        var options = _host.Services.GetRequiredService<IOptions<AgentOptions>>().Value;

        BuildStateIcons();
        BuildNotifyIcon();

        _window = new MainWindow(
            _monitor,
            options,
            _host.Services.GetRequiredService<IAgentPairingClient>(),
            _host.Services.GetRequiredService<IDeviceCredentialStore>(),
            _host.Services.GetRequiredService<UploadStatusTracker>());
        _window.Icon = CreateWindowIcon();
        _window.Show();

        // 트레이 아이콘/툴팁은 창보다 느리게(1s) 갱신해도 충분.
        _trayTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _trayTimer.Tick += (_, _) => UpdateTrayIndicator();
        _trayTimer.Start();
        UpdateTrayIndicator();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayTimer?.Stop();

        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
        }

        foreach (var icon in _stateIcons.Values)
        {
            icon.Dispose();
        }

        if (_host is not null)
        {
            _host.StopAsync(TimeSpan.FromSeconds(3)).GetAwaiter().GetResult();
            _host.Dispose();
        }

        Log.CloseAndFlush();
        base.OnExit(e);
    }

    private void BuildNotifyIcon()
    {
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("열기", null, (_, _) => ShowWindow());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("종료", null, (_, _) => ExitApp());

        _notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = _stateIcons[ConnectionState.Disconnected],
            Visible = true,
            Text = DisplayName,
            ContextMenuStrip = menu,
        };
        _notifyIcon.DoubleClick += (_, _) => ShowWindow();
    }

    private void UpdateTrayIndicator()
    {
        if (_monitor is null || _notifyIcon is null)
        {
            return;
        }

        var state = _monitor.GetSnapshot().State;
        _notifyIcon.Icon = _stateIcons[state];
        _notifyIcon.Text = $"{DisplayName} — {ConnectionStatusText.Describe(state)}";
    }

    private void ShowWindow()
    {
        if (_window is null)
        {
            return;
        }

        _window.Show();
        _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private void ExitApp()
    {
        if (_window is not null)
        {
            _window.AllowExit = true;
        }

        Shutdown();
    }

    private void BuildStateIcons()
    {
        // 시스템 작은 아이콘 크기(배율 100% = 16px, 150% = 24px …)에 맞춰 그려야 트레이에서 흐려지지 않는다.
        var size = System.Windows.Forms.SystemInformation.SmallIconSize;
        using var logo = LoadLogoIcon(size);

        _stateIcons[ConnectionState.Disconnected] = CreateStatusIcon(logo, Color.FromArgb(220, 53, 69), size);  // 🔴
        _stateIcons[ConnectionState.Waiting] = CreateStatusIcon(logo, Color.FromArgb(255, 193, 7), size);       // 🟡
        _stateIcons[ConnectionState.Connected] = CreateStatusIcon(logo, Color.FromArgb(40, 167, 69), size);     // 🟢
    }

    /// <summary>내장 리소스의 SimHub 로고(.ico)에서 <paramref name="size"/>에 가장 가까운 이미지를 읽는다.</summary>
    private static Icon LoadLogoIcon(System.Drawing.Size size)
    {
        using var stream = typeof(App).Assembly.GetManifestResourceStream(LogoResourceName)
            ?? throw new InvalidOperationException($"Embedded resource not found: {LogoResourceName}");
        return new Icon(stream, size);
    }

    /// <summary>창 제목 표시줄·작업 표시줄용 로고(WPF 이미지). exe 아이콘에 기대지 않고 명시한다.</summary>
    private static System.Windows.Media.ImageSource CreateWindowIcon()
    {
        using var logo = LoadLogoIcon(new System.Drawing.Size(WindowIconSize, WindowIconSize));
        return System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
            logo.Handle, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions());
    }

    /// <summary>로고 오른쪽 아래에 연결 상태 색 점을 겹친 트레이 아이콘을 생성한다(앱 수명 동안 재사용).</summary>
    private static Icon CreateStatusIcon(Icon logo, Color color, System.Drawing.Size size)
    {
        using var bmp = new Bitmap(size.Width, size.Height);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.Clear(Color.Transparent);
            g.DrawIcon(logo, new Rectangle(0, 0, size.Width, size.Height));

            // 점 둘레를 로고 배경과 대비되는 어두운 테두리로 감싸 어떤 작업 표시줄 색에서도 보이게 한다.
            var dot = (int)Math.Round(size.Width * StatusDotRatio);
            var ring = Math.Max(1, (int)Math.Round(size.Width * StatusRingRatio));
            var x = size.Width - dot;
            var y = size.Height - dot;
            using var ringBrush = new SolidBrush(StatusRingColor);
            g.FillEllipse(ringBrush, x - ring, y - ring, dot + ring, dot + ring);
            using var brush = new SolidBrush(color);
            g.FillEllipse(brush, x, y, dot - 1, dot - 1);
        }

        IntPtr hIcon = bmp.GetHicon();
        try
        {
            using var tmp = Icon.FromHandle(hIcon);
            return (Icon)tmp.Clone();
        }
        finally
        {
            DestroyIcon(hIcon);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
