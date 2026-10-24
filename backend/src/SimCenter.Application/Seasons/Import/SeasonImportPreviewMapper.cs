using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Import.Building;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 저장 전 그래프 → 미리보기(docs/15 §12, D-55). Standings는 저장 뒤 시즌 화면과 같은 계산(<see cref="SeasonSessionSelector"/> +
/// <see cref="StandingsCalculator"/>)으로 만든다. 순수 함수 — 상태 없음.
/// </summary>
public static class SeasonImportPreviewMapper
{
    private const string ImportedSource = "Imported";
    private const string RecordedSource = "Recorded";

    public static SeasonImportPreviewDto Map(
        ImportBundle bundle,
        SeasonImportGraph graph,
        IReadOnlyDictionary<Guid, string> trackNames,
        long? linkId,
        bool alreadyImported)
    {
        ArgumentNullException.ThrowIfNull(bundle);
        ArgumentNullException.ThrowIfNull(graph);
        ArgumentNullException.ThrowIfNull(trackNames);

        var standings = Standings(graph);
        return new SeasonImportPreviewDto(
            bundle.Title,
            bundle.GameCode,
            bundle.GameMode.ToString(),
            graph.Snapshot.TeamName,
            bundle.PlayerName,
            Documents(bundle),
            Rounds(graph, trackNames),
            standings.Drivers.Select(d =>
            {
                var team = TeamCatalog.Resolve(bundle.GameCode, d.TeamId, d.TeamName);
                return new SeasonImportDriverDto(d.Position, d.Name, team.Name, team.Color, d.Points, d.IsPlayer);
            }).ToList(),
            standings.Constructors.Select(c =>
            {
                var team = TeamCatalog.Resolve(bundle.GameCode, c.TeamId, c.TeamName);
                return new SeasonImportConstructorDto(c.Position, team.Name, team.Color, c.Points);
            }).ToList(),
            linkId is { } id
                ? new SeasonLinkCandidateDto(id, graph.Attachments
                    .OrderBy(a => a.Session.ClassifiedAt)
                    .Select(a => new SeasonLinkCandidateSessionDto(
                        a.Session.Id, a.Session.SessionKind.ToString(), trackNames.GetValueOrDefault(a.Session.TrackId, string.Empty), a.Session.ClassifiedAt))
                    .ToList())
                : null,
            alreadyImported);
    }

    private static List<SeasonImportDocumentDto> Documents(ImportBundle bundle)
    {
        var documents = new List<SeasonImportDocumentDto>();
        if (bundle.InGame is { } inGame)
        {
            var racedRounds = inGame.Drivers.SelectMany(d => d.Cells).Select(c => c.Round).Distinct().Count();
            documents.Add(new SeasonImportDocumentDto("InGameStandings", inGame.Title, inGame.Rounds.Count, racedRounds, inGame.Drivers.Count));
        }

        if (bundle.Summary is { } summary)
        {
            var rounds = summary.Rounds.Where(r => r.HasRace || r.HasQualifying).ToList();
            documents.Add(new SeasonImportDocumentDto(
                "F1LapsSeason", summary.Title, rounds.Count, rounds.Count(r => r.HasRace) + rounds.Count(r => r.HasQualifying), summary.Drivers.Count));
        }

        documents.AddRange(bundle.Sessions.Select(s => new SeasonImportDocumentDto("F1LapsSession", s.Title, 1, 1, s.Classification.Count)));
        return documents;
    }

    private static List<SeasonImportRoundDto> Rounds(SeasonImportGraph graph, IReadOnlyDictionary<Guid, string> trackNames)
    {
        var rounds = RoundNumbering.Assign(graph.Weekends.Select(w => new WeekendRow(
            w.Id, w.SeasonId, string.Empty, w.FirstSessionAt, graph.RoundByWeekend.GetValueOrDefault(w.Id), CalendarRounds: true)));

        return graph.Weekends
            .OrderBy(w => rounds[w.Id])
            .Select(w =>
            {
                var sessions = graph.Sessions.Where(s => s.RaceWeekendId == w.Id).Select(s => (Session: s, Source: ImportedSource))
                    .Concat(graph.Attachments.Where(a => a.Weekend.Id == w.Id).Select(a => (a.Session, Source: RecordedSource)))
                    .OrderBy(x => x.Session.ClassifiedAt)
                    .ToList();
                var myPoints = sessions.SelectMany(x => x.Session.Results).Where(r => r.IsPlayer && !r.IsDeleted).Select(r => r.Points).ToList();
                return new SeasonImportRoundDto(
                    rounds[w.Id],
                    trackNames.GetValueOrDefault(w.TrackId, string.Empty),
                    sessions.Select(x => ToSessionDto(x.Session, x.Source)).ToList(),
                    myPoints.Count == 0 ? null : myPoints.Sum());
            })
            .ToList();
    }

    private static SeasonImportSessionDto ToSessionDto(GameSession session, string source)
    {
        var results = session.Results.Where(r => !r.IsDeleted).ToList();
        var me = results.FirstOrDefault(r => r.IsPlayer);
        var laps = me is null ? 0 : SessionHistory.Parse(session.Details).LapsOf(me.CarIndex).Count(l => l.LapTimeMs > 0);
        return new SeasonImportSessionDto(
            session.SessionType.ToString(), session.SessionKind.ToString(), source, me?.Position, results.Count, laps);
    }

    private static SeasonStandings Standings(SeasonImportGraph graph)
    {
        // 옮길 기록 세션 중 기준선에 이미 든 것은 조회와 같이 점수로 정한다(BaselineCoverage). 모두 가져오기 전에 끝났으므로
        // 점수로 가리지 못하면 모두 들어 있다고 본다(가져온 시각 = 무한대).
        var rows = graph.Sessions.Select(s => (Session: s, WeekendId: s.RaceWeekendId!.Value))
            .Concat(graph.Attachments.Select(a => (a.Session, WeekendId: a.Weekend.Id)))
            .SelectMany(x => x.Session.Results.Where(r => !r.IsDeleted).Select(r => new SeasonResultRow(
                graph.Season.Id,
                x.WeekendId,
                x.Session.Id,
                x.Session.SessionType,
                x.Session.SessionKind,
                x.Session.ClassifiedAt,
                r.DriverKey,
                r.DriverName,
                r.CarIndex,
                r.TeamId,
                r.IsPlayer,
                r.IsAiControlled,
                r.Position,
                r.ResultStatus,
                r.Points,
                IsImported: x.Session.IsImported,
                TeamName: r.TeamName)))
            .ToList();

        return StandingsCalculator.Calculate(SeasonSessionSelector.Select(rows), graph.Season.GameCode, graph.Snapshot, DateTime.MaxValue);
    }
}
