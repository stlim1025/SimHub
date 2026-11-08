namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Agent가 읽는 UDP 형식(헤더의 <c>m_packetFormat</c>). 게임의 텔레메트리 설정에서 고른다 — 이미 F1 25를 하던 저장 데이터는 2025, 새로 깐 게임은 2026이 기본이다.
/// 2025는 F1Game.UDP 25.1.1이 그대로 해석하고, 2026(2026 시즌팩 배치, 24대)은 <see cref="Season2026Wire"/>가 2025 구조체로 옮겨 같은 매핑을 탄다.
/// </summary>
public static class F1PacketFormats
{
    public const int Season2025 = 2025;
    public const int Season2026 = 2026;

    /// <summary>화면·로그에 보이는 지원 형식 목록.</summary>
    public const string SupportedLabel = "2025·2026";

    public static bool IsSupported(int packetFormat) => packetFormat is Season2025 or Season2026;
}
