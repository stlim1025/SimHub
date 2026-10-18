namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 게임 이벤트 1건(F1 Event 패킷 — 패널티·충돌·플래시백·최고 랩·추월·세이프티카 등, D-49 docs/15 §8). 랩 스냅샷 <c>car.details.events</c>에
/// 그 랩 동안 받은 순서대로 쌓인다. <paramref name="Code"/>는 게임의 이벤트 코드(F1: 4글자 <c>PENA</c> 등), 상세 값은 <see cref="CarDetailsFrame"/>과 같은 규칙이다.
/// 세션 경계(시작·종료)는 <see cref="EventMarker"/>로 따로 온다.
/// </summary>
public sealed record GameEventFrame(
    string SessionRef,
    string Code,
    IReadOnlyDictionary<string, object?> Details) : ITelemetryFrame;
