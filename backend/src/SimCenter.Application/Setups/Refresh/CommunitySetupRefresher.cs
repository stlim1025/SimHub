using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Setups.Refresh;

/// <summary>한 번의 갱신 결과(로그·테스트용).</summary>
/// <param name="GroupsReplaced">새 목록으로 맞춘 묶음(트랙·조건) 수.</param>
/// <param name="GroupsFailed">읽기에 실패해 이전 데이터를 그대로 둔 묶음 수.</param>
/// <param name="DetailsFetched">새로 받은 상세 페이지 수.</param>
public sealed record SetupRefreshResult(int GroupsReplaced, int GroupsFailed, int DetailsFetched);

/// <summary>커뮤니티 셋업 갱신 유스케이스.</summary>
public interface ICommunitySetupRefresher
{
    /// <summary>게임들의 트랙 × 조건(Dry·Wet) × 세션 종류(타임 트라이얼·레이스·퀄리파잉) 셋업 상위 <paramref name="topCount"/>개를 출처에서 다시 읽어 맞춘다.</summary>
    Task<SetupRefreshResult> RefreshAsync(
        IReadOnlyList<string> gameCodes, int topCount, CancellationToken cancellationToken = default);
}

/// <summary>
/// 출처(F1Laps) 셋업 순위표 → 우리 DB. 게임마다 트랙 목록 → 트랙 × 조건 × 세션 종류마다 순위표 상위 N개 → 처음 보는 SourceId만 상세를 받는다(SourceId 캐시) →
/// 묶음을 한 번에 맞춘다. 묶음 하나라도 읽기에 실패하면 그 묶음은 이전 데이터를 그대로 둔다. 취소 외의 예외는 밖으로 내보내지 않는다.
/// </summary>
public sealed class CommunitySetupRefresher : ICommunitySetupRefresher
{
    private readonly ISetupSource _source;
    private readonly ICommunitySetupRepository _setups;
    private readonly ITrackRepository _tracks;
    private readonly IIdGenerator _ids;
    private readonly IClock _clock;
    private readonly ILogger<CommunitySetupRefresher> _logger;

    public CommunitySetupRefresher(
        ISetupSource source,
        ICommunitySetupRepository setups,
        ITrackRepository tracks,
        IIdGenerator ids,
        IClock clock,
        ILogger<CommunitySetupRefresher> logger)
    {
        _source = source;
        _setups = setups;
        _tracks = tracks;
        _ids = ids;
        _clock = clock;
        _logger = logger;
    }

    public async Task<SetupRefreshResult> RefreshAsync(
        IReadOnlyList<string> gameCodes, int topCount, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(gameCodes);
        var total = new SetupRefreshResult(0, 0, 0);
        if (topCount < 1)
        {
            return total;
        }

        var allTracks = await _tracks.GetAllAsync(cancellationToken);
        foreach (var gameCode in gameCodes)
        {
            var tracksByGameId = allTracks
                .Where(t => t.GameCode == gameCode)
                .ToDictionary(t => t.GameTrackId);
            var result = await RefreshGameAsync(gameCode, tracksByGameId, topCount, cancellationToken);
            total = new SetupRefreshResult(
                total.GroupsReplaced + result.GroupsReplaced,
                total.GroupsFailed + result.GroupsFailed,
                total.DetailsFetched + result.DetailsFetched);
        }

        return total;
    }

    private async Task<SetupRefreshResult> RefreshGameAsync(
        string gameCode, IReadOnlyDictionary<int, Track> tracksByGameId, int topCount, CancellationToken cancellationToken)
    {
        IReadOnlyList<SetupTrackLink> links;
        try
        {
            links = await _source.GetTracksAsync(gameCode, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            _logger.LogWarning(ex, "Community setup track list fetch failed for {GameCode}", gameCode);
            return new SetupRefreshResult(0, 1, 0);
        }

        int replaced = 0, failed = 0, details = 0;
        foreach (var link in links)
        {
            if (!F1LapsTrackSlugs.TryGetGameTrackId(link.Slug, out var gameTrackId)
                || !tracksByGameId.TryGetValue(gameTrackId, out var track))
            {
                _logger.LogWarning("Community setup track {Slug} ({Name}) has no matching track for {GameCode}", link.Slug, link.Name, gameCode);
                continue;
            }

            foreach (var condition in SetupConditions.All)
            {
                foreach (var session in SetupSessions.For(condition))
                {
                    try
                    {
                        details += await RefreshGroupAsync(gameCode, link.Slug, track, condition, session, topCount, cancellationToken);
                        replaced++;
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
                    {
                        failed++;
                        _logger.LogWarning(ex,
                            "Community setup refresh failed for {GameCode} {Slug} {Condition} {Session}; keeping previous data",
                            gameCode, link.Slug, condition, session);
                    }
                }
            }
        }

        _logger.LogInformation(
            "Community setups refreshed for {GameCode}: {Replaced} groups replaced, {Failed} failed, {Details} details fetched",
            gameCode, replaced, failed, details);
        return new SetupRefreshResult(replaced, failed, details);
    }

    /// <returns>새로 받은 상세 수.</returns>
    private async Task<int> RefreshGroupAsync(
        string gameCode, string slug, Track track, string condition, string session, int topCount, CancellationToken cancellationToken)
    {
        var rows = (await _source.GetRankingAsync(gameCode, slug, condition, session, cancellationToken))
            .GroupBy(r => r.SourceId, StringComparer.Ordinal)
            .Select(g => g.First())
            .OrderBy(r => r.Rank)
            .Take(topCount)
            .ToList();

        var known = (await _setups.GetGroupAsync(gameCode, track.Id, condition, cancellationToken))
            .ToDictionary(s => s.SourceId, StringComparer.Ordinal);

        // 처음 보는 셋업의 상세를 모두 받은 뒤에야 저장한다 — 하나라도 실패하면 묶음 전체를 이전 그대로 둔다.
        var fetched = new Dictionary<string, SetupDetail>(StringComparer.Ordinal);
        foreach (var row in rows.Where(r => !known.ContainsKey(r.SourceId)))
        {
            fetched[row.SourceId] = await _source.GetDetailAsync(row.SourceUrl, cancellationToken);
        }

        var now = _clock.UtcNow;
        var setups = rows
            .Select((row, index) => Build(gameCode, track.Id, condition, session, index + 1, row, known.GetValueOrDefault(row.SourceId),
                fetched.GetValueOrDefault(row.SourceId), now))
            .ToList();

        await _setups.ReplaceGroupAsync(gameCode, track.Id, condition, session, setups, now, cancellationToken);
        return fetched.Count;
    }

    /// <summary>목록 값(순위·팀·랩타임)은 매번 새 값, 세션 종류는 묶음 값, 상세 값은 새로 받았으면 그것, 아니면 저장된 값.</summary>
    private CommunitySetup Build(
        string gameCode,
        Guid trackId,
        string condition,
        string session,
        int rank,
        SetupListRow row,
        CommunitySetup? known,
        SetupDetail? detail,
        DateTime now)
        => new()
        {
            Id = known?.Id ?? _ids.NewId(),
            GameCode = gameCode,
            TrackId = trackId,
            Condition = condition,
            Rank = rank,
            Source = CommunitySetup.SourceF1Laps,
            SourceId = row.SourceId,
            SourceUrl = row.SourceUrl,
            TeamName = row.TeamName ?? detail?.TeamName ?? known?.TeamName,
            SessionType = session,
            LapTimeMs = row.LapTimeMs,
            Steering = detail is null ? known?.Steering : detail.Steering,
            SetOn = detail is null ? known?.SetOn : detail.SetOn,
            Sections = detail is null ? known?.Sections ?? SetupSections.Serialize([]) : SetupSections.Serialize(detail.Sections),
            FetchedAt = now,
            CreatedAt = known?.CreatedAt ?? now,
        };
}
