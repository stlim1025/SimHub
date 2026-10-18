using SimCenter.Application.Seasons.Import.Parsing;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import;

/// <summary>인게임 순위표의 한 칸(드라이버 × 라운드). <see cref="Position"/>은 DNF 등이면 null.</summary>
public sealed record InGameRaceCell(int Round, int? Position, ResultStatus Status, bool FastestLap);

/// <summary>인게임 순위표 드라이버 한 줄. <see cref="Total"/> = TOT(드라이버 포인트 기준값).</summary>
public sealed record InGameDriverRow(int Line, string Name, string? TeamName, bool IsPlayer, IReadOnlyList<InGameRaceCell> Cells, int Total);

public sealed record InGameConstructorRow(string TeamName, int Points);

/// <summary>
/// 인게임 시즌 순위표(docs/15 §12, D-55 — 권위 있는 스탠딩). <see cref="Rounds"/> = 표의 라운드 열(캘린더 순서).
/// </summary>
public sealed record InGameStandingsDocument(
    string Title,
    string GameCode,
    GameMode GameMode,
    string PlayerName,
    IReadOnlyList<int> Rounds,
    IReadOnlyList<InGameDriverRow> Drivers,
    IReadOnlyList<InGameConstructorRow> Constructors);

/// <summary>
/// 인게임 시즌 순위표 파서(<c># In-game Season Standings: …</c>, D-55). 순수 함수 — 상태 없음.
/// <c>## Season Results</c>: Driver · Team · 라운드 코드 열(AUS=1 … ABU=24) · TOT. 칸 = 순위, <c>DNF</c>·<c>DSQ</c>·<c>NC</c>·<c>RET</c>,
/// <c>*</c> = 그 레이스 최고 랩, <c>-</c>·빈 칸 = 출전 기록 없음. <c>## Constructor Standings</c>: Team · Points.
/// 플레이어 = 헤더 <c>Player</c> 이름과 같은 행.
/// </summary>
public static class InGameStandingsParser
{
    public const string TitlePrefix = "In-game Season Standings:";

    private const string ResultsSection = "season results";
    private const string ConstructorsSection = "constructor standings";
    private const string TotalColumn = "tot";

    private static readonly IReadOnlyDictionary<string, ResultStatus> StatusCodes = new Dictionary<string, ResultStatus>(StringComparer.OrdinalIgnoreCase)
    {
        ["DNF"] = ResultStatus.DidNotFinish,
        ["DSQ"] = ResultStatus.Disqualified,
        ["DQ"] = ResultStatus.Disqualified,
        ["NC"] = ResultStatus.NotClassified,
        ["RET"] = ResultStatus.Retired,
    };

    public static InGameStandingsDocument Parse(MarkdownDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);

        var title = document.Title[Math.Min(TitlePrefix.Length, document.Title.Length)..].Trim();
        var (gameCode, mode) = ImportHeaders.GameAndMode(document);
        var player = document.HeaderValue("player")
            ?? throw new F1LapsFormatException(document.TitleLine, "헤더에 Player가 없습니다.");
        var table = document.Section(ResultsSection)?.Table
            ?? throw new F1LapsFormatException(document.TitleLine, "## Season Results 표가 없습니다.");

        var roundColumns = RoundColumns(table);
        var drivers = ReadDrivers(table, roundColumns, player);
        if (!drivers.Any(d => d.IsPlayer))
        {
            throw new F1LapsFormatException(document.HeaderLine("player"), $"Season Results 표에 플레이어 '{player}' 행이 없습니다.");
        }

        return new InGameStandingsDocument(
            title.Length == 0 ? document.Title : title,
            gameCode,
            mode,
            player,
            roundColumns.Select(c => c.Round).ToList(),
            drivers,
            document.Section(ConstructorsSection)?.Table is { } constructors ? ReadConstructors(constructors) : []);
    }

    private static List<(int Column, int Round)> RoundColumns(MarkdownTable table)
    {
        var columns = new List<(int, int)>();
        for (var i = 0; i < table.Headers.Count; i++)
        {
            var header = table.Headers[i];
            if (header.Equals("driver", StringComparison.OrdinalIgnoreCase) || header.Equals("team", StringComparison.OrdinalIgnoreCase)
                || header.Equals(TotalColumn, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var round = ImportCalendar.RoundOfCode(header)
                ?? throw new F1LapsFormatException(table.HeaderLine, $"모르는 라운드 코드입니다: {header} (AUS·CHN·JPN … 24개)");
            if (columns.Any(c => c.Item2 == round))
            {
                throw new F1LapsFormatException(table.HeaderLine, $"라운드 {header}가 두 번 나옵니다.");
            }

            columns.Add((i, round));
        }

        return columns.Count == 0
            ? throw new F1LapsFormatException(table.HeaderLine, "Season Results 표에 라운드 열이 없습니다.")
            : columns;
    }

    private static List<InGameDriverRow> ReadDrivers(MarkdownTable table, List<(int Column, int Round)> roundColumns, string player)
    {
        var driverColumn = table.RequireColumn("driver");
        var totalColumn = table.RequireColumn(TotalColumn);
        var teamColumn = table.Column("team");

        var drivers = new List<InGameDriverRow>(table.Rows.Count);
        foreach (var row in table.Rows)
        {
            var name = MarkdownCells.Text(row, driverColumn) ?? throw new F1LapsFormatException(row.Line, "드라이버 이름이 없습니다.");
            var cells = new List<InGameRaceCell>();
            foreach (var (column, round) in roundColumns)
            {
                if (ReadCell(row, column, round) is { } cell)
                {
                    cells.Add(cell);
                }
            }

            drivers.Add(new InGameDriverRow(
                row.Line,
                name,
                MarkdownCells.Text(row, teamColumn),
                DriverNameMatcher.IsFullMatch(name, player),
                cells,
                MarkdownCells.Int(row, totalColumn, "TOT") ?? 0));
        }

        return drivers;
    }

    private static InGameRaceCell? ReadCell(MarkdownRow row, int column, int round)
    {
        var text = MarkdownCells.Text(row, column);
        if (text is null)
        {
            return null;
        }

        var fastest = MarkdownCells.HasMarker(row, column);
        return StatusCodes.TryGetValue(text, out var status)
            ? new InGameRaceCell(round, null, status, fastest)
            : new InGameRaceCell(round, MarkdownCells.ParseInt(text, row.Line, "순위"), ResultStatus.Finished, fastest);
    }

    private static List<InGameConstructorRow> ReadConstructors(MarkdownTable table)
    {
        var teamColumn = table.RequireColumn("team");
        var pointsColumn = table.RequireColumn("points");
        return table.Rows
            .Select(row => new InGameConstructorRow(
                MarkdownCells.Text(row, teamColumn) ?? throw new F1LapsFormatException(row.Line, "팀 이름이 없습니다."),
                MarkdownCells.Int(row, pointsColumn, "Points") ?? 0))
            .ToList();
    }
}
