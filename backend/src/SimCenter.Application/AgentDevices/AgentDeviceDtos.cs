namespace SimCenter.Application.AgentDevices;

/// <summary>연결 코드 발급 응답(201). <c>Code</c>는 표시 형식(<c>XXXX-XXXX</c>)이며 서버에는 해시만 남는다.</summary>
public sealed record PairingCodeResponse(string Code, DateTime ExpiresAt);

/// <summary>Agent 연결 요청. <c>DeviceName</c>이 비어 있으면 기본 이름을 쓴다.</summary>
public sealed record PairRequest(string? Code, string? DeviceName);

/// <summary>Agent 연결 응답(200). <c>DeviceKey</c> 원문은 이 응답에서 한 번만 내려간다.</summary>
public sealed record PairResponse(Guid DeviceId, string DeviceKey);

/// <summary>연결된 장치 요약.</summary>
public sealed record AgentDeviceDto(Guid DeviceId, string Name, DateTime? LastSeenAt, DateTime CreatedAt);

/// <summary>내 장치 목록 응답(200).</summary>
public sealed record AgentDeviceListResponse(IReadOnlyList<AgentDeviceDto> Items);
