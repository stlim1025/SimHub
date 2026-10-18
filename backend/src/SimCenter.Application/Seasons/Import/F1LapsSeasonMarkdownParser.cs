using SimCenter.Application.Seasons.Import.Parsing;

namespace SimCenter.Application.Seasons.Import;

/// <summary>가져오기 문서를 해석할 수 없음. <see cref="LineNumber"/>는 입력 전체 기준 1부터.</summary>
public sealed class F1LapsFormatException(int lineNumber, string message) : Exception(message)
{
    public int LineNumber { get; } = lineNumber;
}

/// <summary>
/// F1Laps "Season" 요약 내보내기 파서(docs/15 §12, D-55). 순수 함수 — 상태 없음.
/// 제목(<c># Season: …</c>) · 헤더(<c>**Game**: … | **Team**: … | **Mode**: … | **Name**: …</c>) ·
/// <c>## Grand Prix Results</c> · <c>## Driver Standings</c> 표를 읽는다. 열은 머리글 이름으로 찾고(순서 무관),
/// 여분 공백·<c>*</c> 표시는 무시하며 <c>-</c>·빈 칸은 null이다. 모르는 절(Constructor Standings 등)은 건너뛴다.
/// </summary>
public static class F1LapsSeasonMarkdownParser
{
    public const string TitlePrefix = "Season:";

    private const string ResultsSection = "grand prix results";
    private const string DriversSection = "driver standings";
    private const string PlayerDriverName = "you";
    private const string DefaultPlayerName = "You";

    /// <summary>입력 전체를 이 문서 하나로 읽는다(여러 문서는 <see cref="ImportDocumentReader"/>).</summary>
    public static F1LapsSeasonDocument Parse(string markdown)
    {
        ArgumentNullException.ThrowIfNull(markdown);
        return Parse(MarkdownDocument.Read(ImportDocumentReader.SplitLines(markdown), 1));
    }

    public static F1LapsSeasonDocument Parse(MarkdownDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);

        var title = document.Title.StartsWith(TitlePrefix, StringComparison.OrdinalIgnoreCase)
            ? document.Title[TitlePrefix.Length..].Trim()
            : document.Title;
        if (title.Length == 0)
        {
            throw new F1LapsFormatException(document.TitleLine, "시즌 이름이 비어 있습니다.");
        }

        var (gameCode, mode) = ImportHeaders.GameAndMode(document);
        var results = document.Section(ResultsSection)?.Table
            ?? throw new F1LapsFormatException(document.TitleLine, "## Grand Prix Results 표가 없습니다.");

        return new F1LapsSeasonDocument(
            title,
            gameCode,
            mode,
            document.HeaderValue("team"),
            document.HeaderValue("name") ?? DefaultPlayerName,
            ReadRounds(results),
            document.Section(DriversSection)?.Table is { } drivers ? ReadDrivers(drivers) : []);
    }

    private static List<F1LapsRound> ReadRounds(MarkdownTable table)
    {
        var numberColumn = table.RequireColumn("#");
        var trackColumn = table.RequireColumn("track");

        var rounds = new List<F1LapsRound>(table.Rows.Count);
        var seen = new HashSet<int>();
        foreach (var row in table.Rows)
        {
            var number = MarkdownCells.Int(row, numberColumn, "#")
                ?? throw new F1LapsFormatException(row.Line, "라운드 번호(#)가 없습니다.");
            if (!seen.Add(number))
            {
                throw new F1LapsFormatException(row.Line, $"라운드 {number}가 두 번 나옵니다.");
            }

            rounds.Add(new F1LapsRound(
                row.Line,
                number,
                MarkdownCells.Text(row, trackColumn) ?? throw new F1LapsFormatException(row.Line, "트랙 이름이 없습니다."),
                MarkdownCells.Int(row, table.Column("quali"), "Quali"),
                MarkdownCells.Int(row, table.Column("race"), "Race"),
                MarkdownCells.Int(row, table.Column("points"), "Points"),
                MarkdownCells.Time(row, table.Column("best lap"), "Best Lap"),
                MarkdownCells.Text(row, table.Column("conditions")),
                MarkdownCells.Int(row, table.Column("race diff"), "Race Diff"),
                MarkdownCells.Int(row, table.Column("quali diff"), "Quali Diff")));
        }

        return rounds;
    }

    private static List<F1LapsDriverPoints> ReadDrivers(MarkdownTable table)
    {
        var driverColumn = table.RequireColumn("driver");
        var pointsColumn = table.RequireColumn("points");
        var positionColumn = table.Column("pos");

        var drivers = new List<F1LapsDriverPoints>(table.Rows.Count);
        foreach (var row in table.Rows)
        {
            var name = MarkdownCells.Text(row, driverColumn) ?? throw new F1LapsFormatException(row.Line, "드라이버 이름이 없습니다.");
            var points = MarkdownCells.Int(row, pointsColumn, "Points") ?? 0;
            var position = MarkdownCells.Int(row, positionColumn, "Pos") ?? drivers.Count + 1;
            var isPlayer = string.Equals(name, PlayerDriverName, StringComparison.OrdinalIgnoreCase);
            drivers.Add(new F1LapsDriverPoints(position, isPlayer ? DefaultPlayerName : name, points, isPlayer));
        }

        return drivers;
    }
}
