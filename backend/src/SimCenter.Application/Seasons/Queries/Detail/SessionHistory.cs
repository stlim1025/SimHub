using System.Text.Json;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>Session History(11)의 랩 한 칸(f1_25_udp_spec §8 <c>lapHistoryEntry</c>). 섹터 0 = 기록 없음.</summary>
public sealed record HistoryLap(
    int LapNumber,
    int LapTimeMs,
    int Sector1TimeMs,
    int Sector2TimeMs,
    int Sector3TimeMs,
    bool LapValid,
    bool Sector1Valid,
    bool Sector2Valid,
    bool Sector3Valid);

/// <summary>
/// <c>GameSession.Details</c>(D-49) = <c>{lapHistory:[{carIndex, laps:[…]}], lapPositions:[{lapNumber, positions[carIndex]}]}</c>를 읽은 값(docs/15 §11.4).
/// 깨진 칸은 버리고, 같은 차·같은 랩이 두 번 오면 나중 값을 쓴다.
/// </summary>
public sealed class SessionHistory
{
    public static readonly SessionHistory Empty = new(new Dictionary<int, IReadOnlyList<HistoryLap>>(), new Dictionary<int, IReadOnlyList<int>>());

    private SessionHistory(
        IReadOnlyDictionary<int, IReadOnlyList<HistoryLap>> lapsByCar,
        IReadOnlyDictionary<int, IReadOnlyList<int>> positionsByLap)
    {
        LapsByCar = lapsByCar;
        PositionsByLap = positionsByLap;
    }

    /// <summary>carIndex → 랩 번호 오름차순 기록.</summary>
    public IReadOnlyDictionary<int, IReadOnlyList<HistoryLap>> LapsByCar { get; }

    /// <summary>랩 번호 → carIndex 순 순위(0 = 기록 없음).</summary>
    public IReadOnlyDictionary<int, IReadOnlyList<int>> PositionsByLap { get; }

    /// <summary>그 차·그 랩의 순위. 모르거나 0이면 null.</summary>
    public int? PositionOf(int carIndex, int lapNumber)
        => PositionsByLap.TryGetValue(lapNumber, out var positions) && carIndex >= 0 && carIndex < positions.Count && positions[carIndex] > 0
            ? positions[carIndex]
            : null;

    /// <summary>그 차의 랩 기록. 없으면 빈 목록.</summary>
    public IReadOnlyList<HistoryLap> LapsOf(int? carIndex)
        => carIndex is { } car && LapsByCar.TryGetValue(car, out var laps) ? laps : [];

    public static SessionHistory Parse(string? detailsJson)
    {
        using var document = JsonReads.ParseObject(detailsJson);
        if (document is null)
        {
            return Empty;
        }

        var root = document.RootElement;
        return new SessionHistory(ReadLapHistory(root), ReadLapPositions(root));
    }

    private static Dictionary<int, IReadOnlyList<HistoryLap>> ReadLapHistory(JsonElement root)
    {
        var result = new Dictionary<int, IReadOnlyList<HistoryLap>>();
        if (JsonReads.Array(root, "lapHistory") is not { } cars)
        {
            return result;
        }

        foreach (var car in cars.EnumerateArray())
        {
            if (JsonReads.Int(car, "carIndex") is not { } carIndex || JsonReads.Array(car, "laps") is not { } laps)
            {
                continue;
            }

            var byLap = new SortedDictionary<int, HistoryLap>();
            foreach (var lap in laps.EnumerateArray())
            {
                if (ReadLap(lap) is { } entry)
                {
                    byLap[entry.LapNumber] = entry;
                }
            }

            result[carIndex] = byLap.Values.ToList();
        }

        return result;
    }

    private static HistoryLap? ReadLap(JsonElement lap)
    {
        if (JsonReads.Int(lap, "lapNumber") is not { } lapNumber || lapNumber < 1)
        {
            return null;
        }

        return new HistoryLap(
            lapNumber,
            NonNegative(JsonReads.Int(lap, "lapTimeMs")),
            NonNegative(JsonReads.Int(lap, "sector1TimeMs")),
            NonNegative(JsonReads.Int(lap, "sector2TimeMs")),
            NonNegative(JsonReads.Int(lap, "sector3TimeMs")),
            JsonReads.Bool(lap, "lapValid") ?? true,
            JsonReads.Bool(lap, "sector1Valid") ?? true,
            JsonReads.Bool(lap, "sector2Valid") ?? true,
            JsonReads.Bool(lap, "sector3Valid") ?? true);
    }

    private static Dictionary<int, IReadOnlyList<int>> ReadLapPositions(JsonElement root)
    {
        var result = new Dictionary<int, IReadOnlyList<int>>();
        if (JsonReads.Array(root, "lapPositions") is not { } rows)
        {
            return result;
        }

        foreach (var row in rows.EnumerateArray())
        {
            if (JsonReads.Int(row, "lapNumber") is not { } lapNumber || JsonReads.Array(row, "positions") is not { } positions)
            {
                continue;
            }

            result[lapNumber] = positions.EnumerateArray().Select(p => NonNegative(JsonReads.ToInt(p))).ToList();
        }

        return result;
    }

    private static int NonNegative(int? value) => value is > 0 ? value.Value : 0;
}
