using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>텔레메트리 멱등 원장 포트. eventId 중복 여부 확인 및 처리 기록.</summary>
public interface IProcessedEventRepository
{
    Task<bool> ExistsAsync(Guid eventId, CancellationToken cancellationToken = default);

    Task AddAsync(ProcessedEvent processedEvent, CancellationToken cancellationToken = default);
}
