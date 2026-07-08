using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>Lap 영속성/조회 포트. 섹터는 Lap.Sectors로 함께 저장된다(cascade).</summary>
public interface ILapRepository
{
    Task AddAsync(Lap lap, CancellationToken cancellationToken = default);

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

    /// <summary>내 랩 기록 페이지(무효 랩 포함, setAt DESC). Track/Sectors 포함. 총 개수 함께 반환.</summary>
    Task<(IReadOnlyList<Lap> Items, int Total)> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        int skip,
        int take,
        CancellationToken cancellationToken = default);

    /// <summary>사용자의 트랙·게임 개인 최고(랭킹적격) 랩. 없으면 null. PB 판정/조회 공용.</summary>
    Task<Lap?> GetPersonalBestLapAsync(
        Guid userId,
        Guid trackId,
        string gameCode,
        CancellationToken cancellationToken = default);
}
