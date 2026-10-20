using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

public class GameEditionDetectorTests
{
    private const int MyTeamId = 104;
    private const int RedBull2025 = 2;
    private const int Audi2026Grid = 229;
    private const int Cadillac2026 = 486;

    private static ParticipantInfo Car(int carIndex, int teamId) => new(carIndex, $"D{carIndex}", carIndex, teamId, carIndex + 1, IsAiControlled: carIndex != 0);

    private static ParticipantsFrame Participants(string sessionRef, params int[] teamIds)
        => new(sessionRef, teamIds.Select((t, i) => Car(i, t)).ToList(), PlayerCarIndex: 0);

    private static SessionFrame Session(string sessionRef) => new(sessionRef, TrackId: 7, SessionType.Race, PacketFormat: 2025);

    [Fact]
    public void StartsWithConfiguredDefault()
    {
        Assert.Equal(GameEditions.F1_25, new GameEditionDetector(GameEditions.F1_25).GameCode);
    }

    [Theory]
    [InlineData(Audi2026Grid)]
    [InlineData(Cadillac2026)]
    [InlineData(220)]
    [InlineData(476)]
    public void Any2026Team_SwitchesToF1_26(int teamId)
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);

        sut.Observe(Participants("s1", MyTeamId, teamId));

        Assert.Equal(GameEditions.F1_26, sut.GameCode);
    }

    [Fact]
    public void Only2025Teams_StaysDefault()
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);

        sut.Observe(Participants("s1", MyTeamId, RedBull2025, 185, 9));

        Assert.Equal(GameEditions.F1_25, sut.GameCode);
    }

    [Fact]
    public void StaysF1_26ForTheRestOfTheSession_EvenIfLaterFramesLack2026Teams()
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);

        sut.Observe(Participants("s1", Audi2026Grid));
        sut.Observe(Session("s1"));
        sut.Observe(Participants("s1", RedBull2025));

        Assert.Equal(GameEditions.F1_26, sut.GameCode);
    }

    [Fact]
    public void NewSession_ResetsToDefault()
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);
        sut.Observe(Participants("s1", Audi2026Grid));

        sut.Observe(Session("s2"));

        Assert.Equal(GameEditions.F1_25, sut.GameCode);
    }

    [Fact]
    public void NewSessionSeenFirstByParticipants_ResetsThenDetects()
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);
        sut.Observe(Participants("s1", Audi2026Grid));

        sut.Observe(Participants("s2", RedBull2025));
        Assert.Equal(GameEditions.F1_25, sut.GameCode);

        sut.Observe(Participants("s3", Cadillac2026));
        Assert.Equal(GameEditions.F1_26, sut.GameCode);
    }

    [Fact]
    public void OtherFrames_DoNotChangeState()
    {
        var sut = new GameEditionDetector(GameEditions.F1_25);
        sut.Observe(Participants("s1", Audi2026Grid));

        sut.Observe(new EventMarker("s9", SessionBoundary.Start));

        Assert.Equal(GameEditions.F1_26, sut.GameCode);
    }

    [Theory]
    [InlineData(219, false)]
    [InlineData(231, false)]
    [InlineData(475, false)]
    [InlineData(487, false)]
    [InlineData(230, true)]
    public void Is2026TeamId_MatchesBackendRanges(int teamId, bool expected)
    {
        Assert.Equal(expected, GameEditions.Is2026TeamId(teamId));
    }
}
