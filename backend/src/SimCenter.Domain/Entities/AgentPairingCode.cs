using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 1회용 Agent 연결 코드(11 §3.1). 정규화한 코드의 해시만 저장한다.
/// 새 코드를 발급하면 같은 사용자의 미사용 코드는 모두 무효화(soft delete)된다.
/// </summary>
public class AgentPairingCode : BaseEntity
{
    public Guid UserId { get; set; }
    public User? User { get; set; }

    /// <summary>정규화한 코드의 SHA-256 hex. 원문 코드는 저장하지 않는다. Unique(soft delete 행 포함).</summary>
    public required string CodeHash { get; set; }

    /// <summary>만료 시각(UTC). 이 시각 이후(같은 시각 포함)에는 사용할 수 없다.</summary>
    public DateTime ExpiresAt { get; set; }

    /// <summary>사용 시각(UTC). 값이 있으면 재사용 불가.</summary>
    public DateTime? ConsumedAt { get; set; }
}
