using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import.Building;

/// <summary>가져오기 입력(D-55). <paramref name="LinkedSessions"/> = 이 시즌으로 옮길 내 기록 세션(트랙 포함).</summary>
public sealed record SeasonImportInput(
    Guid UserId,
    ImportBundle Bundle,
    IReadOnlyDictionary<int, Track> TracksByRound,
    IReadOnlyList<GameSession> LinkedSessions,
    long SeasonLinkId,
    DateTime Now,
    Func<Guid> NewId);

/// <summary>기록 세션 하나를 이 시즌의 주말로 옮긴다(키·모드 변경은 저장할 때 서비스가 한다).</summary>
public sealed record SessionAttachment(GameSession Session, RaceWeekend Weekend);

/// <summary>가져오기로 만들 것 전부(저장 전, D-55). 미리보기는 이것을 저장하지 않고 보여 준다.</summary>
public sealed record SeasonImportGraph(
    Season Season,
    IReadOnlyList<RaceWeekend> Weekends,
    IReadOnlyList<GameSession> Sessions,
    IReadOnlyList<SessionAttachment> Attachments,
    ImportedSeasonSnapshot Snapshot,
    IReadOnlyDictionary<Guid, int> RoundByWeekend);

/// <summary>
/// 가져오기 그래프 만들기(docs/15 §12, D-55). 저장소를 쓰지 않는 계산이다(Id·시각은 입력으로 받는다).
/// <list type="bullet">
/// <item>라운드 = 인게임 라운드 열 ∪ F1Laps 요약의 값 있는 라운드 ∪ F1Laps 세션의 트랙. 주말 = 라운드 트랙(옮길 기록 세션의 주말이 같은 트랙이면 그 주말).</item>
/// <item>세션: F1Laps 세션마다 1개(같은 라운드·종류의 기록 세션이 있으면 기록이 우선), 본 레이스 1개(인게임 + F1Laps 레이스 + 요약을 합침),
/// 예선 내보내기·기록이 없으면 요약의 예선 1개. 스프린트 주말(스프린트·슛아웃 내보내기가 있는 주말)은 게임과 같이
/// 스프린트 = Race, 본 레이스 = Race2다.</item>
/// <item>분류 시각(가짜): 라운드 순서대로 가장 이른 기록 세션(또는 지금)보다 앞, 주말 안에서는 연습 → 슛아웃 → 스프린트 → 예선 → 레이스.</item>
/// <item>스탠딩 기준선: 인게임 순위표가 있으면 TOT·컨스트럭터 표(권위), 없으면 F1Laps 요약의 Driver Standings.</item>
/// </list>
/// </summary>
public static class SeasonImportBuilder
{
    public const string ImportSource = "F1Laps";

    private const string InGameSource = "InGame";

    public static SeasonImportGraph Build(SeasonImportInput input)
    {
        ArgumentNullException.ThrowIfNull(input);

        var bundle = input.Bundle;
        var playerTeamId = ImportTeams.Resolve(PlayerTeamName(bundle));
        var roster = new DriverRoster(bundle.InGame, bundle.PlayerName, playerTeamId);
        var season = new Season
        {
            Id = input.NewId(),
            UserId = input.UserId,
            GameCode = bundle.GameCode,
            SeasonLinkId = input.SeasonLinkId,
            GameMode = bundle.GameMode,
            ImportedFrom = ImportSource,
            ImportedAt = input.Now,
            CreatedAt = input.Now,
        };

        var weekends = new Dictionary<int, RaceWeekend>();
        var attachments = AttachLinked(input, season, weekends);
        var linkedKinds = attachments.Select(a => (Round: a.Session.Track?.DisplayOrder ?? 0, a.Session.SessionKind)).ToHashSet();

        var factory = new ImportSessionFactory(input.UserId, season.Id, bundle.GameCode, bundle.GameMode, input.Now, input.NewId, roster);
        var anchor = input.LinkedSessions.Select(s => s.ClassifiedAt).Append(input.Now).Min();
        var sessions = new List<GameSession>();
        foreach (var sources in RoundsOf(bundle, roster))
        {
            var created = BuildRound(sources, factory, linkedKinds);
            if (created.Count == 0)
            {
                continue;
            }

            var track = input.TracksByRound.GetValueOrDefault(sources.Round)
                ?? throw new F1LapsFormatException(0, $"라운드 {sources.Round}의 트랙을 찾을 수 없습니다.");
            var weekend = weekends.GetValueOrDefault(sources.Round) ?? NewWeekend(input, season, sources.Round, track);
            weekends[sources.Round] = weekend;
            foreach (var (session, order) in created)
            {
                session.SeasonId = season.Id;
                session.RaceWeekendId = weekend.Id;
                session.TrackId = track.Id;
                session.SeasonLinkId = season.SeasonLinkId;
                session.WeekendLinkId = weekend.WeekendLinkId;
                session.ClassifiedAt = SyntheticTime(anchor, sources.Round, order);
                sessions.Add(session);
            }
        }

        FinishTimes(season, weekends.Values, sessions, attachments);
        var snapshot = Snapshot(bundle, roster, playerTeamId);
        season.ImportedStandings = snapshot.ToJson();
        var roundByWeekend = weekends.ToDictionary(p => p.Value.Id, p => p.Key);
        return new SeasonImportGraph(season, weekends.Values.ToList(), sessions, attachments, snapshot, roundByWeekend);
    }

    private static string? PlayerTeamName(ImportBundle bundle)
        => bundle.InGame?.Drivers.FirstOrDefault(d => d.IsPlayer)?.TeamName
            ?? bundle.Summary?.TeamName
            ?? bundle.Sessions.Select(s => s.TeamName).FirstOrDefault(t => t is not null);

    /// <summary>옮길 기록 세션을 주말 링크별 주말에 넣는다. 주말 트랙과 다른 트랙의 세션은 옮기지 않는다.</summary>
    private static List<SessionAttachment> AttachLinked(SeasonImportInput input, Season season, Dictionary<int, RaceWeekend> weekends)
    {
        var attachments = new List<SessionAttachment>();
        foreach (var group in input.LinkedSessions.GroupBy(s => s.WeekendLinkId).OrderBy(g => g.Min(s => s.ClassifiedAt)))
        {
            var first = group.OrderBy(s => s.ClassifiedAt).First();
            var weekend = new RaceWeekend
            {
                Id = input.NewId(),
                SeasonId = season.Id,
                WeekendLinkId = group.Key,
                TrackId = first.TrackId,
                CreatedAt = input.Now,
            };

            var round = first.Track?.DisplayOrder ?? 0;
            if (round is >= 1 and <= ImportCalendar.RoundCount)
            {
                weekends.TryAdd(round, weekend);
            }
            else
            {
                weekends[-weekends.Count - 1] = weekend;
            }

            attachments.AddRange(group.Where(s => s.TrackId == weekend.TrackId).Select(s => new SessionAttachment(s, weekend)));
        }

        return attachments;
    }

    /// <summary>
    /// 기록 세션이 없는 라운드의 주말. 게임 링크가 없어 주말 링크 = −라운드(게임 링크는 0이 아닌 양수라 겹치지 않는다).
    /// 내비게이션(Track)은 채우지 않는다 — 추적되지 않은 트랙을 EF가 새로 넣으려 하지 않게.
    /// </summary>
    private static RaceWeekend NewWeekend(SeasonImportInput input, Season season, int round, Track track) => new()
    {
        Id = input.NewId(),
        SeasonId = season.Id,
        WeekendLinkId = -round,
        TrackId = track.Id,
        CreatedAt = input.Now,
    };

    /// <summary>문서들에서 라운드별 재료를 모은다(라운드 번호 순).</summary>
    private static IEnumerable<RoundSources> RoundsOf(ImportBundle bundle, DriverRoster roster)
    {
        var inGameCells = new List<(int Round, RosterDriver Driver, InGameRaceCell Cell)>();
        if (bundle.InGame is { } inGame)
        {
            for (var i = 0; i < inGame.Drivers.Count; i++)
            {
                var driver = roster.OfInGameRow(i);
                inGameCells.AddRange(inGame.Drivers[i].Cells.Select(c => (c.Round, driver, c)));
            }
        }

        var summaryRounds = (bundle.Summary?.Rounds ?? []).Where(r => r.HasRace || r.HasQualifying).ToDictionary(r => r.Number);
        var rounds = inGameCells.Select(c => c.Round)
            .Concat(summaryRounds.Keys)
            .Concat(bundle.Sessions.Select(s => s.Round))
            .Distinct()
            .Order();

        foreach (var round in rounds)
        {
            yield return new RoundSources(
                round,
                inGameCells.Where(c => c.Round == round).Select(c => (c.Driver, c.Cell)).ToList(),
                bundle.Sessions.Where(s => s.Round == round).ToList(),
                summaryRounds.GetValueOrDefault(round));
        }
    }

    /// <summary>한 라운드의 세션들과 주말 안 순서 번호.</summary>
    private static List<(GameSession Session, int Order)> BuildRound(
        RoundSources sources, ImportSessionFactory factory, HashSet<(int Round, SessionKind Kind)> linkedKinds)
    {
        var created = new List<(GameSession, int)>();
        var usedKinds = new HashSet<SessionKind>();
        var sprintWeekend = sources.Sessions.Any(s => s.IsSprint || IsShootout(s.SessionKind));

        foreach (var doc in sources.Sessions.Where(s => !IsMainRace(s)))
        {
            var kind = doc.SessionKind;
            if (linkedKinds.Contains((sources.Round, kind)) || !usedKinds.Add(kind))
            {
                continue;
            }

            created.Add((factory.FromDocument(doc, kind), OrderOf(doc.SessionType, kind, doc.IsSprint)));
        }

        var mainKind = sprintWeekend ? SessionKind.Race2 : SessionKind.Race;
        if (!linkedKinds.Contains((sources.Round, mainKind))
            && factory.MainRace(sources, sources.Sessions.FirstOrDefault(IsMainRace), mainKind) is { } race)
        {
            created.Add((race, OrderOf(SessionType.Race, mainKind, isSprint: false)));
        }

        var hasQualifying = created.Any(c => IsQualifying(c.Item1.SessionKind))
            || linkedKinds.Any(k => k.Round == sources.Round && IsQualifying(k.Kind));
        if (!hasQualifying && sources.Summary is { HasQualifying: true } summary)
        {
            created.Add((factory.SummaryQualifying(summary), OrderOf(SessionType.Qualifying, SessionKind.ShortQualifying, false)));
        }

        return created;
    }

    private static bool IsMainRace(F1LapsSessionDocument doc) => doc.SessionType == SessionType.Race && !doc.IsSprint;

    private static bool IsShootout(SessionKind kind) => kind is
        SessionKind.SprintShootout1 or SessionKind.SprintShootout2 or SessionKind.SprintShootout3
        or SessionKind.ShortSprintShootout or SessionKind.OneShotSprintShootout;

    private static bool IsQualifying(SessionKind kind) => kind is
        SessionKind.Qualifying1 or SessionKind.Qualifying2 or SessionKind.Qualifying3 or SessionKind.ShortQualifying or SessionKind.OneShotQualifying;

    /// <summary>주말 안 순서: 연습(0~3) → 슛아웃(4~8) → 스프린트(9) → 예선(10~14) → 레이스(15).</summary>
    private static int OrderOf(SessionType type, SessionKind kind, bool isSprint) => kind switch
    {
        SessionKind.Practice1 => 0,
        SessionKind.Practice2 => 1,
        SessionKind.Practice3 => 2,
        SessionKind.ShortPractice => 3,
        SessionKind.SprintShootout1 => 4,
        SessionKind.SprintShootout2 => 5,
        SessionKind.SprintShootout3 => 6,
        SessionKind.ShortSprintShootout => 7,
        SessionKind.OneShotSprintShootout => 8,
        _ when type == SessionType.Race && isSprint => 9,
        SessionKind.Qualifying1 => 10,
        SessionKind.Qualifying2 => 11,
        SessionKind.Qualifying3 => 12,
        SessionKind.ShortQualifying => 13,
        SessionKind.OneShotQualifying => 14,
        _ => 15,
    };

    /// <summary>라운드 r의 주말 = 기준 시각 − (25 − r)일, 세션은 그 안에서 순서마다 1시간씩.</summary>
    private static DateTime SyntheticTime(DateTime anchor, int round, int order)
        => DateTime.SpecifyKind(anchor, DateTimeKind.Utc).AddDays(-(ImportCalendar.RoundCount + 1 - round)).AddHours(order);

    private static void FinishTimes(
        Season season, IEnumerable<RaceWeekend> weekends, List<GameSession> sessions, List<SessionAttachment> attachments)
    {
        var times = sessions.Select(s => (s.RaceWeekendId, s.ClassifiedAt))
            .Concat(attachments.Select(a => ((Guid?)a.Weekend.Id, a.Session.ClassifiedAt)))
            .ToList();
        foreach (var weekend in weekends)
        {
            weekend.FirstSessionAt = times.Where(t => t.Item1 == weekend.Id).Select(t => t.Item2).DefaultIfEmpty(season.CreatedAt).Min();
        }

        season.FirstSessionAt = times.Select(t => t.Item2).DefaultIfEmpty(season.CreatedAt).Min();
        season.LastSessionAt = times.Select(t => t.Item2).DefaultIfEmpty(season.CreatedAt).Max();
    }

    private static ImportedSeasonSnapshot Snapshot(ImportBundle bundle, DriverRoster roster, int? playerTeamId)
    {
        var teamName = bundle.Summary?.TeamName ?? PlayerTeamName(bundle);
        if (bundle.InGame is { } inGame)
        {
            var drivers = inGame.Drivers
                .Select((row, i) => new ImportedDriverPoints(row.Name, row.Total, row.IsPlayer, roster.OfInGameRow(i).TeamId))
                .ToList();
            var constructors = inGame.Constructors
                .Select(c => (TeamId: ImportTeams.Resolve(c.TeamName), c.Points))
                .Where(c => c.TeamId is not null)
                .Select(c => new ImportedConstructorPoints(c.TeamId!.Value, c.Points))
                .ToList();
            return new ImportedSeasonSnapshot(bundle.Title, bundle.PlayerName, teamName, InGameSource, drivers, constructors);
        }

        var summaryDrivers = bundle.Summary!.Drivers
            .Select(d => new ImportedDriverPoints(d.IsPlayer ? bundle.PlayerName : d.Name, d.Points, d.IsPlayer, d.IsPlayer ? playerTeamId : null))
            .ToList();
        return new ImportedSeasonSnapshot(bundle.Title, bundle.PlayerName, teamName, ImportSource, summaryDrivers);
    }
}
