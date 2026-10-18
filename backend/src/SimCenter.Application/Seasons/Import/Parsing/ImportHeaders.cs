using SimCenter.Domain.Constants;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import.Parsing;

/// <summary>가져오기 문서 헤더의 게임·모드·날씨 해석(docs/15 §12, D-55). 불변 상수 표.</summary>
public static class ImportHeaders
{
    private static readonly IReadOnlyDictionary<string, string> GameCodesByName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["F1 2025"] = GameCodes.F1_25,
        ["F1 25"] = GameCodes.F1_25,
        ["F1_25"] = GameCodes.F1_25,
    };

    private static readonly IReadOnlyDictionary<string, GameMode> ModesByName = new Dictionary<string, GameMode>(StringComparer.OrdinalIgnoreCase)
    {
        ["Driver Career"] = GameMode.DriverCareer,
        ["Career"] = GameMode.DriverCareer,
        ["My Team"] = GameMode.MyTeamCareer,
        ["My Team Career"] = GameMode.MyTeamCareer,
        ["Online Career"] = GameMode.OnlineCareer,
        ["Two Player Career"] = GameMode.OnlineCareer,
        ["Challenge Career"] = GameMode.ChallengeCareer,
        ["Grand Prix"] = GameMode.GrandPrix,
    };

    /// <summary>헤더 <c>Game</c>·<c>Mode</c> → (게임 코드, 모드). 없거나 모르면 그 줄 번호로 오류.</summary>
    public static (string GameCode, GameMode Mode) GameAndMode(MarkdownDocument document)
    {
        var game = document.HeaderValue("game")
            ?? throw new F1LapsFormatException(document.TitleLine, "헤더에 Game이 없습니다.");
        if (!GameCodesByName.TryGetValue(game, out var gameCode))
        {
            throw new F1LapsFormatException(document.HeaderLine("game"), $"지원하지 않는 게임입니다: {game} (F1 2025만 가능)");
        }

        var mode = document.HeaderValue("mode")
            ?? throw new F1LapsFormatException(document.HeaderLine("game"), "헤더에 Mode가 없습니다.");
        return ModesByName.TryGetValue(mode, out var gameMode)
            ? (gameCode, gameMode)
            : throw new F1LapsFormatException(document.HeaderLine("mode"), $"지원하지 않는 모드입니다: {mode}");
    }

    /// <summary>
    /// Conditions → 날씨(D-55): Dry → Clear, Wet → LightRain, Mixed → Overcast(비가 섞인 마른 노면 — 한 값으로 줄일 수 없어 흐림으로 둔다).
    /// 모르면 null.
    /// </summary>
    public static Weather? WeatherOf(string? conditions) => conditions?.Trim().ToLowerInvariant() switch
    {
        "dry" => Weather.Clear,
        "wet" => Weather.LightRain,
        "mixed" => Weather.Overcast,
        _ => null,
    };
}
