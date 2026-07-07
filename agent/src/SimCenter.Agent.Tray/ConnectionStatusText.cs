using SimCenter.Agent.Core.Connection;

namespace SimCenter.Agent.Tray;

/// <summary>연결 상태 → 사용자 표시 문자열(신호등 이모지 + 한국어). App(트레이 툴팁)·MainWindow가 공유.</summary>
internal static class ConnectionStatusText
{
    public static string Describe(ConnectionState state) => state switch
    {
        ConnectionState.Connected => "🟢 연결됨",
        ConnectionState.Waiting => "🟡 대기 중",
        _ => "🔴 미연결",
    };
}
