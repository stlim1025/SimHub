using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Setups;
using SimCenter.Application.Setups.Refresh;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Infrastructure.Setups;
using static SimCenter.Api.IntegrationTests.CommunitySetups.F1LapsFixtures;

namespace SimCenter.Api.IntegrationTests.CommunitySetups;

/// <summary>
/// 갱신 로직(<see cref="CommunitySetupRefresher"/> + 실제 <see cref="F1LapsSetupScraper"/>)을 가짜 HTTP 처리기·메모리 저장소로 확인한다(DB·네트워크 없음).
/// 요청 간격은 0.
/// </summary>
public sealed class CommunitySetupRefresherTests
{
    private const string Base = "https://www.f1laps.com/";
    private const int TopCount = 10;
    private const int AustraliaGameTrackId = 0;
    private const int MiamiGameTrackId = 30;

    private static readonly DateTime T0 = new(2026, 10, 22, 3, 0, 0, DateTimeKind.Utc);

    private readonly FakeHandler _http = new();
    private readonly MemorySetupRepository _repository = new();
    private readonly FakeClock _clock = new() { UtcNow = T0 };
    private readonly Track _australia = NewTrack(AustraliaGameTrackId, "Melbourne");
    private readonly Track _miami = NewTrack(MiamiGameTrackId, "Miami");

    [Fact]
    public async Task Refresh_StoresTopTenPerCondition_WithDetails()
    {
        ServeIndex();
        ServeList("australia", SetupConditions.Dry, Rows("a", 12));
        ServeList("australia", SetupConditions.Wet, Rows("w", 2));
        ServeList("miami", SetupConditions.Dry, []);
        ServeList("miami", SetupConditions.Wet, []);
        ServeDetails("a", 12);
        ServeDetails("w", 2);

        var result = await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        Assert.Equal((10, 0, 12), (result.GroupsReplaced, result.GroupsFailed, result.DetailsFetched)); // 2 트랙 × (Dry 3 + Wet 2)
        var dry = _repository.Active(_australia.Id, SetupConditions.Dry);
        Assert.Equal(Enumerable.Range(1, TopCount), dry.Select(s => s.Rank));
        Assert.Equal(Id("a", 0), dry[0].SourceId);
        Assert.Equal("Aston Martin", dry[0].TeamName);
        Assert.Equal(75_000, dry[0].LapTimeMs);
        Assert.Equal(("Wheel", new DateOnly(2025, 12, 22)), (dry[0].Steering, dry[0].SetOn));
        Assert.Equal("Aerodynamics", SetupSections.Deserialize(dry[0].Sections)[0].Title);
        Assert.All(dry, s => Assert.Equal(T0, s.FetchedAt));
        Assert.Equal(2, _repository.Active(_australia.Id, SetupConditions.Wet).Count);

        // 상위 10개 밖(11·12위)의 상세는 받지 않는다. 트랙 목록에 없는 slug(atlantis)는 건너뛴다.
        Assert.DoesNotContain(_http.Requested, u => u.Contains(Id("a", 10), StringComparison.Ordinal));
        Assert.DoesNotContain(_http.Requested, u => u.Contains("atlantis", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SecondRefresh_SkipsKnownDetails_ReranksAndSoftDeletesDropped()
    {
        ServeIndex();
        ServeList("australia", SetupConditions.Dry, Rows("a", 3));
        ServeList("australia", SetupConditions.Wet, []);
        ServeList("miami", SetupConditions.Dry, []);
        ServeList("miami", SetupConditions.Wet, []);
        ServeDetails("a", 4);
        await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);
        var firstIds = _repository.Active(_australia.Id, SetupConditions.Dry).ToDictionary(s => s.SourceId, s => s.Id);

        // 다음 날: a2가 1위, a0이 2위, a1은 빠지고 a3이 새로 들어온다.
        _clock.UtcNow = T0.AddDays(1);
        _http.Requested.Clear();
        ServeList("australia", SetupConditions.Dry,
        [
            Row("a", 2, rank: 1, lap: "1:14.900"),
            Row("a", 0, rank: 2),
            Row("a", 3, rank: 3),
        ]);
        var result = await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        Assert.Equal(1, result.DetailsFetched);
        Assert.Single(_http.Requested, u => u.Contains(Id("a", 3), StringComparison.Ordinal));
        Assert.DoesNotContain(_http.Requested, u => u.Contains(Id("a", 0), StringComparison.Ordinal));

        var dry = _repository.Active(_australia.Id, SetupConditions.Dry);
        Assert.Equal([Id("a", 2), Id("a", 0), Id("a", 3)], dry.Select(s => s.SourceId));
        Assert.Equal(74_900, dry[0].LapTimeMs);
        Assert.Equal(firstIds[Id("a", 2)], dry[0].Id); // 같은 SourceId는 같은 행
        Assert.Equal("Aerodynamics", SetupSections.Deserialize(dry[0].Sections)[0].Title); // 저장된 상세 유지
        Assert.All(dry, s => Assert.Equal(T0.AddDays(1), s.FetchedAt));
        Assert.True(_repository.All.Single(s => s.SourceId == Id("a", 1)).IsDeleted);
    }

    [Fact]
    public async Task FailedListOrDetail_KeepsPreviousData()
    {
        ServeIndex();
        ServeList("australia", SetupConditions.Dry, Rows("a", 2));
        ServeList("australia", SetupConditions.Wet, Rows("w", 1));
        ServeList("miami", SetupConditions.Dry, []);
        ServeList("miami", SetupConditions.Wet, []);
        ServeDetails("a", 3);
        ServeDetails("w", 1);
        await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        // Dry: 목록이 500. Wet: 새 셋업의 상세가 404. Miami Dry: 표가 없는 페이지(구조 변경).
        _clock.UtcNow = T0.AddDays(1);
        _http.Fail(ListUrl("australia", SetupConditions.Dry), HttpStatusCode.InternalServerError);
        ServeList("australia", SetupConditions.Wet, [Row("w", 5, rank: 1)]);
        _http.Fail(DetailUrl("australia", Id("w", 5)), HttpStatusCode.NotFound);
        _http.Serve(ListUrl("miami", SetupConditions.Dry), NoTablePage);

        var result = await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        Assert.Equal((7, 3), (result.GroupsReplaced, result.GroupsFailed));
        Assert.Equal([Id("a", 0), Id("a", 1)], _repository.Active(_australia.Id, SetupConditions.Dry).Select(s => s.SourceId));
        var wet = Assert.Single(_repository.Active(_australia.Id, SetupConditions.Wet));
        Assert.Equal((Id("w", 0), T0), (wet.SourceId, wet.FetchedAt));
    }

    [Fact]
    public async Task Sessions_AreStoredAsSeparateGroups_FromTheSessionFilteredRankings()
    {
        ServeIndex();
        ServeList("australia", SetupConditions.Dry, Rows("a", 2), SetupSessions.TimeTrial);
        ServeList("australia", SetupConditions.Dry, Rows("w", 1), SetupSessions.Race);
        ServeDetails("a", 2);
        ServeDetails("w", 1);

        await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        Assert.Equal([Id("a", 0), Id("a", 1)],
            _repository.Active(_australia.Id, SetupConditions.Dry, SetupSessions.TimeTrial).Select(s => s.SourceId));
        var race = Assert.Single(_repository.Active(_australia.Id, SetupConditions.Dry, SetupSessions.Race));
        Assert.Equal((Id("w", 0), SetupSessions.Race, 1), (race.SourceId, race.SessionType, race.Rank));
        Assert.Empty(_repository.Active(_australia.Id, SetupConditions.Dry, SetupSessions.Qualifying));
        Assert.Contains($"{Base}f1-25/setups/australia/?session=5", _http.Requested);
        Assert.DoesNotContain(_http.Requested, u => u.Contains("wet/?session=6", StringComparison.Ordinal)); // 젖은 노면엔 타임 트라이얼 없음
    }

    [Fact]
    public async Task IndexFailure_ChangesNothing_AndDoesNotThrow()
    {
        _http.Fail($"{Base}f1-25/setups/", HttpStatusCode.ServiceUnavailable);

        var result = await Refresher().RefreshAsync([GameCodes.F1_25], TopCount);

        Assert.Equal((0, 1), (result.GroupsReplaced, result.GroupsFailed));
        Assert.Empty(_repository.All);
    }

    [Fact]
    public async Task Cancellation_Propagates()
    {
        ServeIndex();
        using var cts = new CancellationTokenSource();
        await cts.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Refresher().RefreshAsync([GameCodes.F1_25], TopCount, cts.Token));
    }

    private CommunitySetupRefresher Refresher()
    {
        var options = Options.Create(new CommunitySetupOptions { RequestDelay = TimeSpan.Zero, BaseUrl = Base });
        var scraper = new F1LapsSetupScraper(new HttpClient(_http), options, NullLogger<F1LapsSetupScraper>.Instance);
        return new CommunitySetupRefresher(
            scraper, _repository, new MemoryTrackRepository([_australia, _miami]), new GuidIds(), _clock,
            NullLogger<CommunitySetupRefresher>.Instance);
    }

    private static Track NewTrack(int gameTrackId, string name) => new()
    {
        Id = Guid.NewGuid(),
        GameCode = GameCodes.F1_25,
        GameTrackId = gameTrackId,
        Name = name,
        DisplayOrder = gameTrackId + 1,
    };

    /// <summary>트랙 목록과, 모든 트랙 × 조건 × 세션 종류의 빈 순위표(테스트가 필요한 묶음만 덮어쓴다).</summary>
    private void ServeIndex()
    {
        _http.Serve($"{Base}f1-25/setups/", Index25);
        foreach (var slug in new[] { "australia", "miami" })
        {
            foreach (var condition in SetupConditions.All)
            {
                foreach (var session in SetupSessions.For(condition))
                {
                    ServeList(slug, condition, [], session);
                }
            }
        }
    }

    private void ServeList(string slug, string condition, IEnumerable<ListRow> rows, string? session = null)
        => _http.Serve(ListUrl(slug, condition, session), ListPage(slug, rows));

    private void ServeDetails(string prefix, int count)
    {
        for (var i = 0; i < count; i++)
        {
            _http.Serve(DetailUrl("australia", Id(prefix, i)), DetailPage(
                "F1 25 Australia Setup (Dry)", $"user {prefix}{i}", "Aston Martin", "Time Trial", "1:15.000",
                prefix == "w" ? "Wet" : "Dry", "Wheel", "Dec. 22, 2025", DrySections));
        }
    }

    /// <summary>순위표 주소: 조건(젖은 노면은 `wet/`) + 세션 필터(타임 트라이얼 6·레이스 5·퀄리파잉 4, 생략하면 조건의 기본 세션 종류).</summary>
    private static string ListUrl(string slug, string condition, string? session = null)
    {
        var code = (session ?? SetupSessions.DefaultFor(condition)) switch
        {
            SetupSessions.TimeTrial => "6",
            SetupSessions.Race => "5",
            _ => "4",
        };
        return $"{Base}f1-25/setups/{slug}/" + (condition == SetupConditions.Wet ? "wet/" : string.Empty) + $"?session={code}";
    }

    private static string DetailUrl(string slug, string id) => $"{Base}f1-25/setups/{slug}/{id}/";

    private static IEnumerable<ListRow> Rows(string prefix, int count)
        => Enumerable.Range(0, count).Select(i => Row(prefix, i, rank: i + 1));

    private static ListRow Row(string prefix, int index, int rank, string? lap = null)
        => new(rank.ToString(System.Globalization.CultureInfo.InvariantCulture), Id(prefix, index), $"user {prefix}{index}",
            "Aston Martin", "Time Trial", lap ?? $"1:{15 + index:00}.000");

    /// <summary>결정적 UUID(접두사 a/w + 번호).</summary>
    private static string Id(string prefix, int index)
        => $"{(prefix == "a" ? "aaaaaaaa" : "eeeeeeee")}-0000-4000-8000-{index:000000000000}";

    private sealed class FakeHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, (HttpStatusCode Status, string Body)> _responses = new(StringComparer.Ordinal);

        public List<string> Requested { get; } = [];

        public void Serve(string url, string html) => _responses[url] = (HttpStatusCode.OK, html);

        public void Fail(string url, HttpStatusCode status) => _responses[url] = (status, string.Empty);

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var url = request.RequestUri!.ToString();
            Requested.Add(url);
            var (status, body) = _responses.TryGetValue(url, out var response) ? response : (HttpStatusCode.NotFound, string.Empty);
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }
    }

    private sealed class FakeClock : IClock
    {
        public DateTime UtcNow { get; set; }
    }

    private sealed class GuidIds : IIdGenerator
    {
        public Guid NewId() => Guid.NewGuid();
    }

    private sealed class MemoryTrackRepository(IReadOnlyList<Track> tracks) : ITrackRepository
    {
        public Task<Track?> GetByGameTrackIdAsync(string gameCode, int gameTrackId, CancellationToken cancellationToken = default)
            => Task.FromResult(tracks.FirstOrDefault(t => t.GameCode == gameCode && t.GameTrackId == gameTrackId));

        public Task<Track?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
            => Task.FromResult(tracks.FirstOrDefault(t => t.Id == id));

        public Task<IReadOnlyList<Track>> GetAllAsync(CancellationToken cancellationToken = default) => Task.FromResult(tracks);
    }

    /// <summary>실제 리포지토리와 같은 규칙의 메모리 저장소(SourceId별 덮어쓰기·되살리기, 빠진 행 soft delete).</summary>
    private sealed class MemorySetupRepository : ICommunitySetupRepository
    {
        public List<CommunitySetup> All { get; } = [];

        public List<CommunitySetup> Active(Guid trackId, string condition, string? session = null)
            => All.Where(s => !s.IsDeleted && s.TrackId == trackId && s.Condition == condition
                              && s.SessionType == (session ?? SetupSessions.DefaultFor(condition)))
                .OrderBy(s => s.Rank)
                .ToList();

        public Task<IReadOnlyList<CommunitySetupCount>> GetCountsAsync(string gameCode, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<CommunitySetup>> GetActiveAsync(
            Guid trackId, string condition, string sessionType, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<CommunitySetup?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<CommunitySetup>> GetGroupAsync(
            string gameCode, Guid trackId, string condition, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<CommunitySetup>>(
                All.Where(s => s.GameCode == gameCode && s.TrackId == trackId && s.Condition == condition).ToList());

        public Task ReplaceGroupAsync(
            string gameCode, Guid trackId, string condition, string sessionType, IReadOnlyList<CommunitySetup> setups, DateTime now,
            CancellationToken cancellationToken = default)
        {
            var group = All.Where(s => s.GameCode == gameCode && s.TrackId == trackId && s.Condition == condition
                                       && s.SessionType == sessionType).ToList();
            foreach (var row in group.Where(r => setups.All(s => s.SourceId != r.SourceId)))
            {
                row.IsDeleted = true;
            }

            foreach (var setup in setups)
            {
                All.RemoveAll(r => r.SourceId == setup.SourceId && r.TrackId == trackId && r.Condition == condition);
                All.Add(setup);
            }

            return Task.CompletedTask;
        }
    }
}
