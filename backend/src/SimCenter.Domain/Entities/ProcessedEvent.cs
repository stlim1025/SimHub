namespace SimCenter.Domain.Entities;

/// <summary>
/// 텔레메트리 인입 멱등 원장. Agent가 생성한 EventId(멱등키)로 중복 처리를 막는다(effectively-once).
/// BaseEntity가 아니다 — Soft Delete/수정 대상이 아닌 추가 전용 원장이며 PK는 EventId 자체다.
/// </summary>
public class ProcessedEvent
{
    /// <summary>Agent 멱등키(PK).</summary>
    public Guid EventId { get; set; }

    /// <summary>이벤트 타입(진단용).</summary>
    public required string EventType { get; set; }

    /// <summary>처리 완료 시각(UTC).</summary>
    public DateTime ProcessedAt { get; set; }
}
