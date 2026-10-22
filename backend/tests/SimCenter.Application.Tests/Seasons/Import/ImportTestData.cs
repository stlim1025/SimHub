using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Tests.Seasons.Import;

/// <summary>가져오기 테스트 재료(docs/15 §12, D-55): 사용자가 준 원문 픽스처 · F1 25 캘린더 트랙 · 기록된 마이애미 예선.</summary>
internal static class ImportTestData
{
    public const long MiamiSeasonLink = 2160041047;
    public const long MiamiWeekendLink = 2160041547;

    public static readonly DateTime Now = new(2026, 10, 18, 12, 0, 0, DateTimeKind.Utc);

    private static readonly string[] CalendarNames =
    [
        "Melbourne", "Shanghai", "Suzuka", "Sakhir (Bahrain)", "Jeddah", "Miami", "Imola", "Monaco", "Catalunya", "Montreal",
        "Austria (Red Bull Ring)", "Silverstone", "Spa", "Hungaroring", "Zandvoort", "Monza", "Baku (Azerbaijan)", "Singapore",
        "Texas (COTA)", "Mexico", "Brazil (Interlagos)", "Las Vegas", "Losail (Qatar)", "Abu Dhabi",
    ];

    public static string Summary => Fixture("f1laps_season_driver_career.md");

    public static string InGame => Fixture("ingame_season1.md");

    public static string Sessions => Fixture("f1laps_session_sample.md");

    /// <summary>합성 My Team 묶음: 시즌 요약(팀 TEAM ALPHA) + 세션 2개(순위표 Team 칸: "My Team"·Kick Sauber·Haas F1 Team·Red Bull Racing).</summary>
    public static string MyTeam => Fixture("f1laps_myteam_sample.md");

    /// <summary>사용자가 한 번에 붙여 넣는 모양: 인게임 순위표 + F1Laps 요약 + F1Laps 세션들.</summary>
    public static string All => string.Join("\n\n", InGame, Summary, Sessions);

    public static string Fixture(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", name));

    public static Guid Id(int number) => new(number, 0, 0, new byte[8]);

    /// <summary>라운드 → 트랙(DisplayOrder = 라운드).</summary>
    public static Dictionary<int, Track> Tracks()
        => CalendarNames.Select((name, i) => new Track
        {
            Id = Id(1000 + i + 1),
            GameCode = GameCodes.F1_25,
            GameTrackId = i,
            Name = name,
            DisplayOrder = i + 1,
        }).ToDictionary(t => t.DisplayOrder);

    /// <summary>기록된 마이애미 Q1~Q3(예전 Other 모드, uid 키 — 실제 dev DB 모양).</summary>
    public static List<GameSession> MiamiQualifying(Track miami, Guid userId)
    {
        SessionKind[] kinds = [SessionKind.Qualifying1, SessionKind.Qualifying2, SessionKind.Qualifying3];
        return kinds.Select((kind, i) =>
        {
            var sessionRef = $"{9000 + i}";
            var sessionId = Id(500 + i);
            return new GameSession
            {
                Id = sessionId,
                UserId = userId,
                AgentDeviceId = Id(77),
                GameCode = GameCodes.F1_25,
                SessionKey = SessionKeys.Uid(sessionRef),
                SeasonLinkId = MiamiSeasonLink,
                WeekendLinkId = MiamiWeekendLink,
                SessionLinkId = 3000 + i,
                SessionRef = sessionRef,
                TrackId = miami.Id,
                Track = miami,
                SessionType = SessionType.Qualifying,
                SessionKind = kind,
                GameMode = GameMode.Other,
                ClassifiedAt = Now.AddDays(-1).AddHours(i),
                CreatedAt = Now.AddDays(-1),
                Results =
                [
                    new SessionResult
                    {
                        Id = Id(600 + i), GameSessionId = sessionId, CarIndex = 3, Position = 5 + i, DriverKey = DriverKeys.Player,
                        DriverName = "GOMDOL SUPER", IsPlayer = true, TeamId = 221, ResultStatus = ResultStatus.Finished, CreatedAt = Now,
                    },
                    new SessionResult
                    {
                        Id = Id(700 + i), GameSessionId = sessionId, CarIndex = 4, Position = 1, DriverKey = "driver:9",
                        DriverName = "NORRIS", TeamId = 228, IsAiControlled = true, ResultStatus = ResultStatus.Finished, CreatedAt = Now,
                    },
                ],
            };
        }).ToList();
    }
}
