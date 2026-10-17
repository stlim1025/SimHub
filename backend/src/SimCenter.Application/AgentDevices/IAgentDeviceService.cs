namespace SimCenter.Application.AgentDevices;

/// <summary>내 장치 관리 유스케이스: 목록 조회와 연결 해제.</summary>
public interface IAgentDeviceService
{
    Task<AgentDeviceListResponse> GetMyDevicesAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>장치 연결을 해제(soft delete)한다. 타인 장치는 403, 없는 장치는 404.</summary>
    Task RevokeAsync(Guid userId, Guid deviceId, CancellationToken cancellationToken = default);
}
