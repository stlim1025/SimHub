namespace SimCenter.Application.Seasons.Import.Building;

/// <summary>
/// 가져온 시즌의 드라이버 한 명: 모든 가져온 세션에서 같은 차 번호·이름을 쓴다. <see cref="Team"/> = 기본 팀(인게임 표·플레이어 헤더) —
/// F1Laps 세션 순위표에 팀 칸이 있으면 그 세션은 그 팀이다.
/// </summary>
public sealed record RosterDriver(int CarIndex, string Name, ImportTeam Team, bool IsPlayer)
{
    public int? TeamId => Team.TeamId;
}

/// <summary>
/// 가져오기 드라이버 명단(docs/15 §12, D-55). 인게임 순위표 행 순서가 차 번호(0부터)이고 팀도 그 표에서 정한다.
/// F1Laps 순위표의 이름("Lewis Hamilton", "You")은 플레이어 → 전체 이름 → 성 순서로 명단에 맞추고, 없으면 새 차 번호로 더한다.
/// 시즌 하나를 만드는 동안만 쓰는 상태 객체다.
/// </summary>
public sealed class DriverRoster
{
    private readonly List<RosterDriver> _drivers = [];

    /// <param name="teamOf">팀 칸 글자 → 팀(<see cref="ImportTeams.Of"/>, 게임 표·My Team 이름이 묶인 함수).</param>
    public DriverRoster(InGameStandingsDocument? inGame, string playerName, ImportTeam playerTeam, Func<string?, ImportTeam> teamOf)
    {
        ArgumentNullException.ThrowIfNull(playerTeam);
        ArgumentNullException.ThrowIfNull(teamOf);

        if (inGame is not null)
        {
            foreach (var row in inGame.Drivers)
            {
                var team = teamOf(row.TeamName);
                _drivers.Add(new RosterDriver(_drivers.Count, row.Name, row.IsPlayer && team.TeamId is null && playerTeam.IsKnown ? playerTeam : team, row.IsPlayer));
            }
        }

        if (!_drivers.Any(d => d.IsPlayer))
        {
            _drivers.Add(new RosterDriver(_drivers.Count, playerName, playerTeam, IsPlayer: true));
        }
    }

    public RosterDriver Player => _drivers.First(d => d.IsPlayer);

    public IReadOnlyList<RosterDriver> Drivers => _drivers;

    /// <summary>이름 → 명단의 드라이버(없으면 새로 더한다). <paramref name="isPlayer"/>면 항상 플레이어.</summary>
    public RosterDriver Resolve(string name, bool isPlayer)
    {
        if (isPlayer)
        {
            return Player;
        }

        var match = _drivers.FirstOrDefault(d => !d.IsPlayer && DriverNameMatcher.IsFullMatch(d.Name, name))
            ?? _drivers.FirstOrDefault(d => !d.IsPlayer && DriverNameMatcher.IsSurnameMatch(d.Name, name));
        if (match is not null)
        {
            return match;
        }

        var added = new RosterDriver(_drivers.Count, name, ImportTeam.None, IsPlayer: false);
        _drivers.Add(added);
        return added;
    }

    /// <summary>인게임 행 이름 → 명단 드라이버(행 순서와 같다).</summary>
    public RosterDriver OfInGameRow(int rowIndex) => _drivers[rowIndex];
}
