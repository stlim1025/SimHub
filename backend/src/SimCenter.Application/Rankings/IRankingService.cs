using SimCenter.Domain.Enums;

namespace SimCenter.Application.Rankings;

/// <summary>랭킹/트랙/내 랩 조회 유스케이스(04 §3.7~3.9). 실시간 갱신은 <see cref="Notifications.IRankingNotifier"/>가 담당.</summary>
public interface IRankingService
{
    /// <summary>트랙·기간별 TOP N(Time Trial·랭킹적격만). date 미지정 시 매장 로컬 "오늘" 기준.</summary>
    Task<RankingSnapshotDto> GetRankingAsync(
        Guid trackId,
        string gameCode,
        RankingPeriod period,
        DateOnly? date,
        CancellationToken cancellationToken = default);

    /// <summary>트랙 마스터 목록(04 §3.8).</summary>
    Task<TrackListResponse> GetTracksAsync(CancellationToken cancellationToken = default);

    /// <summary>내 랩 기록(무효 랩 포함). trackId 지정 시 해당 트랙 개인 최고를 함께 반환.</summary>
    Task<MyLapsResponse> GetMyLapsAsync(
        Guid userId,
        Guid? trackId,
        SessionType? sessionType,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default);
}
