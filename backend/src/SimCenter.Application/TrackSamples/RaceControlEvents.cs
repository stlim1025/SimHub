using System.Text.Json;

namespace SimCenter.Application.TrackSamples;

/// <summary>깃발 구간 종류: 세이프티카·버추얼 세이프티카·적기·옐로 플래그(섹터별, 레이스를 멈추지 않는다).</summary>
public enum RaceFlagKind
{
    SafetyCar,
    VirtualSafetyCar,
    RedFlag,
    YellowFlag,
}

/// <summary>깃발 구간(세션 시간 ms). <see cref="Sectors"/> = 옐로 플래그가 나온 섹터 번호(1~3, 옐로 플래그만, 그 밖은 null).</summary>
public sealed record RaceFlagPeriod(RaceFlagKind Kind, int FromMs, int ToMs, IReadOnlyList<int>? Sectors = null);

/// <summary>리타이어(세션 시간 ms).</summary>
public sealed record RaceRetirement(int CarIndex, int TimeMs);

/// <summary>내 랩 하나의 게임 이벤트 재료: 랩 번호·랩 시간·스냅샷 상세 JSON(<c>events[]</c>: code·lapTimeMs·details).</summary>
public sealed record PlayerLapEvents(int LapNumber, int LapTimeMs, string? DetailsJson);

/// <summary>
/// 내 랩 기록의 게임 이벤트(D-49 <c>car.details.events[]</c>)를 세션 시간으로 옮겨 깃발 구간·리타이어를 뽑는다(순수 계산).
/// 랩 n의 시작 = 내 차의 (n−1)번째 결승선 통과(1랩은 첫 통과 − 1랩 시간). 플래시백(FLBK)이 오면 되감은 시각 뒤의 이벤트는 버린다
/// (사고 → 세이프티카 → 플래시백이면 그 세이프티카는 없던 일). 리타이어는 랩마다 다시 실려 오므로 차마다 처음 것만 쓴다.
/// 랩 끝(내 차 결승선 통과)의 세션 상태(<c>details.session</c>: 세이프티카 상태·지금까지 세이프티카·버추얼 횟수)로 이벤트를 바로잡는다 —
/// 옛 에이전트가 1랩 추월 이벤트에 밀려 종료·되감기 이벤트를 버린 랩이 있어서다. 열린 세이프티카·버추얼은 상태가 0인 첫 랩 끝에서 닫고,
/// 그때 그 종류의 횟수가 출동 전보다 늘지 않았으면(되감기로 성립하지 않은 출동) 구간을 버린다.
/// 옐로 플래그는 에이전트가 섹터가 바뀔 때마다 남긴 <c>YELLOW</c> 이벤트(상세 <c>sectors</c>)로 만든다 — 섹터가 바뀌면 구간을 나누고 빈 목록이면 닫는다.
/// </summary>
public static class RaceControlEvents
{
    private const string SafetyCarCode = "SCAR";
    private const string RedFlagCode = "RDFL";
    private const string RetirementCode = "RTMT";
    private const string FlashbackCode = "FLBK";
    private const string LightsOutCode = "LGOT";

    /// <summary>에이전트가 만든 옐로 플래그 섹터 변화 이벤트 코드와 상세 키(<c>LapDetailsTracker.YellowFlagCode</c>).</summary>
    private const string YellowFlagCode = "YELLOW";
    private const string YellowSectorsKey = "sectors";

    /// <summary>SCAR 상세: safetyCarType 1 = 세이프티카, 2 = 버추얼, 3 = 포메이션 랩. eventType 0 = 출동, 2 = 복귀, 3 = 재개.</summary>
    private const int FullSafetyCar = 1;
    private const int VirtualSafetyCar = 2;
    private const int Deployed = 0;
    private const int Returned = 2;
    private const int Resumed = 3;

    /// <summary>적기 끝을 모르면(재개 이벤트 없음) 이만큼(ms) 이어진 것으로 본다.</summary>
    private const int DefaultRedFlagMs = 120_000;

    /// <summary>세션 상태 <c>safetyCarStatus</c>: 세이프티카 없음.</summary>
    private const int NoSafetyCar = 0;

    private sealed record Event(int TimeMs, string Code, JsonElement Details);

    /// <summary>랩 끝(세션 시간)의 세션 상태. 모르는 값은 null.</summary>
    private sealed record LapEnd(int TimeMs, int? Status, int? SafetyCarPeriods, int? VirtualSafetyCarPeriods);

    /// <summary>열린 깃발 구간. <see cref="CountBefore"/> = 출동 전 그 종류의 횟수(세이프티카·버추얼, 모르면 null).</summary>
    private sealed record OpenFlag(RaceFlagKind Kind, int From, int? CountBefore);

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
        var lapEnds = new List<LapEnd>();
        foreach (var lap in byLap.Values)
        {
            int? start = lap.LapNumber >= 2 && playerCrossingsMs.Count >= lap.LapNumber - 1
                ? playerCrossingsMs[lap.LapNumber - 2]
                : lap.LapNumber == 1 && playerCrossingsMs.Count >= 1 ? playerCrossingsMs[0] - lap.LapTimeMs : null;
            if (start is not { } lapStart || lap.DetailsJson is null)
            {
                continue;
            }

            if (lap.LapNumber >= 1 && playerCrossingsMs.Count >= lap.LapNumber && ReadLapEnd(lap.DetailsJson) is { } state)
            {
                lapEnds.Add(state with { TimeMs = playerCrossingsMs[lap.LapNumber - 1] });
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
        OpenFlag? open = null;
        (int From, IReadOnlyList<int> Sectors)? openYellow = null;
        int? safetyCarsSoFar = 0;
        int? virtualSafetyCarsSoFar = 0;
        var pendingLapEnds = new Queue<LapEnd>(lapEnds.OrderBy(end => end.TimeMs));

        // 랩 끝 상태가 '세이프티카 없음'이면 열린 세이프티카·버추얼을 닫는다(횟수가 그대로면 성립하지 않은 출동이라 버린다).
        void ApplyLapEndsUpTo(int timeMs)
        {
            while (pendingLapEnds.TryPeek(out var end) && end.TimeMs <= timeMs)
            {
                pendingLapEnds.Dequeue();
                if (open is { Kind: RaceFlagKind.SafetyCar or RaceFlagKind.VirtualSafetyCar } period
                    && end.TimeMs > period.From && end.Status == NoSafetyCar)
                {
                    var countNow = period.Kind == RaceFlagKind.SafetyCar ? end.SafetyCarPeriods : end.VirtualSafetyCarPeriods;
                    if (!(countNow is { } now && period.CountBefore is { } before && now <= before))
                    {
                        flags.Add(new RaceFlagPeriod(period.Kind, period.From, end.TimeMs));
                    }

                    open = null;
                }

                safetyCarsSoFar = end.SafetyCarPeriods;
                virtualSafetyCarsSoFar = end.VirtualSafetyCarPeriods;
            }
        }

        foreach (var e in events.OrderBy(e => e.TimeMs))
        {
            ApplyLapEndsUpTo(e.TimeMs);
            switch (e.Code)
            {
                case SafetyCarCode:
                    var type = IntOf(e.Details, "safetyCarType");
                    var phase = IntOf(e.Details, "eventType");
                    if (phase == Deployed && type is FullSafetyCar or VirtualSafetyCar && open is null)
                    {
                        open = type == FullSafetyCar
                            ? new OpenFlag(RaceFlagKind.SafetyCar, e.TimeMs, safetyCarsSoFar)
                            : new OpenFlag(RaceFlagKind.VirtualSafetyCar, e.TimeMs, virtualSafetyCarsSoFar);
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

                    open = new OpenFlag(RaceFlagKind.RedFlag, e.TimeMs, CountBefore: null);
                    break;
                case LightsOutCode when open is { Kind: RaceFlagKind.RedFlag } red:
                    flags.Add(new RaceFlagPeriod(RaceFlagKind.RedFlag, red.From, e.TimeMs));
                    open = null;
                    break;
                case RetirementCode when IntOf(e.Details, "vehicleIndex") is { } car && retirements.All(r => r.CarIndex != car):
                    retirements.Add(new RaceRetirement(car, e.TimeMs));
                    break;
                case YellowFlagCode:
                    var sectors = SectorsOf(e.Details);
                    if (openYellow is { } yellow && yellow.Sectors.SequenceEqual(sectors))
                    {
                        break;
                    }

                    if (openYellow is { } previous)
                    {
                        flags.Add(new RaceFlagPeriod(RaceFlagKind.YellowFlag, previous.From, e.TimeMs, previous.Sectors));
                    }

                    openYellow = sectors.Count > 0 ? (e.TimeMs, sectors) : null;
                    break;
            }
        }

        ApplyLapEndsUpTo(int.MaxValue);

        if (openYellow is { } lastYellow)
        {
            flags.Add(new RaceFlagPeriod(RaceFlagKind.YellowFlag, lastYellow.From, Math.Max(raceEndMs, lastYellow.From), lastYellow.Sectors));
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

    /// <summary>스냅샷 상세의 <c>session</c> 묶음에서 랩 끝 세이프티카 상태·횟수(시각은 부르는 쪽이 채운다). 묶음이 없거나 깨졌으면 null.</summary>
    private static LapEnd? ReadLapEnd(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.TryGetProperty("session", out var session) || session.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            return new LapEnd(
                TimeMs: 0,
                Status: IntOf(session, "safetyCarStatus"),
                SafetyCarPeriods: IntOf(session, "numSafetyCarPeriods"),
                VirtualSafetyCarPeriods: IntOf(session, "numVirtualSafetyCarPeriods"));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>옐로 플래그 이벤트의 섹터 번호(정수만, 오름차순·중복 없이). 없거나 깨졌으면 빈 목록.</summary>
    private static IReadOnlyList<int> SectorsOf(JsonElement details)
    {
        if (details.ValueKind != JsonValueKind.Object
            || !details.TryGetProperty(YellowSectorsKey, out var list) || list.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return list.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.Number && item.TryGetInt32(out _))
            .Select(item => item.GetInt32())
            .Distinct()
            .Order()
            .ToArray();
    }

    private static int? IntOf(JsonElement details, string name)
        => details.ValueKind == JsonValueKind.Object && details.TryGetProperty(name, out var value) && value.TryGetInt32(out var number)
            ? number
            : null;
}
