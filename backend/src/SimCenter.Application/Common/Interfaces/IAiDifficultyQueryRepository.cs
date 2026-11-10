using SimCenter.Application.Seasons.AiDifficulty;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// AI 난이도 가이드 조회 포트. 읽기 전용 — 모두 no tracking, 메서드마다 쿼리 1회다.
/// 시즌 Id는 호출자가 사용자 조건으로 찾은 내 시즌의 Id만 넘긴다.
/// </summary>
public interface IAiDifficultyQueryRepository
{
    /// <summary>시즌의 예선·레이스 세션 결과 행(가져온 세션 제외, 주말이 있는 세션만). 정렬: 세션 시각 → 세션 Id → 차 번호.</summary>
    Task<IReadOnlyList<AiPaceRow>> GetPaceRowsAsync(Guid seasonId, CancellationToken cancellationToken = default);

    /// <summary>주어진 세션 키들에서 내가 달린 랩의 끝 날씨(스냅샷에 날씨가 있는 랩만).</summary>
    Task<IReadOnlyList<SessionLapWeatherRow>> GetMyLapWeatherAsync(
        Guid userId, IReadOnlyCollection<string> sessionKeys, CancellationToken cancellationToken = default);

    /// <summary>주어진 트랙들의 내 유효한 타임트라이얼 랩(게임 코드가 같은 것만).</summary>
    Task<IReadOnlyList<TimeTrialLapRow>> GetMyTimeTrialLapsAsync(
        Guid userId, string gameCode, IReadOnlyCollection<Guid> trackIds, CancellationToken cancellationToken = default);
}
