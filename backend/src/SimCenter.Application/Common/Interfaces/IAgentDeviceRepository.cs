using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>AgentDevice 영속성 포트(내 계정에 연결된 PC). 해제된(soft delete) 장치는 조회되지 않는다.</summary>
public interface IAgentDeviceRepository
{
    Task AddAsync(AgentDevice device, CancellationToken cancellationToken = default);

    /// <summary>Id로 장치 조회(추적 엔티티 — 해제 등 수정용).</summary>
    Task<AgentDevice?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>장치 키 해시로 조회(인입 인증용).</summary>
    Task<AgentDevice?> GetByApiKeyHashAsync(string hash, CancellationToken cancellationToken = default);

    /// <summary>사용자의 장치 목록(생성 시각 내림차순).</summary>
    Task<IReadOnlyList<AgentDevice>> GetByUserAsync(Guid userId, CancellationToken cancellationToken = default);
}
