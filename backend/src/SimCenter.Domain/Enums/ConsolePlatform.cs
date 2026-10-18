namespace SimCenter.Domain.Enums;

/// <summary>
/// 사용자가 게임을 하는 플랫폼(프로필 설정, 14 §3). 지금은 저장만 하고 이후 Phase에서 쓴다.
/// DB·API에는 이름 문자열로 저장한다.
/// </summary>
public enum ConsolePlatform
{
    Pc = 0,
    Xbox = 1,
    PlayStation = 2,
}
