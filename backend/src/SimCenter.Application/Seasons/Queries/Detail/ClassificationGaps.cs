using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// Final Classification 카드의 GAP·CHANGE(docs/15 §11.3·§11.4, D-53). 순수 계산.
/// <list type="bullet">
/// <item>레이스 GAP = (총 시간 + 패널티) − 1위의 (총 시간 + 패널티). 완주(Finished)하고 1위와 같은 랩 수인 차만 — 리타이어·랩 다운·시간 없음은 null, 1위는 0.</item>
/// <item>예선·연습 GAP = 최고 랩 − 세션 최고 랩. 기록이 없으면 null.</item>
/// <item>CHANGE = 그리드 − 순위(레이스만, 그리드 0이면 null).</item>
/// </list>
/// </summary>
public sealed class ClassificationGaps
{
    private readonly bool _isRace;
    private readonly SessionResult? _winner;
    private readonly int? _fastestLapMs;

    private ClassificationGaps(bool isRace, SessionResult? winner, int? fastestLapMs)
    {
        _isRace = isRace;
        _winner = winner;
        _fastestLapMs = fastestLapMs;
    }

    public static ClassificationGaps For(SessionType sessionType, IReadOnlyList<SessionResult> results)
    {
        ArgumentNullException.ThrowIfNull(results);

        var winner = results.Where(r => r.Position == 1).OrderBy(r => r.CarIndex).FirstOrDefault();
        var fastest = results.Where(r => r.BestLapTimeMs > 0).Select(r => (int?)r.BestLapTimeMs).Min();
        return new ClassificationGaps(sessionType == SessionType.Race, winner, fastest);
    }

    public int? GapMs(SessionResult result)
    {
        ArgumentNullException.ThrowIfNull(result);

        if (_isRace)
        {
            return RaceGapMs(result);
        }

        return result.BestLapTimeMs > 0 && _fastestLapMs is { } fastest ? result.BestLapTimeMs - fastest : null;
    }

    public int? PositionChange(SessionResult result)
    {
        ArgumentNullException.ThrowIfNull(result);
        return _isRace && result.GridPosition > 0 && result.Position > 0 ? result.GridPosition - result.Position : null;
    }

    private int? RaceGapMs(SessionResult result)
    {
        if (_winner is null || !IsComparable(result) || !IsComparable(_winner) || result.NumLaps != _winner.NumLaps)
        {
            return null;
        }

        return ClampToInt(TotalMs(result) - TotalMs(_winner));
    }

    private static bool IsComparable(SessionResult result)
        => result.ResultStatus == ResultStatus.Finished && result.TotalRaceTimeMs > 0;

    private static long TotalMs(SessionResult result)
        => (long)result.TotalRaceTimeMs + Math.Max(0, result.PenaltiesTimeMs);

    private static int ClampToInt(long value) => (int)Math.Clamp(value, int.MinValue, int.MaxValue);
}
