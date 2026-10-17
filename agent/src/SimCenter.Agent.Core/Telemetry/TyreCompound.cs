namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 타이어 컴파운드의 화면용(visual) 분류(P7). 게임 고유 라벨(C0~C6 등)은 <see cref="TyreStint.ActualCompound"/> 문자열로 따로 둔다.
/// 백엔드 Domain의 <c>TyreCompound</c>와 이름·순서를 맞춘다. 0번(<see cref="Unknown"/>)은 "모름" 대체값이다.
/// </summary>
public enum TyreCompound
{
    Unknown = 0,
    Soft = 1,
    Medium = 2,
    Hard = 3,
    Intermediate = 4,
    Wet = 5,
}
