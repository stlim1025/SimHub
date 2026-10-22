using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>내 트랙 통계 원시 값. 해당 랩·세션이 없으면 null.</summary>
/// <param name="LapCount">내 랩 수(무효 포함).</param>
/// <param name="SessionCount">랩이 있는 내 세션 수(세션 키 기준).</param>
/// <param name="BestLapMs">유효 랩 최고.</param>
/// <param name="BestTimeTrialLapMs">랭킹 적격(Time Trial) 랩 최고.</param>
/// <param name="AverageLapMs">유효 랩 평균.</param>
/// <param name="AverageAiDifficulty">이 트랙에서 기록된(가져오지 않은) 내 세션의 AI 난이도 평균(0 제외).</param>
public sealed record TrackMyStatsRow(
    int LapCount,
    int SessionCount,
    int? BestLapMs,
    int? BestTimeTrialLapMs,
    double? AverageLapMs,
    double? AverageAiDifficulty);

/// <summary>트랙 전체 기간 Time Trial 순위 한 줄(사용자별 최고 랭킹 적격 랩).</summary>
public sealed record TrackTopLapRow(
    Guid UserId,
    string DisplayName,
    bool ShowOnLeaderboard,
    Guid LapId,
    int LapTimeMs,
    int? TeamId);

/// <summary>내 랩 한 줄(트랙 개요의 내 최고 랩 목록).</summary>
public sealed record TrackMyLapRow(Guid LapId, int LapTimeMs, SessionType SessionType, int? TeamId, bool IsValid, DateTime SetAt);

/// <summary>트레이스가 있는 내 랩(빠른 순)과 그 트레이스 blob.</summary>
public sealed record TrackTracedLapRow(Guid LapId, byte[] Payload);

/// <summary>트랙 개요 화면 전용 읽기 포트(no tracking).</summary>
public interface ITrackOverviewQueryRepository
{
    Task<TrackMyStatsRow> GetMyStatsAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 전체 기간 사용자별 최고 랭킹 적격 Time Trial 랩 상위 <paramref name="top"/>(랩타임 → 먼저 세운 순). 랭킹(<c>GetRankingAsync</c>)과 같은 적격 기준.
    /// </summary>
    Task<IReadOnlyList<TrackTopLapRow>> GetTopTimeTrialAsync(
        Guid trackId, string gameCode, int top, CancellationToken cancellationToken = default);

    /// <summary>내 유효 랩 빠른 순 <paramref name="take"/>개.</summary>
    Task<IReadOnlyList<TrackMyLapRow>> GetMyBestLapsAsync(
        Guid userId, Guid trackId, int take, CancellationToken cancellationToken = default);

    /// <summary>트레이스가 있는 내 랩 빠른 순(유효 랩 우선) <paramref name="take"/>개와 트레이스.</summary>
    Task<IReadOnlyList<TrackTracedLapRow>> GetMyTracedLapsAsync(
        Guid userId, Guid trackId, int take, CancellationToken cancellationToken = default);
}
