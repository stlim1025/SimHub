using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 랩 끝 차량 스냅샷 수집기(D-44, docs/15 §3.2). <see cref="LapAnalyzer"/>가 Car Status·Car Damage·Session·Participants 프레임을 먹이고,
/// 랩이 바뀌는 순간 <see cref="BuildCar"/>·<see cref="BuildConditions"/>로 LapFinished의 <c>car</c>·<c>conditions</c>를 만든 뒤 <see cref="StartLap"/>을 부른다.
/// 끝 값 = 이번 랩 동안 마지막으로 받은 값, 시작 값 = <see cref="StartLap"/>(시작 값 받기) 뒤 처음 받은 값. 팀·주행 조건은 랩을 넘어 최신 값을 유지한다.
/// 상태 저장이라 스레드 안전하지 않다(분석기와 같다).
/// </summary>
public sealed class LapCarStateTracker
{
    // 백엔드 검증 범위(docs/15 §5). 값 하나 때문에 스냅샷·조건 전체가 버려지지 않게 퍼센트는 다듬고, 연료·기온은 범위 밖이면 그 값만 null로 둔다.
    // NaN·무한대는 JSON으로 쓸 수 없어(직렬화 예외 → 랩 유실) 항상 걸러낸다.
    private const float MinPercent = 0f;
    private const float MaxPercent = 100f;
    private const int MaxPercentInt = 100;
    private const float MaxFuelKg = 200f;
    private const int MinTemperatureC = -50;
    private const int MaxTemperatureC = 80;

    // 랩을 넘어 유지
    private SessionFrame? _session;
    private int? _playerTeamId;

    // 이번 랩
    private CarStatusFrame? _endStatus;
    private CarDamageFrame? _endDamage;
    private CarStatusFrame? _startStatus;
    private WheelSet<float>? _startTyreWear;
    private bool _awaitingStartStatus;
    private bool _awaitingStartDamage;

    /// <summary>세션 맥락(날씨·기온·비 예보)의 최신 값을 보관한다.</summary>
    public void OnSession(SessionFrame frame) => _session = frame;

    /// <summary>플레이어 차(헤더의 플레이어 번호)의 팀을 보관한다. 플레이어 칸이 없으면(관전 등) 팀을 모르는 것으로 둔다.</summary>
    public void OnParticipants(ParticipantsFrame frame)
    {
        var player = frame.PlayerCarIndex is int index
            ? frame.Participants.FirstOrDefault(participant => participant.CarIndex == index)
            : null;
        _playerTeamId = player?.TeamId;
    }

    public void OnStatus(CarStatusFrame frame)
    {
        if (_awaitingStartStatus)
        {
            _startStatus = frame;
            _awaitingStartStatus = false;
        }

        _endStatus = frame;
    }

    public void OnDamage(CarDamageFrame frame)
    {
        if (_awaitingStartDamage)
        {
            _startTyreWear = ClampWear(frame.TyreWearPercent);
            _awaitingStartDamage = false;
        }

        _endDamage = frame;
    }

    /// <summary>
    /// 새 랩을 시작한다 — 이전 랩의 값을 잊는다. <paramref name="captureStartValues"/>가 false면(랩 중간에 Agent가 시작) 이번 랩의 시작 값을 비워 둔다.
    /// </summary>
    public void StartLap(bool captureStartValues)
    {
        _endStatus = null;
        _endDamage = null;
        _startStatus = null;
        _startTyreWear = null;
        _awaitingStartStatus = captureStartValues;
        _awaitingStartDamage = captureStartValues;
    }

    /// <summary>세션이 바뀌면 모두 잊는다.</summary>
    public void Reset()
    {
        _session = null;
        _playerTeamId = null;
        StartLap(captureStartValues: false);
    }

    /// <summary>이번 랩의 <c>car</c>. 팀·상태·손상을 하나도 받지 못했으면 null.</summary>
    public LapCarSnapshot? BuildCar()
    {
        if (_playerTeamId is null && _endStatus is null && _endDamage is null)
        {
            return null;
        }

        var status = _endStatus;
        var damage = _endDamage;
        return new LapCarSnapshot(
            TeamId: _playerTeamId,
            VisualTyreCompound: status?.VisualTyreCompound,
            ActualTyreCompound: status?.ActualTyreCompound,
            TyreAgeLaps: status?.TyreAgeLaps,
            TyreWearStart: _startTyreWear,
            TyreWearEnd: damage is null ? null : ClampWear(damage.TyreWearPercent),
            TyreDamage: damage is null ? null : ClampPercent(damage.TyreDamagePercent),
            BrakeDamage: damage is null ? null : ClampPercent(damage.BrakeDamagePercent),
            FrontLeftWingDamage: ClampPercent(damage?.FrontLeftWingDamage),
            FrontRightWingDamage: ClampPercent(damage?.FrontRightWingDamage),
            RearWingDamage: ClampPercent(damage?.RearWingDamage),
            FloorDamage: ClampPercent(damage?.FloorDamage),
            DiffuserDamage: ClampPercent(damage?.DiffuserDamage),
            SidepodDamage: ClampPercent(damage?.SidepodDamage),
            GearboxDamage: ClampPercent(damage?.GearboxDamage),
            EngineDamage: ClampPercent(damage?.EngineDamage),
            FuelStartKg: FuelKg(_startStatus?.FuelInTankKg),
            FuelEndKg: FuelKg(status?.FuelInTankKg),
            FuelRemainingLaps: status?.FuelRemainingLaps is float laps && float.IsFinite(laps) ? laps : null,
            ErsStoreStartJ: ToJoules(_startStatus?.ErsStoreEnergyJ),
            ErsStoreEndJ: ToJoules(status?.ErsStoreEnergyJ),
            ErsDeployedJ: ToJoules(status?.ErsDeployedThisLapJ),
            ErsHarvestedJ: ToJoules(status?.ErsHarvestedThisLapMgukJ + status?.ErsHarvestedThisLapMguhJ));
    }

    /// <summary>최신 Session 값의 <c>conditions</c>. Session을 못 받았거나 조건 값이 하나도 없으면 null.</summary>
    public LapConditions? BuildConditions()
    {
        if (_session is not { } session
            || (session.Weather is null && session.AirTemperatureC is null && session.TrackTemperatureC is null && session.RainForecastPercent is null))
        {
            return null;
        }

        return new LapConditions(
            session.Weather,
            InRange(session.AirTemperatureC, MinTemperatureC, MaxTemperatureC),
            InRange(session.TrackTemperatureC, MinTemperatureC, MaxTemperatureC),
            InRange(session.RainForecastPercent, 0, MaxPercentInt));
    }

    private static int? InRange(int? value, int min, int max) => value is int v && v >= min && v <= max ? v : null;

    /// <summary>연료(kg). 유한하지 않거나 0~200kg 밖이면 null.</summary>
    private static float? FuelKg(float? kg) => kg is float v && float.IsFinite(v) && v >= 0f && v <= MaxFuelKg ? v : null;

    private static int? ClampPercent(int? percent) => percent is int v ? Math.Clamp(v, 0, MaxPercentInt) : null;

    private static WheelSet<int> ClampPercent(WheelSet<int> wheels) => new(
        Math.Clamp(wheels.FrontLeft, 0, MaxPercentInt),
        Math.Clamp(wheels.FrontRight, 0, MaxPercentInt),
        Math.Clamp(wheels.RearLeft, 0, MaxPercentInt),
        Math.Clamp(wheels.RearRight, 0, MaxPercentInt));

    /// <summary>줄(float) → 정수 줄(사사오입). NaN·무한대는 null, 음수는 0.</summary>
    private static int? ToJoules(float? joules)
    {
        if (joules is not float value || !float.IsFinite(value))
        {
            return null;
        }

        var rounded = Math.Round((double)value, MidpointRounding.AwayFromZero);
        return rounded <= 0 ? 0 : rounded >= int.MaxValue ? int.MaxValue : (int)rounded;
    }

    private static WheelSet<float> ClampWear(WheelSet<float> wear) => new(
        ClampPercent(wear.FrontLeft),
        ClampPercent(wear.FrontRight),
        ClampPercent(wear.RearLeft),
        ClampPercent(wear.RearRight));

    private static float ClampPercent(float percent) => float.IsNaN(percent) ? MinPercent : Math.Clamp(percent, MinPercent, MaxPercent);
}
