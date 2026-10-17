namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>참가자 1명(F1 Participants 패킷의 carIndex 칸). <paramref name="GameDriverId"/>는 사람(네트워크) 드라이버면 null.</summary>
public sealed record ParticipantInfo(
    int CarIndex,
    string Name,
    int? GameDriverId,
    int TeamId,
    int RaceNumber,
    bool IsAiControlled);

/// <summary>참가자 목록 프레임(F1 Participants 패킷 매핑, 약 5초마다). 이름·팀·AI 여부를 carIndex로 순위표와 결합하는 데 쓴다.</summary>
public sealed record ParticipantsFrame(
    string SessionRef,
    IReadOnlyList<ParticipantInfo> Participants) : ITelemetryFrame;
