using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>AgentPairingCode 영속성 포트(1회용 연결 코드).</summary>
public interface IAgentPairingCodeRepository
{
    Task AddAsync(AgentPairingCode code, CancellationToken cancellationToken = default);

    /// <summary>사용자의 미사용(<c>ConsumedAt</c> null) 코드(추적 엔티티 — 무효화용).</summary>
    Task<IReadOnlyList<AgentPairingCode>> GetUnconsumedByUserAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>해시 충돌 확인. 고유 인덱스가 soft delete 행도 포함하므로 삭제 여부를 무시하고 조회한다.</summary>
    Task<bool> ExistsByHashAsync(string codeHash, CancellationToken cancellationToken = default);

    /// <summary>
    /// 사용 가능한 코드 조회: 삭제되지 않았고(<c>IsDeleted</c> false), 미사용이며(<c>ConsumedAt</c> null),
    /// <c>ExpiresAt &gt; nowUtc</c>인 코드.
    /// </summary>
    Task<AgentPairingCode?> GetRedeemableByHashAsync(string codeHash, DateTime nowUtc, CancellationToken cancellationToken = default);

    /// <summary>
    /// 조건부 UPDATE(<c>consumed_at IS NULL</c>일 때만 갱신)로 코드를 원자적으로 소비한다.
    /// 영향 행이 1개일 때만 true — 동시에 같은 코드를 소비하려는 요청 중 하나만 성공한다.
    /// </summary>
    Task<bool> TryConsumeAsync(Guid codeId, DateTime nowUtc, CancellationToken cancellationToken = default);
}
