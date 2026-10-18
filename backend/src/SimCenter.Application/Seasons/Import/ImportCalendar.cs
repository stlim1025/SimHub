namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// F1 25 캘린더(라운드 1~24 = <c>Track.DisplayOrder</c>, D-43) ↔ 가져오기 문서의 이름·3글자 코드(docs/15 §12, D-55).
/// 불변 상수 표다. 이름은 대소문자·악센트 무시(<see cref="DriverNameMatcher.Normalize"/>)로 찾는다.
/// </summary>
public static class ImportCalendar
{
    public const int RoundCount = 24;

    // 라운드 순서대로: (F1Laps 이름과 별칭들, 3글자 코드들). F1Laps의 오타 "Unites States (Las Vegas)"도 별칭으로 둔다.
    private static readonly (string[] Names, string[] Codes)[] Rounds =
    [
        (["Australia", "Melbourne", "Australian Grand Prix"], ["AUS"]),
        (["China", "Shanghai", "Chinese Grand Prix"], ["CHN", "CHI"]),
        (["Japan", "Suzuka", "Japanese Grand Prix"], ["JPN", "JAP"]),
        (["Bahrain", "Sakhir", "Sakhir (Bahrain)", "Bahrain Grand Prix"], ["BHR", "BAH"]),
        (["Saudi Arabia", "Jeddah", "Saudi Arabian Grand Prix"], ["SAU", "KSA"]),
        (["United States (Miami)", "Miami", "Miami Grand Prix"], ["MIA"]),
        (["Italy (Imola)", "Imola", "Emilia Romagna", "Emilia-Romagna Grand Prix"], ["EMI", "IMO"]),
        (["Monaco", "Monaco Grand Prix"], ["MON", "MCO", "MC"]),
        (["Spain", "Catalunya", "Barcelona", "Spanish Grand Prix"], ["ESP", "SPA"]),
        (["Canada", "Montreal", "Canadian Grand Prix"], ["CAN"]),
        (["Austria", "Austria (Red Bull Ring)", "Red Bull Ring", "Austrian Grand Prix"], ["AUT"]),
        (["Great Britain", "Silverstone", "British Grand Prix"], ["GBR", "GB"]),
        (["Belgium", "Spa", "Belgian Grand Prix"], ["BEL"]),
        (["Hungary", "Hungaroring", "Hungarian Grand Prix"], ["HUN"]),
        (["Netherlands", "Zandvoort", "Dutch Grand Prix"], ["NED", "NLD"]),
        (["Italy (Monza)", "Monza", "Italy", "Italian Grand Prix"], ["ITA", "MZA"]),
        (["Azerbaijan", "Baku", "Baku (Azerbaijan)", "Azerbaijan Grand Prix"], ["AZE", "BAK"]),
        (["Singapore", "Marina Bay", "Singapore Grand Prix"], ["SIN", "SGP"]),
        (["United States (Austin)", "Austin", "Texas", "Texas (COTA)", "COTA", "United States", "United States Grand Prix"], ["USA", "COTA"]),
        (["Mexico", "Mexico City", "Mexican Grand Prix", "Mexico City Grand Prix"], ["MEX"]),
        (["Brazil", "Interlagos", "Brazil (Interlagos)", "Sao Paulo", "Sao Paulo Grand Prix"], ["BRA", "SAP"]),
        (["United States (Las Vegas)", "Unites States (Las Vegas)", "Las Vegas", "Las Vegas Grand Prix"], ["LVG", "LAS", "VEG", "LV"]),
        (["Qatar", "Losail", "Losail (Qatar)", "Qatar Grand Prix"], ["QAT"]),
        (["Abu Dhabi", "Yas Marina", "Abu Dhabi Grand Prix"], ["ABU", "UAE", "ABD"]),
    ];

    private static readonly IReadOnlyDictionary<string, int> RoundByName = Build(r => r.Names);
    private static readonly IReadOnlyDictionary<string, int> RoundByCode = Build(r => r.Codes);

    /// <summary>트랙·나라 이름 → 라운드. 모르면 null.</summary>
    public static int? RoundOfName(string? name)
        => RoundByName.TryGetValue(DriverNameMatcher.Normalize(name), out var round) ? round : null;

    /// <summary>3글자 코드(AUS·CHN…) → 라운드. 모르면 null.</summary>
    public static int? RoundOfCode(string? code)
        => RoundByCode.TryGetValue(DriverNameMatcher.Normalize(code), out var round) ? round : null;

    private static Dictionary<string, int> Build(Func<(string[] Names, string[] Codes), string[]> pick)
    {
        var map = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < Rounds.Length; i++)
        {
            foreach (var key in pick(Rounds[i]))
            {
                map.TryAdd(DriverNameMatcher.Normalize(key), i + 1);
            }
        }

        return map;
    }
}
