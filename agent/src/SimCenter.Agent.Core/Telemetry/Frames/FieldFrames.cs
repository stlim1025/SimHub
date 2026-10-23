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

/// <summary>
/// 차 한 대의 월드 위치(m, 수평면은 X·Z, <paramref name="Y"/>는 높이)와 횡·종 G-force(g). G가 급변하면 충격(벽·차)으로 본다.
/// </summary>
public readonly record struct FieldPosition(float X, float Z, float GLateral = 0, float GLongitudinal = 0, float Y = 0);

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

/// <summary>
/// 모든 차의 바퀴 노면과 주행 상태(F1 Car Telemetry). 칸 번호 = 차 번호. 노면은 바퀴 4개를 4비트씩 묶은 값(FL·FR·RL·RR 순, 하위 비트부터).
/// 노면 뒤 목록이 비었으면 그 값을 모른다(0으로 싣는다).
/// </summary>
/// <param name="Gears">−1 = R, 0 = N, 1~8.</param>
/// <param name="Throttles">스로틀(%).</param>
/// <param name="Brakes">브레이크(%).</param>
/// <param name="Steers">조향(−100~100, 왼쪽 −).</param>
/// <param name="Rpms">엔진 RPM.</param>
public sealed record FieldSurfacesFrame(
    string SessionRef,
    uint FrameId,
    IReadOnlyList<ushort> Surfaces,
    IReadOnlyList<ushort>? SpeedsKph = null,
    IReadOnlyList<sbyte>? Gears = null,
    IReadOnlyList<byte>? Throttles = null,
    IReadOnlyList<byte>? Brakes = null,
    IReadOnlyList<bool>? DrsOpen = null,
    IReadOnlyList<sbyte>? Steers = null,
    IReadOnlyList<ushort>? Rpms = null) : ITelemetryFrame;

/// <summary>
/// 모든 차의 타이어·ERS(F1 Car Status): 보이는 컴파운드(게임 원시 값)·사용 랩 수·ERS 배터리 잔량(kJ). 칸 번호 = 차 번호, 최신 값을 쓴다.
/// </summary>
public sealed record FieldStatusFrame(
    string SessionRef,
    IReadOnlyList<byte> TyreCompounds,
    IReadOnlyList<byte> TyreAgeLaps,
    IReadOnlyList<ushort>? ErsStoreKj = null) : ITelemetryFrame;

/// <summary>추월(F1 Event OVTK): 추월한 차와 당한 차 번호.</summary>
public sealed record FieldOvertakeFrame(string SessionRef, int Overtaker, int Overtaken) : ITelemetryFrame;

/// <summary>
/// 모든 차의 차체 손상(F1 Car Damage). 칸 번호 = 차 번호, 값은 날개·플로어·디퓨저·사이드포드 손상률(%) 가운데 가장 큰 값.
/// 다른 패킷과 빈도가 달라 게임 프레임으로 짝짓지 않고 최신 값을 쓴다. 값이 오르면 충격으로 본다.
/// </summary>
public sealed record FieldDamageFrame(string SessionRef, IReadOnlyList<byte> Damage) : ITelemetryFrame;

/// <summary>차 대 차 충돌(F1 Event COLL). 두 차 번호.</summary>
public sealed record FieldCollisionFrame(string SessionRef, int Car1, int Car2) : ITelemetryFrame;
