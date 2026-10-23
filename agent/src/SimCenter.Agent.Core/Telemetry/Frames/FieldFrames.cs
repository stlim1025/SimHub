namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 모든 차의 월드 위치(F1 Motion). 칸 번호 = 차 번호. 트랙 형상 표본(<c>TrackSamplesChunk</c>, 헌장 Agent Rules 예외)의 원천이다.
/// 같은 게임 프레임의 <see cref="FieldLapStatesFrame"/>·<see cref="FieldSurfacesFrame"/>와 <paramref name="FrameId"/>로 짝짓는다.
/// </summary>
/// <param name="SessionTimeMs">세션 경과 시간(ms).</param>
public sealed record FieldPositionsFrame(
    string SessionRef,
    uint FrameId,
    int SessionTimeMs,
    IReadOnlyList<FieldPosition> Cars) : ITelemetryFrame;

/// <summary>차 한 대의 월드 위치(m). 수평면은 X·Z다.</summary>
public readonly record struct FieldPosition(float X, float Z);

/// <summary>모든 차의 랩 상태(F1 Lap Data). 칸 번호 = 차 번호.</summary>
public sealed record FieldLapStatesFrame(
    string SessionRef,
    uint FrameId,
    IReadOnlyList<FieldLapState> Cars) : ITelemetryFrame;

/// <summary>
/// 차 한 대의 랩 상태. <paramref name="IsOnTrack"/>은 매퍼가 정한다(달리는 중 · 피트 아님 · 차고 아님).
/// <paramref name="Status"/>는 그대로 표본에 싣는 게임 원시 상태 묶음이다(뜻은 매퍼와 계약 문서가 정한다).
/// </summary>
/// <param name="LapDistanceM">현재 랩에서 달린 거리(m). 출발선을 지나기 전에는 음수일 수 있다.</param>
public readonly record struct FieldLapState(float LapDistanceM, bool IsOnTrack, byte Status);

/// <summary>모든 차의 바퀴 노면(F1 Car Telemetry). 칸 번호 = 차 번호, 값은 바퀴 4개를 4비트씩 묶은 값(FL·FR·RL·RR 순, 하위 비트부터).</summary>
public sealed record FieldSurfacesFrame(
    string SessionRef,
    uint FrameId,
    IReadOnlyList<ushort> Surfaces) : ITelemetryFrame;
