namespace SimCenter.Application.Laps.Ingest;

/// <summary>
/// 트레이스 검증(15 §5): <c>resolutionM</c> 1~50, 배열 7개가 모두 있고 길이가 같으며 2~5,000,
/// 값 범위(시간 0~3,600,000 · 속도 0~500 · 스로틀/브레이크 0~100 · 스티어 −100~100 · 기어 −1~9 · RPM 0~25,000).
/// 틀린 값의 설명 목록을 돌려준다(비면 통과). 틀리면 트레이스만 버린다.
/// </summary>
public static class LapTraceValidator
{
    public const int MinResolutionM = 1;
    public const int MaxResolutionM = 50;
    public const int MinSamples = 2;
    public const int MaxSamples = 5_000;

    public const int MaxTimeMs = 3_600_000;
    public const int MaxSpeedKph = 500;
    public const int MaxPedalPercent = 100;
    public const int MaxSteer = 100;
    public const int MinGear = -1;
    public const int MaxGear = 9;
    public const int MaxRpm = 25_000;

    public static IReadOnlyList<string> Validate(LapTracePayload trace)
    {
        ArgumentNullException.ThrowIfNull(trace);
        var errors = new List<string>();

        if (trace.ResolutionM is not (>= MinResolutionM and <= MaxResolutionM))
        {
            errors.Add($"resolutionM={trace.ResolutionM?.ToString() ?? "null"}(허용 {MinResolutionM}~{MaxResolutionM})");
        }

        var channels = Channels(trace);
        var missing = channels.Where(c => c.Values is null).Select(c => c.Name).ToList();
        if (missing.Count > 0)
        {
            errors.Add($"채널 없음: {string.Join(", ", missing)}");
            return errors;
        }

        var lengths = channels.Select(c => c.Values!.Length).Distinct().ToList();
        if (lengths.Count > 1)
        {
            errors.Add($"채널 길이가 다릅니다: {string.Join(", ", channels.Select(c => $"{c.Name}={c.Values!.Length}"))}");
            return errors;
        }

        if (lengths[0] is < MinSamples or > MaxSamples)
        {
            errors.Add($"표본 수={lengths[0]}(허용 {MinSamples}~{MaxSamples})");
            return errors;
        }

        foreach (var channel in channels)
        {
            CheckRange(errors, channel);
        }

        return errors;
    }

    private static (string Name, int[]? Values, int Min, int Max)[] Channels(LapTracePayload trace) =>
    [
        ("timeMs", trace.TimeMs, 0, MaxTimeMs),
        ("speedKph", trace.SpeedKph, 0, MaxSpeedKph),
        ("throttle", trace.Throttle, 0, MaxPedalPercent),
        ("brake", trace.Brake, 0, MaxPedalPercent),
        ("steer", trace.Steer, -MaxSteer, MaxSteer),
        ("gear", trace.Gear, MinGear, MaxGear),
        ("rpm", trace.Rpm, 0, MaxRpm),
    ];

    /// <summary>범위를 벗어난 첫 표본만 알린다(로그가 길어지지 않게).</summary>
    private static void CheckRange(List<string> errors, (string Name, int[]? Values, int Min, int Max) channel)
    {
        var values = channel.Values!;
        for (var i = 0; i < values.Length; i++)
        {
            if (values[i] < channel.Min || values[i] > channel.Max)
            {
                errors.Add($"{channel.Name}[{i}]={values[i]}(허용 {channel.Min}~{channel.Max})");
                return;
            }
        }
    }
}
