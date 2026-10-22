using SimCenter.Domain.Constants;

namespace SimCenter.Application.Common;

/// <summary>트랙의 정적 정보. 모르는 칸은 null.</summary>
/// <param name="CircuitName">서킷 공식 이름.</param>
/// <param name="GrandPrixName">그 게임 캘린더의 그랑프리 이름. 리버스·캘린더 밖 트랙은 null.</param>
/// <param name="LengthKm">1랩 길이(km).</param>
/// <param name="F1LapRecord">F1 레이스 랩 레코드(<c>m:ss.fff</c>). 확실하지 않거나 리버스 트랙이면 null.</param>
public sealed record TrackFacts(string CircuitName, string? GrandPrixName, double? LengthKm, string? F1LapRecord);

/// <summary>
/// 게임 트랙 ID(F1 25 UDP <c>m_trackId</c>, F1 26 동일)별 정적 트랙 정보. 불변 상수 표다(헌장의 Global Static 금지 대상 아님).
/// 랩 레코드는 공개 기록 중 확실한 값만 넣는다(2025 시즌 중반까지 확인한 값). 리버스 트랙은 정방향과 길이·서킷이 같고 랩 레코드·그랑프리가 없다.
/// F1 26(2026 캘린더)에서 그랑프리 이름이 달라지는 트랙은 <see cref="F126GrandPrixOverrides"/>가 덮는다.
/// </summary>
public static class TrackCatalog
{
    private static readonly IReadOnlyDictionary<int, TrackFacts> Tracks = new Dictionary<int, TrackFacts>
    {
        [0] = new("Albert Park Circuit", "Australian Grand Prix", 5.278, "1:19.813"),
        [2] = new("Shanghai International Circuit", "Chinese Grand Prix", 5.451, "1:32.238"),
        [13] = new("Suzuka International Racing Course", "Japanese Grand Prix", 5.807, "1:30.965"),
        [3] = new("Bahrain International Circuit", "Bahrain Grand Prix", 5.412, "1:31.447"),
        [29] = new("Jeddah Corniche Circuit", "Saudi Arabian Grand Prix", 6.174, "1:30.734"),
        [30] = new("Miami International Autodrome", "Miami Grand Prix", 5.412, "1:29.708"),
        [27] = new("Autodromo Internazionale Enzo e Dino Ferrari", "Emilia Romagna Grand Prix", 4.909, "1:15.484"),
        [5] = new("Circuit de Monaco", "Monaco Grand Prix", 3.337, "1:12.909"),
        [4] = new("Circuit de Barcelona-Catalunya", "Spanish Grand Prix", 4.657, null),
        [6] = new("Circuit Gilles Villeneuve", "Canadian Grand Prix", 4.361, "1:13.078"),
        [17] = new("Red Bull Ring", "Austrian Grand Prix", 4.318, "1:05.619"),
        [7] = new("Silverstone Circuit", "British Grand Prix", 5.891, "1:27.097"),
        [10] = new("Circuit de Spa-Francorchamps", "Belgian Grand Prix", 7.004, "1:46.286"),
        [9] = new("Hungaroring", "Hungarian Grand Prix", 4.381, "1:16.627"),
        [26] = new("Circuit Zandvoort", "Dutch Grand Prix", 4.259, "1:11.097"),
        [11] = new("Autodromo Nazionale Monza", "Italian Grand Prix", 5.793, null),
        [20] = new("Baku City Circuit", "Azerbaijan Grand Prix", 6.003, "1:43.009"),
        [12] = new("Marina Bay Street Circuit", "Singapore Grand Prix", 4.940, null),
        [15] = new("Circuit of the Americas", "United States Grand Prix", 5.513, "1:36.169"),
        [19] = new("Autódromo Hermanos Rodríguez", "Mexico City Grand Prix", 4.304, "1:17.774"),
        [16] = new("Autódromo José Carlos Pace", "São Paulo Grand Prix", 4.309, "1:10.540"),
        [31] = new("Las Vegas Strip Circuit", "Las Vegas Grand Prix", 6.201, null),
        [32] = new("Lusail International Circuit", "Qatar Grand Prix", 5.419, null),
        [14] = new("Yas Marina Circuit", "Abu Dhabi Grand Prix", 5.281, "1:25.637"),
        [41] = new("Circuit Zandvoort", null, 4.259, null),
        [40] = new("Red Bull Ring", null, 4.318, null),
        [39] = new("Silverstone Circuit", null, 5.891, null),
        [42] = new("Madring", null, null, null),
        [1] = new("Circuit Paul Ricard", "French Grand Prix", 5.842, "1:32.740"),
        [8] = new("Hockenheimring", "German Grand Prix", 4.574, "1:13.780"),
        [28] = new("Autódromo Internacional do Algarve", "Portuguese Grand Prix", 4.653, "1:18.750"),
    };

    /// <summary>F1 26(2026 캘린더)의 그랑프리 이름: Madrid가 Spanish GP, Barcelona는 Barcelona-Catalunya GP.</summary>
    private static readonly IReadOnlyDictionary<int, string> F126GrandPrixOverrides = new Dictionary<int, string>
    {
        [4] = "Barcelona-Catalunya Grand Prix",
        [42] = "Spanish Grand Prix",
    };

    /// <summary>(게임, 게임 트랙 ID)의 정적 정보. 모르는 트랙이면 null.</summary>
    public static TrackFacts? Find(string gameCode, int gameTrackId)
    {
        if (!Tracks.TryGetValue(gameTrackId, out var info))
        {
            return null;
        }

        return gameCode == GameCodes.F1_26 && F126GrandPrixOverrides.TryGetValue(gameTrackId, out var grandPrix)
            ? info with { GrandPrixName = grandPrix }
            : info;
    }
}
