using SimCenter.Domain.Constants;

namespace SimCenter.Application.Common;

/// <summary>팀의 표시 이름과 색(<c>#RRGGBB</c>).</summary>
public sealed record TeamInfo(string Name, string Color);

/// <summary>
/// 게임별 팀 이름·색 정적 카탈로그(D-33, 12 §7.4). 불변 상수 표라 헌장의 "Global Static 금지"(가변 전역 상태)에 해당하지 않는다.
/// 시즌·세션 결과와 랩 목록·상세의 팀(15 §4.2)이 함께 쓴다.
/// <see cref="GameCodes.F1_25"/>와 <see cref="GameCodes.F1_26"/>(같은 표)를 등록한다 — 2025 팀 10개, 2024 차량 10개(ID 185~), 2026 시즌팩 팀 9개(ID 476~) + Audi·Cadillac,
/// v1.26 2026 그리드(ID 220~230, docs/15 §11.1 D-52), F1 Generic(41), My Team(104). 없는 ID는 <c>Team {id}</c> + 중립 회색, 팀이 없으면 <c>Unknown Team</c> + 중립 회색.
/// </summary>
public static class TeamCatalog
{
    /// <summary>등록되지 않은 팀·팀 정보 없음의 중립 회색.</summary>
    public const string FallbackColor = "#9CA3AF";

    public const string UnknownTeamName = "Unknown Team";

    private const int Season2024FirstTeamId = 185;
    private const int Season2026FirstTeamId = 476;
    private const int Season2026TeamCount = 9;
    private const int AudiTeamId = 485;
    private const int CadillacTeamId = 486;
    private const int Grid2026FirstTeamId = 220;
    private const int Grid2026BaseTeamCount = 9;
    private const int Grid2026AudiTeamId = 229;
    private const int Grid2026CadillacTeamId = 230;
    private const int F1GenericTeamId = 41;

    /// <summary>F1 25 "My Team"(사용자가 만든 팀)의 게임 팀 ID. 표시 이름은 결과에 저장된 팀 이름(<c>TeamName</c>)이 있으면 그것이다.</summary>
    public const int MyTeamId = 104;

    /// <summary>My Team·사용자 팀 이름의 강조색.</summary>
    public const string MyTeamColor = "#6366F1";

    // 2025 팀 순서 = 게임 팀 ID 0~9. 2024 차량(185~194)과 2026 팀(476~484)은 같은 이름·색을 앞쪽부터 따라 쓴다.
    private static readonly TeamInfo[] BaseTeams =
    [
        new("Mercedes", "#27F4D2"),
        new("Ferrari", "#E8002D"),
        new("Red Bull Racing", "#3671C6"),
        new("Williams", "#64C4FF"),
        new("Aston Martin", "#229971"),
        new("Alpine", "#FF87BC"),
        new("Racing Bulls", "#6692FF"),
        new("Haas", "#B6BABD"),
        new("McLaren", "#FF8000"),
        new("Sauber", "#52E252"),
    ];

    private static readonly TeamInfo UnknownTeam = new(UnknownTeamName, FallbackColor);

    private static readonly IReadOnlyDictionary<int, TeamInfo> F125Teams = BuildF125Teams();

    /// <summary>(게임 코드, 팀 ID) → 표시 이름·색. 팀 ID가 null이면 <c>Unknown Team</c>.</summary>
    public static TeamInfo Resolve(string gameCode, int? teamId)
    {
        if (teamId is not { } id)
        {
            return UnknownTeam;
        }

        // F1 26(2026 시즌팩)은 F1 25와 같은 팀 ID 표를 쓴다.
        if ((gameCode is GameCodes.F1_25 or GameCodes.F1_26) && F125Teams.TryGetValue(id, out var team))
        {
            return team;
        }

        return new TeamInfo($"Team {id}", FallbackColor);
    }

    /// <summary>
    /// (게임 코드, 팀 ID, 저장된 팀 이름) → 표시 이름·색. 팀 ID가 없거나 My Team(<see cref="MyTeamId"/>)이고 팀 이름이 있으면
    /// 그 이름(가져온 My Team 이름 "TEAM ALPHA" 등)을 쓴다 — My Team이면 강조색, 팀 ID가 없으면 중립 회색. 그 밖에는 <see cref="Resolve(string, int?)"/>.
    /// </summary>
    public static TeamInfo Resolve(string gameCode, int? teamId, string? teamName)
    {
        if (!string.IsNullOrWhiteSpace(teamName) && teamId is null or MyTeamId)
        {
            return new TeamInfo(teamName.Trim(), teamId is null ? FallbackColor : MyTeamColor);
        }

        return Resolve(gameCode, teamId);
    }

    private static Dictionary<int, TeamInfo> BuildF125Teams()
    {
        var teams = new Dictionary<int, TeamInfo>();

        for (var i = 0; i < BaseTeams.Length; i++)
        {
            teams[i] = BaseTeams[i];
            teams[Season2024FirstTeamId + i] = BaseTeams[i];
        }

        for (var i = 0; i < Season2026TeamCount; i++)
        {
            teams[Season2026FirstTeamId + i] = BaseTeams[i];
        }

        // docs/15 §11.1 D-52: v1.26 2026 그리드 220~228 = 기본 팀 0~8 순서, 229 Audi, 230 Cadillac.
        for (var i = 0; i < Grid2026BaseTeamCount; i++)
        {
            teams[Grid2026FirstTeamId + i] = BaseTeams[i];
        }

        var audi = new TeamInfo("Audi", "#BB0A30");
        var cadillac = new TeamInfo("Cadillac", "#B5B5B5");
        teams[AudiTeamId] = audi;
        teams[CadillacTeamId] = cadillac;
        teams[Grid2026AudiTeamId] = audi;
        teams[Grid2026CadillacTeamId] = cadillac;
        teams[F1GenericTeamId] = new TeamInfo("F1 Generic", FallbackColor);
        teams[MyTeamId] = new TeamInfo("My Team", MyTeamColor);
        return teams;
    }
}
