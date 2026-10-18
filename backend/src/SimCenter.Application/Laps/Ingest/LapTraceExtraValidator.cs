using System.Text.RegularExpressions;

namespace SimCenter.Application.Laps.Ingest;

/// <summary>
/// 트레이스 추가 채널 맵(<c>trace.extra</c>, D-49, 15 §8) 검증 — 구조·크기만 본다: 채널 수 ≤ 150, 이름 <c>^[A-Za-z0-9]{1,40}$</c>,
/// 배열 길이 = 7채널 표본 수, 유한 숫자. 채널 목록·단위는 <c>shared/telemetry/f1_25_udp_spec.md</c>가 정하고 백엔드는 해석하지 않는다.
/// 틀리면 extra만 버린다(7채널은 그대로).
/// </summary>
public static partial class LapTraceExtraValidator
{
    public const int MaxChannels = 150;
    public const int MaxNameLength = 40;

    public static IReadOnlyList<string> Validate(IReadOnlyDictionary<string, double[]?> extra, int sampleCount)
    {
        ArgumentNullException.ThrowIfNull(extra);
        var errors = new List<string>();

        if (extra.Count > MaxChannels)
        {
            errors.Add($"채널 수={extra.Count}(최대 {MaxChannels})");
            return errors;
        }

        foreach (var (name, values) in extra)
        {
            var error = ValidateChannel(name, values, sampleCount);
            if (error is not null)
            {
                errors.Add(error);
            }
        }

        return errors;
    }

    private static string? ValidateChannel(string name, double[]? values, int sampleCount)
    {
        if (!ChannelName().IsMatch(name))
        {
            return $"채널 이름 '{Shorten(name)}'(허용 영문·숫자 1~{MaxNameLength}자)";
        }

        if (values is null)
        {
            return $"{name}: 배열이 없습니다";
        }

        if (values.Length != sampleCount)
        {
            return $"{name}: 길이 {values.Length} ≠ 표본 수 {sampleCount}";
        }

        var bad = Array.FindIndex(values, v => !double.IsFinite(v));
        return bad >= 0 ? $"{name}[{bad}]: 유한한 숫자가 아닙니다" : null;
    }

    /// <summary>로그가 길어지지 않게 이름 앞부분만.</summary>
    private static string Shorten(string name) => name.Length <= MaxNameLength ? name : name[..MaxNameLength] + "…";

    [GeneratedRegex("^[A-Za-z0-9]{1,40}$", RegexOptions.CultureInvariant)]
    private static partial Regex ChannelName();
}
