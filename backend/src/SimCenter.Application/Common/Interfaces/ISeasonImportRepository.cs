using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 시즌 가져오기(docs/15 §12, D-55) 전용 영속성 포트. 조회는 추적(tracked)된 엔티티를 돌려주어,
/// 호출자가 바꾼 값(세션 이동·랩 키 변경)이 가져오기 커밋에 함께 저장된다. 저장 호출은 <see cref="IUnitOfWork"/>가 한다.
/// </summary>
public interface ISeasonImportRepository
{
    /// <summary>
    /// 시즌에 속하지 않았고(<c>SeasonId</c> null) 시즌·주말 링크가 모두 0이 아닌 내 기록 세션(가져온 것 제외, 트랙 포함, tracked).
    /// <paramref name="modes"/>의 게임 모드만.
    /// </summary>
    Task<IReadOnlyList<GameSession>> GetUnseasonedLinkedSessionsAsync(
        Guid userId, string gameCode, IReadOnlyCollection<GameMode> modes, CancellationToken cancellationToken = default);

    /// <summary>내 가져온 시즌들(<c>ImportedFrom</c> 있음, 삭제 제외, no tracking).</summary>
    Task<IReadOnlyList<Season>> GetImportedSeasonsAsync(Guid userId, string gameCode, CancellationToken cancellationToken = default);

    /// <summary>
    /// 지운 시즌에 남은 내 가져온 세션(<c>IsImported</c>, 이 시즌 링크, 시즌이 삭제됨 — tracked). 같은 시즌을 지우고 다시 가져올 때
    /// 옛 가져온 세션이 세션 목록에 겹쳐 남지 않게 지운다.
    /// </summary>
    Task<IReadOnlyList<GameSession>> GetImportedSessionsOfDeletedSeasonsAsync(
        Guid userId, string gameCode, long seasonLinkId, CancellationToken cancellationToken = default);

    /// <summary>이 세션 키를 쓰는 내 활성 세션이 있는가.</summary>
    Task<bool> SessionKeyInUseAsync(Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default);

    /// <summary>이 세션 키를 가진 내 랩(tracked) — 세션 키를 바꿀 때 랩도 같이 바꾼다.</summary>
    Task<IReadOnlyList<Lap>> GetLapsBySessionKeyAsync(
        Guid userId, string gameCode, string sessionKey, CancellationToken cancellationToken = default);
}
