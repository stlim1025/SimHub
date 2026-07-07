namespace SimCenter.Agent.Core.Connection;

/// <summary>특정 시점의 연결 상태 스냅샷(GUI가 폴링해 표시).</summary>
public sealed record ConnectionSnapshot(
    ConnectionState State,
    DateTime? LastDatagramAt,
    double? SecondsSinceLast,
    long TotalDatagrams,
    int? DetectedPacketFormat,
    string? ListenerError);
