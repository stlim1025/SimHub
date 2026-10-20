using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 내 랩 조회 포트(15 §4.2). 읽기 전용 — 모두 no tracking이고 <c>UserId</c> 조건으로 내 것만 찾는다(남의 것 = 없는 것, D-34).
/// 인입·랭킹용 <see cref="ILapRepository"/>와 분리한다.
/// </summary>
public interface ILapQueryRepository
{
    /// <summary>
    /// 내 랩 페이지(무효 랩 포함, <see cref="MyLapsFilter.ValidOnly"/>면 유효 랩만). 총 개수 함께 반환.
    /// 정렬: <see cref="MyLapsSort.Recent"/> = SetAt DESC, <see cref="MyLapsSort.Fastest"/> = 유효 랩 우선 → LapTimeMs ASC → SetAt ASC.
    /// </summary>
    Task<(IReadOnlyList<LapRow> Items, int Total)> GetMyPageAsync(
        Guid userId, MyLapsFilter filter, MyLapsSort sort, int skip, int take, CancellationToken cancellationToken = default);

    /// <summary>내 랩 1건. 남의 것·없는 것은 null.</summary>
    Task<LapRow?> GetMineAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 비교 대상 최고 랩(docs/15 §10, D-51): <see cref="LapComparisonCriteria.Scope"/> 범위(내 유효 랩 / 모든 사용자의 랭킹 적격 랩)에서
    /// 같은 트랙·게임 + 값이 있는 조건(팀·세션 유형·어시스트 칸)에 맞는 가장 빠른 랩. 같으면 먼저 세운 랩. 없으면 null.
    /// </summary>
    Task<LapRow?> FindFastestAsync(LapComparisonCriteria criteria, CancellationToken cancellationToken = default);

    /// <summary>
    /// 비교할 수 있는 랩 1건(D-51): 내 랩이면 무엇이든, 남의 랩이면 랭킹 적격 랩만. 그 밖·없는 것은 null.
    /// </summary>
    Task<LapRow?> GetComparableAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 공유 링크로 여는 랩 1건(로그인 없이, 주인 무관). 지운 랩·없는 랩은 null.
    /// 랩 ID는 UUID v7이라 추측해 훑을 수 없다 — 링크를 받은 사람만 본다.
    /// </summary>
    Task<LapRow?> GetSharedAsync(Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>남의 랩 주인의 표시 이름·공개 설정(D-39). 사용자 행이 없으면 null(서비스가 익명으로 보인다).</summary>
    Task<LapDriverRow?> GetDriverAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>랩의 스냅샷. 없으면 null. 호출자가 먼저 랩 주인을 확인한다.</summary>
    Task<LapSnapshot?> GetSnapshotAsync(Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>내 랩의 트레이스. 트레이스가 없거나 남의 랩이면 null.</summary>
    Task<LapTelemetryTrace?> GetMyTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>공유 링크로 여는 랩의 트레이스(<see cref="GetSharedAsync"/>와 같은 규칙). 트레이스가 없거나 지운·없는 랩이면 null.</summary>
    Task<LapTelemetryTrace?> GetSharedTraceAsync(Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>
    /// 비교할 수 있는 랩의 트레이스(D-51, <see cref="GetComparableAsync"/>와 같은 공개 규칙). 트레이스가 없거나 비교할 수 없는 랩이면 null.
    /// </summary>
    Task<LapTelemetryTrace?> GetComparableTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);
}
