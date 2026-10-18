using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// Lap 영속성/랭킹 조회 포트. 섹터(Lap.Sectors)·스냅샷(Lap.Snapshot)은 랩과 함께 저장된다(cascade).
/// 내 랩 목록·상세 조회는 <see cref="ILapQueryRepository"/>가 맡는다.
/// </summary>
public interface ILapRepository
{
    Task AddAsync(Lap lap, CancellationToken cancellationToken = default);

    /// <summary>랩의 텔레메트리 트레이스를 추적에 더한다(D-45). 저장은 랩과 같은 커밋(호출자의 SaveChanges)으로 한다.</summary>
    Task AddTraceAsync(LapTelemetryTrace trace, CancellationToken cancellationToken = default);

    /// <summary>
    /// 트랙·기간·세션타입별 유저별 최고 랩 상위 N(랭킹적격만, lapTimeMs ASC). 04 §3.7 / 05 §3.4.
    /// 기간은 [fromUtc, toUtc) 반열림 구간(SetAt 기준).
    /// </summary>
    Task<IReadOnlyList<RankingLapRow>> GetRankingAsync(
        Guid trackId,
        string gameCode,
        SessionType sessionType,
        DateTime fromUtc,
        DateTime toUtc,
        int top,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// 내 랩을 트랙별로 묶은 요약(무효 랩 포함 개수, 유효 랩 최고 랩타임, 마지막 SetAt). LastSetAt 내림차순.
    /// </summary>
    Task<IReadOnlyList<MyTrackSummaryRow>> GetMyTrackSummariesAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    /// <summary>사용자의 트랙·게임 개인 최고(랭킹적격) 랩. 없으면 null. PB 판정/조회 공용.</summary>
    Task<Lap?> GetPersonalBestLapAsync(
        Guid userId,
        Guid trackId,
        string gameCode,
        CancellationToken cancellationToken = default);
}
