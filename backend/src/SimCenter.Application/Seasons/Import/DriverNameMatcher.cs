using System.Globalization;
using System.Text;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 가져온 드라이버 이름 ↔ 게임 드라이버 이름 맞추기(docs/15 §12, D-55). 순수 함수 — 상태 없음.
/// 대소문자·악센트·여분 공백을 무시하고, 전체 이름이 같거나 성(마지막 낱말)이 같으면 같은 드라이버다
/// (게임 "PÉREZ" ↔ "Sergio Perez", "ANTONELLI" ↔ "Andrea-Kimi Antonelli").
/// </summary>
public static class DriverNameMatcher
{
    private static readonly char[] WordSeparators = [' ', '-', '.'];

    /// <summary>악센트를 지우고 대문자로, 공백을 하나로 줄인다.</summary>
    public static string Normalize(string? name)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            return string.Empty;
        }

        var decomposed = name.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var ch in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(ch);
            }
        }

        var plain = builder.ToString().Normalize(NormalizationForm.FormC).ToUpperInvariant();
        return string.Join(' ', plain.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
    }

    /// <summary>전체 이름이 같은가(정규화 후).</summary>
    public static bool IsFullMatch(string? importedName, string? gameName)
    {
        var a = Normalize(importedName);
        return a.Length > 0 && a == Normalize(gameName);
    }

    /// <summary>성(마지막 낱말, 하이픈·점도 낱말 구분)이 같은가(정규화 후).</summary>
    public static bool IsSurnameMatch(string? importedName, string? gameName)
    {
        var a = Surname(Normalize(importedName));
        return a.Length > 0 && a == Surname(Normalize(gameName));
    }

    private static string Surname(string normalized)
    {
        var words = normalized.Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);
        return words.Length == 0 ? string.Empty : words[^1];
    }
}
