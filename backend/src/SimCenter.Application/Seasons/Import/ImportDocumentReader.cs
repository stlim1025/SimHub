using SimCenter.Application.Seasons.Import.Parsing;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 붙여넣은 입력 하나에 섞여 온 문서들(docs/15 §12, D-55): F1Laps 시즌 요약 0~1개, 인게임 순위표 0~1개, F1Laps 세션 0개 이상.
/// 시즌 요약이나 인게임 순위표 중 하나는 있어야 한다.
/// </summary>
public sealed record ImportBundle(
    F1LapsSeasonDocument? Summary,
    InGameStandingsDocument? InGame,
    IReadOnlyList<F1LapsSessionDocument> Sessions)
{
    public string GameCode => InGame?.GameCode ?? Summary!.GameCode;

    public GameMode GameMode => InGame?.GameMode ?? Summary!.GameMode;

    /// <summary>시즌 이름: 인게임 순위표 제목이 우선(같은 시즌을 두 번 가져오는지 보는 키 중 하나).</summary>
    public string Title => InGame?.Title ?? Summary!.Title;

    /// <summary>플레이어 이름: 인게임 <c>Player</c>가 우선, 없으면 F1Laps <c>Name</c>.</summary>
    public string PlayerName => InGame?.PlayerName ?? Summary!.PlayerName;
}

/// <summary>
/// 입력을 <c># 제목</c> 줄마다 문서로 나눠 종류별 파서에 넘긴다(D-55). 순수 함수 — 상태 없음.
/// 제목이 <c>Season:</c>이면 F1Laps 시즌 요약, <c>In-game Season Standings:</c>면 인게임 순위표, 헤더에 <c>Session</c>이 있으면 F1Laps 세션.
/// 줄 번호는 입력 전체 기준이다. 게임·모드가 문서끼리 다르면 오류다.
/// </summary>
public static class ImportDocumentReader
{
    public static string[] SplitLines(string markdown)
        => markdown.Replace("\0", string.Empty, StringComparison.Ordinal).Split('\n').Select(l => l.TrimEnd('\r')).ToArray();

    public static ImportBundle Read(string markdown)
    {
        ArgumentNullException.ThrowIfNull(markdown);

        F1LapsSeasonDocument? summary = null;
        InGameStandingsDocument? inGame = null;
        var sessions = new List<F1LapsSessionDocument>();

        foreach (var document in Split(SplitLines(markdown)))
        {
            if (document.Title.StartsWith(InGameStandingsParser.TitlePrefix, StringComparison.OrdinalIgnoreCase))
            {
                inGame = inGame is null
                    ? InGameStandingsParser.Parse(document)
                    : throw new F1LapsFormatException(document.TitleLine, "인게임 순위표가 두 번 나옵니다.");
            }
            else if (document.Title.StartsWith(F1LapsSeasonMarkdownParser.TitlePrefix, StringComparison.OrdinalIgnoreCase))
            {
                summary = summary is null
                    ? F1LapsSeasonMarkdownParser.Parse(document)
                    : throw new F1LapsFormatException(document.TitleLine, "F1Laps 시즌 요약이 두 번 나옵니다.");
            }
            else if (F1LapsSessionParser.LooksLikeSession(document))
            {
                sessions.Add(F1LapsSessionParser.Parse(document));
            }
            else
            {
                throw new F1LapsFormatException(document.TitleLine, $"모르는 문서입니다: {document.Title}");
            }
        }

        if (summary is null && inGame is null)
        {
            throw new F1LapsFormatException(1, "F1Laps 시즌 요약(# Season: …)이나 인게임 순위표(# In-game Season Standings: …)가 필요합니다.");
        }

        var bundle = new ImportBundle(summary, inGame, sessions);
        CheckSameGame(bundle);
        return bundle;
    }

    private static IEnumerable<MarkdownDocument> Split(string[] lines)
    {
        var start = -1;
        for (var i = 0; i <= lines.Length; i++)
        {
            var isTitle = i < lines.Length && IsTitleLine(lines[i]);
            if (i < lines.Length && !isTitle)
            {
                if (start < 0 && lines[i].Trim().Length > 0)
                {
                    throw new F1LapsFormatException(i + 1, "첫 문서 제목(# …) 앞에 내용이 있습니다.");
                }

                continue;
            }

            if (start >= 0)
            {
                yield return MarkdownDocument.Read(lines[start..i], start + 1);
            }

            start = i;
        }
    }

    private static bool IsTitleLine(string line)
    {
        var trimmed = line.TrimStart();
        return trimmed.StartsWith('#') && !trimmed.StartsWith("##", StringComparison.Ordinal);
    }

    private static void CheckSameGame(ImportBundle bundle)
    {
        if (bundle.Summary is { } summary && bundle.InGame is { } inGame
            && (summary.GameCode != inGame.GameCode || summary.GameMode != inGame.GameMode))
        {
            throw new F1LapsFormatException(1, "F1Laps 시즌 요약과 인게임 순위표의 게임·모드가 다릅니다.");
        }

        foreach (var session in bundle.Sessions)
        {
            if (session.GameCode != bundle.GameCode || session.GameMode != bundle.GameMode)
            {
                throw new F1LapsFormatException(session.Line, $"세션 '{session.Title}'의 게임·모드가 시즌과 다릅니다.");
            }
        }
    }
}
