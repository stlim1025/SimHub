using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>SimRig 영속성 포트. 체크인·텔레메트리 인입이 RigCode로 좌석을 조회한다.</summary>
public interface ISimRigRepository
{
    Task<SimRig?> GetByRigCodeAsync(string rigCode, CancellationToken cancellationToken = default);

    /// <summary>API Key 해시로 좌석을 조회한다(Agent 인증, D-21).</summary>
    Task<SimRig?> GetByApiKeyHashAsync(string apiKeyHash, CancellationToken cancellationToken = default);
}
