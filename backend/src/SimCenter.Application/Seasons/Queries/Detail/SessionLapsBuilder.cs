namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// Laps 카드 행 만들기(docs/15 §11.3·§11.4, D-53). 순수 계산.
/// <list type="bullet">
/// <item>원천: 세션 <c>lapHistory</c>의 내 차(랩타임 0 = 진행 중 랩은 뺀다). 없으면 저장된 내 랩으로 대신한다.</item>
/// <item>순위: <c>lapPositions</c>. 변동 = 이전 랩 순위 − 이 랩 순위(1랩은 그리드 대비, 그리드 0이면 null).</item>
/// <item>타이어: 스틴트 범위. 피트: 내 랩 스냅샷 <c>lapData.pitStatus != 0</c> 또는 스틴트가 바뀐 랩.</item>
/// <item>최고 랩·간격: 유효 랩 중 최소(유효 랩이 없으면 전체). 최고 섹터(보라): 유효 섹터 중 최소와 같은 칸.</item>
/// </list>
/// </summary>
public static class SessionLapsBuilder
{
    private const int SectorCount = 3;

    public static IReadOnlyList<SessionLapDto> Build(
        int? playerCarIndex,
        int? gridPosition,
        SessionHistory history,
        IReadOnlyList<StintSpan> stints,
        IReadOnlyList<MySessionLap> myLaps)
    {
        ArgumentNullException.ThrowIfNull(history);
        ArgumentNullException.ThrowIfNull(stints);
        ArgumentNullException.ThrowIfNull(myLaps);

        var source = SourceLaps(history.LapsOf(playerCarIndex), myLaps);
        if (source.Count == 0)
        {
            return [];
        }

        var myLapByNumber = LatestByLapNumber(myLaps);
        var candidates = source.Any(l => l.IsValid) ? source.Where(l => l.IsValid).ToList() : source;
        var bestLapMs = candidates.Min(l => l.LapTimeMs);
        var bestSectorMs = BestSectors(source);

        var rows = new List<SessionLapDto>(source.Count);
        int? previousPosition = gridPosition is > 0 ? gridPosition : null;
        foreach (var lap in source)
        {
            var position = playerCarIndex is { } car ? history.PositionOf(car, lap.LapNumber) : null;
            int? change = position is { } now && previousPosition is { } before ? before - now : null;
            myLapByNumber.TryGetValue(lap.LapNumber, out var stored);

            rows.Add(new SessionLapDto(
                lap.LapNumber,
                position,
                change,
                StintSpan.CompoundAt(stints, lap.LapNumber),
                stored?.PitStatus is > 0 || StintSpan.IsPitLap(stints, lap.LapNumber),
                lap.LapTimeMs,
                lap.LapTimeMs - bestLapMs,
                lap.Sectors.Select(s => s is > 0 ? s : null).ToList(),
                lap.IsValid,
                lap.LapTimeMs == bestLapMs && candidates.Contains(lap),
                Enumerable.Range(0, SectorCount)
                    .Select(i => lap.SectorValid[i] && lap.Sectors[i] is > 0 && lap.Sectors[i] == bestSectorMs[i])
                    .ToList(),
                stored?.Row.LapId));

            previousPosition = position;
        }

        return rows;
    }

    /// <summary>랩 번호마다 마지막에 저장된 내 랩(같은 번호가 여럿이면 <c>SetAt</c>이 늦은 것).</summary>
    internal static Dictionary<int, MySessionLap> LatestByLapNumber(IReadOnlyList<MySessionLap> myLaps)
        => myLaps
            .GroupBy(l => l.LapNumber)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(l => l.Row.SetAt).ThenByDescending(l => l.Row.LapId).First());

    private static List<SourceLap> SourceLaps(IReadOnlyList<HistoryLap> history, IReadOnlyList<MySessionLap> myLaps)
    {
        var fromHistory = history
            .Where(h => h.LapTimeMs > 0)
            .Select(h => new SourceLap(
                h.LapNumber,
                h.LapTimeMs,
                h.LapValid,
                [h.Sector1TimeMs, h.Sector2TimeMs, h.Sector3TimeMs],
                [h.Sector1Valid, h.Sector2Valid, h.Sector3Valid]))
            .ToList();
        if (fromHistory.Count > 0)
        {
            return fromHistory;
        }

        // 세션 기록이 없는 세션(예전 Agent) — 저장된 내 랩으로 대신한다.
        return LatestByLapNumber(myLaps).Values
            .Where(l => l.Row.LapTimeMs > 0)
            .OrderBy(l => l.LapNumber)
            .Select(l => new SourceLap(
                l.LapNumber,
                l.Row.LapTimeMs,
                l.Row.IsValid,
                Enumerable.Range(0, SectorCount).Select(i => i < l.Row.Sectors.Count ? l.Row.Sectors[i] : null).ToArray(),
                [true, true, true]))
            .ToList();
    }

    private static int?[] BestSectors(IReadOnlyList<SourceLap> laps)
        => Enumerable.Range(0, SectorCount)
            .Select(i => laps
                .Where(l => l.SectorValid[i] && l.Sectors[i] is > 0)
                .Select(l => l.Sectors[i])
                .Min())
            .ToArray();

    private sealed record SourceLap(int LapNumber, int LapTimeMs, bool IsValid, int?[] Sectors, bool[] SectorValid);
}
