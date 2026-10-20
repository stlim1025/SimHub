using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Laps;

/// <summary>
/// 랩 상세 비교 대상 선택·필터·어시스트(docs/15 §10, D-51): 종류 4개, 남의 랩 공개 규칙(랭킹 적격만)·이름 규칙(D-39),
/// 필터(같은 팀·세션 유형·어시스트, 이 랩의 값을 모르면 빠짐), 비교 트레이스 공개 규칙.
/// </summary>
public class LapComparisonServiceTests
{
    private const string PublicName = "빠른 드라이버";
    private const string HiddenName = "숨은 드라이버";

    private static readonly Guid Me = Guid.Parse("00000000-0000-0000-0000-0000000000b1");
    private static readonly Guid Rival = Guid.Parse("00000000-0000-0000-0000-0000000000b2");
    private static readonly Guid Hidden = Guid.Parse("00000000-0000-0000-0000-0000000000b3");
    private static readonly Guid Jeddah = Guid.Parse("00000000-0000-0000-0000-0000000000c5");
    private static readonly Guid Monza = Guid.Parse("00000000-0000-0000-0000-0000000000c6");
    private static readonly DateTime T0 = new(2026, 10, 18, 9, 0, 0, DateTimeKind.Utc);

    private readonly FakeLapQueryRepository _laps = new();
    private readonly LapQueryService _sut;

    public LapComparisonServiceTests()
    {
        _sut = new LapQueryService(_laps, new NoSessions(), NullLogger<LapQueryService>.Instance);
        _laps.Drivers[Rival] = new LapDriverRow(PublicName, ShowOnLeaderboard: true);
        _laps.Drivers[Hidden] = new LapDriverRow(HiddenName, ShowOnLeaderboard: false);
    }

    private LapRow AddLap(Guid userId, int lapTimeMs, bool isValid = true, bool? eligible = null, Guid? trackId = null,
        int? teamId = null, SessionType sessionType = SessionType.TimeTrial, bool hasTrace = false, int minute = 0)
    {
        var row = FakeLapQueryRepository.Row(
            Guid.NewGuid(), trackId ?? Jeddah, lapTimeMs, isValid, T0.AddMinutes(minute), teamId, hasTrace: hasTrace,
            userId: userId, sessionType: sessionType, isRankingEligible: eligible);
        _laps.Laps.Add((userId, row));
        return row;
    }

    private void SetAssists(LapRow lap, LapAssistValues values)
    {
        var snapshot = _laps.Snapshots.GetValueOrDefault(lap.LapId) ?? new LapSnapshot { LapId = lap.LapId };
        values.ApplyTo(snapshot);
        _laps.Snapshots[lap.LapId] = snapshot;
    }

    private Task<LapDetailResponse> Detail(LapRow lap, LapComparisonRequest request) => _sut.GetMyLapAsync(Me, lap.LapId, request);

    [Fact]
    public async Task Default_IsMyBestValidLap_MarkedMine()
    {
        var current = AddLap(Me, 98_000);
        var best = AddLap(Me, 97_000, teamId: 1);
        AddLap(Rival, 90_000); // 리더보드는 더 빠르지만 기본은 내 최고

        var detail = await _sut.GetMyLapAsync(Me, current.LapId);

        var comparison = Assert.IsType<LapComparisonDto>(detail.Comparison);
        Assert.Equal(LapComparisonKinds.Best, comparison.Kind);
        Assert.Equal(best.LapId, comparison.LapId);
        Assert.True(comparison.IsMine);
        Assert.Null(comparison.DisplayName);
        Assert.Equal("Ferrari", comparison.Team!.Name);
        Assert.Equal("TimeTrial", comparison.SessionType);
        Assert.Empty(comparison.AppliedFilters);
        Assert.Null(detail.ComparisonUnavailable);
        Assert.Equal(0, _laps.DriverCalls);
    }

    [Fact]
    public async Task None_HidesComparison_WithoutLookup()
    {
        var current = AddLap(Me, 98_000);
        AddLap(Me, 97_000);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.None));

        Assert.Null(detail.Comparison);
        Assert.Null(detail.ComparisonUnavailable);
        Assert.Null(_laps.LastCriteria);
    }

    [Fact]
    public async Task Leaderboard_IsFastestRankingEligibleLapOfAnyUser_WithPublicName()
    {
        var current = AddLap(Me, 98_000);
        AddLap(Me, 97_000);
        AddLap(Hidden, 89_000, isValid: true, eligible: false);  // 랭킹 부적격(레이스 등) → 제외
        AddLap(Rival, 92_000, trackId: Monza);                  // 다른 트랙 → 제외
        var rivalBest = AddLap(Rival, 93_000, hasTrace: true);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard));

        var comparison = Assert.IsType<LapComparisonDto>(detail.Comparison);
        Assert.Equal(LapComparisonKinds.Leaderboard, comparison.Kind);
        Assert.Equal(rivalBest.LapId, comparison.LapId);
        Assert.False(comparison.IsMine);
        Assert.Equal(PublicName, comparison.DisplayName);
        Assert.True(comparison.HasTrace);
        Assert.Equal(LapComparisonScope.LeaderboardEligible, _laps.LastCriteria!.Scope);
    }

    [Fact]
    public async Task Leaderboard_HiddenOrMissingDriver_IsAnonymous()
    {
        var current = AddLap(Me, 98_000);
        AddLap(Hidden, 91_000);

        var hidden = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard));
        Assert.Equal(RankingPrivacy.AnonymousDisplayName, hidden.Comparison!.DisplayName);

        var ghost = Guid.NewGuid(); // 사용자 행 없음(soft delete 등)
        AddLap(ghost, 90_000);
        var missing = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard));
        Assert.Equal(RankingPrivacy.AnonymousDisplayName, missing.Comparison!.DisplayName);
    }

    [Fact]
    public async Task Leaderboard_MyOwnLapOnTop_IsMine()
    {
        var current = AddLap(Me, 98_000);
        var mine = AddLap(Me, 90_000);
        AddLap(Rival, 91_000);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard));

        Assert.Equal(mine.LapId, detail.Comparison!.LapId);
        Assert.True(detail.Comparison.IsMine);
        Assert.Null(detail.Comparison.DisplayName);
        Assert.Equal(0, _laps.DriverCalls);
    }

    [Fact]
    public async Task Leaderboard_NoEligibleLap_IsNoMatch()
    {
        var current = AddLap(Me, 98_000, eligible: false);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard));

        Assert.Null(detail.Comparison);
        Assert.Equal(LapComparisonUnavailable.NoMatch, detail.ComparisonUnavailable);
    }

    [Fact]
    public async Task LapId_MyAnyLap_EvenInvalid_IsComparable()
    {
        var current = AddLap(Me, 98_000);
        var invalid = AddLap(Me, 95_000, isValid: false, trackId: Monza);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Lap, invalid.LapId));

        Assert.Equal(LapComparisonKinds.Lap, detail.Comparison!.Kind);
        Assert.Equal(invalid.LapId, detail.Comparison.LapId);
        Assert.True(detail.Comparison.IsMine);
    }

    [Fact]
    public async Task LapId_OthersEligibleLap_IsComparable_WithAnonymizedName()
    {
        var current = AddLap(Me, 98_000);
        var hiddenLap = AddLap(Hidden, 94_000);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Lap, hiddenLap.LapId));

        Assert.Equal(hiddenLap.LapId, detail.Comparison!.LapId);
        Assert.False(detail.Comparison.IsMine);
        Assert.Equal(RankingPrivacy.AnonymousDisplayName, detail.Comparison.DisplayName);
    }

    [Fact]
    public async Task LapId_OthersNonPublicLap_OrUnknown_IsNotFound()
    {
        var current = AddLap(Me, 98_000);
        var rivalRace = AddLap(Rival, 94_000, sessionType: SessionType.Race, eligible: false);

        var notPublic = await Detail(current, new LapComparisonRequest(LapComparisonKind.Lap, rivalRace.LapId));
        var unknown = await Detail(current, new LapComparisonRequest(LapComparisonKind.Lap, Guid.NewGuid()));

        Assert.Null(notPublic.Comparison);
        Assert.Equal(LapComparisonUnavailable.NotFound, notPublic.ComparisonUnavailable);
        Assert.Null(unknown.Comparison);
        Assert.Equal(LapComparisonUnavailable.NotFound, unknown.ComparisonUnavailable);
        Assert.Equal(0, _laps.DriverCalls); // 공개되지 않은 랩의 주인 이름은 읽지도 않는다
    }

    [Fact]
    public async Task LapId_Missing_IsValidationError()
    {
        var current = AddLap(Me, 98_000);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => Detail(current, new LapComparisonRequest(LapComparisonKind.Lap)));
        Assert.True(ex.Errors!.ContainsKey("compareLapId"));
    }

    [Fact]
    public async Task UndefinedKind_IsValidationError()
    {
        var current = AddLap(Me, 98_000);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => Detail(current, new LapComparisonRequest((LapComparisonKind)42)));
        Assert.True(ex.Errors!.ContainsKey("compare"));
    }

    [Fact]
    public async Task SameTeam_PicksFastestOfSameTeam()
    {
        var current = AddLap(Me, 98_000, teamId: 8);
        AddLap(Me, 96_000, teamId: 1);
        var sameTeam = AddLap(Me, 97_000, teamId: 8);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Best, SameTeam: true));

        Assert.Equal(sameTeam.LapId, detail.Comparison!.LapId);
        Assert.Equal([LapComparisonFilters.SameTeam], detail.Comparison.AppliedFilters);
        Assert.Equal(8, _laps.LastCriteria!.TeamId);
    }

    [Fact]
    public async Task SameTeam_UnknownOwnTeam_IsNotApplied()
    {
        var current = AddLap(Me, 98_000, teamId: null);
        var fastest = AddLap(Me, 96_000, teamId: 1);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Best, SameTeam: true));

        Assert.Equal(fastest.LapId, detail.Comparison!.LapId);
        Assert.Empty(detail.Comparison.AppliedFilters);
        Assert.Null(_laps.LastCriteria!.TeamId);
    }

    [Fact]
    public async Task SameSessionType_OnLeaderboard_RaceLap_IsNoMatch()
    {
        var current = AddLap(Me, 98_000, sessionType: SessionType.Race, eligible: false);
        AddLap(Rival, 91_000);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Leaderboard, SameSessionType: true));

        Assert.Null(detail.Comparison);
        Assert.Equal(LapComparisonUnavailable.NoMatch, detail.ComparisonUnavailable);
        Assert.Equal(SessionType.Race, _laps.LastCriteria!.SessionType);
    }

    [Fact]
    public async Task SameAssists_MatchesKnownAssistValues()
    {
        var assists = new LapAssistValues(1, 1, 0, 0, 1, 1);
        var current = AddLap(Me, 98_000);
        SetAssists(current, assists);
        var differentTc = AddLap(Rival, 90_000);
        SetAssists(differentTc, assists with { TractionControl = 2 });
        var same = AddLap(Rival, 92_000);
        SetAssists(same, assists);

        var detail = await Detail(current, new LapComparisonRequest(
            LapComparisonKind.Leaderboard, SameTeam: true, SameSessionType: true, SameAssists: true));

        Assert.Equal(same.LapId, detail.Comparison!.LapId);
        Assert.Equal([LapComparisonFilters.SameSessionType, LapComparisonFilters.SameAssists], detail.Comparison.AppliedFilters);
    }

    [Fact]
    public async Task SameAssists_UnknownOwnAssists_IsNotApplied()
    {
        var current = AddLap(Me, 98_000);
        var fastest = AddLap(Me, 96_000);
        SetAssists(fastest, new LapAssistValues(2, 1, 1, 3, 3, 2));

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Best, SameAssists: true));

        Assert.Equal(fastest.LapId, detail.Comparison!.LapId);
        Assert.Empty(detail.Comparison.AppliedFilters);
        Assert.Null(_laps.LastCriteria!.Assists);
    }

    [Fact]
    public async Task Filters_AreIgnored_ForLapIdComparison()
    {
        var current = AddLap(Me, 98_000, teamId: 8);
        var other = AddLap(Me, 99_000, teamId: 1);

        var detail = await Detail(current, new LapComparisonRequest(LapComparisonKind.Lap, other.LapId, SameTeam: true));

        Assert.Equal(other.LapId, detail.Comparison!.LapId);
        Assert.Empty(detail.Comparison.AppliedFilters);
    }

    [Fact]
    public async Task Assists_AreMappedToNames_NullWhenUnknown()
    {
        var withAssists = AddLap(Me, 98_000);
        SetAssists(withAssists, new LapAssistValues(1, 1, 0, 0, 1, 1));
        var partial = AddLap(Me, 98_100);
        SetAssists(partial, LapAssistValues.Unknown with { GearboxAssist = 3, BrakingAssist = 9 });
        var none = AddLap(Me, 98_200);

        var full = (await _sut.GetMyLapAsync(Me, withAssists.LapId)).Assists;
        Assert.Equal(new LapAssistsDto("Medium", "On", "Off", "Off", "Manual", "CornersOnly"), full);

        var some = (await _sut.GetMyLapAsync(Me, partial.LapId)).Assists;
        Assert.Equal(new LapAssistsDto(null, null, null, null, "Automatic", null), some); // 모르는 값(9)은 null

        Assert.Null((await _sut.GetMyLapAsync(Me, none.LapId)).Assists);
    }

    [Fact]
    public async Task ComparableTrace_MineOrOthersEligible_IsReturned()
    {
        var mine = AddLap(Me, 98_000, isValid: false, hasTrace: true);
        var rivalTt = AddLap(Rival, 91_000, hasTrace: true);
        _laps.Traces[mine.LapId] = Trace(mine.LapId);
        _laps.Traces[rivalTt.LapId] = Trace(rivalTt.LapId);

        Assert.Equal(mine.LapId, (await _sut.GetComparableLapTraceAsync(Me, mine.LapId)).LapId);
        Assert.Equal(rivalTt.LapId, (await _sut.GetComparableLapTraceAsync(Me, rivalTt.LapId)).LapId);
    }

    [Fact]
    public async Task ComparableTrace_OthersNonPublicOrMissing_IsNotFound()
    {
        var rivalRace = AddLap(Rival, 91_000, eligible: false, hasTrace: true);
        _laps.Traces[rivalRace.LapId] = Trace(rivalRace.LapId);
        var noTrace = AddLap(Rival, 92_000);

        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetComparableLapTraceAsync(Me, rivalRace.LapId));
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetComparableLapTraceAsync(Me, noTrace.LapId));
        await Assert.ThrowsAsync<NotFoundException>(() => _sut.GetComparableLapTraceAsync(Me, Guid.NewGuid()));
    }

    private static LapTelemetryTrace Trace(Guid lapId) => new()
    {
        LapId = lapId,
        ResolutionM = 5,
        SampleCount = 2,
        Payload = LapTraceCodec.Encode(new LapTraceChannels([0, 1], [1, 2], [0, 0], [0, 0], [0, 0], [1, 1], [1, 1])),
    };

    /// <summary>세션 키 없는 랩만 쓰므로 호출되지 않는다.</summary>
    private sealed class NoSessions : IGameSessionQueryRepository
    {
        public Task<Guid?> FindMySessionIdAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default)
            => Task.FromResult<Guid?>(null);

        public Task<(IReadOnlyList<SessionSummaryRow> Items, int Total)> GetMyPageAsync(
            Guid userId, SessionType? sessionType, int skip, int take, string? gameCode = null, CancellationToken cancellationToken = default)
            => throw new NotImplementedException();

        public Task<GameSession?> GetMineDetailAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
            => throw new NotImplementedException();
    }
}
