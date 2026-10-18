namespace SimCenter.Domain.Enums;

/// <summary>
/// 랩 끝의 날씨(15 §3.1, D-44). 이름·순서는 게임 값 0~5와 같다. DB에는 문자열로 저장한다.
/// 인입은 이 이름만 받고, 모르는 값은 저장하지 않는다(null) — 날씨 하나 때문에 스냅샷을 버리지 않는다.
/// </summary>
public enum Weather
{
    Clear = 0,
    LightCloud = 1,
    Overcast = 2,
    LightRain = 3,
    HeavyRain = 4,
    Storm = 5,
}
