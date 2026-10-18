using SimCenter.Application.Laps.Ingest;

namespace SimCenter.Application.Tests.Laps;

/// <summary>스냅샷 검증 규칙(15 §5): 퍼센트 0~100, 기온 −50~80, 연료 0~200kg, ERS 0~10MJ, 컴파운드·나이 0~255.</summary>
public class LapSnapshotValidatorTests
{
    private static readonly WheelValuesPayload Wheels = new(10, 10, 10, 10);

    [Fact]
    public void ValidCarAndConditions_Pass()
    {
        Assert.Empty(LapSnapshotValidator.Validate(LapDetailSamples.ValidCar()));
        Assert.Empty(LapSnapshotValidator.Validate(LapDetailSamples.ValidConditions()));
    }

    [Fact]
    public void AllNullFields_Pass()
    {
        // 받지 못한 값은 null로 온다 — 그 자체는 틀린 값이 아니다.
        Assert.Empty(LapSnapshotValidator.Validate(new LapCarPayload()));
        Assert.Empty(LapSnapshotValidator.Validate(new LapConditionsPayload()));
    }

    public static TheoryData<string, LapCarPayload> InvalidCars() => new()
    {
        { "teamId", new LapCarPayload(TeamId: -1) },
        { "teamId", new LapCarPayload(TeamId: 65_536) },
        { "visualTyreCompound", new LapCarPayload(VisualTyreCompound: 256) },
        { "actualTyreCompound", new LapCarPayload(ActualTyreCompound: -1) },
        { "tyreAgeLaps", new LapCarPayload(TyreAgeLaps: 256) },
        { "tyreWearStart.frontLeft", new LapCarPayload(TyreWearStart: new(100.01, 0, 0, 0)) },
        { "tyreWearEnd.rearRight", new LapCarPayload(TyreWearEnd: new(0, 0, 0, -0.5)) },
        { "tyreDamage", new LapCarPayload(TyreDamage: new(1, 1, 1, null)) },
        { "brakeDamage.frontRight", new LapCarPayload(BrakeDamage: new(0, 101, 0, 0)) },
        { "frontLeftWingDamage", new LapCarPayload(FrontLeftWingDamage: 101) },
        { "frontRightWingDamage", new LapCarPayload(FrontRightWingDamage: -1) },
        { "rearWingDamage", new LapCarPayload(RearWingDamage: 101) },
        { "floorDamage", new LapCarPayload(FloorDamage: 101) },
        { "diffuserDamage", new LapCarPayload(DiffuserDamage: 101) },
        { "sidepodDamage", new LapCarPayload(SidepodDamage: 101) },
        { "gearboxDamage", new LapCarPayload(GearboxDamage: 101) },
        { "engineDamage", new LapCarPayload(EngineDamage: 101) },
        { "fuelStartKg", new LapCarPayload(FuelStartKg: 200.1) },
        { "fuelEndKg", new LapCarPayload(FuelEndKg: -0.1) },
        { "fuelRemainingLaps", new LapCarPayload(FuelRemainingLaps: 200.5) },
        { "ersStoreStartJ", new LapCarPayload(ErsStoreStartJ: 10_000_001) },
        { "ersStoreEndJ", new LapCarPayload(ErsStoreEndJ: -1) },
        { "ersDeployedJ", new LapCarPayload(ErsDeployedJ: double.NaN) },
        { "ersHarvestedJ", new LapCarPayload(ErsHarvestedJ: double.PositiveInfinity) },
    };

    [Theory]
    [MemberData(nameof(InvalidCars))]
    public void OutOfRangeCarValue_IsReported(string field, LapCarPayload car)
    {
        var errors = LapSnapshotValidator.Validate(car);

        var error = Assert.Single(errors);
        Assert.StartsWith(field, error);
    }

    [Fact]
    public void Boundaries_AreInclusive()
    {
        var car = new LapCarPayload(
            TeamId: 0, VisualTyreCompound: 255, ActualTyreCompound: 0, TyreAgeLaps: 255,
            TyreWearStart: new(0, 100, 0, 100), TyreWearEnd: Wheels, TyreDamage: Wheels, BrakeDamage: Wheels,
            FrontLeftWingDamage: 100, EngineDamage: 0,
            FuelStartKg: 200, FuelEndKg: 0, FuelRemainingLaps: -200,
            ErsStoreStartJ: 10_000_000, ErsStoreEndJ: 0);
        var conditions = new LapConditionsPayload("Storm", AirTempC: -50, TrackTempC: 80, RainForecastPercent: 100);

        Assert.Empty(LapSnapshotValidator.Validate(car));
        Assert.Empty(LapSnapshotValidator.Validate(conditions));
    }

    [Fact]
    public void NegativeFuelRemainingLaps_IsAllowed()
    {
        // MFD의 남은 랩은 연료가 모자라면 음수다.
        Assert.Empty(LapSnapshotValidator.Validate(new LapCarPayload(FuelRemainingLaps: -0.8)));
    }

    [Theory]
    [InlineData(-51, 30, 0, "airTempC")]
    [InlineData(20, 81, 0, "trackTempC")]
    [InlineData(20, 30, 101, "rainForecastPercent")]
    [InlineData(20, 30, -1, "rainForecastPercent")]
    public void OutOfRangeCondition_IsReported(int air, int track, int rain, string field)
    {
        var errors = LapSnapshotValidator.Validate(new LapConditionsPayload("Clear", air, track, rain));

        Assert.StartsWith(field, Assert.Single(errors));
    }

    [Fact]
    public void UnknownWeatherName_IsNotAValidationError()
    {
        // 모르는 날씨는 저장만 하지 않는다(LapDetailExtractor) — 그것 때문에 날씨 영역 전체를 버리지 않는다.
        Assert.Empty(LapSnapshotValidator.Validate(new LapConditionsPayload("Sandstorm", 20, 30, 0)));
    }
}
