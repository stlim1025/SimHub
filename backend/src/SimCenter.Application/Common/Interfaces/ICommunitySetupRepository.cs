using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>트랙·조건별 활성 셋업 개수.</summary>
public sealed record CommunitySetupCount(Guid TrackId, string Condition, int Count);

/// <summary>
/// 커뮤니티 셋업 영속성 포트. 조회는 모두 no tracking이다. 갱신은 묶음(게임·트랙·조건) 단위 <see cref="ReplaceGroupAsync"/> 한 번으로 원자적으로 한다.
/// </summary>
public interface ICommunitySetupRepository
{
    /// <summary>게임의 트랙·조건별 활성 셋업 개수(셋업이 없는 묶음은 행이 없다).</summary>
    Task<IReadOnlyList<CommunitySetupCount>> GetCountsAsync(string gameCode, CancellationToken cancellationToken = default);

    /// <summary>트랙·조건·세션 종류의 활성 셋업(순위 오름차순).</summary>
    Task<IReadOnlyList<CommunitySetup>> GetActiveAsync(
        Guid trackId, string condition, string sessionType, CancellationToken cancellationToken = default);

    /// <summary>활성 셋업 1건(트랙 포함). 없으면 null.</summary>
    Task<CommunitySetup?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>게임·트랙·조건의 모든 행(세션 종류 전부, 지운 행 포함) — 갱신 때 상세를 다시 받지 않을 SourceId를 고른다.</summary>
    Task<IReadOnlyList<CommunitySetup>> GetGroupAsync(
        string gameCode, Guid trackId, string condition, CancellationToken cancellationToken = default);

    /// <summary>
    /// 묶음(게임·트랙·조건·세션 종류)을 <paramref name="setups"/>로 맞춘다(한 트랜잭션): 같은 SourceId 행(같은 조건이면 세션 종류가 달라도)은
    /// 값을 덮어쓰고 되살리며, 없는 SourceId는 새 행으로 넣고, 이 세션 종류의 목록에 없는 활성 행은 soft delete한다.
    /// 실패하면 아무것도 바꾸지 않고 예외를 던진다.
    /// </summary>
    Task ReplaceGroupAsync(
        string gameCode,
        Guid trackId,
        string condition,
        string sessionType,
        IReadOnlyList<CommunitySetup> setups,
        DateTime now,
        CancellationToken cancellationToken = default);
}
