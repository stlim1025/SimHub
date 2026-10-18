using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>Lap 영속성/조회 포트. 섹터(Lap.Sectors)·스냅샷(Lap.Snapshot)은 랩과 함께 저장된다(cascade).</summary>
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
    /// 내 랩 기록 페이지(무효 랩 포함). Track/Sectors 포함, 총 개수 함께 반환.
    /// 정렬: <see cref="MyLapsSort.Recent"/> = SetAt DESC, <see cref="MyLapsSort.Fastest"/> = 유효 랩 우선 → LapTimeMs ASC → SetAt ASC.
    /// </summary>
    Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        MyLapsSort sort,
        int skip,
        int take,
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
