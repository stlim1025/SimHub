using SimCenter.Application.Common;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 가져온 결과 한 줄의 팀(D-55): 게임 팀 ID와, 표로 풀 수 없는 사용자 팀 이름(My Team "TEAM ALPHA" 등 — 없으면 null).
/// </summary>
public sealed record ImportTeam(int? TeamId, string? TeamName)
{
    /// <summary>팀 정보 없음.</summary>
    public static readonly ImportTeam None = new(null, null);

    public bool IsKnown => TeamId is not null || TeamName is not null;
}

/// <summary>
/// 가져오기 문서의 팀 이름 → 게임 팀 ID(docs/15 §12, D-55). 정식 이름("Scuderia Ferrari HP")은 들어 있는 낱말로 찾는다.
/// <list type="bullet">
/// <item>F1 25 그리드(F1Laps 내보내기 "Kick Sauber"·"Haas F1 Team" 등) = F1 25 팀 ID 0~9(<see cref="TeamCatalog"/> 기본 팀 순서, Kick·Sauber = Sauber).</item>
/// <item>2026 그리드(<see cref="GameCodes.F1_26"/>, 또는 Audi·Cadillac이 있는 인게임 순위표 — <see cref="TeamGameOf"/>) = v1.26 2026 그리드 ID 220~230(D-52).</item>
/// <item>"My Team"·My Team 모드 헤더의 팀 이름 = My Team(104) + 그 이름. "F1 Generic" = 팀 정보 없음. 모르는 이름은 ID 없이 이름만 남긴다.</item>
/// </list>
/// </summary>
public static class ImportTeams
{
    private const int Grid2026FirstTeamId = 220;
    private const int RacingBullsIndex = 6;
    private const int CadillacIndex = 10;
    private const string MyTeamText = "MY TEAM";
    private const string GenericText = "F1 GENERIC";
    private const char HighlightMark = '*';

    // 순서 = 2026 그리드 ID 220~230(TeamCatalog: 기본 팀 0~8 순서, 229 Audi, 230 Cadillac) = F1 25 팀 ID 0~9(9 = Sauber). 각 팀의 이름 조각(정규화 후 포함 검사).
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

    // 2026 그리드에만 있는 팀 이름 조각 — 인게임 순위표가 2026 시즌팩인지 가린다.
    private static readonly string[] Grid2026Markers = ["AUDI", "CADILLAC"];

    /// <summary>
    /// 팀 이름 → 게임 팀 ID. <paramref name="gameCode"/>가 <see cref="GameCodes.F1_26"/>면 2026 그리드(220~230), 아니면 F1 25 팀(0~9 —
    /// Cadillac은 없다). 모르면 null.
    /// </summary>
    public static int? Resolve(string gameCode, string? teamName)
    {
        var normalized = DriverNameMatcher.Normalize(teamName);
        if (normalized.Length == 0)
        {
            return null;
        }

        var index = IndexOf(normalized);
        if (index is not { } i)
        {
            return null;
        }

        if (gameCode == GameCodes.F1_26)
        {
            return Grid2026FirstTeamId + i;
        }

        return i < CadillacIndex ? i : null;
    }

    /// <summary>
    /// 결과·순위표 칸의 팀 글자 → 팀. 끝의 <c>*</c>(F1Laps의 내 팀 표시)는 뗀다. "My Team"과 <paramref name="myTeamName"/>(My Team 모드의
    /// 헤더 팀 이름)은 그 이름의 My Team(104)이다 — 단 그 이름이 실제 팀이면 그 팀. 표에 없는 이름은 ID 없이 이름만.
    /// </summary>
    public static ImportTeam Of(string gameCode, string? text, string? myTeamName)
    {
        var name = Clean(text);
        if (name is null)
        {
            return ImportTeam.None;
        }

        var normalized = DriverNameMatcher.Normalize(name);
        if (normalized == GenericText)
        {
            // F1Laps가 팀을 모를 때 쓰는 값 — 팀 정보 없음(다른 문서의 팀을 쓴다).
            return ImportTeam.None;
        }

        var myName = Clean(myTeamName);
        if (normalized == MyTeamText)
        {
            if (myName is null)
            {
                return new ImportTeam(TeamCatalog.MyTeamId, null);
            }

            return Resolve(gameCode, myName) is { } realId ? new ImportTeam(realId, null) : new ImportTeam(TeamCatalog.MyTeamId, myName);
        }

        if (Resolve(gameCode, name) is { } id)
        {
            return new ImportTeam(id, null);
        }

        return myName is not null && normalized == DriverNameMatcher.Normalize(myName)
            ? new ImportTeam(TeamCatalog.MyTeamId, myName)
            : new ImportTeam(null, name);
    }

    /// <summary>
    /// 팀 ID 표를 고를 게임 코드: 묶음의 게임 코드, 단 인게임 순위표에 2026 그리드 팀(Audi·Cadillac)이 있으면 <see cref="GameCodes.F1_26"/>
    /// (F1 25에서 2026 시즌팩을 달린 순위표 — v1.26 2026 그리드 ID를 쓴다).
    /// </summary>
    public static string TeamGameOf(ImportBundle bundle)
    {
        ArgumentNullException.ThrowIfNull(bundle);

        var inGameTeams = bundle.InGame is { } inGame
            ? inGame.Drivers.Select(d => d.TeamName).Concat(inGame.Constructors.Select(c => c.TeamName))
            : [];
        var grid2026 = inGameTeams
            .Select(DriverNameMatcher.Normalize)
            .Any(t => Grid2026Markers.Any(m => t.Contains(m, StringComparison.Ordinal)));
        return grid2026 ? GameCodes.F1_26 : bundle.GameCode;
    }

    private static int? IndexOf(string normalized)
    {
        // "Racing Bulls"가 "Red Bull" 조각에 걸리지 않게 긴 조각(Racing Bulls)을 먼저 본다.
        if (Keywords[RacingBullsIndex].Any(k => normalized.Contains(k, StringComparison.Ordinal)))
        {
            return RacingBullsIndex;
        }

        for (var i = 0; i < Keywords.Length; i++)
        {
            if (Keywords[i].Any(k => normalized.Contains(k, StringComparison.Ordinal)))
            {
                return i;
            }
        }

        return null;
    }

    /// <summary>앞뒤 공백과 끝의 <c>*</c>를 뗀 이름(저장 길이 <see cref="SessionResult.TeamNameMaxLength"/>까지). 비면 null.</summary>
    private static string? Clean(string? text)
    {
        var trimmed = text?.Trim().TrimEnd(HighlightMark).Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        return trimmed.Length > SessionResult.TeamNameMaxLength ? trimmed[..SessionResult.TeamNameMaxLength] : trimmed;
    }
}
