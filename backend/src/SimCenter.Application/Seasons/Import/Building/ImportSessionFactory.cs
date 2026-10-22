using System.Globalization;
using System.Text.Json;
using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Import.Parsing;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Seasons.Import.Building;

/// <summary>가져올 라운드 하나의 재료(D-55): 그 라운드의 인게임 칸·F1Laps 세션들·F1Laps 요약 행.</summary>
internal sealed record RoundSources(
    int Round,
    IReadOnlyList<(RosterDriver Driver, InGameRaceCell Cell)> InGameCells,
    IReadOnlyList<F1LapsSessionDocument> Sessions,
    F1LapsRound? Summary);

/// <summary>
/// 가져온 세션 만들기(docs/15 §12, D-55). 세션 = 가져온 표시(<c>IsImported</c>) + 결과(순위표의 모든 드라이버, 요약만 있으면 나 1명)
/// + Details(내 랩·순위·셋업·벌칙 — §11 조립기가 읽는 모양). 시즌·주말 연결과 분류 시각은 <see cref="SeasonImportBuilder"/>가 정한다.
/// </summary>
/// <remarks><c>teamOf</c> = 순위표 팀 칸 → 팀(<see cref="ImportTeams.Of"/>). 팀 칸이 비면 명단의 기본 팀을 쓴다.</remarks>
internal sealed class ImportSessionFactory(
    Guid userId, Guid seasonId, string gameCode, GameMode mode, DateTime now, Func<Guid> newId, DriverRoster roster,
    Func<string?, ImportTeam> teamOf)
{
    private const string SourceName = "F1Laps";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <summary>F1Laps 세션 내보내기 하나 → 세션(본 레이스는 <see cref="MainRace"/>가 합친다).</summary>
    public GameSession FromDocument(F1LapsSessionDocument doc, SessionKind kind)
    {
        var results = new Dictionary<int, ImportedResult>();
        foreach (var row in doc.Classification)
        {
            var result = Row(results, roster.Resolve(row.Name, row.IsPlayer));
            ApplyTeam(result, row);
            result.Position = row.Position;
            result.BestLapTimeMs = row.BestLapTimeMs;

            // 예선·슛아웃의 Points·Gap은 F1Laps 버그로 엉뚱한 값이라 쓰지 않는다(예선 gap은 최고 랩 차로 계산된다).
            if (doc.SessionType == SessionType.Race)
            {
                result.Points = row.Points;
                result.GapMs = row.GapMs ?? (row.Position == 1 ? 0 : null);
            }
        }

        var me = Row(results, roster.Player);
        me.Position ??= doc.FinishPosition;
        if (doc.SessionType == SessionType.Race)
        {
            me.Points ??= doc.Points;
        }

        ApplyMyLaps(me, doc);
        foreach (var result in results.Values.Where(r => r.Points is null && doc.SessionType == SessionType.Race))
        {
            result.Points = ImportPoints.For(result.Position ?? 0, result.Status, doc.IsSprint);
        }

        return NewSession(doc.SessionType, kind, doc.TotalLaps, doc.AiDifficulty, ImportHeaders.WeatherOf(doc.Conditions), results.Values,
            DetailsOf(doc, results.Values, fastestCar: null));
    }

    /// <summary>
    /// 본 레이스 1개 = 인게임 순위(모든 드라이버, 권위) + F1Laps 레이스 내보내기(랩·셋업·최고 랩·Gap·포인트) + F1Laps 요약(내 포인트·최고 랩).
    /// 재료가 하나도 없으면 null.
    /// </summary>
    public GameSession? MainRace(RoundSources sources, F1LapsSessionDocument? raceDoc, SessionKind kind)
    {
        var summary = sources.Summary is { HasRace: true } s ? s : null;
        if (sources.InGameCells.Count == 0 && raceDoc is null && summary is null)
        {
            return null;
        }

        var results = new Dictionary<int, ImportedResult>();
        int? fastestCar = null;
        foreach (var (driver, cell) in sources.InGameCells)
        {
            var result = Row(results, driver);
            result.Position = cell.Position;
            result.Status = cell.Status;
            if (cell.FastestLap)
            {
                fastestCar = driver.CarIndex;
            }
        }

        foreach (var row in raceDoc?.Classification ?? [])
        {
            var result = Row(results, roster.Resolve(row.Name, row.IsPlayer));
            ApplyTeam(result, row);
            result.Position ??= row.Position;
            result.BestLapTimeMs = row.BestLapTimeMs;
            result.GapMs = row.GapMs ?? (row.Position == 1 ? 0 : null);
            result.Points = row.Points;
        }

        var me = Row(results, roster.Player);
        if (summary is not null)
        {
            me.Position ??= summary.RacePosition;
            me.Points ??= summary.Points;
            me.BestLapTimeMs ??= summary.BestLapTimeMs;
        }

        if (raceDoc is not null)
        {
            me.Position ??= raceDoc.FinishPosition;
            me.Points ??= raceDoc.Points;
            ApplyMyLaps(me, raceDoc);
        }

        FillMissingPositions(results.Values);
        foreach (var result in results.Values.Where(r => r.Points is null))
        {
            result.Points = ImportPoints.For(result.Position ?? 0, result.Status, isSprint: false);
        }

        var weather = ImportHeaders.WeatherOf(raceDoc?.Conditions ?? summary?.Conditions);
        var details = raceDoc is not null
            ? DetailsOf(raceDoc, results.Values, fastestCar)
            : EmptyDetails(fastestCar);
        return NewSession(SessionType.Race, kind, raceDoc?.TotalLaps, raceDoc?.AiDifficulty ?? summary?.RaceAiDifficulty, weather,
            results.Values, details);
    }

    /// <summary>F1Laps 요약의 예선(짧은/원샷 구분 불가 → <see cref="SessionKind.ShortQualifying"/>, 나 1명).</summary>
    public GameSession SummaryQualifying(F1LapsRound summary)
    {
        var me = new ImportedResult(roster.Player) { Position = summary.QualifyingPosition };
        return NewSession(SessionType.Qualifying, SessionKind.ShortQualifying, null, summary.QualifyingAiDifficulty,
            ImportHeaders.WeatherOf(summary.Conditions), [me], details: null);
    }

    /// <summary>
    /// 순위표 팀 칸이 있으면 이 세션의 팀으로 쓴다(없으면 명단의 기본 팀 그대로). 표에 없는 이름은 기본 팀을 모를 때만 쓴다.
    /// </summary>
    private void ApplyTeam(ImportedResult result, F1LapsClassificationRow row)
    {
        var team = teamOf(row.TeamName);
        if (team.TeamId is not null || (team.IsKnown && !result.Team.IsKnown))
        {
            result.Team = team;
        }
    }

    private static ImportedResult Row(Dictionary<int, ImportedResult> results, RosterDriver driver)
    {
        if (!results.TryGetValue(driver.CarIndex, out var result))
        {
            result = new ImportedResult(driver);
            results[driver.CarIndex] = result;
        }

        return result;
    }

    /// <summary>순위 없는 행(DNF 등)은 순위가 있는 행 뒤에 들어온 순서대로 번호를 받는다.</summary>
    private static void FillMissingPositions(IEnumerable<ImportedResult> results)
    {
        var list = results.ToList();
        var next = list.Select(r => r.Position ?? 0).DefaultIfEmpty(0).Max() + 1;
        foreach (var result in list.Where(r => r.Position is null))
        {
            result.Position = next++;
        }
    }

    /// <summary>내 랩 → 최고 랩·랩 수·피트 수·스틴트(같은 컴파운드가 이어지는 구간, 끝 = 그 구간 마지막 랩).</summary>
    private static void ApplyMyLaps(ImportedResult me, F1LapsSessionDocument doc)
    {
        var timed = doc.Laps.Where(l => l.LapTimeMs is > 0).ToList();
        if (timed.Count > 0)
        {
            me.BestLapTimeMs ??= timed.Min(l => l.LapTimeMs);
        }

        me.NumLaps = doc.Laps.Count == 0 ? doc.TotalLaps ?? 0 : doc.Laps.Max(l => l.LapNumber);
        me.NumPitStops = doc.Laps.Count(l => l.Pit);

        var stints = new List<(int EndLap, TyreCompound Compound)>();
        foreach (var lap in doc.Laps.Where(l => l.Compound != TyreCompound.Unknown))
        {
            if (stints.Count > 0 && stints[^1].Compound == lap.Compound)
            {
                stints[^1] = (lap.LapNumber, lap.Compound);
            }
            else
            {
                stints.Add((lap.LapNumber, lap.Compound));
            }
        }

        // 랩 표가 없으면 Tyre Strategy 목록만 안다(끝 랩 미상 = 0).
        me.Stints = stints.Count > 0 ? stints : doc.TyreStrategy.Select(c => (0, c)).ToList();
        if (stints.Count == 0 && doc.TyreStrategy.Count > 1)
        {
            me.NumPitStops = Math.Max(me.NumPitStops, doc.TyreStrategy.Count - 1);
        }
    }

    private string DetailsOf(F1LapsSessionDocument doc, IEnumerable<ImportedResult> results, int? fastestCar)
    {
        var playerCar = roster.Player.CarIndex;
        var history = doc.Laps
            .Where(l => l.LapTimeMs is > 0)
            .Select(l => new HistoryLap(l.LapNumber, l.LapTimeMs ?? 0, l.Sector1Ms ?? 0, l.Sector2Ms ?? 0, l.Sector3Ms ?? 0, true, true, true, true))
            .ToList();
        var positions = doc.Laps.Where(l => l.Position is > 0).ToDictionary(l => l.LapNumber, l => l.Position!.Value);

        var imported = new ImportedSessionDetails(
            SourceName,
            SetupOf(doc.Setup),
            doc.Laps.Select(l => new ImportedLapMark(l.LapNumber, l.Compound == TyreCompound.Unknown ? null : l.Compound.ToString(), l.Pit)).ToList(),
            results.Where(r => r.GapMs is not null).Select(r => new ImportedGap(r.Driver.CarIndex, r.GapMs!.Value)).ToList(),
            fastestCar,
            doc.Penalties.Select(p => new ImportedPenalty(
                p.Lap ?? 0, p.Penalty, p.Infringement, PenaltyCatalog.FindPenaltyType(p.Penalty), PenaltyCatalog.FindInfringementType(p.Infringement)))
                .ToList());
        return imported.ToDetailsJson(playerCar, history, positions);
    }

    private static string? EmptyDetails(int? fastestCar)
        => fastestCar is null
            ? null
            : new ImportedSessionDetails(SourceName, null, [], [], fastestCar, []).ToDetailsJson(0, [], new Dictionary<int, int>());

    /// <summary>셋업 값 → JSON 객체(정수면 정수로 — Agent가 보내는 모양과 같게).</summary>
    private static JsonElement? SetupOf(IReadOnlyDictionary<string, double> setup)
    {
        if (setup.Count == 0)
        {
            return null;
        }

        var values = setup.ToDictionary(
            p => p.Key,
            p => p.Value == Math.Floor(p.Value) && Math.Abs(p.Value) < int.MaxValue ? (object)(int)p.Value : p.Value);
        return JsonSerializer.SerializeToElement(values, JsonOptions);
    }

    private GameSession NewSession(
        SessionType type, SessionKind kind, int? totalLaps, int? aiDifficulty, Weather? weather,
        IEnumerable<ImportedResult> results, string? details)
    {
        var sessionId = newId();
        var sessionRef = string.Create(CultureInfo.InvariantCulture, $"import-{sessionId:N}")[..32];
        return new GameSession
        {
            Id = sessionId,
            UserId = userId,
            AgentDeviceId = null,
            GameCode = gameCode,
            SessionKey = string.Create(CultureInfo.InvariantCulture, $"import:{seasonId:N}:{sessionId:N}"),
            SessionRef = sessionRef,
            SessionType = type,
            SessionKind = kind,
            GameMode = mode,
            TotalLaps = totalLaps ?? 0,
            AiDifficulty = aiDifficulty ?? 0,
            IsImported = true,
            Weather = weather,
            Details = details,
            CreatedAt = now,
            Results = results.OrderBy(r => r.Position ?? int.MaxValue).ThenBy(r => r.Driver.CarIndex)
                .Select(r => ToEntity(sessionId, sessionRef, r)).ToList(),
        };
    }

    private SessionResult ToEntity(Guid sessionId, string sessionRef, ImportedResult result)
    {
        var resultId = newId();
        var driver = result.Driver;
        return new SessionResult
        {
            Id = resultId,
            GameSessionId = sessionId,
            CarIndex = driver.CarIndex,
            Position = result.Position ?? 0,
            NumLaps = result.NumLaps,
            Points = result.Points ?? 0,
            NumPitStops = result.NumPitStops,
            ResultStatus = result.Position is null && result.Status == ResultStatus.Finished ? ResultStatus.Unknown : result.Status,
            BestLapTimeMs = result.BestLapTimeMs ?? 0,
            DriverKey = DriverKeys.Build(driver.IsPlayer, null, driver.Name, null, sessionRef, driver.CarIndex),
            DriverName = driver.Name,
            TeamId = result.Team.TeamId,
            TeamName = result.Team.TeamName,
            IsAiControlled = !driver.IsPlayer,
            IsPlayer = driver.IsPlayer,
            CreatedAt = now,
            TyreStints = result.Stints.Select((s, i) => new SessionResultTyreStint
            {
                Id = newId(),
                SessionResultId = resultId,
                StintNumber = i + 1,
                EndLap = s.EndLap,
                VisualCompound = s.Compound,
                CreatedAt = now,
            }).ToList(),
        };
    }
}
