using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

/// <summary>랩 끝 차량 스냅샷(D-44, docs/15 §3.2): 끝 값 = 랩 동안 마지막 값, 시작 값 = 새 랩 시작 뒤 첫 값, 값이 없으면 생략.</summary>
public class LapCarStateTrackerTests
{
    private const string S1 = "1001";
    private readonly LapCarStateTracker _sut = new();

    private static CarStatusFrame Status(
        float fuel = 30f, float fuelLaps = 12.5f, float ers = 4_000_000f, float deployed = 0f,
        float mguk = 0f, float mguh = 0f, int actual = 18, int visual = 16, int age = 3)
        => new(S1, fuel, fuelLaps, ers, deployed, mguk, mguh, actual, visual, age);

    private static WheelSet<float> Wear(float fl, float fr, float rl, float rr) => new(fl, fr, rl, rr);

    private static CarDamageFrame Damage(WheelSet<float>? wear = null, int frontLeftWing = 0, int engine = 0) => new(
        S1,
        TyreWearPercent: wear ?? Wear(10f, 11f, 12f, 13f),
        TyreDamagePercent: new WheelSet<int>(1, 2, 3, 4),
        BrakeDamagePercent: new WheelSet<int>(5, 6, 7, 8),
        FrontLeftWingDamage: frontLeftWing,
        FrontRightWingDamage: 10,
        RearWingDamage: 11,
        FloorDamage: 12,
        DiffuserDamage: 13,
        SidepodDamage: 14,
        GearboxDamage: 15,
        EngineDamage: engine);

    private static ParticipantsFrame Participants(int? playerCarIndex, params (int CarIndex, int TeamId)[] cars) => new(
        S1,
        cars.Select(c => new ParticipantInfo(c.CarIndex, $"CAR{c.CarIndex}", 1, c.TeamId, 10 + c.CarIndex, false)).ToArray(),
        playerCarIndex);

    [Fact]
    public void Build_NothingReceived_ReturnsNull()
    {
        _sut.StartLap(captureStartValues: true);

        Assert.Null(_sut.BuildCar());
        Assert.Null(_sut.BuildConditions());
    }

    [Fact]
    public void BuildCar_UsesLastValuesAsEnd_AndFirstValuesAfterLapStartAsStart()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status(fuel: 24.4f, ers: 1_494_000f));
        _sut.OnDamage(Damage(Wear(27f, 14f, 20f, 14f)));
        _sut.OnStatus(Status(fuel: 23.5f, ers: 1_200_000f));
        _sut.OnDamage(Damage(Wear(29f, 16f, 22f, 16f)));
        _sut.OnStatus(Status(fuel: 22.7f, ers: 988_000f, deployed: 2_100_000f, mguk: 1_000_000f, mguh: 600_000f, age: 4));
        _sut.OnDamage(Damage(Wear(31f, 18f, 24f, 18f), frontLeftWing: 3, engine: 30));

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Equal(24.4f, car.FuelStartKg);
        Assert.Equal(22.7f, car.FuelEndKg);
        Assert.Equal(12.5f, car.FuelRemainingLaps);
        Assert.Equal(1_494_000, car.ErsStoreStartJ);
        Assert.Equal(988_000, car.ErsStoreEndJ);
        Assert.Equal(2_100_000, car.ErsDeployedJ);
        Assert.Equal(1_600_000, car.ErsHarvestedJ);   // MGU-K + MGU-H
        Assert.Equal(Wear(27f, 14f, 20f, 14f), car.TyreWearStart);
        Assert.Equal(Wear(31f, 18f, 24f, 18f), car.TyreWearEnd);
        Assert.Equal(new WheelSet<int>(1, 2, 3, 4), car.TyreDamage);
        Assert.Equal(new WheelSet<int>(5, 6, 7, 8), car.BrakeDamage);
        Assert.Equal(16, car.VisualTyreCompound);
        Assert.Equal(18, car.ActualTyreCompound);
        Assert.Equal(4, car.TyreAgeLaps);
        Assert.Equal(3, car.FrontLeftWingDamage);
        Assert.Equal(10, car.FrontRightWingDamage);
        Assert.Equal(11, car.RearWingDamage);
        Assert.Equal(12, car.FloorDamage);
        Assert.Equal(13, car.DiffuserDamage);
        Assert.Equal(14, car.SidepodDamage);
        Assert.Equal(15, car.GearboxDamage);
        Assert.Equal(30, car.EngineDamage);
    }

    [Fact]
    public void BuildCar_WithoutObservedLapStart_LeavesStartValuesNull()
    {
        // 랩 중간에 Agent가 시작한 경우 — 시작 값은 보내지 않는다.
        _sut.StartLap(captureStartValues: false);
        _sut.OnStatus(Status(fuel: 22.7f));
        _sut.OnDamage(Damage());

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Null(car.FuelStartKg);
        Assert.Null(car.ErsStoreStartJ);
        Assert.Null(car.TyreWearStart);
        Assert.Equal(22.7f, car.FuelEndKg);
        Assert.NotNull(car.TyreWearEnd);
    }

    [Fact]
    public void BuildCar_OnlyStatus_LeavesDamageFieldsNull()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status());

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Null(car.TyreWearStart);
        Assert.Null(car.TyreWearEnd);
        Assert.Null(car.TyreDamage);
        Assert.Null(car.BrakeDamage);
        Assert.Null(car.EngineDamage);
        Assert.Null(car.TeamId);
        Assert.Equal(30f, car.FuelEndKg);
    }

    [Fact]
    public void StartLap_ForgetsPreviousLapValues()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status(fuel: 30f));
        _sut.OnDamage(Damage());

        _sut.StartLap(captureStartValues: true);

        Assert.Null(_sut.BuildCar());   // 이번 랩에 받은 값이 없다
    }

    [Fact]
    public void BuildCar_TeamId_ComesFromPlayerParticipant_AndSurvivesLapStart()
    {
        _sut.OnParticipants(Participants(playerCarIndex: 1, (0, 3), (1, 1)));
        _sut.StartLap(captureStartValues: true);

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Equal(1, car.TeamId);
        Assert.Null(car.FuelEndKg);
    }

    [Fact]
    public void BuildCar_PlayerNotInParticipants_HasNoTeam()
    {
        _sut.OnParticipants(Participants(playerCarIndex: 255, (0, 3)));   // 관전 중 등

        Assert.Null(_sut.BuildCar());
    }

    [Fact]
    public void BuildCar_TyreWearOutsidePercentRange_IsClamped()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnDamage(Damage(Wear(-0.5f, 100.4f, float.NaN, 50f)));

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Equal(Wear(0f, 100f, 0f, 50f), car.TyreWearEnd);
    }

    [Fact]
    public void BuildCar_ErsNotANumber_IsNull_AndNegativeIsZero()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status(ers: float.NaN, deployed: -3f));

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Null(car.ErsStoreStartJ);
        Assert.Null(car.ErsStoreEndJ);
        Assert.Equal(0, car.ErsDeployedJ);
    }

    [Fact]
    public void BuildCar_FuelNotFiniteOrOutOfRange_IsNull()
    {
        // NaN은 JSON으로 쓸 수 없어 랩 전체를 잃는다. 범위 밖(0~200kg)은 백엔드가 스냅샷 전체를 버린다 — 그 값만 null로.
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status(fuel: float.NaN, fuelLaps: float.PositiveInfinity));
        _sut.OnStatus(Status(fuel: 250f, fuelLaps: -0.4f));

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Null(car.FuelStartKg);
        Assert.Null(car.FuelEndKg);
        Assert.Equal(-0.4f, car.FuelRemainingLaps);   // 모자라면 음수일 수 있다
    }

    [Fact]
    public void BuildCar_FuelRemainingLapsNotFinite_IsNull()
    {
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status(fuelLaps: float.NaN));

        Assert.Null(Assert.IsType<LapCarSnapshot>(_sut.BuildCar()).FuelRemainingLaps);
    }

    [Fact]
    public void BuildCar_DamageOutsidePercentRange_IsClamped()
    {
        var damage = Damage(frontLeftWing: 140, engine: -5) with { TyreDamagePercent = new WheelSet<int>(101, 0, 50, 255) };
        _sut.StartLap(captureStartValues: true);
        _sut.OnDamage(damage);

        var car = Assert.IsType<LapCarSnapshot>(_sut.BuildCar());

        Assert.Equal(100, car.FrontLeftWingDamage);
        Assert.Equal(0, car.EngineDamage);
        Assert.Equal(new WheelSet<int>(100, 0, 50, 100), car.TyreDamage);
    }

    [Fact]
    public void BuildConditions_TemperatureOutOfRange_IsNull()
    {
        _sut.OnSession(new SessionFrame(S1, 7, SessionType.Race, 2025, Weather: Weather.Clear, AirTemperatureC: -120, TrackTemperatureC: 95, RainForecastPercent: 140));

        Assert.Equal(new LapConditions(Weather.Clear, null, null, null), _sut.BuildConditions());
    }

    [Fact]
    public void BuildConditions_UsesLatestSessionValues()
    {
        _sut.OnSession(new SessionFrame(S1, 7, SessionType.Race, 2025, Weather: Weather.Overcast, AirTemperatureC: 20, TrackTemperatureC: 29, TrackLengthM: 5891, RainForecastPercent: 10));
        _sut.OnSession(new SessionFrame(S1, 7, SessionType.Race, 2025, Weather: Weather.LightRain, AirTemperatureC: 19, TrackTemperatureC: 27, TrackLengthM: 5891, RainForecastPercent: 60));

        var conditions = Assert.IsType<LapConditions>(_sut.BuildConditions());

        Assert.Equal(new LapConditions(Weather.LightRain, 19, 27, 60), conditions);
    }

    [Fact]
    public void BuildConditions_SessionWithoutConditions_ReturnsNull()
    {
        _sut.OnSession(new SessionFrame(S1, 7, SessionType.TimeTrial, 2025));

        Assert.Null(_sut.BuildConditions());
    }

    [Fact]
    public void Reset_ForgetsEverything()
    {
        _sut.OnSession(new SessionFrame(S1, 7, SessionType.Race, 2025, Weather: Weather.Clear, AirTemperatureC: 20));
        _sut.OnParticipants(Participants(playerCarIndex: 0, (0, 3)));
        _sut.StartLap(captureStartValues: true);
        _sut.OnStatus(Status());

        _sut.Reset();

        Assert.Null(_sut.BuildCar());
        Assert.Null(_sut.BuildConditions());
    }
}
