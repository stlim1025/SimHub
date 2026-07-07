namespace SimCenter.Agent.Infrastructure.Configuration;

/// <summary>Agent 실행 설정(appsettings "Agent" 섹션). 시크릿(BackendUrl/Credential)은 P3에서 추가.</summary>
public sealed class AgentOptions
{
    public const string SectionName = "Agent";

    /// <summary>이 Agent가 담당하는 좌석 코드(서버 SimRig.RigCode와 일치).</summary>
    public string RigCode { get; set; } = string.Empty;

    /// <summary>게임 텔레메트리 UDP 포트(F1 기본 20777).</summary>
    public int UdpPort { get; set; } = 20777;

    /// <summary>대상 게임 코드(D-14).</summary>
    public string GameCode { get; set; } = "F1_25";

    /// <summary>기대 UDP 패킷 포맷(F1 25 = 2025). 불일치 패킷은 스킵(OCP, D-20).</summary>
    public int ExpectedPacketFormat { get; set; } = 2025;
}
