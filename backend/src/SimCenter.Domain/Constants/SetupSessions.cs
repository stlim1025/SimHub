namespace SimCenter.Domain.Constants;

/// <summary>커뮤니티 셋업의 세션 종류(출처 F1Laps 표기 그대로 저장한다). 셋업 묶음 = 게임·트랙·조건·세션 종류.</summary>
public static class SetupSessions
{
    public const string TimeTrial = "Time Trial";
    public const string Race = "Race";
    public const string Qualifying = "Qualifying";

    /// <summary>지원하는 세션 종류 전체(갱신 순서).</summary>
    public static readonly IReadOnlyList<string> All = [TimeTrial, Race, Qualifying];

    /// <summary>조건별 세션 종류: 타임 트라이얼은 마른 노면만 있다.</summary>
    public static IReadOnlyList<string> For(string condition)
        => condition == SetupConditions.Wet ? [Race, Qualifying] : All;

    /// <summary>조건의 기본 세션 종류(세션 종류를 고르지 않았을 때): 마른 노면은 타임 트라이얼, 젖은 노면은 레이스.</summary>
    public static string DefaultFor(string condition)
        => condition == SetupConditions.Wet ? Race : TimeTrial;

    /// <summary>대소문자·공백을 무시하고 표준 표기로 바꾼다(<c>timetrial</c>·<c>Time Trial</c> → <see cref="TimeTrial"/>). 모르는 값은 null.</summary>
    public static string? Normalize(string? value)
    {
        var key = value?.Replace(" ", string.Empty, StringComparison.Ordinal).Trim();
        return All.FirstOrDefault(s => string.Equals(s.Replace(" ", string.Empty, StringComparison.Ordinal), key, StringComparison.OrdinalIgnoreCase));
    }
}
