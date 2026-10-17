namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>
/// unique index에 다는 부분 인덱스 필터(PostgreSQL, snake_case 열 이름). 시즌·세션 계열의 unique index는 모두 이 필터를 단다(12 §4.1) —
/// 지워진(soft delete) 행 때문에 같은 키의 새 행 삽입이 매번 unique 위반으로 실패하지 않게 한다.
/// </summary>
internal static class SoftDeleteFilters
{
    /// <summary>활성(삭제되지 않은) 행만 인덱스에 담는다.</summary>
    public const string ActiveRows = "is_deleted = false";
}
