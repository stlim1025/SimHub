namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 세션 날씨(docs/15 §3.1, 게임 원시 값 0~5와 같은 순서). 직렬화 시 문자열. 모르는 값은 null로 보낸다(매퍼가 거른다).
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
