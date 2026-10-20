using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Rankings;

/// <summary>
/// 랭킹/트랙/내 랩 조회 유스케이스. Domain·포트에만 의존(프레임워크 무의존).
/// 랭킹은 쿼리 온디맨드(materialized 테이블 없음) — 기간 경계는 서버 설정 타임존(Ranking:TimeZoneId)으로 계산한다(D-8, D-27).
/// </summary>
public sealed class RankingService : IRankingService
{
    private const int TopCount = 10;
    private const int DefaultPageSize = 20;
    private const int MaxPageSize = 100;

    private readonly ILapRepository _laps;
    private readonly ILapQueryRepository _lapQueries;
    private readonly ITrackRepository _tracks;
    private readonly IRankingTimeZoneProvider _timeZone;
    private readonly IClock _clock;

    public RankingService(
        ILapRepository laps,
        ILapQueryRepository lapQueries,
        ITrackRepository tracks,
        IRankingTimeZoneProvider timeZone,
        IClock clock)
    {
        _laps = laps;
        _lapQueries = lapQueries;
        _tracks = tracks;
        _timeZone = timeZone;
        _clock = clock;
    }

    public async Task<RankingSnapshotDto> GetRankingAsync(
        Guid trackId,
        string gameCode,
        RankingPeriod period,
        DateOnly? date,
        CancellationToken cancellationToken = default)
    {
        var track = await _tracks.GetByIdAsync(trackId, cancellationToken)
            ?? throw new NotFoundException("트랙을 찾을 수 없습니다.");

        var timeZoneId = _timeZone.TimeZoneId;
        var localDate = date ?? RankingPeriodRange.LocalToday(timeZoneId, _clock.UtcNow);
        var range = RankingPeriodRange.For(period, localDate, timeZoneId);

        // 실시간 랭킹은 Time Trial만(D-16). 랭킹적격 필터는 리포지토리가 적용한다.
        var rows = await _laps.GetRankingAsync(
            trackId, gameCode, SessionType.TimeTrial, range.FromUtc, range.ToUtc, TopCount, cancellationToken);

        // 이름 비공개 사용자는 익명으로 보인다(D-39). REST와 RankingUpdated 브로드캐스트가 모두 이 스냅샷을 쓴다.
        var entries = rows
            .Select((row, index) => new RankingEntryDto(
                index + 1, RankingPrivacy.DisplayNameFor(row), row.LapTimeMs, row.SetAt))
            .ToList();

        return new RankingSnapshotDto(
            track.Id, track.Name, gameCode, period.ToString().ToLowerInvariant(), range.PeriodKey, entries);
    }

    public async Task<TrackListResponse> GetTracksAsync(string? gameCode = null, CancellationToken cancellationToken = default)
    {
        // 순서(게임 → 표시 순서 → 이름, D-43)는 리포지토리가 보장한다 — 그대로 매핑한다. 트랙 마스터는 작아 게임 필터는 메모리에서 건다.
        var tracks = await _tracks.GetAllAsync(cancellationToken);
        var items = tracks
            .Where(t => gameCode is null || t.GameCode == gameCode)
            .Select(t => new TrackDto(t.Id, t.GameCode, t.Name, t.CountryCode, t.DisplayOrder))
            .ToList();

        return new TrackListResponse(items);
    }

    public async Task<MyLapsResponse> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        bool validOnly,
        MyLapsSort sort,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default)
    {
        page = page < 1 ? 1 : page;
        pageSize = pageSize switch
        {
            < 1 => DefaultPageSize,
            > MaxPageSize => MaxPageSize,
            _ => pageSize,
        };

        // 팀·날씨·트레이스 유무까지 한 쿼리 프로젝션으로 읽는다(15 §4.2, N+1 없음).
        var (rows, total) = await _lapQueries.GetMyPageAsync(
            userId, new MyLapsFilter(trackId, sessionType, validOnly), sort, (page - 1) * pageSize, pageSize, cancellationToken);

        var items = rows.Select(LapDtoMapper.ToLapDto).ToList();

        // 개인 최고는 트랙이 지정된 경우에만 의미가 있다(랭킹적격 기준). 트랙은 게임별 행이라 그 트랙의 게임 코드로 찾는다.
        PersonalBestDto? personalBest = null;
        if (trackId.HasValue && await _tracks.GetByIdAsync(trackId.Value, cancellationToken) is { } track)
        {
            var best = await _laps.GetPersonalBestLapAsync(userId, track.Id, track.GameCode, cancellationToken);
            if (best is not null)
            {
                personalBest = new PersonalBestDto(best.TrackId, best.LapTimeMs, best.SetAt);
            }
        }

        return new MyLapsResponse(personalBest, new PagedResult<LapDto>(page, pageSize, total, items));
    }

    public async Task<MyTracksResponse> GetMyTracksAsync(
        Guid userId, string? gameCode = null, CancellationToken cancellationToken = default)
    {
        var rows = await _laps.GetMyTrackSummariesAsync(userId, cancellationToken);

        // 순서(마지막 세운 시각 내림차순)는 리포지토리가 보장한다 — 그대로 매핑한다. 요약 행은 트랙 수만큼이라 게임 필터는 메모리에서 건다.
        var items = rows
            .Where(r => gameCode is null || r.GameCode == gameCode)
            .Select(r => new MyTrackDto(
                r.TrackId, r.TrackName, r.GameCode, r.LapCount, r.BestValidLapTimeMs, r.LastSetAt, r.CountryCode, r.DisplayOrder))
            .ToList();

        return new MyTracksResponse(items);
    }
}
