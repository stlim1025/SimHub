using System.Text.Json;
using System.Text.Json.Serialization;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

public class SessionResultTrackerTests
{
    private const int TrackId = 10;
    private const uint SeasonLink = 11;
    private const uint WeekendLink = 22;
    private const uint SessionLink = 33;
    private const int TotalLaps = 29;
    private const int AiDifficulty = 85;

    private readonly SessionResultTracker _sut = new();

    private static SessionFrame Session(
        string sessionRef,
        SessionType type = SessionType.Race,
        GameMode mode = GameMode.DriverCareer,
        uint seasonLink = SeasonLink)
        => new(
            sessionRef,
            TrackId,
            type,
            PacketFormat: 2025,
            SessionKind.Race,
            mode,
            seasonLink,
            WeekendLink,
            SessionLink,
            TotalLaps,
            AiDifficulty,
            IsNetworkGame: false);

    // 일부러 carIndex 역순으로 만든다 — 결합 키가 목록 위치가 아니라 carIndex임을 보이기 위해서다.
    private static ParticipantsFrame Participants(string sessionRef, int count)
        => new(sessionRef, Enumerable.Range(0, count).Reverse().Select(Participant).ToList());

    private static ParticipantInfo Participant(int carIndex)
        => new(carIndex, $"Driver {carIndex}", GameDriverId: 100 + carIndex, TeamId: 10 + carIndex,
            RaceNumber: 40 + carIndex, IsAiControlled: carIndex % 2 == 0);

    private static ClassificationFrame Classification(string sessionRef, int count, int player = 0)
        => new(sessionRef, player, Enumerable.Range(0, count).Select(Row).ToList());

    private static ClassificationRow Row(int carIndex)
        => new(
            CarIndex: carIndex,
            Position: carIndex + 1,
            GridPosition: 5 - carIndex,
            NumLaps: TotalLaps,
            Points: 25 - (carIndex * 7),
            NumPitStops: 1,
            NumPenalties: carIndex,
            ResultStatus: ResultStatus.Finished,
            BestLapTimeMs: 81000 + carIndex,
            TotalRaceTimeMs: 2490000 + (carIndex * 1000),
            PenaltiesTimeMs: carIndex * 5000,
            TyreStints: new[]
            {
                new TyreStint(10 + carIndex, TyreCompound.Medium, "C3"),
                new TyreStint(TotalLaps, TyreCompound.Hard, null),
            });

    [Fact]
    public void Classification_WithContextAndParticipants_EmitsOneEvent()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));

        var events = _sut.Process(Classification("A", 3, player: 1));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal(TelemetryEventType.SessionClassified, classified.Type);
        Assert.Equal("A", classified.SessionRef);
        Assert.Equal(TrackId, classified.TrackId);
        Assert.Equal(SessionType.Race, classified.SessionType);
        Assert.Equal(SessionKind.Race, classified.SessionKind);
        Assert.Equal(GameMode.DriverCareer, classified.GameMode);
        Assert.Equal(SeasonLink, classified.SeasonLinkId);
        Assert.Equal(WeekendLink, classified.WeekendLinkId);
        Assert.Equal(SessionLink, classified.SessionLinkId);
        Assert.Equal(TotalLaps, classified.TotalLaps);
        Assert.Equal(AiDifficulty, classified.AiDifficulty);
        Assert.False(classified.IsNetworkGame);
        Assert.Equal(3, classified.Results.Count);

        for (var car = 0; car < 3; car++)
        {
            var result = classified.Results[car];
            var row = Row(car);
            Assert.Equal(car, result.CarIndex);
            Assert.Equal(car == 1, result.IsPlayer);
            Assert.Equal(row.Position, result.Position);
            Assert.Equal(row.GridPosition, result.GridPosition);
            Assert.Equal(row.NumLaps, result.NumLaps);
            Assert.Equal(row.Points, result.Points);
            Assert.Equal(row.NumPitStops, result.NumPitStops);
            Assert.Equal(row.NumPenalties, result.NumPenalties);
            Assert.Equal(row.ResultStatus, result.ResultStatus);
            Assert.Equal(row.BestLapTimeMs, result.BestLapTimeMs);
            Assert.Equal(row.TotalRaceTimeMs, result.TotalRaceTimeMs);
            Assert.Equal(row.PenaltiesTimeMs, result.PenaltiesTimeMs);
            Assert.Equal($"Driver {car}", result.DriverName);
            Assert.Equal(100 + car, result.GameDriverId);
            Assert.Equal(10 + car, result.TeamId);
            Assert.Equal(40 + car, result.RaceNumber);
            Assert.Equal(car % 2 == 0, result.IsAiControlled);
            Assert.Equal(row.TyreStints, result.TyreStints);
        }
    }

    [Fact]
    public void SecondClassification_SameSessionRef_IsIgnored()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));
        Assert.Single(_sut.Process(Classification("A", 3)));

        var again = _sut.Process(Classification("A", 3));

        Assert.Empty(again);
    }

    [Fact]
    public void Classification_ForDifferentSessionRef_IsIgnored()
    {
        _sut.Process(Session("A"));

        var events = _sut.Process(Classification("B", 3));

        Assert.Empty(events);
    }

    [Fact]
    public void Classification_WithoutContext_IsIgnored()
    {
        var events = _sut.Process(Classification("A", 3));

        Assert.Empty(events);
    }

    [Fact]
    public void Classification_InTimeTrial_IsIgnored()
    {
        _sut.Process(Session("A", SessionType.TimeTrial));
        _sut.Process(Participants("A", 3));

        var events = _sut.Process(Classification("A", 3));

        Assert.Empty(events);
    }

    [Fact]
    public void MissingParticipant_SendsNullIdentity()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 2));

        var events = _sut.Process(Classification("A", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal(3, classified.Results.Count);

        // 참가자가 있는 차는 결합된다(0번 차는 AI).
        Assert.Equal("Driver 0", classified.Results[0].DriverName);
        Assert.True(classified.Results[0].IsAiControlled);

        var missing = classified.Results[2];
        Assert.Equal(2, missing.CarIndex);
        Assert.Null(missing.DriverName);
        Assert.Null(missing.GameDriverId);
        Assert.Null(missing.TeamId);
        Assert.Null(missing.RaceNumber);
        Assert.False(missing.IsAiControlled);
        Assert.Equal(Row(2).Points, missing.Points); // 순위표 쪽 값은 그대로
    }

    [Fact]
    public void NewSessionRef_ClearsParticipants()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));
        _sut.Process(Session("B"));

        var events = _sut.Process(Classification("B", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.All(classified.Results, r =>
        {
            Assert.Null(r.DriverName);
            Assert.Null(r.GameDriverId);
            Assert.Null(r.TeamId);
            Assert.Null(r.RaceNumber);
            Assert.False(r.IsAiControlled);
        });
    }

    [Fact]
    public void RepeatedSessionFrame_SameSessionRef_KeepsParticipants()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));
        _sut.Process(Session("A")); // Session 패킷은 초당 2회 — 같은 세션이면 참가자를 지우지 않는다.

        var events = _sut.Process(Classification("A", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.All(classified.Results, r => Assert.NotNull(r.DriverName));
    }

    [Fact]
    public void LatestSessionFrame_ProvidesContext()
    {
        _sut.Process(Session("A", seasonLink: 0));
        _sut.Process(Session("A", seasonLink: SeasonLink)); // 같은 세션의 뒤 프레임이 맥락을 갱신

        var events = _sut.Process(Classification("A", 1));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal(SeasonLink, classified.SeasonLinkId);
    }

    [Fact]
    public void ParticipantsForOtherSession_AreIgnored()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("B", 3));

        var events = _sut.Process(Classification("A", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.All(classified.Results, r => Assert.Null(r.DriverName));
    }

    [Fact]
    public void ParticipantsBeforeAnySession_AreIgnored()
    {
        _sut.Process(Participants("A", 3));
        _sut.Process(Session("A"));

        var events = _sut.Process(Classification("A", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.All(classified.Results, r => Assert.Null(r.DriverName));
    }

    [Fact]
    public void Participants_AreMatchedByCarIndex_NotListPosition()
    {
        _sut.Process(Session("A"));
        _sut.Process(new ParticipantsFrame("A", new[] { Participant(7), Participant(3) }));

        var events = _sut.Process(new ClassificationFrame("A", PlayerCarIndex: 3, new[] { Row(3), Row(7) }));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal("Driver 3", classified.Results[0].DriverName);
        Assert.Equal(3, classified.Results[0].CarIndex);
        Assert.True(classified.Results[0].IsPlayer);
        Assert.Equal("Driver 7", classified.Results[1].DriverName);
        Assert.False(classified.Results[1].IsPlayer);
    }

    [Fact]
    public void LatestParticipantsFrame_ReplacesEarlier_AndDuplicateCarIndexDoesNotThrow()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));
        _sut.Process(new ParticipantsFrame("A", new[]
        {
            new ParticipantInfo(0, "First", 1, 1, 1, false),
            new ParticipantInfo(0, "Second", 2, 2, 2, true),
        }));

        var events = _sut.Process(Classification("A", 2));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal("Second", classified.Results[0].DriverName);
        Assert.Null(classified.Results[1].DriverName); // 새 목록에 없는 차는 이전 목록에서 가져오지 않는다.
    }

    [Fact]
    public void Classification_WithNoRows_IsIgnored_AndDoesNotConsumeSession()
    {
        _sut.Process(Session("A"));

        var empty = _sut.Process(new ClassificationFrame("A", 0, Array.Empty<ClassificationRow>()));
        var real = _sut.Process(Classification("A", 3));

        Assert.Empty(empty);
        Assert.IsType<SessionClassified>(Assert.Single(real));
    }

    [Fact]
    public void NewSessionAfterEmit_EmitsAgain()
    {
        _sut.Process(Session("A"));
        Assert.Single(_sut.Process(Classification("A", 3)));

        _sut.Process(Session("B"));
        var events = _sut.Process(Classification("B", 3));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.Equal("B", classified.SessionRef);
    }

    [Fact]
    public void SessionEnded_DoesNotResetTracker()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 3));

        var onEnd = _sut.Process(new EventMarker("A", SessionBoundary.End));
        var events = _sut.Process(Classification("A", 3));

        Assert.Empty(onEnd);
        var classified = Assert.IsType<SessionClassified>(Assert.Single(events));
        Assert.All(classified.Results, r => Assert.NotNull(r.DriverName));
    }

    [Fact]
    public void LapFrame_IsIgnored()
    {
        _sut.Process(Session("A"));

        var events = _sut.Process(new LapFrame("A", 1, 0, 0, 0, 0, false, false));

        Assert.Empty(events);
    }

    [Fact]
    public void SessionClassified_SerializesToSpecShape_CamelCaseWithStringEnums()
    {
        _sut.Process(Session("A"));
        _sut.Process(Participants("A", 2));
        var classified = Assert.IsType<SessionClassified>(Assert.Single(_sut.Process(Classification("A", 2, player: 1))));

        var json = JsonSerializer.Serialize<object>(classified, WireJson);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        // 봉투 직렬화(OutboxTelemetrySink)와 같은 옵션: Web 기본값(camelCase) + 문자열 enum. "type"은 기존 이벤트와 같이 베이스 속성이 함께 실린다.
        Assert.Equal(
            new[] { "sessionRef", "trackId", "sessionType", "sessionKind", "gameMode", "seasonLinkId", "weekendLinkId", "sessionLinkId", "totalLaps", "aiDifficulty", "isNetworkGame", "results", "lapPositions" }.Order(),
            root.EnumerateObject().Select(p => p.Name).Where(n => n != "type").Order());
        Assert.Equal("A", root.GetProperty("sessionRef").GetString());
        Assert.Equal("Race", root.GetProperty("sessionType").GetString());
        Assert.Equal("Race", root.GetProperty("sessionKind").GetString());
        Assert.Equal("DriverCareer", root.GetProperty("gameMode").GetString());
        Assert.Equal(SeasonLink, root.GetProperty("seasonLinkId").GetUInt32());
        Assert.Equal(WeekendLink, root.GetProperty("weekendLinkId").GetUInt32());
        Assert.Equal(SessionLink, root.GetProperty("sessionLinkId").GetUInt32());

        var player = root.GetProperty("results")[1];
        Assert.Equal(
            new[] { "carIndex", "isPlayer", "position", "gridPosition", "numLaps", "points", "numPitStops", "numPenalties", "resultStatus", "bestLapTimeMs", "totalRaceTimeMs", "penaltiesTimeMs", "driverName", "gameDriverId", "teamId", "raceNumber", "isAiControlled", "tyreStints", "lapHistory" }.Order(),
            player.EnumerateObject().Select(p => p.Name).Order());
        Assert.True(player.GetProperty("isPlayer").GetBoolean());
        Assert.Equal("Finished", player.GetProperty("resultStatus").GetString());

        var stints = player.GetProperty("tyreStints");
        Assert.Equal(
            new[] { "endLap", "visualCompound", "actualCompound" }.Order(),
            stints[0].EnumerateObject().Select(p => p.Name).Order());
        Assert.Equal("Medium", stints[0].GetProperty("visualCompound").GetString());
        Assert.Equal("C3", stints[0].GetProperty("actualCompound").GetString());
        Assert.Equal(JsonValueKind.Null, stints[1].GetProperty("actualCompound").ValueKind);
    }

    // ---- D-49: 전 차량 랩 기록·랩별 순위 ----

    private static LapHistoryEntry HistoryLap(int lap, int ms) => new(lap, ms, 27_000, 30_000, ms - 57_000, true, true, true, true);

    [Fact]
    public void Classified_CarriesLapHistoryPerCar_LatestPacketWins()
    {
        _sut.Process(Session("A"));
        _sut.Process(new SessionHistoryFrame("A", 0, IsPlayer: true, [HistoryLap(1, 90_000)]));
        _sut.Process(new SessionHistoryFrame("A", 0, IsPlayer: true, [HistoryLap(1, 90_000), HistoryLap(2, 89_000)]));
        _sut.Process(new SessionHistoryFrame("A", 1, IsPlayer: false, [HistoryLap(1, 91_000)]));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(_sut.Process(Classification("A", 3))));

        Assert.Equal(new[] { HistoryLap(1, 90_000), HistoryLap(2, 89_000) }, classified.Results[0].LapHistory);
        Assert.Equal(new[] { HistoryLap(1, 91_000) }, classified.Results[1].LapHistory);
        Assert.Null(classified.Results[2].LapHistory);   // 받지 못한 차
    }

    [Fact]
    public void Classified_MergesLapPositionsAcrossPackets_InLapOrder()
    {
        _sut.Process(Session("A"));
        _sut.Process(new LapPositionsFrame("A", FirstLapNumber: 3, [new[] { 2, 1 }, new[] { 1, 2 }]));
        _sut.Process(new LapPositionsFrame("A", FirstLapNumber: 1, [new[] { 1, 2 }, new[] { 1, 2 }, new[] { 9, 9 }]));   // 랩 3은 나중 값

        var classified = Assert.IsType<SessionClassified>(Assert.Single(_sut.Process(Classification("A", 2))));

        var positions = Assert.IsAssignableFrom<IReadOnlyList<LapPositionsEntry>>(classified.LapPositions);
        Assert.Equal(new[] { 1, 2, 3, 4 }, positions.Select(lap => lap.LapNumber));
        Assert.Equal(new[] { 9, 9 }, positions[2].Positions);
        Assert.Equal(new[] { 1, 2 }, positions[3].Positions);
    }

    [Fact]
    public void LapRecords_FromOtherSession_OrBeforeSession_AreIgnored_AndNewSessionClears()
    {
        _sut.Process(new SessionHistoryFrame("A", 0, IsPlayer: true, [HistoryLap(1, 90_000)]));   // 세션 맥락 전
        _sut.Process(Session("A"));
        _sut.Process(new LapPositionsFrame("B", 1, [new[] { 1 }]));                               // 다른 세션
        _sut.Process(new SessionHistoryFrame("A", 1, IsPlayer: false, [HistoryLap(1, 91_000)]));
        _sut.Process(Session("B"));                                                               // 세션 변경 = 비움

        var classified = Assert.IsType<SessionClassified>(Assert.Single(_sut.Process(Classification("B", 2))));

        Assert.All(classified.Results, result => Assert.Null(result.LapHistory));
        Assert.Null(classified.LapPositions);
    }

    [Fact]
    public void LapPositions_OutOfRangeLapNumbers_AreDropped()
    {
        _sut.Process(Session("A"));
        _sut.Process(new LapPositionsFrame("A", FirstLapNumber: SessionLapRecords.MaxLapNumber, [new[] { 1 }, new[] { 2 }]));

        var classified = Assert.IsType<SessionClassified>(Assert.Single(_sut.Process(Classification("A", 1))));

        Assert.Equal(new[] { SessionLapRecords.MaxLapNumber }, classified.LapPositions!.Select(lap => lap.LapNumber));
    }

    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };
}
