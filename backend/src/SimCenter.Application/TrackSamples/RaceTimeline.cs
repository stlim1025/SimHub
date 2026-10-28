using SimCenter.Domain.Enums;

namespace SimCenter.Application.TrackSamples;

/// <summary>레이스 한 순간 차 한 대(표본 열을 한데 모은 값). 상태·표시 비트는 계약(<c>shared/schema/track_samples_chunk.json</c>) 그대로.</summary>
public readonly record struct RaceSample(
    int TimeMs,
    float LapDistanceM,
    float X,
    float Y,
    float Z,
    ushort SpeedKph,
    sbyte Gear,
    byte Throttle,
    byte Brake,
    byte Status,
    byte Flags2,
    byte Damage,
    float GLateral,
    float GLongitudinal,
    byte TyreVisualRaw = 0)
{
    /// <summary>F1 게임 보이는 컴파운드 원시 값(소프트·미디엄·하드·인터·웻).</summary>
    private const byte RawSoft = 16;
    private const byte RawMedium = 17;
    private const byte RawHard = 18;
    private const byte RawInter = 7;
    private const byte RawWet = 8;

    /// <summary>보이는 컴파운드(<see cref="TyreCompound"/> 값, 모르면 0 — format 3 이전 표본·클래식 타이어).</summary>
    public int Tyre => (int)(TyreVisualRaw switch
    {
        RawSoft => TyreCompound.Soft,
        RawMedium => TyreCompound.Medium,
        RawHard => TyreCompound.Hard,
        RawInter => TyreCompound.Intermediate,
        RawWet => TyreCompound.Wet,
        _ => TyreCompound.Unknown,
    });

    /// <summary>상태 비트: 차 대 차 충돌·충격 순간.</summary>
    public const byte CollisionFlag = 0x20;
    public const byte ImpactFlag = 0x40;

    /// <summary>표시 비트 2: 이 표본에 추월함·추월당함.</summary>
    public const byte OvertookFlag = 0x02;
    public const byte OvertakenFlag = 0x04;

    private const int PitStatusShift = 3;
    private const int PitStatusMask = 0x3;

    /// <summary>피트 레인에 있는지(게임 Pit Status가 0이 아님).</summary>
    public bool InPit => ((Status >> PitStatusShift) & PitStatusMask) != 0;
}

/// <summary>
/// 세션 하나(저장했다가 이어 달린 여러 조각 묶음 포함)의 차별 시계열(순수 계산).
/// 조각을 받은 순서대로 이어 붙이다가 세션 시간이 뒤로 가면(플래시백, 또는 저장한 곳에서 다시 달림) 그 시각 이후의 표본을 버린다 —
/// 그래서 남는 것은 실제로 이어진 최종 주행뿐이다.
/// </summary>
public sealed class RaceTimeline
{
    /// <summary>세션 시간이 이보다 크게 뒤로 가면 되감기로 본다(같은 프레임 안 반올림 흔들림은 무시).</summary>
    private const int RewindToleranceMs = 50;

    private RaceTimeline(IReadOnlyDictionary<int, IReadOnlyList<RaceSample>> cars, int startMs, int endMs)
    {
        Cars = cars;
        StartMs = startMs;
        EndMs = endMs;
    }

    /// <summary>차 번호 → 시간 순 표본.</summary>
    public IReadOnlyDictionary<int, IReadOnlyList<RaceSample>> Cars { get; }

    public int StartMs { get; }
    public int EndMs { get; }

    /// <summary>[chunks]는 받은 순서(이어 달린 조각이면 앞 세션의 조각부터). 표본이 없으면 시작·끝 0.</summary>
    public static RaceTimeline Build(IReadOnlyList<DecodedTrackSamples> chunks)
    {
        var kept = new List<(int Car, RaceSample Sample)>();
        var last = int.MinValue;
        foreach (var chunk in chunks)
        {
            for (var i = 0; i < chunk.Count; i++)
            {
                var time = chunk.TimeMs[i];
                if (time < last - RewindToleranceMs)
                {
                    var cut = FirstAtOrAfter(kept, time);
                    kept.RemoveRange(cut, kept.Count - cut);
                }

                last = time;
                kept.Add((chunk.CarIndex[i], new RaceSample(
                    time,
                    chunk.LapDistanceM[i],
                    chunk.X[i],
                    chunk.Y?[i] ?? 0,
                    chunk.Z[i],
                    chunk.SpeedKph?[i] ?? 0,
                    chunk.Gear?[i] ?? 0,
                    chunk.Throttle?[i] ?? 0,
                    chunk.Brake?[i] ?? 0,
                    chunk.Status[i],
                    chunk.Flags2?[i] ?? 0,
                    chunk.Damage?[i] ?? 0,
                    chunk.GLateral?[i] ?? 0,
                    chunk.GLongitudinal?[i] ?? 0,
                    chunk.TyreCompound?[i] ?? 0)));
            }
        }

        var cars = kept
            .GroupBy(k => k.Car)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<RaceSample>)g.Select(k => k.Sample).ToList());
        return kept.Count == 0
            ? new RaceTimeline(cars, 0, 0)
            : new RaceTimeline(cars, kept[0].Sample.TimeMs, kept[^1].Sample.TimeMs);
    }

    /// <summary>
    /// 그 차가 결승선을 지난 시각들(랩 거리가 트랙 길이 절반 넘게 줄어든 곳의 뒤 표본). 앞서 랩 앞쪽 절반을 지난 적이 있어야 센다 —
    /// 그리드(출발선 뒤, 랩 끝 쪽 거리)에서 출발선을 처음 넘는 것은 랩을 끝낸 것이 아니다.
    /// </summary>
    public IReadOnlyList<int> CrossingsOf(int car, double trackLengthM)
    {
        var crossings = new List<int>();
        if (!Cars.TryGetValue(car, out var samples) || samples.Count == 0)
        {
            return crossings;
        }

        var half = trackLengthM / 2;
        var lapStarted = samples[0].LapDistanceM < half;
        for (var k = 1; k < samples.Count; k++)
        {
            if (samples[k - 1].LapDistanceM - samples[k].LapDistanceM > half)
            {
                if (lapStarted)
                {
                    crossings.Add(samples[k].TimeMs);
                }

                lapStarted = true;
            }
            else if (samples[k].LapDistanceM < half)
            {
                lapStarted = true;
            }
        }

        return crossings;
    }

    /// <summary>[cars]의 표본(차마다 시간 순)으로 타임라인을 만든다(그리드를 다시 만든 뒤 등).</summary>
    public static RaceTimeline FromCars(IReadOnlyDictionary<int, IReadOnlyList<RaceSample>> cars)
    {
        var all = cars.Values.Where(s => s.Count > 0).ToList();
        return all.Count == 0
            ? new RaceTimeline(cars, 0, 0)
            : new RaceTimeline(cars, all.Min(s => s[0].TimeMs), all.Max(s => s[^1].TimeMs));
    }

    /// <summary>그 차의 [timeMs]에 가장 가까운 표본(없으면 null).</summary>
    public RaceSample? SampleAt(int car, int timeMs)
    {
        if (!Cars.TryGetValue(car, out var samples) || samples.Count == 0)
        {
            return null;
        }

        var low = 0;
        var high = samples.Count - 1;
        while (low < high)
        {
            var mid = (low + high) / 2;
            if (samples[mid].TimeMs < timeMs)
            {
                low = mid + 1;
            }
            else
            {
                high = mid;
            }
        }

        if (low > 0 && Math.Abs(samples[low - 1].TimeMs - timeMs) < Math.Abs(samples[low].TimeMs - timeMs))
        {
            low--;
        }

        return samples[low];
    }

    private static int FirstAtOrAfter(List<(int Car, RaceSample Sample)> kept, int timeMs)
    {
        var low = 0;
        var high = kept.Count;
        while (low < high)
        {
            var mid = (low + high) / 2;
            if (kept[mid].Sample.TimeMs < timeMs)
            {
                low = mid + 1;
            }
            else
            {
                high = mid;
            }
        }

        return low;
    }
}
