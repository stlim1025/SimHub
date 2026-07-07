namespace SimCenter.Agent.Core.Connection;

/// <summary>게임(UDP) 텔레메트리 수신 연결 상태. GUI 색상 매핑: 🔴/🟡/🟢.</summary>
public enum ConnectionState
{
    /// <summary>미연결(🔴): 리스너 오류이거나 오랫동안 데이터그램 없음.</summary>
    Disconnected = 0,

    /// <summary>대기/연결 중(🟡): 리스너는 떴으나 아직 수신 없음 또는 짧은 끊김.</summary>
    Waiting = 1,

    /// <summary>연결됨(🟢): 최근 데이터그램 수신 중.</summary>
    Connected = 2,
}
