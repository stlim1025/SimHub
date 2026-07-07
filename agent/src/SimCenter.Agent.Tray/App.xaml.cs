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
using SimCenter.Agent.Infrastructure.Hosting;
using Application = System.Windows.Application;

namespace SimCenter.Agent.Tray;

/// <summary>
/// Tray 앱 진입점. Cli와 동일한 Generic Host를 조립해 텔레메트리 파이프라인을 백그라운드로 돌리고,
/// 트레이 아이콘(신호등)으로 게임 연결 상태를 노출한다. 닫기 = 트레이 최소화, 종료 = 트레이 메뉴.
/// </summary>
public partial class App : Application
{
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

        _window = new MainWindow(_monitor, options);
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
            Text = "SimCenter Agent",
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
        _notifyIcon.Text = $"SimCenter Agent — {ConnectionStatusText.Describe(state)}";
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
        _stateIcons[ConnectionState.Disconnected] = CreateDotIcon(Color.FromArgb(220, 53, 69));  // 🔴
        _stateIcons[ConnectionState.Waiting] = CreateDotIcon(Color.FromArgb(255, 193, 7));       // 🟡
        _stateIcons[ConnectionState.Connected] = CreateDotIcon(Color.FromArgb(40, 167, 69));     // 🟢
    }

    /// <summary>상태 색상 원형 트레이 아이콘을 생성한다(앱 수명 동안 재사용).</summary>
    private static Icon CreateDotIcon(Color color)
    {
        using var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var brush = new SolidBrush(color);
            g.FillEllipse(brush, 2, 2, 12, 12);
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
