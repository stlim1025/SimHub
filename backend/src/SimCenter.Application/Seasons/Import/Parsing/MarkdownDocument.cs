namespace SimCenter.Application.Seasons.Import.Parsing;

/// <summary>마크다운 표 한 행: 칸(정리된 값)과 원문 줄 번호(입력 전체 기준, 1부터).</summary>
public sealed record MarkdownRow(IReadOnlyList<string> Cells, int Line);

/// <summary>마크다운 표: 머리글(소문자) → 열 번호, 데이터 행(구분 행·빈 행 제외).</summary>
public sealed record MarkdownTable(IReadOnlyDictionary<string, int> Columns, IReadOnlyList<string> Headers, int HeaderLine, IReadOnlyList<MarkdownRow> Rows)
{
    public int? Column(string name) => Columns.TryGetValue(name, out var index) ? index : null;

    public int RequireColumn(string name)
        => Column(name) ?? throw new F1LapsFormatException(HeaderLine, $"표 머리글에 '{name}' 열이 없습니다.");
}

/// <summary><c>## 절</c> 하나: 표(있으면)와 목록 항목(<c>- …</c>).</summary>
public sealed record MarkdownSection(string Name, int Line, MarkdownTable? Table, IReadOnlyList<string> ListItems);

/// <summary>
/// 가져오기 문서 하나(<c># 제목</c>부터 다음 <c># 제목</c> 전까지, docs/15 §12 D-55)를 줄 단위로 나눈 값. 순수 — 상태 없음.
/// 헤더 = 제목 다음의 <c>**Key**: Value | …</c> 줄(키는 소문자). 여분 공백·<c>*</c> 강조는 지우고, 칸의 <c>*</c>는 <see cref="MarkdownCells"/>가 다룬다.
/// </summary>
public sealed class MarkdownDocument
{
    private const char CellSeparator = '|';

    private MarkdownDocument(
        string title,
        int titleLine,
        IReadOnlyDictionary<string, (string Value, int Line)> header,
        IReadOnlyDictionary<string, MarkdownSection> sections)
    {
        Title = title;
        TitleLine = titleLine;
        Header = header;
        Sections = sections;
    }

    public string Title { get; }

    public int TitleLine { get; }

    public IReadOnlyDictionary<string, (string Value, int Line)> Header { get; }

    /// <summary>절 이름(소문자) → 절. 같은 이름이 또 나오면 처음 것만.</summary>
    public IReadOnlyDictionary<string, MarkdownSection> Sections { get; }

    /// <summary>헤더 값(없거나 <c>-</c>면 null).</summary>
    public string? HeaderValue(string key)
        => Header.TryGetValue(key, out var value) && value.Value.Length > 0 && value.Value != MarkdownCells.EmptyValue ? value.Value : null;

    public int HeaderLine(string key) => Header.TryGetValue(key, out var value) ? value.Line : TitleLine;

    public MarkdownSection? Section(string name) => Sections.GetValueOrDefault(name);

    /// <summary><paramref name="lines"/>(<paramref name="firstLine"/> = 첫 줄의 번호)를 읽는다. 첫 비지 않은 줄이 <c># 제목</c>이어야 한다.</summary>
    public static MarkdownDocument Read(IReadOnlyList<string> lines, int firstLine)
    {
        ArgumentNullException.ThrowIfNull(lines);

        string? title = null;
        var titleLine = firstLine;
        Dictionary<string, (string, int)>? header = null;
        var sections = new Dictionary<string, MarkdownSection>(StringComparer.Ordinal);
        SectionBuilder? current = null;

        for (var i = 0; i < lines.Count; i++)
        {
            var lineNumber = firstLine + i;
            var line = lines[i].Trim();
            if (line.Length == 0)
            {
                continue;
            }

            if (line.StartsWith("##", StringComparison.Ordinal))
            {
                Flush(current, sections);
                current = new SectionBuilder(line.TrimStart('#').Trim().ToLowerInvariant(), lineNumber);
            }
            else if (line.StartsWith('#'))
            {
                if (title is not null)
                {
                    throw new F1LapsFormatException(lineNumber, "한 문서에 제목(# …)이 두 번 나옵니다.");
                }

                title = line.TrimStart('#').Trim();
                titleLine = lineNumber;
            }
            else if (line.StartsWith(CellSeparator))
            {
                current?.TableLines.Add((line, lineNumber));
            }
            else if (line.StartsWith("- ", StringComparison.Ordinal) || line == "-")
            {
                current?.ListItems.Add(MarkdownCells.Clean(line[1..]));
            }
            else if (current is null && header is null && line.Contains("**", StringComparison.Ordinal) && line.Contains(':', StringComparison.Ordinal))
            {
                header = ReadHeader(line, lineNumber);
            }
        }

        Flush(current, sections);
        if (string.IsNullOrEmpty(title))
        {
            throw new F1LapsFormatException(firstLine, "문서 제목(# …)이 없습니다.");
        }

        return new MarkdownDocument(title, titleLine, header ?? new Dictionary<string, (string, int)>(), sections);
    }

    private static void Flush(SectionBuilder? builder, Dictionary<string, MarkdownSection> sections)
    {
        if (builder is null || sections.ContainsKey(builder.Name))
        {
            return;
        }

        sections[builder.Name] = new MarkdownSection(builder.Name, builder.Line, ReadTable(builder.TableLines), builder.ListItems);
    }

    /// <summary><c>**Key**: Value | **Key**: Value</c> → 소문자 키 → (값, 줄).</summary>
    private static Dictionary<string, (string, int)> ReadHeader(string line, int lineNumber)
    {
        var header = new Dictionary<string, (string, int)>(StringComparer.Ordinal);
        foreach (var part in line.Split(CellSeparator))
        {
            var colon = part.IndexOf(':', StringComparison.Ordinal);
            if (colon <= 0)
            {
                continue;
            }

            var key = MarkdownCells.Clean(part[..colon]).ToLowerInvariant();
            if (key.Length > 0)
            {
                header[key] = (MarkdownCells.Clean(part[(colon + 1)..]), lineNumber);
            }
        }

        return header;
    }

    private static MarkdownTable? ReadTable(List<(string Text, int Line)> tableLines)
    {
        if (tableLines.Count == 0)
        {
            return null;
        }

        var headers = SplitRow(tableLines[0].Text).Select(MarkdownCells.Clean).ToList();
        var columns = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < headers.Count; i++)
        {
            columns.TryAdd(headers[i].ToLowerInvariant(), i);
        }

        var rows = tableLines.Skip(1)
            .Select(l => new MarkdownRow(SplitRow(l.Text).Select(c => c.Trim()).ToList(), l.Line))
            .Where(r => !r.Cells.All(c => c.Length == 0 || c.All(ch => ch is '-' or ':')))
            .ToList();

        return new MarkdownTable(columns, headers, tableLines[0].Line, rows);
    }

    /// <summary>앞뒤 <c>|</c>를 떼고 칸으로 나눈다(칸 정리는 읽는 쪽이 한다 — <c>*</c>가 의미 있는 표가 있다).</summary>
    private static string[] SplitRow(string row)
    {
        var inner = row.Trim();
        if (inner.StartsWith(CellSeparator))
        {
            inner = inner[1..];
        }

        if (inner.EndsWith(CellSeparator))
        {
            inner = inner[..^1];
        }

        return inner.Split(CellSeparator);
    }

    private sealed class SectionBuilder(string name, int line)
    {
        public string Name { get; } = name;

        public int Line { get; } = line;

        public List<(string Text, int Line)> TableLines { get; } = [];

        public List<string> ListItems { get; } = [];
    }
}
