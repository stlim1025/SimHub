using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 시즌 조회 포트(P7, 12 §7). 읽기 전용 — 모두 no tracking이다.
/// 인입용 <see cref="ISeasonRepository"/>(tracked, 쓰기 경로)와 분리한다.
/// </summary>
public interface ISeasonQueryRepository
{
    /// <summary>
    /// 내 시즌 페이지(삭제 제외). <paramref name="gameCode"/>가 있으면 그 게임만. 정렬: <c>LastSessionAt</c> 내림차순 → Id 내림차순. 총 개수 함께 반환.
    /// </summary>
    Task<(IReadOnlyList<Season> Items, int Total)> GetMyPageAsync(
        Guid userId, int skip, int take, string? gameCode = null, CancellationToken cancellationToken = default);

    /// <summary>내 시즌 1건(삭제 제외). 남의 것·없는 것은 null.</summary>
    Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default);

    /// <summary>주어진 시즌들의 활성 주말 행(시즌 Id 무관, 한 번의 쿼리).</summary>
    Task<IReadOnlyList<WeekendRow>> GetWeekendRowsAsync(
        IReadOnlyCollection<Guid> seasonIds, CancellationToken cancellationToken = default);

    /// <summary>
    /// 주어진 시즌들의 활성 세션 결과 행(한 번의 쿼리 — 시즌마다 따로 읽지 않는다).
    /// <paramref name="scoringRowsOnly"/>가 true면 레이스 세션이거나 <c>Points &gt; 0</c>인 행만 읽는다(시즌 목록용, 12 §7.3).
    /// </summary>
    Task<IReadOnlyList<SeasonResultRow>> GetResultRowsAsync(
        IReadOnlyCollection<Guid> seasonIds, bool scoringRowsOnly, CancellationToken cancellationToken = default);
}
