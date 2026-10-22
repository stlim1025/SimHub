using System.Text;

namespace SimCenter.Api.IntegrationTests.CommunitySetups;

/// <summary>
/// F1Laps 셋업 페이지를 흉내 낸 합성 HTML(실제 페이지 구조만 따라 했다 — 2026-10 확인). 값은 임의다.
/// </summary>
internal static class F1LapsFixtures
{
    public sealed record ListRow(string Rank, string Id, string User, string? Team, string Session, string LapTime);

    /// <summary>트랙 목록: Dry/Wet 전환 링크(이름 칸 없음), 트랙 카드 링크, 중복·다른 게임 링크.</summary>
    public const string Index25 = """
        <html><body>
          <nav><a href="/f1-25/setups/meta/">Meta</a></nav>
          <div class="toggle">
            <a href="/f1-25/setups/" class="relative"><svg><path d="M1 1"/></svg>Dry</a>
            <a href="/f1-25/setups/wet/" class="relative"><svg><path d="M1 1"/></svg>Wet</a>
          </div>
          <ul>
            <li><div><a href="/f1-25/setups/australia/" class="focus:outline-none">
                <span class="absolute inset-0" aria-hidden="true"></span>
                <p class="text-sm font-medium text-foreground">
                    Australia
                </p>
                <p class="text-sm text-foreground-muted truncate">
                    Melbourne Grand Prix Circuit
                </p>
            </a></div></li>
            <li><div><a href="/f1-25/setups/miami/" class="focus:outline-none">
                <p>United States (Miami)</p>
                <p>Miami International Autodrome</p>
            </a></div></li>
            <li><div><a href="https://www.f1laps.com/f1-25/setups/netherlands_reverse/" class="focus:outline-none">
                <p>Netherlands Reverse</p>
                <p>Zandvoort&nbsp;Circuit</p>
            </a></div></li>
            <li><div><a href="/f1-25/setups/atlantis/" class="focus:outline-none">
                <p>Atlantis</p>
            </a></div></li>
            <li><div><a href="/f1-25/setups/australia/" class="focus:outline-none"><p>Australia again</p></a></div></li>
            <li><div><a href="/f1-26/setups/japan/" class="focus:outline-none"><p>Japan</p><p>Suzuka</p></a></div></li>
          </ul>
        </body></html>
        """;

    /// <summary>순위표 페이지. <paramref name="rows"/>를 표 행으로 만든다.</summary>
    public static string ListPage(string slug, IEnumerable<ListRow> rows, string game = "f1-25")
    {
        var body = new StringBuilder();
        foreach (var row in rows)
        {
            var href = $"/{game}/setups/{slug}/{row.Id}/";
            body.Append($"""
                <tr class=" hover:bg-background-subtle">
                  <td class="px-4 text-center"><a href="{href}">
                      {row.Rank}
                    </a></td>
                  <td class="px-4 text-left"><a href="{href}">
                      {row.User}
                    </a></td>
                  <td class="hidden sm:table-cell"><a href="{href}">
                      <div class="flex flex-row flex-nowrap"><div><span class="team-color-bar" style="background-color: #006F62"></span></div>
                      <div><div class="text-sm truncate">{row.Team}</div></div></div>
                    </a></td>
                  <td class="px-4"><a href="{href}">
                      {row.Session}
                    </a></td>
                  <td class="px-4"><a href="{href}">
                      {row.LapTime}
                    </a></td>
                  <td class="px-4"><svg aria-hidden="true"><path d="M12 12"/></svg></td>
                </tr>
                """);
        }

        return $"""
            <html><body>
              <a href="/{game}/setups/{slug}/meta/">Meta</a>
              <table class="table-auto min-w-full">
                <thead class="bg-background-muted"><tr>
                  <th scope="col">
                    #
                  </th>
                  <th scope="col">
                    User
                  </th>
                  <th scope="col" class="hidden sm:table-cell">
                    Team
                  </th>
                  <th scope="col">
                    Session
                  </th>
                  <th scope="col">
                    Lap time
                  </th>
                  <th scope="col">
                  </th>
                </tr></thead>
                <tbody class="bg-background">
                  {body}
                </tbody>
              </table>
            </body></html>
            """;
    }

    /// <summary>표가 없는 페이지(구조 변경·오류 페이지).</summary>
    public const string NoTablePage = "<html><body><h1>Something went wrong</h1><p>No setups here.</p></body></html>";

    /// <summary>상세 페이지. <paramref name="steering"/>·<paramref name="date"/>가 null이면 그 칸을 싣지 않는다.</summary>
    public static string DetailPage(
        string title,
        string author,
        string team,
        string session,
        string lapTime,
        string conditions,
        string? steering,
        string? date,
        IReadOnlyList<(string Title, (string Label, string Value)[] Items)> sections)
    {
        var summary = new StringBuilder();
        AppendSummary(summary, "Team", team);
        AppendSummary(summary, "Session", session);
        AppendSummary(summary, "Lap time", lapTime);
        AppendSummary(summary, "Conditions", $"&nbsp;{conditions}");
        if (steering is not null)
        {
            AppendSummary(summary, "Steering", $"&nbsp;{steering}");
        }

        if (date is not null)
        {
            AppendSummary(summary, "Date", date);
        }

        var cards = new StringBuilder();
        foreach (var (sectionTitle, items) in sections)
        {
            var rows = new StringBuilder();
            foreach (var (label, value) in items)
            {
                rows.Append($"""
                    <div class="bg-background-muted px-4 py-2 flex">
                      <dt class="w-10/12 text-sm">
                        {label}
                      </dt>
                      <dd class="sm:w-4/12 hidden sm:block"><div class="p-0.5 h-4"><div class="h-3 bg-primary" style="width: 46%"></div></div></dd>
                      <dd class="w-2/12 text-right text-base">
                        {value}
                      </dd>
                    </div>
                    """);
            }

            cards.Append($"""
                <div class="relative rounded-lg border border-border bg-background py-1.5 shadow-sm items-center">
                  <div class="px-4 pb-1.5 sm:px-6">
                    <span class="text-lg font-medium">{sectionTitle}</span>
                  </div>
                  <div class="border-t border-border-muted font-medium"><dl>{rows}</dl></div>
                </div>
                """);
        }

        return $"""
            <html><head><title>{title} - F1Laps</title></head><body>
              <div class="text-center">
                <h1 class="text-3xl">
                    {title}
                    <br>
                    by {author}
                </h1>
              </div>
              <div class="mt-8"><div class="py-4 px-6 bg-primary rounded-lg max-w-3xl"><div class="grid grid-cols-2 gap-4">
                {summary}
              </div></div></div>
              <div class="text-left pt-6 space-y-5">
                {cards}
              </div>
            </body></html>
            """;
    }

    /// <summary>전형적인 Dry 셋업 값 묶음(실제 라벨, F1Laps 오타 "Break" 포함).</summary>
    public static readonly IReadOnlyList<(string Title, (string Label, string Value)[] Items)> DrySections =
    [
        ("Aerodynamics", [("Front Wing", "23"), ("Rear Wing", "10")]),
        ("Transmission", [("Differential Adjustment On Throttle", "100%"), ("Differential Adjustment Off Throttle", "25%")]),
        ("Suspension Geometry", [("Front Camber", "-3.50˚"), ("Rear Camber", "-2.00˚"), ("Front Toe", "0.00˚"), ("Rear Toe", "0.10˚")]),
        ("Brakes", [("Break Pressure", "100"), ("Front Break Bias", "52")]),
        ("Tyres", [("Front Right Tyre Pressure", "29.5"), ("Front Left Tyre Pressure", "29.5")]),
    ];

    private static void AppendSummary(StringBuilder summary, string label, string value)
        => summary.Append($"""
            <div>
              <dt class="text-primary-foreground text-sm">{label}</dt>
              <dd class="">
                {value}
              </dd>
            </div>
            """);
}
