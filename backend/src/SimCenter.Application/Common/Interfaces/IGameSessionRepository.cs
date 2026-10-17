using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 게임 세션(최종 순위표) 영속성 포트(P7, 12 §4.2). 저장 호출은 <see cref="IUnitOfWork"/>가 한다.
/// </summary>
public interface IGameSessionRepository
{
    /// <summary>
    /// 키 (UserId, GameCode, SessionKey)로 세션 조회(삭제 제외, tracked). 활성 <see cref="GameSession.Results"/>와
    /// 그 활성 <see cref="SessionResult.TyreStints"/>를 함께 불러온다(재분류 병합용, 12 §4.5). 없으면 null.
    /// </summary>
    Task<GameSession?> GetByKeyWithResultsAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default);

    /// <summary>새 세션을 결과·스틴트 그래프째 추가한다.</summary>
    Task AddAsync(GameSession session, CancellationToken cancellationToken = default);
}
