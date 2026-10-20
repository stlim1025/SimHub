namespace SimCenter.Domain.Constants;

/// <summary>
/// 게임 에디션 판별 규칙. F1 25 2026 시즌팩(<see cref="GameCodes.F1_26"/>)은 패킷 형식이 F1 25와 같아
/// 차량의 팀 ID로만 가릴 수 있다 — 2026 팀(476~486) 또는 v1.26 2026 그리드(220~230)가 하나라도 있으면 F1 26이다.
/// </summary>
public static class GameEditions
{
    /// <summary>2026 시즌팩 팀 ID 첫 값(476~484 기본 팀, 485 Audi, 486 Cadillac).</summary>
    public const int Season2026FirstTeamId = 476;

    /// <summary>2026 시즌팩 팀 ID 끝 값(Cadillac).</summary>
    public const int Season2026LastTeamId = 486;

    /// <summary>v1.26 2026 그리드 팀 ID 첫 값(220~228 기본 팀, 229 Audi, 230 Cadillac).</summary>
    public const int Grid2026FirstTeamId = 220;

    /// <summary>v1.26 2026 그리드 팀 ID 끝 값(Cadillac).</summary>
    public const int Grid2026LastTeamId = 230;

    /// <summary>2026 시즌팩의 팀 ID인지.</summary>
    public static bool Is2026TeamId(int teamId) =>
        teamId is >= Season2026FirstTeamId and <= Season2026LastTeamId
        || teamId is >= Grid2026FirstTeamId and <= Grid2026LastTeamId;

    /// <summary>2026 시즌팩의 팀 ID인지(null = 아님).</summary>
    public static bool Is2026TeamId(int? teamId) => teamId is { } id && Is2026TeamId(id);
}
