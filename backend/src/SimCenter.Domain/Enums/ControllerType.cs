namespace SimCenter.Domain.Enums;

/// <summary>
/// 사용자가 주로 쓰는 입력 장치(프로필 설정, 14 §3). 지금은 저장만 하고 이후 Phase(분석·필터)에서 쓴다.
/// DB·API에는 이름 문자열로 저장한다.
/// </summary>
public enum ControllerType
{
    Gamepad = 0,
    Wheel = 1,
}
