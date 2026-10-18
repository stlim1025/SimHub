using System.Globalization;

namespace SimCenter.Application.Profile;

/// <summary>
/// 사용자 타임존 ID 검증·정규화(14 §5). 이 서버가 찾을 수 있는 <b>IANA</b> ID만 받는다 —
/// Windows ID("Korea Standard Time")는 OS마다 달라 저장하지 않는다.
/// 저장 값은 <see cref="TimeZoneInfo.TryFindSystemTimeZoneById"/>가 돌려준 <see cref="TimeZoneInfo.Id"/>(정식 표기)다.
/// </summary>
public static class IanaTimeZones
{
    private static readonly char[] SegmentSeparators = ['/', '_', '-'];

    public static bool IsValid(string? timeZoneId) => TryCanonicalize(timeZoneId, out _);

    /// <summary>
    /// 찾을 수 있는 IANA ID면 정식 표기(예: <c>asia/seoul</c> → <c>Asia/Seoul</c>)를 돌려준다.
    /// 런타임의 대소문자 처리는 캐시 여부에 따라 달라서, 그대로 못 찾으면 구간마다 첫 글자만 대문자로 바꾼 후보로 한 번 더 찾는다.
    /// </summary>
    public static bool TryCanonicalize(string? timeZoneId, out string canonical)
    {
        canonical = string.Empty;
        if (string.IsNullOrWhiteSpace(timeZoneId))
        {
            return false;
        }

        var trimmed = timeZoneId.Trim();
        foreach (var candidate in new[] { trimmed, TitleCaseSegments(trimmed) })
        {
            if (TimeZoneInfo.TryFindSystemTimeZoneById(candidate, out var zone) && zone.HasIanaId)
            {
                canonical = zone.Id;
                return true;
            }
        }

        return false;
    }

    /// <summary><c>america/new_york</c> → <c>America/New_York</c>: 구분자(<c>/ _ -</c>) 다음 글자만 대문자, 나머지는 소문자.</summary>
    private static string TitleCaseSegments(string value)
    {
        var chars = value.ToLowerInvariant().ToCharArray();
        for (var i = 0; i < chars.Length; i++)
        {
            if (i == 0 || Array.IndexOf(SegmentSeparators, chars[i - 1]) >= 0)
            {
                chars[i] = char.ToUpper(chars[i], CultureInfo.InvariantCulture);
            }
        }

        return new string(chars);
    }
}
