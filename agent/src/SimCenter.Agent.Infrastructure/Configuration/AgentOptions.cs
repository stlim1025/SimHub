namespace SimCenter.Agent.Infrastructure.Configuration;

/// <summary>
/// Agent 실행 설정(appsettings "Agent" 섹션). 장치 키는 설정이 아니라
/// <see cref="Credentials.IDeviceCredentialStore"/>(DPAPI)에 보관한다(docs/11 §6.1·§6.2).
/// </summary>
public sealed class AgentOptions
{
    public const string SectionName = "Agent";

    /// <summary>게임 텔레메트리 UDP 포트(F1 기본 20777).</summary>
    public int UdpPort { get; set; } = 20777;

    /// <summary>대상 게임 코드(D-14).</summary>
    public string GameCode { get; set; } = "F1_25";

    /// <summary>기대 UDP 패킷 포맷(F1 25 = 2025). 불일치 패킷은 스킵(OCP, D-20).</summary>
    public int ExpectedPacketFormat { get; set; } = 2025;

    /// <summary>
    /// 서버 기본 주소(예: http://localhost:5284). 연결 API·TelemetryHub 주소는 <see cref="AgentEndpoints"/>로 만든다.
    /// 비면 업로드 비활성(이벤트는 Outbox에 계속 적재된다).
    /// </summary>
    public string ServerBaseUrl { get; set; } = string.Empty;

    /// <summary>Outbox SQLite 파일 경로(앱 실행 디렉터리 기준).</summary>
    public string OutboxPath { get; set; } = "outbox.db";
}
