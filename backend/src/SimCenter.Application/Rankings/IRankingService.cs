using SimCenter.Domain.Enums;

namespace SimCenter.Application.Rankings;

/// <summary>랭킹/트랙/내 랩 조회 유스케이스(04 §3.7~3.9). 실시간 갱신은 <see cref="Notifications.IRankingNotifier"/>가 담당.</summary>
public interface IRankingService
{
    /// <summary>트랙·기간별 TOP N(Time Trial·랭킹적격만). date 미지정 시 랭킹 타임존(D-27)의 "오늘" 기준.</summary>
    Task<RankingSnapshotDto> GetRankingAsync(
        Guid trackId,
        string gameCode,
        RankingPeriod period,
        DateOnly? date,
        CancellationToken cancellationToken = default);

    /// <summary>트랙 마스터 목록(04 §3.8). <paramref name="gameCode"/>가 있으면 그 게임의 트랙만.</summary>
    Task<TrackListResponse> GetTracksAsync(string? gameCode = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// 내 랩 기록(무효 랩 포함, <paramref name="validOnly"/>면 유효 랩만). trackId 지정 시 해당 트랙 개인 최고를 함께 반환.
    /// sort로 최근 순/빠른 순을 고른다.
    /// </summary>
    Task<MyLapsResponse> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        bool validOnly,
        MyLapsSort sort,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// 내 트랙별 요약(랩 수·유효 랩 최고·마지막 세운 시각). 마지막으로 랩을 세운 트랙이 먼저 온다(11 §8).
    /// <paramref name="gameCode"/>가 있으면 그 게임의 트랙만.
    /// </summary>
    Task<MyTracksResponse> GetMyTracksAsync(Guid userId, string? gameCode = null, CancellationToken cancellationToken = default);
}
