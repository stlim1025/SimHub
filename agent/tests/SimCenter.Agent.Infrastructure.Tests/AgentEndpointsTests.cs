using SimCenter.Agent.Infrastructure.Configuration;

namespace SimCenter.Agent.Infrastructure.Tests;

public class AgentEndpointsTests
{
    [Theory]
    [InlineData("http://localhost:5284")]
    [InlineData("http://localhost:5284/")]
    public void AgentEndpoints_BuildPairAndHubUris(string baseUrl)
    {
        Assert.Equal(new Uri("http://localhost:5284/api/v1/agent/pair"), AgentEndpoints.PairUri(baseUrl));
        Assert.Equal(new Uri("http://localhost:5284/hubs/telemetry"), AgentEndpoints.TelemetryHubUri(baseUrl));
    }

    [Fact]
    public void AgentEndpoints_KeepBasePath()
    {
        Assert.Equal(
            new Uri("https://example.com/simcenter/hubs/telemetry"),
            AgentEndpoints.TelemetryHubUri("https://example.com/simcenter"));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("localhost:5284")]
    [InlineData("ftp://localhost:5284")]
    [InlineData("not a url")]
    public void AgentEndpoints_RejectNonHttpAbsoluteUrls(string baseUrl)
    {
        Assert.ThrowsAny<ArgumentException>(() => AgentEndpoints.TelemetryHubUri(baseUrl));
    }
}
