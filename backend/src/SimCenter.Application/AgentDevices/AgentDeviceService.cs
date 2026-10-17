using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.AgentDevices;

/// <summary>
/// 내 장치 목록·연결 해제 유스케이스. Domain·포트에만 의존(프레임워크 무의존).
/// 해제 = soft delete — 전역 필터로 이후 인증 조회에서 자동 제외된다.
/// </summary>
public sealed class AgentDeviceService : IAgentDeviceService
{
    private readonly IAgentDeviceRepository _devices;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IClock _clock;

    public AgentDeviceService(IAgentDeviceRepository devices, IUnitOfWork unitOfWork, IClock clock)
    {
        _devices = devices;
        _unitOfWork = unitOfWork;
        _clock = clock;
    }

    public async Task<AgentDeviceListResponse> GetMyDevicesAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        // 저장소가 본인 장치만 생성 시각 내림차순으로 돌려준다.
        var devices = await _devices.GetByUserAsync(userId, cancellationToken);

        var items = devices
            .Select(d => new AgentDeviceDto(d.Id, d.Name, d.LastSeenAt, d.CreatedAt))
            .ToList();

        return new AgentDeviceListResponse(items);
    }

    public async Task RevokeAsync(Guid userId, Guid deviceId, CancellationToken cancellationToken = default)
    {
        var device = await _devices.GetByIdAsync(deviceId, cancellationToken)
            ?? throw new NotFoundException("장치를 찾을 수 없습니다.");

        if (device.UserId != userId)
        {
            throw new ForbiddenException("본인의 장치만 해제할 수 있습니다.");
        }

        device.IsDeleted = true;
        device.UpdatedAt = _clock.UtcNow;
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }
}
