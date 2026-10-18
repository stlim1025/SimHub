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
    /// 같은 트랙·게임에서 내 가장 빠른 유효(<c>IsValid</c>) 랩(D-46의 비교 대상). 같으면 먼저 세운 랩. 없으면 null.
    /// </summary>
    Task<LapRow?> GetMyFastestValidAsync(
        Guid userId, Guid trackId, string gameCode, CancellationToken cancellationToken = default);

    /// <summary>랩의 스냅샷. 없으면 null. 호출자가 먼저 랩 주인을 확인한다.</summary>
    Task<LapSnapshot?> GetSnapshotAsync(Guid lapId, CancellationToken cancellationToken = default);

    /// <summary>내 랩의 트레이스. 트레이스가 없거나 남의 랩이면 null.</summary>
    Task<LapTelemetryTrace?> GetMyTraceAsync(Guid userId, Guid lapId, CancellationToken cancellationToken = default);
}
