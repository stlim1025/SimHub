namespace SimCenter.Agent.Infrastructure.Configuration;

/// <summary>
/// <see cref="AgentOptions.ServerBaseUrl"/>에서 서버 주소를 만든다(docs/11 §6.1). 기본 주소 끝의 <c>/</c> 유무와 무관하다.
/// </summary>
public static class AgentEndpoints
{
    private const string PairPath = "api/v1/agent/pair";
    private const string TelemetryHubPath = "hubs/telemetry";

    /// <summary>계정 연결 API: <c>{ServerBaseUrl}/api/v1/agent/pair</c>.</summary>
    /// <exception cref="ArgumentException">http(s) 절대 URL이 아닐 때.</exception>
    public static Uri PairUri(string serverBaseUrl) => Combine(serverBaseUrl, PairPath);

    /// <summary>텔레메트리 허브: <c>{ServerBaseUrl}/hubs/telemetry</c>.</summary>
    /// <exception cref="ArgumentException">http(s) 절대 URL이 아닐 때.</exception>
    public static Uri TelemetryHubUri(string serverBaseUrl) => Combine(serverBaseUrl, TelemetryHubPath);

    private static Uri Combine(string serverBaseUrl, string relativePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(serverBaseUrl);

        // 끝에 '/'를 붙여야 상대 경로가 기본 경로(예: /simcenter) 아래로 붙는다.
        var normalized = serverBaseUrl.Trim().TrimEnd('/') + "/";
        if (!Uri.TryCreate(normalized, UriKind.Absolute, out var baseUri)
            || (baseUri.Scheme != Uri.UriSchemeHttp && baseUri.Scheme != Uri.UriSchemeHttps))
        {
            throw new ArgumentException("ServerBaseUrl은 http 또는 https 절대 URL이어야 합니다.", nameof(serverBaseUrl));
        }

        return new Uri(baseUri, relativePath);
    }
}
