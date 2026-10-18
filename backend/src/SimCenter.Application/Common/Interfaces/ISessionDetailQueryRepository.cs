using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>같은 주말 예선 세션 1건의 내 순위(내 결과가 없으면 null).</summary>
public sealed record WeekendQualifyingRow(Guid SessionId, SessionKind SessionKind, DateTime ClassifiedAt, int? MyPosition);

/// <summary>
/// 세션 상세 F1Laps 카드용 조회 포트(P8, docs/15 §11.4 D-53). 읽기 전용(no tracking), 메서드마다 쿼리 1회 — 랩마다 따로 읽지 않는다.
/// </summary>
public interface ISessionDetailQueryRepository
{
    /// <summary>
    /// 세션에 연결된 내 랩 전부(<c>(UserId, GameCode, SessionKey)</c> + 트랙, 삭제 제외)와 스냅샷·섹터. 랩 번호 오름차순.
    /// </summary>
    Task<IReadOnlyList<SessionLapRow>> GetMySessionLapsAsync(
        Guid userId, string gameCode, Guid trackId, string sessionKey, CancellationToken cancellationToken = default);

    /// <summary>같은 그랑프리 주말의 내 예선 세션들(<c>SessionType.Qualifying</c>).</summary>
    Task<IReadOnlyList<WeekendQualifyingRow>> GetMyWeekendQualifyingAsync(
        Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default);

    /// <summary>그 그랑프리 주말에 내 Race2 세션이 있는지(스프린트 주말, <see cref="SimCenter.Application.Seasons.Queries.SessionPositions"/>).</summary>
    Task<bool> IsMySprintWeekendAsync(Guid userId, Guid raceWeekendId, CancellationToken cancellationToken = default);

    /// <summary>내 시즌 전부의 번호 매기기 재료(<see cref="SeasonNumbering"/>).</summary>
    Task<IReadOnlyList<SeasonOrderRow>> GetMySeasonOrderAsync(Guid userId, CancellationToken cancellationToken = default);
}
