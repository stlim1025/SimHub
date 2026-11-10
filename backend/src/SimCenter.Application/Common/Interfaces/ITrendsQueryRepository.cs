using SimCenter.Application.Trends;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>추세 조회 포트. 읽기 전용 — 모두 no tracking, 메서드마다 쿼리 1회다. 삭제된 행은 전역 필터로 빠진다.</summary>
public interface ITrendsQueryRepository
{
    /// <summary>내 예선·레이스 세션의 결과 행(<paramref name="gameCode"/>가 있으면 그 게임만). 정렬: 세션 시각 → 세션 Id → 차 번호.</summary>
    Task<IReadOnlyList<TrendResultRow>> GetMyResultRowsAsync(
        Guid userId, string? gameCode, CancellationToken cancellationToken = default);

    /// <summary>내 랩 전부(<paramref name="gameCode"/>가 있으면 그 게임만).</summary>
    Task<IReadOnlyList<TrendLapRow>> GetMyLapsAsync(Guid userId, string? gameCode, CancellationToken cancellationToken = default);
}
