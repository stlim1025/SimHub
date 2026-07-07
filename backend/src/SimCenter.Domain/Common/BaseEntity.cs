namespace SimCenter.Domain.Common;

/// <summary>
/// 모든 Entity의 공통 베이스. 헌장/03-entity-design §1 공통 규약.
/// PK는 UUID v7(Guid), 모든 시각은 UTC, Soft Delete를 표준으로 한다.
/// </summary>
public abstract class BaseEntity
{
    /// <summary>Primary Key (UUID v7). 생성은 IIdGenerator를 통해 주입한다.</summary>
    public Guid Id { get; set; }

    /// <summary>생성 시각(UTC).</summary>
    public DateTime CreatedAt { get; set; }

    /// <summary>마지막 수정 시각(UTC). 최초 생성 시 null.</summary>
    public DateTime? UpdatedAt { get; set; }

    /// <summary>Soft Delete 플래그. 전역 쿼리 필터로 자동 제외한다.</summary>
    public bool IsDeleted { get; set; }
}
