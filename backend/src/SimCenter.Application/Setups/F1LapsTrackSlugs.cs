using SimCenter.Domain.Constants;

namespace SimCenter.Application.Setups;

/// <summary>
/// F1Laps 셋업 주소의 게임·트랙 조각 ↔ 우리 게임 코드·게임 트랙 ID. 셋업 목록 페이지(<c>/f1-25/setups/</c>)가 링크로 주는 트랙 slug를
/// 이 표로 우리 트랙에 잇는다(이름 대신 slug — 국가 표기·오타가 바뀌어도 링크는 그대로다). 표에 없는 slug는 건너뛴다.
/// </summary>
public static class F1LapsTrackSlugs
{
    private static readonly IReadOnlyDictionary<string, string> GamePaths = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        [GameCodes.F1_25] = "f1-25",
        [GameCodes.F1_26] = "f1-26",
    };

    private static readonly IReadOnlyDictionary<string, int> Slugs = new Dictionary<string, int>(StringComparer.Ordinal)
    {
        ["australia"] = 0,
        ["china"] = 2,
        ["japan"] = 13,
        ["bahrain"] = 3,
        ["saudi_arabia"] = 29,
        ["miami"] = 30,
        ["imola"] = 27,
        ["monaco"] = 5,
        ["spain"] = 4,
        ["canada"] = 6,
        ["austria"] = 17,
        ["silverstone"] = 7,
        ["spa"] = 10,
        ["hungary"] = 9,
        ["netherlands"] = 26,
        ["monza"] = 11,
        ["azerbaijan"] = 20,
        ["singapore"] = 12,
        ["usa"] = 15,
        ["mexico"] = 19,
        ["brazil"] = 16,
        ["las_vegas"] = 31,
        ["qatar"] = 32,
        ["abudhabi"] = 14,
        ["netherlands_reverse"] = 41,
        ["austria_reverse"] = 40,
        ["silverstone_reverse"] = 39,
        ["madrid"] = 42,
    };

    /// <summary>게임 코드의 F1Laps 주소 조각(<c>f1-25</c>). 지원하지 않는 게임이면 null.</summary>
    public static string? GamePath(string gameCode) => GamePaths.GetValueOrDefault(gameCode);

    /// <summary>slug의 게임 트랙 ID. 모르는 slug면 false.</summary>
    public static bool TryGetGameTrackId(string slug, out int gameTrackId) => Slugs.TryGetValue(slug, out gameTrackId);
}
