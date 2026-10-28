using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Application.Setups;
using SimCenter.Application.Setups.Refresh;
using SimCenter.Domain.Constants;

namespace SimCenter.Infrastructure.Setups;

/// <summary>
/// F1Laps 공개 셋업 페이지 읽기(<see cref="ISetupSource"/>). 로그인 없이 공개 페이지만 GET하고, 두 번째 요청부터 매번
/// <see cref="CommunitySetupOptions.RequestDelay"/>만큼 쉰다. HTTP 오류는 예외(<see cref="HttpRequestException"/>), 구조 변경은
/// <see cref="F1LapsPageException"/>으로 알린다. 출처 밖 주소는 요청하지 않는다.
/// </summary>
public sealed class F1LapsSetupScraper : ISetupSource
{
    private const string WetSegment = "wet/";

    /// <summary>세션 종류 → 출처 순위표의 `session` 필터 값.</summary>
    private static readonly IReadOnlyDictionary<string, string> SessionCodes = new Dictionary<string, string>
    {
        [SetupSessions.TimeTrial] = "6",
        [SetupSessions.Race] = "5",
        [SetupSessions.Qualifying] = "4",
    };

    private readonly HttpClient _http;
    private readonly CommunitySetupOptions _options;
    private readonly ILogger<F1LapsSetupScraper> _logger;
    private readonly Uri _baseUri;
    private bool _hasRequested;

    public F1LapsSetupScraper(HttpClient http, IOptions<CommunitySetupOptions> options, ILogger<F1LapsSetupScraper> logger)
    {
        _http = http;
        _options = options.Value;
        _logger = logger;
        _baseUri = new Uri(_options.BaseUrl, UriKind.Absolute);
    }

    public async Task<IReadOnlyList<SetupTrackLink>> GetTracksAsync(string gameCode, CancellationToken cancellationToken = default)
    {
        var gamePath = GamePath(gameCode);
        var html = await GetAsync(new Uri(_baseUri, $"{gamePath}/setups/"), cancellationToken);
        return F1LapsHtmlParser.ParseTrackIndex(html, gamePath);
    }

    public async Task<IReadOnlyList<SetupListRow>> GetRankingAsync(
        string gameCode, string slug, string condition, string sessionType, CancellationToken cancellationToken = default)
    {
        var path = $"{GamePath(gameCode)}/setups/{Uri.EscapeDataString(slug)}/";
        if (condition == SetupConditions.Wet)
        {
            path += WetSegment;
        }

        // 순위표의 세션 필터(`?session=`, 출처 값: 타임 트라이얼 6·레이스 5·퀄리파잉 4). 고르지 않으면 출처는 타임 트라이얼을 보인다.
        var session = SessionCodes.TryGetValue(sessionType, out var code)
            ? code
            : throw new ArgumentException($"셋업 출처가 지원하지 않는 세션 종류입니다: {sessionType}", nameof(sessionType));
        var html = await GetAsync(new Uri(_baseUri, $"{path}?session={session}"), cancellationToken);
        return F1LapsHtmlParser.ParseRanking(html, _baseUri);
    }

    public async Task<SetupDetail> GetDetailAsync(string sourceUrl, CancellationToken cancellationToken = default)
    {
        var uri = new Uri(sourceUrl, UriKind.Absolute);
        if (!string.Equals(uri.Host, _baseUri.Host, StringComparison.OrdinalIgnoreCase) || uri.Scheme != _baseUri.Scheme)
        {
            throw new InvalidOperationException($"셋업 출처 밖의 주소입니다: {uri.Host}");
        }

        var html = await GetAsync(uri, cancellationToken);
        return F1LapsHtmlParser.ParseDetail(html);
    }

    private static string GamePath(string gameCode)
        => F1LapsTrackSlugs.GamePath(gameCode)
            ?? throw new ArgumentException($"셋업 출처가 지원하지 않는 게임입니다: {gameCode}", nameof(gameCode));

    private async Task<string> GetAsync(Uri uri, CancellationToken cancellationToken)
    {
        if (_hasRequested && _options.RequestDelay > TimeSpan.Zero)
        {
            await Task.Delay(_options.RequestDelay, cancellationToken);
        }

        _hasRequested = true;
        _logger.LogDebug("Fetching community setup page {Url}", uri);

        using var response = await _http.GetAsync(uri, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }
}
