using SimCenter.Application.Common;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// Penalties 카드 행 만들기(docs/15 §11.3·§11.4, D-53). 원천 = 세션에 연결된 내 랩들의 <c>details.events</c> 중 PENA. 순수 계산.
/// <list type="bullet">
/// <item>랩 = 이벤트의 <c>lapNumber</c>(없으면 그 이벤트가 실린 내 랩 번호). 차 번호가 없는 이벤트는 버린다.</item>
/// <item>같은 (랩, 차, 침해, 벌칙)은 한 번만(재전송·중복 수집 방어). 순서 = 랩 → 받은 순서.</item>
/// <item>드라이버 = 순위표의 같은 carIndex 행(이름 규칙은 결과표와 같다). 행이 없으면 <c>Car {n+1}</c> + 중립 회색.</item>
/// </list>
/// </summary>
public static class SessionPenaltiesBuilder
{
    /// <summary>UDP <c>time</c> 칸의 "해당 없음" 값.</summary>
    private const int NotApplicableTime = 255;

    public static IReadOnlyList<SessionPenaltyDto> Build(
        string gameCode,
        int? playerCarIndex,
        IReadOnlyList<SessionResult> results,
        IReadOnlyList<MySessionLap> myLaps)
    {
        ArgumentNullException.ThrowIfNull(results);
        ArgumentNullException.ThrowIfNull(myLaps);

        var resultByCar = results.GroupBy(r => r.CarIndex).ToDictionary(g => g.Key, g => g.First());
        var seen = new HashSet<(int Lap, int Car, int? Infringement, int? Penalty)>();
        var rows = new List<SessionPenaltyDto>();

        foreach (var lap in myLaps.OrderBy(l => l.LapNumber).ThenBy(l => l.Row.SetAt))
        {
            foreach (var penalty in lap.Penalties)
            {
                if (penalty.VehicleIndex is not { } carIndex)
                {
                    continue;
                }

                var lapNumber = penalty.LapNumber is > 0 ? penalty.LapNumber.Value : lap.LapNumber;
                if (!seen.Add((lapNumber, carIndex, penalty.InfringementType, penalty.PenaltyType)))
                {
                    continue;
                }

                rows.Add(ToDto(gameCode, playerCarIndex, resultByCar.GetValueOrDefault(carIndex), lapNumber, carIndex, penalty));
            }
        }

        // 안정 정렬: 같은 랩 안에서는 받은 순서를 지킨다.
        return rows.OrderBy(r => r.Lap).ToList();
    }

    private static SessionPenaltyDto ToDto(
        string gameCode, int? playerCarIndex, SessionResult? driver, int lapNumber, int carIndex, PenaltyEvent penalty)
    {
        var team = driver is null ? new TeamInfo(TeamCatalog.UnknownTeamName, TeamCatalog.FallbackColor) : TeamCatalog.Resolve(gameCode, driver.TeamId);

        return new SessionPenaltyDto(
            lapNumber,
            carIndex,
            DriverLabels.Name(driver?.DriverName, carIndex),
            driver?.IsPlayer ?? carIndex == playerCarIndex,
            team.Color,
            PenaltyCatalog.InfringementName(penalty.InfringementType),
            PenaltyCatalog.PenaltyName(penalty.PenaltyType),
            penalty.TimeS is > 0 and < NotApplicableTime ? penalty.TimeS : null,
            penalty.InfringementType,
            penalty.PenaltyType);
    }
}
