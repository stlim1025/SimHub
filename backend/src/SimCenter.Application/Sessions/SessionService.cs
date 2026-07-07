using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Sessions;

/// <summary>
/// 체크인/체크아웃 유스케이스. Domain·포트에만 의존(프레임워크 무의존) → Fake 주입 단위 테스트 가능.
/// 체크인 규칙(D-10): 본인의 다른 활성 세션은 자동 종료, 대상 Rig가 타인 점유면 409.
/// </summary>
public sealed class SessionService : ISessionService
{
    private const int MaxGameCodeLength = 20;

    private readonly ISimRigRepository _rigs;
    private readonly IDrivingSessionRepository _sessions;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;

    public SessionService(
        ISimRigRepository rigs,
        IDrivingSessionRepository sessions,
        IUnitOfWork unitOfWork,
        IIdGenerator idGenerator,
        IClock clock)
    {
        _rigs = rigs;
        _sessions = sessions;
        _unitOfWork = unitOfWork;
        _idGenerator = idGenerator;
        _clock = clock;
    }

    public async Task<SessionDto> CheckInAsync(Guid userId, CheckInRequest request, CancellationToken cancellationToken = default)
    {
        var rigCode = (request.RigCode ?? string.Empty).Trim();
        if (rigCode.Length == 0)
        {
            throw new ValidationException("rigCode", "좌석 코드는 필수입니다.");
        }

        var gameCode = (request.GameCode ?? string.Empty).Trim();
        if (gameCode.Length is 0 or > MaxGameCodeLength)
        {
            throw new ValidationException("gameCode", $"게임 코드는 1~{MaxGameCodeLength}자여야 합니다.");
        }

        var rig = await _rigs.GetByRigCodeAsync(rigCode, cancellationToken)
            ?? throw new NotFoundException("좌석을 찾을 수 없습니다.");

        // 대상 Rig를 타인이 점유 중이면 409(D-10).
        var rigActive = await _sessions.GetActiveByRigAsync(rig.Id, cancellationToken);
        if (rigActive is not null && rigActive.UserId != userId)
        {
            throw new ConflictException("다른 사용자가 사용 중인 좌석입니다.");
        }

        var now = _clock.UtcNow;

        // 본인의 활성 세션은 모두 종료(대상 Rig의 본인 세션 포함) 후 저장한다.
        // 같은 Rig 재체크인 시 Active 부분 유니크 인덱스와 충돌하지 않도록 종료를 먼저 커밋한다.
        var myActives = await _sessions.GetActiveSessionsByUserAsync(userId, cancellationToken);
        if (myActives.Count > 0)
        {
            foreach (var active in myActives)
            {
                EndSession(active, now);
            }

            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }

        var session = new DrivingSession
        {
            Id = _idGenerator.NewId(),
            UserId = userId,
            SimRigId = rig.Id,
            StoreId = rig.StoreId,
            GameCode = gameCode,
            SessionType = SessionType.Unknown, // 게임 SessionStarted로 확정(P3 저장은 LapFinished가 자기완결적).
            Status = SessionStatus.Active,
            StartedAt = now,
            CreatedAt = now,
        };

        await _sessions.AddAsync(session, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return new SessionDto(session.Id, rig.RigCode, session.Status.ToString(), session.StartedAt);
    }

    public async Task<CheckOutResponse> CheckOutAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetByIdAsync(sessionId, cancellationToken)
            ?? throw new NotFoundException("세션을 찾을 수 없습니다.");

        if (session.UserId != userId)
        {
            throw new ForbiddenException("본인의 세션만 종료할 수 있습니다.");
        }

        // 이미 종료된 세션은 멱등하게 현재 상태를 반환한다.
        if (session.Status == SessionStatus.Ended)
        {
            return new CheckOutResponse(session.Id, session.Status.ToString(), session.EndedAt);
        }

        EndSession(session, _clock.UtcNow);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        return new CheckOutResponse(session.Id, session.Status.ToString(), session.EndedAt);
    }

    public async Task<SessionDto?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetActiveByUserAsync(userId, cancellationToken);
        if (session is null)
        {
            return null;
        }

        var rigCode = session.SimRig?.RigCode ?? string.Empty;
        return new SessionDto(session.Id, rigCode, session.Status.ToString(), session.StartedAt);
    }

    private static void EndSession(DrivingSession session, DateTime now)
    {
        session.Status = SessionStatus.Ended;
        session.EndedAt = now;
        session.UpdatedAt = now;
    }
}
