using SimCenter.Application.Seasons.Ingest;

namespace SimCenter.Application.Tests.Seasons;

public class SessionClassificationValidatorTests
{
    private static ClassifiedResultDto Car(int carIndex, bool isPlayer = false) => new(
        CarIndex: carIndex,
        IsPlayer: isPlayer,
        Position: carIndex + 1,
        GridPosition: carIndex + 1,
        NumLaps: 20,
        Points: 0,
        NumPitStops: 1,
        NumPenalties: 0,
        ResultStatus: "Finished",
        BestLapTimeMs: 81234,
        TotalRaceTimeMs: 1_620_000,
        PenaltiesTimeMs: 0,
        DriverName: $"DRIVER {carIndex}",
        GameDriverId: carIndex,
        TeamId: 1,
        RaceNumber: carIndex + 10,
        IsAiControlled: !isPlayer,
        TyreStints: new List<TyreStintDto> { new(EndLap: 20, VisualCompound: "Medium", ActualCompound: "C3") });

    private static SessionClassifiedPayloadDto ValidPayload() => new(
        SessionRef: "1844674407370955161",
        TrackId: 10,
        SessionType: "Race",
        SessionKind: "Race",
        GameMode: "DriverCareer",
        SeasonLinkId: 11,
        WeekendLinkId: 22,
        SessionLinkId: 33,
        TotalLaps: 20,
        AiDifficulty: 85,
        IsNetworkGame: false,
        Results: new List<ClassifiedResultDto> { Car(0, isPlayer: true), Car(1) });

    private static SessionClassifiedPayloadDto WithResults(params ClassifiedResultDto[] results)
        => ValidPayload() with { Results = results };

    private static SessionClassifiedPayloadDto WithRow(ClassifiedResultDto row) => WithResults(Car(0, isPlayer: true), row);

    [Fact]
    public void Validate_ValidPayload_ReturnsNull()
    {
        Assert.Null(SessionClassificationValidator.Validate(ValidPayload()));
    }

    [Fact]
    public void Validate_BoundaryValues_Pass()
    {
        var cars = Enumerable.Range(0, SessionClassificationValidator.MaxClassificationEntries)
            .Select(i => Car(i, isPlayer: i == 0))
            .ToList();
        cars[31] = cars[31] with
        {
            CarIndex = 31,
            Position = 32,
            DriverName = new string('A', SessionClassificationValidator.MaxDriverNameLength),
            RaceNumber = int.MaxValue,
            TyreStints = Enumerable.Range(1, SessionClassificationValidator.MaxTyreStints)
                .Select(n => new TyreStintDto(n, "Hard", new string('C', SessionClassificationValidator.MaxActualCompoundLength)))
                .ToList(),
        };
        cars[1] = cars[1] with { TyreStints = null, RaceNumber = null, DriverName = null, GameDriverId = null };
        var payload = ValidPayload() with
        {
            SessionRef = new string('9', SessionClassificationValidator.MaxSessionRefLength),
            Results = cars,
        };

        Assert.Null(SessionClassificationValidator.Validate(payload));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(33)]
    public void Validate_ResultCountOutOfRange_Fails(int count)
    {
        var results = Enumerable.Range(0, count).Select(i => Car(i)).ToList();

        var detail = SessionClassificationValidator.Validate(ValidPayload() with { Results = results });

        Assert.NotNull(detail);
        Assert.Contains("results", detail);
    }

    [Fact]
    public void Validate_NullResults_Fails()
    {
        var detail = SessionClassificationValidator.Validate(ValidPayload() with { Results = null });

        Assert.NotNull(detail);
        Assert.Contains("results", detail);
    }

    [Fact]
    public void Validate_DuplicateCarIndex_Fails()
    {
        var detail = SessionClassificationValidator.Validate(WithResults(Car(0, isPlayer: true), Car(1), Car(1)));

        Assert.Equal("carIndex 중복(1)", detail);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(32)]
    public void Validate_CarIndexOutOfRange_Fails(int carIndex)
    {
        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { CarIndex = carIndex }));

        Assert.NotNull(detail);
        Assert.Contains("carIndex", detail);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(33)]
    public void Validate_PositionOutOfRange_Fails(int position)
    {
        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { Position = position }));

        Assert.NotNull(detail);
        Assert.Contains("position", detail);
    }

    [Theory]
    [InlineData("bestLapTimeMs")]
    [InlineData("numLaps")]
    [InlineData("penaltiesTimeMs")]
    public void Validate_NegativeValue_Fails(string field)
    {
        var detail = SessionClassificationValidator.Validate(WithRow(WithNegative(Car(1), field)));

        Assert.NotNull(detail);
        Assert.Contains(field, detail);
    }

    [Theory]
    [InlineData("gridPosition")]
    [InlineData("points")]
    [InlineData("numPitStops")]
    [InlineData("numPenalties")]
    [InlineData("totalRaceTimeMs")]
    public void Validate_OtherNegativeValues_Fail(string field)
    {
        var detail = SessionClassificationValidator.Validate(WithRow(WithNegative(Car(1), field)));

        Assert.NotNull(detail);
        Assert.Contains(field, detail);
    }

    [Fact]
    public void Validate_NegativeRaceNumber_Fails()
    {
        // DriverKey("name:{NAME}#{raceNumber}")가 열 길이(80)를 넘지 않도록 음수 차 번호를 거른다.
        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { RaceNumber = -1 }));

        Assert.NotNull(detail);
        Assert.Contains("raceNumber", detail);
    }

    [Fact]
    public void Validate_DriverNameOver64_Fails()
    {
        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { DriverName = new string('A', 65) }));

        Assert.NotNull(detail);
        Assert.Contains("driverName", detail);
    }

    [Fact]
    public void Validate_TooManyStints_Fails()
    {
        var stints = Enumerable.Range(1, 9).Select(n => new TyreStintDto(n * 3, "Soft", "C5")).ToList();

        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { TyreStints = stints }));

        Assert.NotNull(detail);
        Assert.Contains("tyreStints", detail);
    }

    [Fact]
    public void Validate_NullStints_AreTreatedAsEmpty()
    {
        Assert.Null(SessionClassificationValidator.Validate(WithRow(Car(1) with { TyreStints = null })));
    }

    [Fact]
    public void Validate_NullElements_Fail()
    {
        var nullResult = SessionClassificationValidator.Validate(
            ValidPayload() with { Results = new List<ClassifiedResultDto> { Car(0, isPlayer: true), null! } });
        var nullStint = SessionClassificationValidator.Validate(
            WithRow(Car(1) with { TyreStints = new List<TyreStintDto> { null! } }));

        Assert.NotNull(nullResult);
        Assert.NotNull(nullStint);
    }

    [Fact]
    public void Validate_StintNegativeEndLap_Fails()
    {
        var stints = new List<TyreStintDto> { new(EndLap: -1, VisualCompound: "Soft", ActualCompound: "C5") };

        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { TyreStints = stints }));

        Assert.NotNull(detail);
        Assert.Contains("endLap", detail);
    }

    [Fact]
    public void Validate_ActualCompoundOver10_Fails()
    {
        var stints = new List<TyreStintDto> { new(EndLap: 10, VisualCompound: "Soft", ActualCompound: new string('C', 11)) };

        var detail = SessionClassificationValidator.Validate(WithRow(Car(1) with { TyreStints = stints }));

        Assert.NotNull(detail);
        Assert.Contains("actualCompound", detail);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("123456789012345678901234567890123")] // 33자
    public void Validate_BadSessionRef_Fails(string? sessionRef)
    {
        var detail = SessionClassificationValidator.Validate(ValidPayload() with { SessionRef = sessionRef! });

        Assert.NotNull(detail);
        Assert.Contains("sessionRef", detail);
    }

    [Fact]
    public void Validate_TwoPlayers_Fails()
    {
        var detail = SessionClassificationValidator.Validate(WithResults(Car(0, isPlayer: true), Car(1, isPlayer: true)));

        Assert.NotNull(detail);
        Assert.Contains("isPlayer", detail);
    }

    private static ClassifiedResultDto WithNegative(ClassifiedResultDto row, string field) => field switch
    {
        "bestLapTimeMs" => row with { BestLapTimeMs = -1 },
        "numLaps" => row with { NumLaps = -1 },
        "penaltiesTimeMs" => row with { PenaltiesTimeMs = -1 },
        "gridPosition" => row with { GridPosition = -1 },
        "points" => row with { Points = -1 },
        "numPitStops" => row with { NumPitStops = -1 },
        "numPenalties" => row with { NumPenalties = -1 },
        "totalRaceTimeMs" => row with { TotalRaceTimeMs = -1 },
        _ => throw new ArgumentOutOfRangeException(nameof(field), field, "테스트 입력 오류"),
    };
}
