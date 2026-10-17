namespace SimCenter.Domain.Enums;

/// <summary>
/// 타이어 컴파운드의 화면용(visual) 분류(P7). 게임 고유 라벨(C1~C6 등)은 별도 문자열로 따로 둔다.
/// 0번(<see cref="Unknown"/>)은 "모름" 대체값이다. Agent.Core의 같은 이름 enum과 이름·순서를 맞춘다. DB에는 문자열로 저장한다.
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
