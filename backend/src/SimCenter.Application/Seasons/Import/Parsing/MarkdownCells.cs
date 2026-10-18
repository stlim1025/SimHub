using System.Globalization;

namespace SimCenter.Application.Seasons.Import.Parsing;

/// <summary>
/// 가져오기 표 칸 읽기(docs/15 §12, D-55). 순수 함수 — 상태 없음. <c>-</c>·빈 칸은 null, 형식이 틀리면 줄 번호와 함께
/// <see cref="F1LapsFormatException"/>.
/// </summary>
public static class MarkdownCells
{
    public const string EmptyValue = "-";

    private const char Marker = '*';
    private const int MillisecondsPerSecond = 1000;
    private const int SecondsPerMinute = 60;
    private const int MinutesPerHour = 60;

    /// <summary>강조·본인 표시(<c>*</c>)를 지우고 공백을 하나로 줄인다.</summary>
    public static string Clean(string value)
        => string.Join(' ', value.Replace(Marker.ToString(), string.Empty, StringComparison.Ordinal)
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

    /// <summary>칸 원문(정리 전). 열이 없거나 행이 짧으면 빈 문자열.</summary>
    public static string Raw(MarkdownRow row, int? column)
        => column is { } index && index < row.Cells.Count ? row.Cells[index] : string.Empty;

    /// <summary>정리한 칸 값. 비었거나 <c>-</c>면 null.</summary>
    public static string? Text(MarkdownRow row, int? column)
    {
        var value = Clean(Raw(row, column));
        return value.Length == 0 || value == EmptyValue ? null : value;
    }

    public static int? Int(MarkdownRow row, int? column, string name)
        => ParseInt(Text(row, column), row.Line, name);

    public static int? ParseInt(string? text, int line, string name)
    {
        if (text is null)
        {
            return null;
        }

        var trimmed = text.TrimStart('P', 'p');
        return int.TryParse(trimmed, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) && value >= 0
            ? value
            : throw new F1LapsFormatException(line, $"{name} 값이 숫자가 아닙니다: {text}");
    }

    /// <summary>실수(설정 값 등). 형식이 틀리면 null이 아니라 오류다.</summary>
    public static double? ParseDouble(string? text, int line, string name)
    {
        if (text is null)
        {
            return null;
        }

        return double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) && double.IsFinite(value)
            ? value
            : throw new F1LapsFormatException(line, $"{name} 값이 숫자가 아닙니다: {text}");
    }

    /// <summary>시간 칸(<c>m:ss.fff</c>, <c>ss.fff</c>, <c>h:mm:ss.fff</c>) → 밀리초. 0은 null.</summary>
    public static int? Time(MarkdownRow row, int? column, string name)
        => ParseTime(Text(row, column), row.Line, name);

    public static int? ParseTime(string? text, int line, string name)
    {
        if (text is null)
        {
            return null;
        }

        var parts = text.TrimStart('+').Split(':');
        if (parts.Length > 3
            || !decimal.TryParse(parts[^1], NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var seconds)
            || seconds >= SecondsPerMinute)
        {
            throw new F1LapsFormatException(line, $"{name} 형식이 아닙니다(m:ss.fff): {text}");
        }

        decimal total = seconds;
        var multiplier = SecondsPerMinute;
        for (var i = parts.Length - 2; i >= 0; i--)
        {
            if (!int.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out var unit))
            {
                throw new F1LapsFormatException(line, $"{name} 형식이 아닙니다(m:ss.fff): {text}");
            }

            total += (decimal)unit * multiplier;
            multiplier *= MinutesPerHour;
        }

        var ms = total * MillisecondsPerSecond;
        if (ms > int.MaxValue)
        {
            throw new F1LapsFormatException(line, $"{name} 값이 범위를 벗어납니다: {text}");
        }

        return ms <= 0 ? null : (int)decimal.Round(ms);
    }

    /// <summary>칸에 <c>*</c> 표시가 있는가(인게임 표의 최고 랩).</summary>
    public static bool HasMarker(MarkdownRow row, int? column) => Raw(row, column).Contains(Marker, StringComparison.Ordinal);
}
