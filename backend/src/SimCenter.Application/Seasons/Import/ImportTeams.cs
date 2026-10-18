namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 가져오기 문서의 팀 이름 → 게임 팀 ID(docs/15 §12, D-55). 인게임 순위표가 2026 그리드(Audi·Cadillac·Lindblad)라
/// v1.26 2026 그리드 ID(220~230, D-52)를 쓴다 — F1Laps 헤더의 짧은 이름("Ferrari")도 같은 ID로 맞춘다.
/// 정식 이름("Scuderia Ferrari HP")은 들어 있는 낱말로 찾는다. 모르는 이름·"F1 Generic"은 null(팀 미상).
/// </summary>
public static class ImportTeams
{
    private const int Grid2026FirstTeamId = 220;

    // 순서 = 2026 그리드 ID 220~230(TeamCatalog: 기본 팀 0~8 순서, 229 Audi, 230 Cadillac). 각 팀의 이름 조각(정규화 후 포함 검사).
    private static readonly string[][] Keywords =
    [
        ["MERCEDES"],
        ["FERRARI"],
        ["RED BULL RACING", "ORACLE RED BULL", "RED BULL"],
        ["WILLIAMS"],
        ["ASTON MARTIN"],
        ["ALPINE"],
        ["RACING BULLS", "VISA CASH APP", "VCARB", "RB F1"],
        ["HAAS"],
        ["MCLAREN"],
        ["AUDI", "SAUBER", "KICK"],
        ["CADILLAC"],
    ];

    /// <summary>팀 이름 → 2026 그리드 팀 ID. 모르면 null.</summary>
    public static int? Resolve(string? teamName)
    {
        var normalized = DriverNameMatcher.Normalize(teamName);
        if (normalized.Length == 0)
        {
            return null;
        }

        // "Racing Bulls"가 "Red Bull" 조각에 걸리지 않게 긴 조각(Racing Bulls)을 먼저 본다.
        if (Keywords[6].Any(k => normalized.Contains(k, StringComparison.Ordinal)))
        {
            return Grid2026FirstTeamId + 6;
        }

        for (var i = 0; i < Keywords.Length; i++)
        {
            if (Keywords[i].Any(k => normalized.Contains(k, StringComparison.Ordinal)))
            {
                return Grid2026FirstTeamId + i;
            }
        }

        return null;
    }
}
