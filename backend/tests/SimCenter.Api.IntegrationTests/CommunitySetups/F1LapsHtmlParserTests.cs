using System.Text.Json;
using SimCenter.Domain.Constants;
using SimCenter.Infrastructure.Setups;
using static SimCenter.Api.IntegrationTests.CommunitySetups.F1LapsFixtures;

namespace SimCenter.Api.IntegrationTests.CommunitySetups;

/// <summary>F1Laps 셋업 페이지 파서(순수 함수, DB·네트워크 없음).</summary>
public sealed class F1LapsHtmlParserTests
{
    private static readonly Uri BaseUri = new("https://www.f1laps.com/");

    [Fact]
    public void TrackIndex_ReadsTrackCards_SkipsToggleOtherGameAndDuplicates()
    {
        var links = F1LapsHtmlParser.ParseTrackIndex(Index25, "f1-25");

        Assert.Equal(["australia", "miami", "netherlands_reverse", "atlantis"], links.Select(l => l.Slug));
        Assert.Equal(("Australia", "Melbourne Grand Prix Circuit"), (links[0].Name, links[0].CircuitName));
        Assert.Equal("United States (Miami)", links[1].Name);
        Assert.Equal("Zandvoort Circuit", links[2].CircuitName); // nbsp → 공백, 절대 주소 링크
        Assert.Null(links[3].CircuitName);
    }

    [Fact]
    public void Ranking_ReadsRowsInPageOrder_WithAbsoluteDetailUrls()
    {
        var id1 = "B6C69BDB-F8FC-4355-A92E-FCD3DDA46D80";
        var html = ListPage("australia",
        [
            new("1", id1, "setup_author_1", "Aston Martin", "Time Trial", "1:15.974"),
            new("2", "01c50aac-a785-4beb-bd2d-308b457a817b", "driver two", "", "Race", "1:16.100"),
            new("3", "063a15fd-6196-4ce7-830c-ec4179f015b2", "broken", "Ferrari", "Race", "n/a"), // 랩타임 없음 → 뺀다
            new("x", "27b71c71-78f4-4c60-83ae-0220c2b469ff", "no rank", "McLaren", "Qualifying", "59.5"),
        ]);

        var rows = F1LapsHtmlParser.ParseRanking(html, BaseUri);

        Assert.Equal(3, rows.Count);
        var first = rows[0];
        Assert.Equal((1, id1.ToLowerInvariant(), "Aston Martin", "Time Trial", 75_974),
            (first.Rank, first.SourceId, first.TeamName, first.SessionType, first.LapTimeMs));
        Assert.DoesNotContain("setup_author_1", JsonSerializer.Serialize(rows)); // User 칸(닉네임)은 읽지 않는다
        Assert.Equal($"https://www.f1laps.com/f1-25/setups/australia/{id1.ToLowerInvariant()}/".ToLowerInvariant(),
            first.SourceUrl.ToLowerInvariant());
        Assert.Null(rows[1].TeamName);
        Assert.Equal((3, 59_500), (rows[2].Rank, rows[2].LapTimeMs)); // 순위 칸이 숫자가 아니면 행 순서
    }

    [Fact]
    public void ParsedRecords_HaveNoAuthorField()
    {
        Assert.DoesNotContain(typeof(SimCenter.Application.Setups.Refresh.SetupListRow).GetProperties(), p => p.Name.Contains("Author", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(typeof(SimCenter.Application.Setups.Refresh.SetupDetail).GetProperties(), p => p.Name.Contains("Author", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Ranking_EmptyTable_IsEmptyList()
        => Assert.Empty(F1LapsHtmlParser.ParseRanking(ListPage("australia", []), BaseUri));

    [Fact]
    public void Ranking_NoTable_Throws()
        => Assert.Throws<F1LapsPageException>(() => F1LapsHtmlParser.ParseRanking(NoTablePage, BaseUri));

    [Fact]
    public void Detail_Dry_ReadsSummaryAndSections()
    {
        var html = DetailPage("F1 25 Australia Setup (Dry)", "setup_author_1", "Aston Martin", "Time Trial", "1:15.974",
            "Dry", "Wheel", "Dec. 22, 2025", DrySections);

        var detail = F1LapsHtmlParser.ParseDetail(html);

        Assert.DoesNotContain("setup_author_1", JsonSerializer.Serialize(detail)); // 제목의 "by {user}"는 읽지 않는다
        Assert.Equal(("Aston Martin", "Time Trial", 75_974), (detail.TeamName, detail.SessionType, detail.LapTimeMs));
        Assert.Equal((SetupConditions.Dry, "Wheel"), (detail.Condition, detail.Steering));
        Assert.Equal(new DateOnly(2025, 12, 22), detail.SetOn);
        Assert.Equal(["Aerodynamics", "Transmission", "Suspension Geometry", "Brakes", "Tyres"], detail.Sections.Select(s => s.Title));
        Assert.Equal(("Front Camber", "-3.50˚"), (detail.Sections[2].Items[0].Label, detail.Sections[2].Items[0].Value));
        Assert.Equal(("Front Break Bias", "52"), (detail.Sections[3].Items[1].Label, detail.Sections[3].Items[1].Value));
        Assert.Equal("100%", detail.Sections[1].Items[0].Value);
    }

    [Fact]
    public void Detail_WetWithoutSteeringAndDate_LeavesThemNull()
    {
        var html = DetailPage("F1 25 Australia Setup (Wet)", "rain man", "Ferrari", "Race", "1:31.002", "Wet", null, null,
            [("Aerodynamics", [("Front Wing", "40"), ("Rear Wing", "38")])]);

        var detail = F1LapsHtmlParser.ParseDetail(html);

        Assert.Equal((SetupConditions.Wet, null, null), (detail.Condition, detail.Steering, detail.SetOn));
        Assert.DoesNotContain("rain man", JsonSerializer.Serialize(detail));
        Assert.Single(detail.Sections);
    }

    [Fact]
    public void Detail_NotASetupPage_Throws()
        => Assert.Throws<F1LapsPageException>(() => F1LapsHtmlParser.ParseDetail("<html><body><p>hi</p></body></html>"));

    [Theory]
    [InlineData("1:15.974", 75_974)]
    [InlineData("59.5", 59_500)]
    [InlineData("10:01.02", 601_020)]
    [InlineData("abc", null)]
    [InlineData("", null)]
    public void LapTime(string text, int? expected) => Assert.Equal(expected, F1LapsHtmlParser.ParseLapTime(text));

    [Theory]
    [InlineData("Dec. 22, 2025", 2025, 12, 22)]
    [InlineData("March 3, 2025", 2025, 3, 3)]
    [InlineData("Sept. 5, 2025", 2025, 9, 5)]
    [InlineData("May 1, 2026", 2026, 5, 1)]
    public void Date(string text, int year, int month, int day)
        => Assert.Equal(new DateOnly(year, month, day), F1LapsHtmlParser.ParseDate(text));

    [Theory]
    [InlineData("22/12/2025")]
    [InlineData("Feb. 30, 2025")]
    [InlineData("yesterday")]
    public void Date_Unreadable_IsNull(string text) => Assert.Null(F1LapsHtmlParser.ParseDate(text));
}
