using System.Globalization;
using System.Text.RegularExpressions;
using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using SimCenter.Application.Setups;
using SimCenter.Application.Setups.Refresh;
using SimCenter.Domain.Constants;

namespace SimCenter.Infrastructure.Setups;

/// <summary>F1Laps 페이지 구조가 예상과 달라 읽지 못했다(표·제목이 없음 등).</summary>
public sealed class F1LapsPageException(string message) : Exception(message);

/// <summary>
/// F1Laps 공개 셋업 페이지 HTML → 값(순수 함수, 네트워크 없음). 페이지 구조(2026-10 확인):
/// <list type="bullet">
/// <item>트랙 목록(<c>/f1-25/setups/</c>): <c>a[href=/f1-25/setups/{slug}/]</c> 안의 <c>p</c> 두 개 = 국가 이름 · 서킷 이름.</item>
/// <item>순위표(<c>/{slug}/</c>, <c>/{slug}/wet/</c>): 머리 <c>#|User|Team|Session|Lap time</c>인 표, 행마다 상세 링크 <c>/{slug}/{uuid}/</c>.
/// User(작성자 닉네임) 칸은 개인정보라 읽지 않는다.</item>
/// <item>상세(<c>/{slug}/{uuid}/</c>): <c>h1</c> 제목(작성자 "by …"는 읽지 않는다), <c>dl</c> 밖의 <c>dt</c>/<c>dd</c> 요약(Team·Session·Lap time·Conditions·Steering·Date),
/// 카드(<c>.rounded-lg</c>)마다 제목 <c>span.text-lg</c> + <c>dl</c>의 줄(<c>dt</c> 라벨 · 마지막 <c>dd</c> 값).</item>
/// </list>
/// </summary>
public static partial class F1LapsHtmlParser
{
    private const string RankHeader = "#";
    private const string TeamHeader = "Team";
    private const string SessionHeader = "Session";
    private const string LapTimeHeader = "Lap time";

    private const string TeamLabel = "Team";
    private const string SessionLabel = "Session";
    private const string LapTimeLabel = "Lap time";
    private const string ConditionsLabel = "Conditions";
    private const string SteeringLabel = "Steering";
    private const string DateLabel = "Date";

    private const int MonthPrefixLength = 3;
    private const int MillisecondsPerSecond = 1000;
    private const int SecondsPerMinute = 60;

    private static readonly IReadOnlyDictionary<string, int> Months = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
    {
        ["jan"] = 1, ["feb"] = 2, ["mar"] = 3, ["apr"] = 4, ["may"] = 5, ["jun"] = 6,
        ["jul"] = 7, ["aug"] = 8, ["sep"] = 9, ["oct"] = 10, ["nov"] = 11, ["dec"] = 12,
    };

    /// <summary>트랙 목록 페이지 → slug·이름 목록(페이지 순서, slug 중복 제거). Dry/Wet 전환 링크처럼 이름 칸이 없는 링크는 뺀다.</summary>
    public static IReadOnlyList<SetupTrackLink> ParseTrackIndex(string html, string gamePath)
    {
        var document = Parse(html);
        var links = new List<SetupTrackLink>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        foreach (var anchor in document.QuerySelectorAll("a[href]"))
        {
            var match = TrackLinkPattern().Match(PathOf(anchor.GetAttribute("href")));
            if (!match.Success || match.Groups["game"].Value != gamePath)
            {
                continue;
            }

            var lines = anchor.QuerySelectorAll("p").Select(p => Clean(p.TextContent)).Where(t => t.Length > 0).ToList();
            var slug = match.Groups["slug"].Value;
            if (lines.Count == 0 || !seen.Add(slug))
            {
                continue;
            }

            links.Add(new SetupTrackLink(slug, lines[0], lines.Count > 1 ? lines[1] : null));
        }

        return links;
    }

    /// <summary>
    /// 순위표 페이지 → 행 목록(페이지 순서). 랩타임·링크를 읽지 못한 행은 뺀다. 순위 칸이 숫자가 아니면 행 순서(1부터)를 쓴다.
    /// </summary>
    /// <exception cref="F1LapsPageException">순위표(필수 머리 Lap time)가 없다 — 빈 목록과 구분해 이전 데이터를 지키게 한다.</exception>
    public static IReadOnlyList<SetupListRow> ParseRanking(string html, Uri baseUri)
    {
        ArgumentNullException.ThrowIfNull(baseUri);
        var document = Parse(html);

        foreach (var table in document.QuerySelectorAll("table"))
        {
            var headers = table.QuerySelectorAll("thead th").Select(th => Clean(th.TextContent)).ToList();
            var lapIndex = IndexOf(headers, LapTimeHeader);
            if (lapIndex < 0)
            {
                continue;
            }

            return ReadRows(table, headers, lapIndex, baseUri);
        }

        throw new F1LapsPageException("셋업 순위표를 찾지 못했습니다.");
    }

    /// <summary>상세 페이지 → 요약·셋업 값 묶음. 없는 칸은 null(묶음은 빈 목록).</summary>
    /// <exception cref="F1LapsPageException">제목(<c>h1</c>)도 셋업 값 묶음도 없다(셋업 페이지가 아님).</exception>
    public static SetupDetail ParseDetail(string html)
    {
        var document = Parse(html);

        var summary = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var dt in document.QuerySelectorAll("dt").Where(dt => dt.Closest("dl") is null))
        {
            var value = dt.ParentElement?.Children.LastOrDefault(e => e.LocalName == "dd");
            var label = Clean(dt.TextContent);
            if (value is not null && label.Length > 0)
            {
                summary.TryAdd(label, Clean(value.TextContent));
            }
        }

        var sections = document.QuerySelectorAll("dl").Select(ReadSection).Where(s => s.Items.Count > 0).ToList();
        var heading = document.QuerySelector("h1");
        if (heading is null && sections.Count == 0)
        {
            throw new F1LapsPageException("셋업 상세를 찾지 못했습니다.");
        }

        return new SetupDetail(
            NullIfEmpty(summary.GetValueOrDefault(TeamLabel)),
            NullIfEmpty(summary.GetValueOrDefault(SessionLabel)),
            ParseLapTime(summary.GetValueOrDefault(LapTimeLabel)),
            SetupConditions.Normalize(summary.GetValueOrDefault(ConditionsLabel)),
            NullIfEmpty(summary.GetValueOrDefault(SteeringLabel)),
            ParseDate(summary.GetValueOrDefault(DateLabel)),
            sections);
    }

    /// <summary><c>m:ss.fff</c> 또는 <c>ss.fff</c> → 밀리초. 읽지 못하면 null.</summary>
    public static int? ParseLapTime(string? text)
    {
        var match = LapTimePattern().Match(text?.Trim() ?? string.Empty);
        if (!match.Success)
        {
            return null;
        }

        var minutes = match.Groups["min"].Success ? int.Parse(match.Groups["min"].Value, CultureInfo.InvariantCulture) : 0;
        var seconds = int.Parse(match.Groups["sec"].Value, CultureInfo.InvariantCulture);
        var fraction = match.Groups["frac"].Value.PadRight(3, '0');
        var milliseconds = int.Parse(fraction, CultureInfo.InvariantCulture);
        return (((minutes * SecondsPerMinute) + seconds) * MillisecondsPerSecond) + milliseconds;
    }

    /// <summary>F1Laps 날짜 표기(<c>Dec. 22, 2025</c>·<c>March 3, 2025</c>·<c>Sept. 5, 2025</c>) → 날짜. 읽지 못하면 null.</summary>
    public static DateOnly? ParseDate(string? text)
    {
        var match = DatePattern().Match(text?.Trim() ?? string.Empty);
        if (!match.Success)
        {
            return null;
        }

        var monthName = match.Groups["month"].Value;
        if (monthName.Length < MonthPrefixLength || !Months.TryGetValue(monthName[..MonthPrefixLength], out var month))
        {
            return null;
        }

        var day = int.Parse(match.Groups["day"].Value, CultureInfo.InvariantCulture);
        var year = int.Parse(match.Groups["year"].Value, CultureInfo.InvariantCulture);
        return day <= DateTime.DaysInMonth(year, month) ? new DateOnly(year, month, day) : null;
    }

    private static List<SetupListRow> ReadRows(IElement table, List<string> headers, int lapIndex, Uri baseUri)
    {
        var rankIndex = IndexOf(headers, RankHeader);
        var teamIndex = IndexOf(headers, TeamHeader);
        var sessionIndex = IndexOf(headers, SessionHeader);
        var rows = new List<SetupListRow>();

        foreach (var tr in table.QuerySelectorAll("tbody tr"))
        {
            var cells = tr.Children.Where(c => c.LocalName == "td").ToList();
            var link = tr.QuerySelectorAll("a[href]")
                .Select(a => a.GetAttribute("href"))
                .Select(href => (Href: href!, Match: DetailLinkPattern().Match(PathOf(href))))
                .FirstOrDefault(x => x.Match.Success);
            var lapTimeMs = ParseLapTime(CellText(cells, lapIndex));
            if (link.Href is null || lapTimeMs is null)
            {
                continue;
            }

            var rank = int.TryParse(CellText(cells, rankIndex), NumberStyles.None, CultureInfo.InvariantCulture, out var parsed)
                ? parsed
                : rows.Count + 1;

            rows.Add(new SetupListRow(
                rank,
                link.Match.Groups["id"].Value.ToLowerInvariant(),
                new Uri(baseUri, link.Match.Value).ToString(),
                NullIfEmpty(CellText(cells, teamIndex)),
                NullIfEmpty(CellText(cells, sessionIndex)),
                lapTimeMs.Value));
        }

        return rows;
    }

    private static SetupSectionDto ReadSection(IElement dl)
    {
        var card = dl.Closest(".rounded-lg");
        var title = Clean(card?.QuerySelector("span.text-lg")?.TextContent ?? string.Empty);
        var items = new List<SetupItemDto>();

        foreach (var row in dl.Children)
        {
            var dt = row.LocalName == "dt" ? row : row.QuerySelector("dt");
            var dd = row.LocalName == "dt" ? row.NextElementSibling : row.QuerySelectorAll("dd").LastOrDefault();
            var label = Clean(dt?.TextContent ?? string.Empty);
            if (label.Length > 0 && dd is not null)
            {
                items.Add(new SetupItemDto(label, Clean(dd.TextContent)));
            }
        }

        return new SetupSectionDto(title, items);
    }

    private static IDocument Parse(string html) => new HtmlParser().ParseDocument(html ?? string.Empty);

    private static int IndexOf(List<string> headers, string name)
        => headers.FindIndex(h => string.Equals(h, name, StringComparison.OrdinalIgnoreCase));

    private static string? CellText(List<IElement> cells, int index)
        => index >= 0 && index < cells.Count ? Clean(cells[index].TextContent) : null;

    /// <summary>절대 주소면 경로만, 아니면 그대로.</summary>
    private static string PathOf(string? href)
        => href is not null && Uri.TryCreate(href, UriKind.Absolute, out var absolute) && absolute.Scheme.StartsWith("http", StringComparison.Ordinal)
            ? absolute.AbsolutePath
            : href ?? string.Empty;

    /// <summary>공백(줄바꿈·nbsp 포함)을 한 칸으로 줄이고 앞뒤를 자른다.</summary>
    private static string Clean(string text) => Whitespace().Replace(text.Replace(' ', ' '), " ").Trim();

    private static string? NullIfEmpty(string? text) => string.IsNullOrWhiteSpace(text) ? null : text;

    [GeneratedRegex(@"^/(?<game>f1-\d{2})/setups/(?<slug>[a-z0-9_]+)/$")]
    private static partial Regex TrackLinkPattern();

    [GeneratedRegex(@"^/f1-\d{2}/setups/[a-z0-9_]+/(?<id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/$")]
    private static partial Regex DetailLinkPattern();

    [GeneratedRegex(@"^(?:(?<min>\d{1,2}):)?(?<sec>\d{1,2})\.(?<frac>\d{1,3})$")]
    private static partial Regex LapTimePattern();

    [GeneratedRegex(@"^(?<month>[A-Za-z]+)\.?\s+(?<day>\d{1,2}),\s*(?<year>\d{4})$")]
    private static partial Regex DatePattern();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();
}
