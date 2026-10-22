using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Application.Setups.Refresh;

namespace SimCenter.Infrastructure.Setups;

/// <summary>
/// 커뮤니티 셋업 주기 갱신(호스티드 서비스). <see cref="CommunitySetupOptions.Enabled"/>가 꺼져 있으면 아무것도 하지 않는다.
/// 시작 후 <see cref="CommunitySetupOptions.StartupDelay"/> 뒤 첫 갱신, 이후 <see cref="CommunitySetupOptions.Interval"/>마다.
/// 갱신마다 새 DI 범위를 만들고, 어떤 예외도 호스트를 멈추지 않게 기록만 한다.
/// </summary>
public sealed class CommunitySetupRefreshService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly CommunitySetupOptions _options;
    private readonly ILogger<CommunitySetupRefreshService> _logger;

    public CommunitySetupRefreshService(
        IServiceScopeFactory scopeFactory,
        IOptions<CommunitySetupOptions> options,
        ILogger<CommunitySetupRefreshService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Community setup refresh is disabled");
            return;
        }

        try
        {
            await Task.Delay(_options.StartupDelay, stoppingToken);
            while (!stoppingToken.IsCancellationRequested)
            {
                await RunOnceAsync(stoppingToken);
                await Task.Delay(_options.Interval, stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // 호스트 종료.
        }
    }

    private async Task RunOnceAsync(CancellationToken stoppingToken)
    {
        try
        {
            await using var scope = _scopeFactory.CreateAsyncScope();
            var refresher = scope.ServiceProvider.GetRequiredService<ICommunitySetupRefresher>();
            var result = await refresher.RefreshAsync(_options.Games, _options.TopCount, stoppingToken);
            _logger.LogInformation(
                "Community setup refresh finished: {Replaced} groups replaced, {Failed} failed, {Details} details fetched",
                result.GroupsReplaced, result.GroupsFailed, result.DetailsFetched);
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !stoppingToken.IsCancellationRequested)
        {
            _logger.LogError(ex, "Community setup refresh failed");
        }
    }
}
