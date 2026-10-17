using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Infrastructure.Pipeline;
using SimCenter.Agent.Infrastructure.Sinks;

namespace SimCenter.Agent.Infrastructure.Tests;

public class DependencyInjectionTests
{
    // Outbox가 디스크에 파일을 만들지 않도록 메모리 DB를 쓴다(연결은 처음 쓸 때 열린다).
    private static ServiceProvider BuildProvider()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Agent:OutboxPath"] = ":memory:" })
            .Build();
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddAgentInfrastructure(configuration);
        return services.BuildServiceProvider();
    }

    [Fact]
    public async Task Analyzers_AreRegistered_AsSingletons()
    {
        await using var provider = BuildProvider();

        var analyzers = provider.GetServices<ITelemetryAnalyzer>().ToList();

        Assert.Equal(2, analyzers.Count);
        var lapAnalyzer = Assert.Single(analyzers.OfType<LapAnalyzer>());
        var tracker = Assert.Single(analyzers.OfType<SessionResultTracker>());

        // 분석기 목록의 LapAnalyzer는 직접 주입받는 LapAnalyzer와 같은 인스턴스다(상태 저장 — 둘로 갈라지면 안 된다).
        Assert.Same(provider.GetRequiredService<LapAnalyzer>(), lapAnalyzer);
        Assert.Same(provider.GetRequiredService<SessionResultTracker>(), tracker);

        // 싱글턴: 다시 풀어도 같은 인스턴스.
        var again = provider.GetServices<ITelemetryAnalyzer>().ToList();
        Assert.Same(lapAnalyzer, Assert.Single(again.OfType<LapAnalyzer>()));
        Assert.Same(tracker, Assert.Single(again.OfType<SessionResultTracker>()));
    }

    [Fact]
    public async Task Pipeline_AndOutboxSink_CanBeResolved()
    {
        await using var provider = BuildProvider();

        Assert.NotNull(provider.GetRequiredService<TelemetryPipeline>());
        Assert.IsType<OutboxTelemetrySink>(provider.GetRequiredService<ITelemetrySink>());
    }
}
