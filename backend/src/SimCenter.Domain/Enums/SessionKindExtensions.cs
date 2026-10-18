namespace SimCenter.Domain.Enums;

public static class SessionKindExtensions
{
    /// <summary>스프린트 슛아웃(스프린트 예선) 종류인지.</summary>
    public static bool IsSprintShootout(this SessionKind kind) => kind is
        SessionKind.SprintShootout1 or SessionKind.SprintShootout2 or SessionKind.SprintShootout3
        or SessionKind.ShortSprintShootout or SessionKind.OneShotSprintShootout;

    /// <summary>본 레이스 그리드를 정하는 예선(Q1~Q3·단축·원샷) 종류인지 — 슛아웃 제외.</summary>
    public static bool IsGrandPrixQualifying(this SessionKind kind) => kind is
        SessionKind.Qualifying1 or SessionKind.Qualifying2 or SessionKind.Qualifying3
        or SessionKind.ShortQualifying or SessionKind.OneShotQualifying;
}
