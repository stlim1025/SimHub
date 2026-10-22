namespace SimCenter.Domain.Constants;

/// <summary>커뮤니티 셋업의 노면 조건(F1Laps 표기 그대로). 저장·조회 필터 값이다.</summary>
public static class SetupConditions
{
    public const string Dry = "Dry";
    public const string Wet = "Wet";

    /// <summary>조건 저장 열 길이.</summary>
    public const int MaxLength = 10;

    /// <summary>지원하는 조건 전체(갱신 순서: Dry → Wet).</summary>
    public static readonly IReadOnlyList<string> All = [Dry, Wet];

    /// <summary>대소문자를 무시하고 표준 표기(<see cref="Dry"/>/<see cref="Wet"/>)로 바꾼다. 모르는 값은 null.</summary>
    public static string? Normalize(string? value)
        => All.FirstOrDefault(c => string.Equals(c, value?.Trim(), StringComparison.OrdinalIgnoreCase));
}
