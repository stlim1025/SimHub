using System.Text.Json;

namespace SimCenter.Application.TrackSamples;

/// <summary>깃발 구간 종류: 세이프티카·버추얼 세이프티카·적기.</summary>
public enum RaceFlagKind
{
    SafetyCar,
    VirtualSafetyCar,
    RedFlag,
}

/// <summary>깃발 구간(세션 시간 ms).</summary>
public sealed record RaceFlagPeriod(RaceFlagKind Kind, int FromMs, int ToMs);

/// <summary>리타이어(세션 시간 ms).</summary>
public sealed record RaceRetirement(int CarIndex, int TimeMs);

/// <summary>내 랩 하나의 게임 이벤트 재료: 랩 번호·랩 시간·스냅샷 상세 JSON(<c>events[]</c>: code·lapTimeMs·details).</summary>
public sealed record PlayerLapEvents(int LapNumber, int LapTimeMs, string? DetailsJson);

/// <summary>
/// 내 랩 기록의 게임 이벤트(D-49 <c>car.details.events[]</c>)를 세션 시간으로 옮겨 깃발 구간·리타이어를 뽑는다(순수 계산).
/// 랩 n의 시작 = 내 차의 (n−1)번째 결승선 통과(1랩은 첫 통과 − 1랩 시간). 플래시백(FLBK)이 오면 되감은 시각 뒤의 이벤트는 버린다
/// (사고 → 세이프티카 → 플래시백이면 그 세이프티카는 없던 일). 리타이어는 랩마다 다시 실려 오므로 차마다 처음 것만 쓴다.
/// </summary>
public static class RaceControlEvents
{
    private const string SafetyCarCode = "SCAR";
    private const string RedFlagCode = "RDFL";
    private const string RetirementCode = "RTMT";
    private const string FlashbackCode = "FLBK";
    private const string LightsOutCode = "LGOT";

    /// <summary>SCAR 상세: safetyCarType 1 = 세이프티카, 2 = 버추얼, 3 = 포메이션 랩. eventType 0 = 출동, 2 = 복귀, 3 = 재개.</summary>
    private const int FullSafetyCar = 1;
    private const int VirtualSafetyCar = 2;
    private const int Deployed = 0;
    private const int Returned = 2;
    private const int Resumed = 3;

    /// <summary>적기 끝을 모르면(재개 이벤트 없음) 이만큼(ms) 이어진 것으로 본다.</summary>
    private const int DefaultRedFlagMs = 120_000;

    private sealed record Event(int TimeMs, string Code, JsonElement Details);

    public static (IReadOnlyList<RaceFlagPeriod> Flags, IReadOnlyList<RaceRetirement> Retirements) Build(
        IReadOnlyList<PlayerLapEvents> laps, IReadOnlyList<int> playerCrossingsMs, int raceEndMs)
    {
        // 같은 랩 번호가 여러 번 기록됐으면(플래시백 뒤 다시 기록) 마지막 것.
        var byLap = new SortedDictionary<int, PlayerLapEvents>();
        foreach (var lap in laps)
        {
            byLap[lap.LapNumber] = lap;
        }

        var events = new List<Event>();
        foreach (var lap in byLap.Values)
        {
            int? start = lap.LapNumber >= 2 && playerCrossingsMs.Count >= lap.LapNumber - 1
                ? playerCrossingsMs[lap.LapNumber - 2]
                : lap.LapNumber == 1 && playerCrossingsMs.Count >= 1 ? playerCrossingsMs[0] - lap.LapTimeMs : null;
            if (start is not { } lapStart || lap.DetailsJson is null)
            {
                continue;
            }

            foreach (var (code, lapTimeMs, details) in ReadEvents(lap.DetailsJson))
            {
                if (code == FlashbackCode)
                {
                    if (details.ValueKind == JsonValueKind.Object
                        && details.TryGetProperty("flashbackSessionTimeMs", out var target) && target.TryGetInt32(out var rewindTo))
                    {
                        events.RemoveAll(e => e.TimeMs > rewindTo);
                    }

                    continue;
                }

                events.Add(new Event(lapStart + lapTimeMs, code, details));
            }
        }

        var flags = new List<RaceFlagPeriod>();
        var retirements = new List<RaceRetirement>();
        (RaceFlagKind Kind, int From)? open = null;
        foreach (var e in events.OrderBy(e => e.TimeMs))
        {
            switch (e.Code)
            {
                case SafetyCarCode:
                    var type = IntOf(e.Details, "safetyCarType");
                    var phase = IntOf(e.Details, "eventType");
                    if (phase == Deployed && type is FullSafetyCar or VirtualSafetyCar && open is null)
                    {
                        open = (type == FullSafetyCar ? RaceFlagKind.SafetyCar : RaceFlagKind.VirtualSafetyCar, e.TimeMs);
                    }
                    else if (phase is Returned or Resumed && open is { } period)
                    {
                        flags.Add(new RaceFlagPeriod(period.Kind, period.From, e.TimeMs));
                        open = null;
                    }

                    break;
                case RedFlagCode:
                    if (open is { } before)
                    {
                        flags.Add(new RaceFlagPeriod(before.Kind, before.From, e.TimeMs));
                    }

                    open = (RaceFlagKind.RedFlag, e.TimeMs);
                    break;
                case LightsOutCode when open is { Kind: RaceFlagKind.RedFlag } red:
                    flags.Add(new RaceFlagPeriod(RaceFlagKind.RedFlag, red.From, e.TimeMs));
                    open = null;
                    break;
                case RetirementCode when IntOf(e.Details, "vehicleIndex") is { } car && retirements.All(r => r.CarIndex != car):
                    retirements.Add(new RaceRetirement(car, e.TimeMs));
                    break;
            }
        }

        if (open is { } last)
        {
            var to = last.Kind == RaceFlagKind.RedFlag ? Math.Min(raceEndMs, last.From + DefaultRedFlagMs) : raceEndMs;
            flags.Add(new RaceFlagPeriod(last.Kind, last.From, Math.Max(to, last.From)));
        }

        return (flags, retirements);
    }

    private static IEnumerable<(string Code, int LapTimeMs, JsonElement Details)> ReadEvents(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            yield break;
        }

        using (document)
        {
            if (!document.RootElement.TryGetProperty("events", out var list) || list.ValueKind != JsonValueKind.Array)
            {
                yield break;
            }

            foreach (var item in list.EnumerateArray())
            {
                if (item.TryGetProperty("code", out var code) && code.GetString() is { } text
                    && item.TryGetProperty("lapTimeMs", out var at) && at.TryGetInt32(out var lapTimeMs))
                {
                    var details = item.TryGetProperty("details", out var d) ? d.Clone() : default;
                    yield return (text, lapTimeMs, details);
                }
            }
        }
    }

    private static int? IntOf(JsonElement details, string name)
        => details.ValueKind == JsonValueKind.Object && details.TryGetProperty(name, out var value) && value.TryGetInt32(out var number)
            ? number
            : null;
}
