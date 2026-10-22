using SimCenter.Application.Seasons.Import.Parsing;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import;

/// <summary>F1Laps 세션의 내 랩 한 줄. 섹터는 모르면 null.</summary>
public sealed record F1LapsLap(int LapNumber, int? Position, TyreCompound Compound, bool Pit, int? LapTimeMs, int? Sector1Ms, int? Sector2Ms, int? Sector3Ms);

/// <summary>F1Laps 세션 순위표 한 줄. <see cref="IsPlayer"/> = "You". <see cref="TeamName"/> = <c>Team</c> 칸 그대로(없으면 null, My Team 차는 "My Team").</summary>
public sealed record F1LapsClassificationRow(int Position, string Name, bool IsPlayer, int? BestLapTimeMs, int? GapMs, int? Points, string? TeamName = null);

/// <summary>F1Laps 세션의 벌칙 한 줄(차는 알 수 없다).</summary>
public sealed record F1LapsPenalty(int? Lap, string Penalty, string Infringement);

/// <summary>
/// F1Laps 세션 내보내기(docs/15 §12, D-55). <see cref="Round"/> = 제목의 트랙 → 캘린더 순서.
/// <see cref="Setup"/>은 Agent <c>F1DetailSections.FromSetup</c> 키로 바꾼 값이다.
/// </summary>
public sealed record F1LapsSessionDocument(
    int Line,
    string Title,
    string GameCode,
    GameMode GameMode,
    int Round,
    string TrackName,
    SessionType SessionType,
    SessionKind SessionKind,
    bool IsSprint,
    string? TeamName,
    string? Conditions,
    int? AiDifficulty,
    int? FinishPosition,
    int? Points,
    int? TotalLaps,
    IReadOnlyDictionary<string, double> Setup,
    IReadOnlyList<F1LapsLap> Laps,
    IReadOnlyList<F1LapsClassificationRow> Classification,
    IReadOnlyList<F1LapsPenalty> Penalties,
    IReadOnlyList<TyreCompound> TyreStrategy);

/// <summary>
/// F1Laps 세션 내보내기 파서(<c># {트랙} {세션}</c>, D-55). 순수 함수 — 상태 없음.
/// 헤더: Game · Session · Mode · Team · Conditions · Difficulty · Finish Position(<c>P1</c>) · Points · Total Laps.
/// 절: Setup · Lap Times · Classification · Penalties · Tyre Strategy(목록). 없는 절은 빈 값이다.
/// </summary>
public static class F1LapsSessionParser
{
    private const string PlayerName = "you";
    private const string PitYes = "yes";

    private static readonly IReadOnlyDictionary<string, (SessionType Type, SessionKind Kind, bool Sprint)> Sessions =
        new Dictionary<string, (SessionType, SessionKind, bool)>(StringComparer.OrdinalIgnoreCase)
        {
            ["Practice 1"] = (SessionType.Practice, SessionKind.Practice1, false),
            ["Practice 2"] = (SessionType.Practice, SessionKind.Practice2, false),
            ["Practice 3"] = (SessionType.Practice, SessionKind.Practice3, false),
            ["Short Practice"] = (SessionType.Practice, SessionKind.ShortPractice, false),
            ["Qualifying 1"] = (SessionType.Qualifying, SessionKind.Qualifying1, false),
            ["Qualifying 2"] = (SessionType.Qualifying, SessionKind.Qualifying2, false),
            ["Qualifying 3"] = (SessionType.Qualifying, SessionKind.Qualifying3, false),
            ["Short Qualifying"] = (SessionType.Qualifying, SessionKind.ShortQualifying, false),
            ["Qualifying"] = (SessionType.Qualifying, SessionKind.ShortQualifying, false),
            ["One-Shot Qualifying"] = (SessionType.Qualifying, SessionKind.OneShotQualifying, false),
            ["One Shot Qualifying"] = (SessionType.Qualifying, SessionKind.OneShotQualifying, false),
            ["Sprint Shootout 1"] = (SessionType.Qualifying, SessionKind.SprintShootout1, false),
            ["Sprint Shootout 2"] = (SessionType.Qualifying, SessionKind.SprintShootout2, false),
            ["Sprint Shootout 3"] = (SessionType.Qualifying, SessionKind.SprintShootout3, false),
            ["Short Sprint Shootout"] = (SessionType.Qualifying, SessionKind.ShortSprintShootout, false),
            ["One-Shot Sprint Shootout"] = (SessionType.Qualifying, SessionKind.OneShotSprintShootout, false),
            ["Race"] = (SessionType.Race, SessionKind.Race, false),
            ["Sprint Race"] = (SessionType.Race, SessionKind.Race, true),
            ["Sprint"] = (SessionType.Race, SessionKind.Race, true),
        };

    // F1Laps 설정 이름 → Agent FromSetup 키(docs/15 §11.3 Setup 카드가 읽는 키).
    private static readonly IReadOnlyDictionary<string, string> SetupKeys = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["Front Wing"] = "frontWing",
        ["Rear Wing"] = "rearWing",
        ["On Throttle Diff"] = "onThrottle",
        ["Off Throttle Diff"] = "offThrottle",
        ["Engine Braking"] = "engineBraking",
        ["Front Camber"] = "frontCamber",
        ["Rear Camber"] = "rearCamber",
        ["Front Toe"] = "frontToe",
        ["Rear Toe"] = "rearToe",
        ["Front Suspension"] = "frontSuspension",
        ["Rear Suspension"] = "rearSuspension",
        ["Front Anti-Roll Bar"] = "frontAntiRollBar",
        ["Rear Anti-Roll Bar"] = "rearAntiRollBar",
        ["Front Ride Height"] = "frontSuspensionHeight",
        ["Rear Ride Height"] = "rearSuspensionHeight",
        ["Brake Pressure"] = "brakePressure",
        ["Front Brake Bias"] = "brakeBias",
        ["Brake Bias"] = "brakeBias",
        ["FL Tyre Pressure"] = "tyrePressureFL",
        ["FR Tyre Pressure"] = "tyrePressureFR",
        ["RL Tyre Pressure"] = "tyrePressureRL",
        ["RR Tyre Pressure"] = "tyrePressureRR",
        ["Ballast"] = "ballast",
        ["Fuel Load"] = "fuelLoad",
    };

    public static bool LooksLikeSession(MarkdownDocument document) => document.HeaderValue("session") is not null;

    public static F1LapsSessionDocument Parse(MarkdownDocument document)
    {
        ArgumentNullException.ThrowIfNull(document);

        var (gameCode, mode) = ImportHeaders.GameAndMode(document);
        var sessionName = document.HeaderValue("session")
            ?? throw new F1LapsFormatException(document.TitleLine, "헤더에 Session이 없습니다.");
        if (!Sessions.TryGetValue(sessionName, out var session))
        {
            throw new F1LapsFormatException(document.HeaderLine("session"), $"모르는 세션 종류입니다: {sessionName}");
        }

        var trackName = TrackOf(document.Title, sessionName);
        var round = ImportCalendar.RoundOfName(trackName)
            ?? throw new F1LapsFormatException(document.TitleLine, $"모르는 트랙입니다: {trackName}");
        var line = document.HeaderLine("session");

        return new F1LapsSessionDocument(
            document.TitleLine,
            document.Title,
            gameCode,
            mode,
            round,
            trackName,
            session.Type,
            session.Kind,
            session.Sprint,
            document.HeaderValue("team"),
            document.HeaderValue("conditions"),
            MarkdownCells.ParseInt(document.HeaderValue("difficulty"), line, "Difficulty"),
            MarkdownCells.ParseInt(document.HeaderValue("finish position"), line, "Finish Position"),
            MarkdownCells.ParseInt(document.HeaderValue("points"), line, "Points"),
            MarkdownCells.ParseInt(document.HeaderValue("total laps"), line, "Total Laps"),
            ReadSetup(document.Section("setup")?.Table),
            ReadLaps(document.Section("lap times")?.Table),
            ReadClassification(document.Section("classification")?.Table),
            ReadPenalties(document.Section("penalties")?.Table),
            (document.Section("tyre strategy")?.ListItems ?? []).Select(CompoundOf).Where(c => c != TyreCompound.Unknown).ToList());
    }

    /// <summary>제목 끝의 세션 이름을 떼면 트랙(<c>Australia Race</c> → <c>Australia</c>). 끝이 세션 이름이 아니면 제목 전체.</summary>
    private static string TrackOf(string title, string sessionName)
        => title.EndsWith(sessionName, StringComparison.OrdinalIgnoreCase) && title.Length > sessionName.Length
            ? title[..^sessionName.Length].Trim()
            : title;

    /// <summary><c>F1 Soft</c>·<c>Soft</c>·<c>Inter</c> … → 컴파운드. 모르면 <see cref="TyreCompound.Unknown"/>.</summary>
    public static TyreCompound CompoundOf(string? text)
    {
        var value = (text ?? string.Empty).Trim();
        if (value.StartsWith("F1 ", StringComparison.OrdinalIgnoreCase))
        {
            value = value[3..].Trim();
        }

        return value.ToLowerInvariant() switch
        {
            "soft" or "s" => TyreCompound.Soft,
            "medium" or "m" => TyreCompound.Medium,
            "hard" or "h" => TyreCompound.Hard,
            "inter" or "intermediate" or "i" => TyreCompound.Intermediate,
            "wet" or "w" => TyreCompound.Wet,
            _ => TyreCompound.Unknown,
        };
    }

    private static Dictionary<string, double> ReadSetup(MarkdownTable? table)
    {
        var setup = new Dictionary<string, double>(StringComparer.Ordinal);
        if (table is null)
        {
            return setup;
        }

        var settingColumn = table.RequireColumn("setting");
        var valueColumn = table.RequireColumn("value");
        foreach (var row in table.Rows)
        {
            var setting = MarkdownCells.Text(row, settingColumn);
            var value = MarkdownCells.ParseDouble(MarkdownCells.Text(row, valueColumn), row.Line, setting ?? "Setup");
            if (setting is null || value is null)
            {
                continue;
            }

            setup[SetupKeys.TryGetValue(setting, out var key) ? key : CamelCase(setting)] = value.Value;
        }

        return setup;
    }

    /// <summary>모르는 설정 이름은 camelCase로 둔다(<c>Front Wing Flap</c> → <c>frontWingFlap</c>).</summary>
    private static string CamelCase(string setting)
    {
        var words = setting.Split([' ', '-'], StringSplitOptions.RemoveEmptyEntries);
        return string.Concat(words.Select((w, i) => i == 0 ? w.ToLowerInvariant() : char.ToUpperInvariant(w[0]) + w[1..].ToLowerInvariant()));
    }

    private static List<F1LapsLap> ReadLaps(MarkdownTable? table)
    {
        if (table is null)
        {
            return [];
        }

        var lapColumn = table.RequireColumn("lap");
        var laps = new SortedDictionary<int, F1LapsLap>();
        foreach (var row in table.Rows)
        {
            var lap = MarkdownCells.Int(row, lapColumn, "Lap") ?? throw new F1LapsFormatException(row.Line, "랩 번호가 없습니다.");
            if (lap < 1)
            {
                throw new F1LapsFormatException(row.Line, "랩 번호는 1 이상입니다.");
            }

            laps[lap] = new F1LapsLap(
                lap,
                MarkdownCells.Int(row, table.Column("pos"), "Pos"),
                CompoundOf(MarkdownCells.Text(row, table.Column("tyre"))),
                string.Equals(MarkdownCells.Text(row, table.Column("pit")), PitYes, StringComparison.OrdinalIgnoreCase),
                MarkdownCells.Time(row, table.Column("time"), "Time"),
                MarkdownCells.Time(row, table.Column("s1"), "S1"),
                MarkdownCells.Time(row, table.Column("s2"), "S2"),
                MarkdownCells.Time(row, table.Column("s3"), "S3"));
        }

        return laps.Values.ToList();
    }

    private static List<F1LapsClassificationRow> ReadClassification(MarkdownTable? table)
    {
        if (table is null)
        {
            return [];
        }

        var positionColumn = table.RequireColumn("pos");
        var driverColumn = table.RequireColumn("driver");
        var rows = new List<F1LapsClassificationRow>(table.Rows.Count);
        foreach (var row in table.Rows)
        {
            var name = MarkdownCells.Text(row, driverColumn) ?? throw new F1LapsFormatException(row.Line, "드라이버 이름이 없습니다.");
            rows.Add(new F1LapsClassificationRow(
                MarkdownCells.Int(row, positionColumn, "Pos") ?? throw new F1LapsFormatException(row.Line, "순위가 없습니다."),
                name,
                string.Equals(name, PlayerName, StringComparison.OrdinalIgnoreCase),
                MarkdownCells.Time(row, table.Column("best lap"), "Best Lap"),
                MarkdownCells.Time(row, table.Column("gap"), "Gap"),
                MarkdownCells.Int(row, table.Column("points"), "Points"),
                MarkdownCells.Text(row, table.Column("team"))));
        }

        return rows;
    }

    private static List<F1LapsPenalty> ReadPenalties(MarkdownTable? table)
    {
        if (table is null)
        {
            return [];
        }

        return table.Rows
            .Select(row => new F1LapsPenalty(
                MarkdownCells.Int(row, table.Column("lap"), "Lap"),
                MarkdownCells.Text(row, table.Column("type")) ?? string.Empty,
                MarkdownCells.Text(row, table.Column("infringement")) ?? string.Empty))
            .Where(p => p.Penalty.Length > 0 || p.Infringement.Length > 0)
            .ToList();
    }
}
