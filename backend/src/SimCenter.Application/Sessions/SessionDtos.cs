namespace SimCenter.Application.Sessions;

/// <summary>체크인 요청(04-api-design §3.4). 좌석 코드 + 게임 코드.</summary>
public sealed record CheckInRequest(string RigCode, string GameCode);

/// <summary>세션 요약(체크인 201 / 활성 조회 200 공용).</summary>
public sealed record SessionDto(Guid SessionId, string RigCode, string Status, DateTime StartedAt);

/// <summary>체크아웃 응답(200).</summary>
public sealed record CheckOutResponse(Guid SessionId, string Status, DateTime? EndedAt);
