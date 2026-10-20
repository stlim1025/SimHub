namespace SimCenter.Domain.Constants;

/// <summary>
/// 지원 게임 코드 상수(Magic string 회피, 헌장 Coding Convention).
/// 도메인은 게임 중립이다(D-14). F1 26은 F1 25의 "2026 시즌팩"으로, UDP 형식·트랙 ID는 F1 25와 같고
/// 2026 팀 ID(<see cref="GameEditions.Is2026TeamId"/>)로 가린다.
/// </summary>
public static class GameCodes
{
    public const string F1_25 = "F1_25";

    /// <summary>F1 25 2026 시즌팩(UDP 형식 2025, 트랙 ID 동일).</summary>
    public const string F1_26 = "F1_26";

    /// <summary>게임 코드 저장 열 길이.</summary>
    public const int MaxLength = 20;

    /// <summary>지원하는 게임 코드 전체(프로필의 선호 게임 검증, 조회 필터 검증 등).</summary>
    public static readonly IReadOnlyList<string> Supported = [F1_25, F1_26];

    /// <summary>지원하는 게임 코드인지(대소문자 구분).</summary>
    public static bool IsSupported(string code) => Supported.Contains(code, StringComparer.Ordinal);
}
