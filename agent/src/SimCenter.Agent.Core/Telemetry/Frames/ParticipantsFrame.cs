namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>참가자 1명(F1 Participants 패킷의 carIndex 칸). <paramref name="GameDriverId"/>는 사람(네트워크) 드라이버면 null.</summary>
public sealed record ParticipantInfo(
    int CarIndex,
    string Name,
    int? GameDriverId,
    int TeamId,
    int RaceNumber,
    bool IsAiControlled);

/// <summary>
/// 참가자 목록 프레임(F1 Participants 패킷 매핑, 약 5초마다). 이름·팀·AI 여부를 carIndex로 순위표와 결합하는 데 쓴다.
/// <paramref name="PlayerCarIndex"/>(패킷 헤더)는 랩 스냅샷의 팀(D-44)을 고르는 데 쓴다 — null = 모름. 관전 중이면 어느 칸과도 맞지 않는 값이 온다.
/// </summary>
public sealed record ParticipantsFrame(
    string SessionRef,
    IReadOnlyList<ParticipantInfo> Participants,
    int? PlayerCarIndex = null) : ITelemetryFrame;
