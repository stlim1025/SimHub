namespace SimCenter.Domain.Enums;

/// <summary>
/// 속도·거리 표시 단위(프로필 설정, 14 §3). Metric = km/h, Imperial = mph. 지금은 저장만 하고 텔레메트리 화면(P9)에서 쓴다.
/// DB·API에는 이름 문자열로 저장한다.
/// </summary>
public enum UnitSystem
{
    Metric = 0,
    Imperial = 1,
}
