using SimCenter.Application.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Import;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 내 세션 조회(12 §7 + docs/15 §11, D-53·D-54). 목록은 저장소가 만든 요약 행을 DTO로 옮기고, 상세는 결과 행을 정렬·매핑한 뒤
/// F1Laps 카드 재료를 <see cref="SessionDetailAssembler"/>로 만든다. 상세의 <c>round</c>는 시즌 상세와 같은 <see cref="RoundNumbering"/> 계산을 쓴다.
/// </summary>
public sealed class SessionQueryService : ISessionQueryService
{
    private readonly IGameSessionQueryRepository _sessions;
    private readonly ISeasonQueryRepository _seasons;
    private readonly ISessionDetailQueryRepository _details;

    public SessionQueryService(
        IGameSessionQueryRepository sessions, ISeasonQueryRepository seasons, ISessionDetailQueryRepository details)
    {
        _sessions = sessions;
        _seasons = seasons;
        _details = details;
    }

    public async Task<PagedResult<SessionSummaryDto>> GetMySessionsAsync(
        Guid userId, SessionType? sessionType, int page, int pageSize, string? gameCode = null,
        CancellationToken cancellationToken = default)
    {
        var window = PageWindow.Resolve(page, pageSize, ISessionQueryService.DefaultPageSize, ISessionQueryService.MaxPageSize);

        var (rows, total) = await _sessions.GetMyPageAsync(
            userId, sessionType, window.Skip, window.PageSize, gameCode, cancellationToken);

        var seasonNumbers = rows.Any(r => r.SeasonId.HasValue)
            ? SeasonNumbering.Assign(await _details.GetMySeasonOrderAsync(userId, cancellationToken))
            : new Dictionary<Guid, int>();

        var items = rows.Select(row => ToSummary(row, seasonNumbers)).ToList();
        return new PagedResult<SessionSummaryDto>(window.Page, window.PageSize, total, items);
    }

    public async Task<SessionDetailDto> GetMySessionAsync(
        Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetMineDetailAsync(userId, sessionId, cancellationToken)
            ?? throw new NotFoundException("세션을 찾을 수 없습니다.");

        // 순위 모름(0)은 맨 뒤.
        var results = session.Results
            .Where(r => !r.IsDeleted)
            .OrderBy(r => r.Position > 0 ? r.Position : int.MaxValue)
            .ThenBy(r => r.CarIndex)
            .ToList();

        var round = await FindRoundAsync(session, cancellationToken);
        var sprintWeekend = session.RaceWeekendId is { } sprintWeekendId
            && await _details.IsMySprintWeekendAsync(userId, sprintWeekendId, cancellationToken);
        var seasonNumber = await FindSeasonNumberAsync(userId, session.SeasonId, cancellationToken);
        var hasFieldSamples = await _details.HasMyTrackSamplesAsync(userId, session.SessionRef, cancellationToken);

        // docs/15 §11.4: 내 랩·스냅샷은 한 쿼리로(랩마다 따로 읽지 않는다).
        var lapRows = await _details.GetMySessionLapsAsync(
            userId, session.GameCode, session.TrackId, session.SessionKey, cancellationToken);
        var weekendQualifying = session.SessionType == SessionType.Qualifying && session.RaceWeekendId is { } weekendId
            ? await _details.GetMyWeekendQualifyingAsync(userId, weekendId, cancellationToken)
            : [];

        var extras = SessionDetailAssembler.Build(session, results, lapRows, weekendQualifying);

        return new SessionDetailDto(
            // 가져온 세션(D-55)은 랩이 없어 세션에 저장한 날씨를 쓴다.
            ToHeader(session, results, round, seasonNumber, extras.Weather ?? session.Weather?.ToString(), sprintWeekend)
                with { HasFieldSamples = hasFieldSamples },
            ToResultDtos(session, results),
            extras.QualifyingPositions,
            extras.MyBestLap,
            extras.Setup,
            extras.Laps,
            extras.EngineWear,
            extras.TyreStints,
            extras.Penalties,
            extras.RaceReview);
    }

    /// <summary>시즌에 속한 세션이면 그 시즌의 주말 순서에서 라운드 번호를 찾는다. 아니면(또는 주말 행이 없으면) null.</summary>
    private async Task<int?> FindRoundAsync(GameSession session, CancellationToken cancellationToken)
    {
        if (session.SeasonId is not { } seasonId || session.RaceWeekendId is not { } weekendId)
        {
            return null;
        }

        var weekends = await _seasons.GetWeekendRowsAsync(new[] { seasonId }, cancellationToken);
        var rounds = RoundNumbering.Assign(weekends);
        return rounds.TryGetValue(weekendId, out var round) ? round : null;
    }

    private async Task<int?> FindSeasonNumberAsync(Guid userId, Guid? seasonId, CancellationToken cancellationToken)
    {
        if (seasonId is null)
        {
            return null;
        }

        var numbers = SeasonNumbering.Assign(await _details.GetMySeasonOrderAsync(userId, cancellationToken));
        return SeasonNumbering.Of(numbers, seasonId);
    }

    // ---- 매핑: 목록 ----

    /// <summary>번호가 있는(= 지우지 않은 내) 시즌만 Id를 낸다. 지운 시즌을 가리키는 세션은 시즌 없음(null)으로 보인다.</summary>
    private static Guid? ActiveSeasonId(IReadOnlyDictionary<Guid, int> seasonNumbers, Guid? seasonId)
        => SeasonNumbering.Of(seasonNumbers, seasonId) is null ? null : seasonId;

    private static SessionSummaryDto ToSummary(SessionSummaryRow row, IReadOnlyDictionary<Guid, int> seasonNumbers) => new(
        row.SessionId,
        row.ClassifiedAt,
        row.TrackName,
        row.SessionType.ToString(),
        row.SessionKind.ToString(),
        row.GameMode.ToString(),
        // 지운 시즌(번호가 없다)은 가리키지 않는다.
        ActiveSeasonId(seasonNumbers, row.SeasonId),
        row.CarCount,
        SessionPositions.Known(row.MyPosition),
        SessionPositions.Known(row.MyGridPosition),
        row.MyResultStatus?.ToString(),
        NullIfNoTime(row.MyBestLapTimeMs),
        row.MyPoints,
        row.CountryCode,
        // 행의 저장 순위(0 포함)가 있으면 = 내 결과 행이 있다 → 팀을 낸다.
        row.MyPosition is null ? null : ToMyTeam(row.GameCode, row.MyTeamId, row.MyTeamName),
        SeasonNumbering.Of(seasonNumbers, row.SeasonId),
        row.IsSprintWeekend);

    // ---- 매핑: 상세 ----

    private static SessionDetailHeaderDto ToHeader(
        GameSession session, IReadOnlyList<SessionResult> results, int? round, int? seasonNumber, string? weather, bool sprintWeekend)
    {
        var me = results.FirstOrDefault(r => r.IsPlayer);

        return new SessionDetailHeaderDto(
            session.Id,
            session.ClassifiedAt,
            session.Track?.Name ?? string.Empty,
            session.SessionType.ToString(),
            session.SessionKind.ToString(),
            session.GameMode.ToString(),
            // 지운 시즌(번호가 없다)은 가리키지 않는다.
            seasonNumber is null ? null : session.SeasonId,
            results.Count,
            SessionPositions.Known(me?.Position),
            SessionPositions.Known(me?.GridPosition),
            me?.ResultStatus.ToString(),
            NullIfNoTime(me?.BestLapTimeMs),
            me?.Points,
            session.TotalLaps,
            session.AiDifficulty,
            session.IsNetworkGame,
            round,
            session.Track?.CountryCode,
            me is null ? null : ToMyTeam(session.GameCode, me.TeamId, me.TeamName),
            seasonNumber,
            weather,
            sprintWeekend);
    }

    private static MyTeamDto ToMyTeam(string gameCode, int? teamId, string? teamName)
    {
        var team = TeamCatalog.Resolve(gameCode, teamId, teamName);
        return new MyTeamDto(team.Name, team.Color);
    }

    private static List<SessionResultDto> ToResultDtos(GameSession session, IReadOnlyList<SessionResult> results)
    {
        // 최고 랩: 기록이 있는 행(0 초과) 중 최소값. 같으면 모두 true, 기록이 없으면 아무도 아님.
        var fastestLapMs = results
            .Where(r => r.BestLapTimeMs > 0)
            .Select(r => (int?)r.BestLapTimeMs)
            .Min();
        var gaps = ClassificationGaps.For(session.SessionType, results);
        var dtos = results.Select(r => ToResultDto(session.GameCode, r, fastestLapMs, gaps)).ToList();

        // 가져온 세션(docs/15 §12, D-55): 총 시간이 없어 레이스 GAP은 F1Laps 값, 최고 랩은 인게임 표의 * 표시를 쓴다.
        if (!session.IsImported || ImportedSessionDetails.TryRead(session.Details) is not { } imported)
        {
            return dtos;
        }

        var importedGaps = imported.Gaps.GroupBy(g => g.CarIndex).ToDictionary(g => g.Key, g => g.Last().GapMs);
        return dtos.Select(dto => dto with
        {
            GapMs = importedGaps.TryGetValue(dto.CarIndex, out var gap) ? gap : dto.GapMs,
            IsFastestLap = imported.FastestLapCarIndex is { } fastestCar ? dto.CarIndex == fastestCar : dto.IsFastestLap,
        }).ToList();
    }

    private static SessionResultDto ToResultDto(string gameCode, SessionResult result, int? fastestLapMs, ClassificationGaps gaps)
    {
        var team = TeamCatalog.Resolve(gameCode, result.TeamId, result.TeamName);
        var bestLapMs = NullIfNoTime(result.BestLapTimeMs);

        return new SessionResultDto(
            result.Position,
            result.CarIndex,
            DriverLabels.Name(result.DriverName, result.CarIndex),
            result.TeamId,
            team.Name,
            team.Color,
            result.RaceNumber,
            result.IsAiControlled,
            result.IsPlayer,
            result.GridPosition,
            result.NumLaps,
            bestLapMs,
            bestLapMs is not null && bestLapMs == fastestLapMs,
            NullIfNoTime(result.TotalRaceTimeMs),
            result.PenaltiesTimeMs,
            result.NumPenalties,
            result.NumPitStops,
            result.Points,
            result.ResultStatus.ToString(),
            ToStintDtos(result),
            gaps.GapMs(result),
            gaps.PositionChange(result));
    }

    private static List<TyreStintViewDto> ToStintDtos(SessionResult result)
    {
        return result.TyreStints
            .Where(s => !s.IsDeleted)
            .OrderBy(s => s.StintNumber)
            .Select(s => new TyreStintViewDto(s.EndLap, s.VisualCompound.ToString(), s.ActualCompound))
            .ToList();
    }

    /// <summary>시간 값 0(기록 없음)을 null로 내보낸다(기존 <c>bestValidLapTimeMs</c>와 같은 방식).</summary>
    private static int? NullIfNoTime(int? milliseconds) => milliseconds is > 0 ? milliseconds : null;
}
