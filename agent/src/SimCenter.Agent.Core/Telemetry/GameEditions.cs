namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 게임 코드와 에디션 판별 규칙(백엔드 <c>GameCodes</c>·<c>GameEditions</c>와 같은 값 — Agent는 백엔드를 참조하지 않는다).
/// F1 26은 F1 25의 "2026 시즌팩"이라 UDP 형식(2025)·트랙 ID가 같고, 차량의 팀 ID로만 가린다.
/// </summary>
public static class GameEditions
{
    public const string F1_25 = "F1_25";

    /// <summary>F1 25 2026 시즌팩.</summary>
    public const string F1_26 = "F1_26";

    /// <summary>2026 시즌팩 팀 ID 범위(476~484 기본 팀, 485 Audi, 486 Cadillac).</summary>
    public const int Season2026FirstTeamId = 476;
    public const int Season2026LastTeamId = 486;

    /// <summary>v1.26 2026 그리드 팀 ID 범위(220~228 기본 팀, 229 Audi, 230 Cadillac).</summary>
    public const int Grid2026FirstTeamId = 220;
    public const int Grid2026LastTeamId = 230;

    /// <summary>2026 시즌팩의 팀 ID인지.</summary>
    public static bool Is2026TeamId(int teamId) =>
        teamId is >= Season2026FirstTeamId and <= Season2026LastTeamId
        || teamId is >= Grid2026FirstTeamId and <= Grid2026LastTeamId;

    /// <summary>화면 표시 이름("F1_26" → "F1 26").</summary>
    public static string DisplayName(string gameCode) => gameCode.Replace('_', ' ');
}
