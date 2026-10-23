namespace SimCenter.Application.Laps;

/// <summary>랩 상세·트레이스 조회 유스케이스(15 §4.2, §10). 남의 랩·없는 랩은 같은 404다(D-34).</summary>
public interface ILapQueryService
{
    /// <summary>
    /// 내 랩 상세(랩 + 트랙 국가 + 세션 연결 + 스냅샷 + 어시스트 + 비교 대상). <paramref name="comparison"/>이 null이면 내 최고 유효 랩과 비교(D-51 기본).
    /// </summary>
    /// <exception cref="Common.Exceptions.NotFoundException">남의 랩이거나 없을 때.</exception>
    /// <exception cref="Common.Exceptions.ValidationException">모르는 비교 종류, <c>compare=lap</c>인데 <c>compareLapId</c>가 없을 때.</exception>
    Task<LapDetailResponse> GetMyLapAsync(
        Guid userId, Guid lapId, LapComparisonRequest? comparison = null, CancellationToken cancellationToken = default);

    /// <summary>내 랩 트레이스(7채널 복원).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">트레이스가 없거나 남의 랩일 때.</exception>
    Task<LapTraceResponse> GetMyLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 공유 링크로 보는 랩 상세(로그인 없음, 주인 무관). 주인 이름은 랭킹과 같은 공개 규칙(D-39).
    /// <paramref name="compareLapId"/>가 같은 트랙·게임의 지우지 않은 다른 랩이면 비교 대상으로 싣고, 아니면 비교 없이 돌려준다.
    /// </summary>
    /// <exception cref="Common.Exceptions.NotFoundException">지운 랩이거나 없을 때.</exception>
    Task<PublicLapDetailResponse> GetPublicLapAsync(
        Guid lapId, Guid? compareLapId = null, CancellationToken cancellationToken = default);

    /// <summary>공유 링크로 보는 랩의 트레이스(로그인 없음).</summary>
    /// <exception cref="Common.Exceptions.NotFoundException">트레이스가 없거나 지운·없는 랩일 때.</exception>
    Task<LapTraceResponse> GetPublicLapTraceAsync(Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 비교 랩 트레이스(docs/15 §10, D-51): 내 랩이거나 남의 랭킹 적격 랩일 때만. 남의 비공개 랩은 없는 것과 같다.
    /// </summary>
    /// <exception cref="Common.Exceptions.NotFoundException">트레이스가 없거나 비교할 수 없는 랩일 때.</exception>
    Task<LapTraceResponse> GetComparableLapTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);
}
