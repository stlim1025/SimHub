namespace SimCenter.Application.Laps;

/// <summary>랩 상세·트레이스 조회 유스케이스(15 §4.2). 남의 랩·없는 랩은 같은 404다(D-34).</summary>
public interface ILapQueryService
{
    /// <summary>내 랩 상세(랩 + 트랙 국가 + 세션 연결 + 스냅샷 + 비교 대상).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">남의 랩이거나 없을 때.</exception>
    Task<LapDetailResponse> GetMyLapAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>내 랩 트레이스(7채널 복원).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">트레이스가 없거나 남의 랩일 때.</exception>
    Task<LapTraceResponse> GetMyLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);
}
