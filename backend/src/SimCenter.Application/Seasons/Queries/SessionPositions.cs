using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 세션 순위·종류 표시 규칙(순수 함수).
/// <list type="bullet">
/// <item>순위 0 이하 = 모름(가져온 예선에 Finish Position이 없으면 0으로 저장, D-55) → null.</item>
/// <item>스프린트 주말 = 그 주말에 <see cref="SessionKind.Race2"/>나 스프린트 슛아웃이 있다(<see cref="SprintWeekendMarkers"/>).
/// 그 주말의 <see cref="SessionKind.Race"/>는 스프린트, <see cref="SessionKind.Race2"/>는 본 레이스다(게임 관례).
/// 슛아웃은 스프린트 주말에만 있어서 본 레이스를 달리기 전에도 판정된다. 표시 이름은 앱이 이 플래그(<c>isSprintWeekend</c>)로 정한다.</item>
/// </list>
/// </summary>
public static class SessionPositions
{
    /// <summary>
    /// 이 종류의 세션이 한 주말에 하나라도 있으면 스프린트 주말이다. 저장소 쿼리도 같은 배열을 쓴다(<c>Contains</c> → SQL <c>IN</c>).
    /// </summary>
    public static readonly IReadOnlyList<SessionKind> SprintWeekendMarkers =
    [
        SessionKind.Race2,
        SessionKind.SprintShootout1,
        SessionKind.SprintShootout2,
        SessionKind.SprintShootout3,
        SessionKind.ShortSprintShootout,
        SessionKind.OneShotSprintShootout,
    ];

    /// <summary>순위 0 이하(모름)를 null로.</summary>
    public static int? Known(int? position) => position is > 0 ? position : null;

    /// <summary>
    /// 점수를 세는 세션인지: 레이스(스프린트 포함)만. F1 25는 스프린트 뒤 예선 결과에도 그 주말에 딴 점수를 실어 보내므로
    /// 예선·연습의 점수 칸은 더하지 않는다(더하면 같은 스프린트 점수가 예선 수만큼 다시 더해진다).
    /// </summary>
    public static bool CountsForPoints(SessionType type) => type == SessionType.Race;

    /// <summary>주말의 세션 종류들로 스프린트 주말인지.</summary>
    public static bool IsSprintWeekend(IEnumerable<SessionKind> weekendKinds) => weekendKinds.Any(SprintWeekendMarkers.Contains);

    /// <summary>
    /// 주말 안 세션 표시 순서: 연습 → 스프린트 슛아웃 → 스프린트 → 예선 → 레이스 → 그 밖. 같은 순서끼리는 시각 순(호출자가 정렬).
    /// 스프린트 주말이 아니면 <see cref="SessionKind.Race"/>는 레이스 자리다.
    /// </summary>
    public static int WeekendOrder(SessionKind kind, bool sprintWeekend) => kind switch
    {
        SessionKind.Practice1 or SessionKind.Practice2 or SessionKind.Practice3 or SessionKind.ShortPractice => 0,
        _ when kind.IsSprintShootout() => 1,
        SessionKind.Race when sprintWeekend => 2,
        _ when kind.IsGrandPrixQualifying() => 3,
        SessionKind.Race or SessionKind.Race2 or SessionKind.Race3 => 4,
        _ => 5,
    };
}
