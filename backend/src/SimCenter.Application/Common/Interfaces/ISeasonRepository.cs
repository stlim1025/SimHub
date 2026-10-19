using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 시즌·주말 영속성 포트(P7, 12 §4.1). 조회는 추적(tracked)된 엔티티를 돌려주어,
/// 호출자가 바꾼 범위(Touch)가 인입 커밋에 함께 저장된다. 저장 호출은 <see cref="IUnitOfWork"/>가 한다.
/// </summary>
public interface ISeasonRepository
{
    /// <summary>키 (UserId, GameCode, SeasonLinkId)로 시즌 조회(삭제 제외, tracked). 없으면 null.</summary>
    Task<Season?> GetByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 같은 키의 지운(soft delete) 시즌 중 가장 최근에 지운 것(tracked). 없으면 null.
    /// 지운 시즌의 링크로 세션이 다시 들어오면 새로 만들지 않고 이것을 되살린다.
    /// </summary>
    Task<Season?> GetDeletedByLinkAsync(Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default);

    /// <summary>내 시즌 1건(삭제 제외, tracked — 이름·완료·삭제 수정용). 남의 것·없는 것은 null.</summary>
    Task<Season?> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default);

    /// <summary>키 (SeasonId, WeekendLinkId)로 주말 조회(삭제 제외, tracked). 없으면 null.</summary>
    Task<RaceWeekend?> GetWeekendAsync(Guid seasonId, long weekendLinkId, CancellationToken cancellationToken = default);

    Task AddAsync(Season season, CancellationToken cancellationToken = default);

    Task AddWeekendAsync(RaceWeekend weekend, CancellationToken cancellationToken = default);
}
