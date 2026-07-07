namespace SimCenter.Application.Sessions;

/// <summary>체크인 세션 유스케이스(얇은 Service, D-3). 랩-사용자 귀속의 시작점(D-2).</summary>
public interface ISessionService
{
    Task<SessionDto> CheckInAsync(Guid userId, CheckInRequest request, CancellationToken cancellationToken = default);

    Task<CheckOutResponse> CheckOutAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default);

    Task<SessionDto?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default);
}
