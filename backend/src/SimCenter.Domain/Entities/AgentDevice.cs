using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 내 계정에 연결된 PC(Agent 장치, 11 §3.1). 연결 코드로 만들어지며 장치별 API 키로 인입을 인증한다.
/// 연결 해제 = soft delete(<see cref="BaseEntity.IsDeleted"/>).
/// </summary>
public class AgentDevice : BaseEntity
{
    public Guid UserId { get; set; }
    public User? User { get; set; }

    /// <summary>장치 이름(1~50자). 기본값은 Agent가 보낸 컴퓨터 이름.</summary>
    public required string Name { get; set; }

    /// <summary>장치 키의 SHA-256 hex. 원문 키는 저장하지 않는다. Unique.</summary>
    public required string ApiKeyHash { get; set; }

    /// <summary>마지막 이벤트 수신 시각(UTC). 수신 이력이 없으면 null.</summary>
    public DateTime? LastSeenAt { get; set; }
}
