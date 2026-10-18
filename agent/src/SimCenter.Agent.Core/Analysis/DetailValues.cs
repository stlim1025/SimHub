using System.Collections;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// <c>car.details</c> 값 다듬기(D-49, docs/15 §8). 상세 묶음은 형이 정해지지 않은 사전이라, 직렬화 예외(NaN·무한대·순환 등)로 랩을 잃지 않게
/// 랩 끝에 한 번 <b>새 사전</b>으로 다듬는다(원본은 바꾸지 않는다): 정수·불리언·문자열은 그대로, 실수는 유한하면 소수 셋째 자리로 반올림하고 아니면 null,
/// 사전·목록은 안쪽까지(깊이 <see cref="MaxDepth"/>까지) 같은 규칙, 그 밖의 형은 null.
/// </summary>
public static class DetailValues
{
    /// <summary>중첩 허용 깊이(묶음 → 목록 → 항목 사전 → 값). 더 깊으면 null.</summary>
    public const int MaxDepth = 4;

    private const int Decimals = 3;

    public static IReadOnlyDictionary<string, object?> Sanitize(IReadOnlyDictionary<string, object?> values) =>
        SanitizeDictionary(values, depth: 1);

    private static Dictionary<string, object?> SanitizeDictionary(IReadOnlyDictionary<string, object?> values, int depth)
    {
        var sanitized = new Dictionary<string, object?>(values.Count, StringComparer.Ordinal);
        foreach (var (key, value) in values)
        {
            sanitized[key] = SanitizeValue(value, depth);
        }

        return sanitized;
    }

    private static object? SanitizeValue(object? value, int depth) => value switch
    {
        null => null,
        bool or string or int or long or short or byte or sbyte or ushort or uint => value,
        double number => Finite(number),
        float number => Finite(number),
        IReadOnlyDictionary<string, object?> nested => depth < MaxDepth ? SanitizeDictionary(nested, depth + 1) : null,
        IEnumerable items => depth < MaxDepth ? SanitizeList(items, depth + 1) : null,
        _ => null,
    };

    private static object?[] SanitizeList(IEnumerable items, int depth)
    {
        var sanitized = new List<object?>();
        foreach (var item in items)
        {
            sanitized.Add(SanitizeValue(item, depth));
        }

        return sanitized.ToArray();
    }

    private static double? Finite(double number) =>
        double.IsFinite(number) ? Math.Round(number, Decimals, MidpointRounding.AwayFromZero) : null;
}
