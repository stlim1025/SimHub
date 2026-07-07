using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>DrivingSession 영속성 포트(체크인 세션 = 랩 귀속 단위, D-2).</summary>
public interface IDrivingSessionRepository
{
    Task<DrivingSession?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>해당 Rig의 활성 세션(부분 유니크로 0~1개). 점유 판정용.</summary>
    Task<DrivingSession?> GetActiveByRigAsync(Guid simRigId, CancellationToken cancellationToken = default);

    /// <summary>사용자의 활성 세션(SimRig 포함). 활성 조회/랩 귀속용.</summary>
    Task<DrivingSession?> GetActiveByUserAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>사용자의 모든 활성 세션(체크인 시 자동 종료 대상, D-10).</summary>
    Task<IReadOnlyList<DrivingSession>> GetActiveSessionsByUserAsync(Guid userId, CancellationToken cancellationToken = default);

    Task AddAsync(DrivingSession session, CancellationToken cancellationToken = default);
}
