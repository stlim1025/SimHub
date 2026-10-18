using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// Final Classification 카드의 GAP·CHANGE(docs/15 §11.3·§11.4, D-53). 순수 계산.
/// <list type="bullet">
/// <item>레이스 GAP = (총 시간 + 패널티) − 1위의 (총 시간 + 패널티). 내 시간이나 1위 시간이 없으면 null, 1위는 0.</item>
/// <item>예선·연습 GAP = 최고 랩 − 세션 최고 랩. 기록이 없으면 null.</item>
/// <item>CHANGE = 그리드 − 순위(레이스만, 그리드 0이면 null).</item>
/// </list>
/// </summary>
public sealed class ClassificationGaps
{
    private readonly bool _isRace;
    private readonly long? _winnerTotalMs;
    private readonly int? _fastestLapMs;

    private ClassificationGaps(bool isRace, long? winnerTotalMs, int? fastestLapMs)
    {
        _isRace = isRace;
        _winnerTotalMs = winnerTotalMs;
        _fastestLapMs = fastestLapMs;
    }

    public static ClassificationGaps For(SessionType sessionType, IReadOnlyList<SessionResult> results)
    {
        ArgumentNullException.ThrowIfNull(results);

        var winner = results.Where(r => r.Position == 1).OrderBy(r => r.CarIndex).FirstOrDefault();
        var fastest = results.Where(r => r.BestLapTimeMs > 0).Select(r => (int?)r.BestLapTimeMs).Min();
        return new ClassificationGaps(sessionType == SessionType.Race, winner is null ? null : TotalMs(winner), fastest);
    }

    public int? GapMs(SessionResult result)
    {
        ArgumentNullException.ThrowIfNull(result);

        if (_isRace)
        {
            return TotalMs(result) is { } total && _winnerTotalMs is { } winner ? ClampToInt(total - winner) : null;
        }

        return result.BestLapTimeMs > 0 && _fastestLapMs is { } fastest ? result.BestLapTimeMs - fastest : null;
    }

    public int? PositionChange(SessionResult result)
    {
        ArgumentNullException.ThrowIfNull(result);
        return _isRace && result.GridPosition > 0 && result.Position > 0 ? result.GridPosition - result.Position : null;
    }

    private static long? TotalMs(SessionResult result)
        => result.TotalRaceTimeMs > 0 ? (long)result.TotalRaceTimeMs + Math.Max(0, result.PenaltiesTimeMs) : null;

    private static int ClampToInt(long value) => (int)Math.Clamp(value, int.MinValue, int.MaxValue);
}
