namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// Store 조회 포트. 랭킹 기간 경계 계산에 매장 로컬 타임존이 필요하다(D-8).
/// MVP는 단일 매장이므로 대표 매장의 타임존만 노출한다(멀티스토어 확장 시 storeId 파라미터화).
/// </summary>
public interface IStoreRepository
{
    /// <summary>대표(첫) 매장의 IANA 타임존 ID. 매장이 없으면 예외.</summary>
    Task<string> GetPrimaryTimeZoneIdAsync(CancellationToken cancellationToken = default);
}
