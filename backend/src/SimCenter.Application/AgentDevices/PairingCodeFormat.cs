using System.Text;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.AgentDevices;

/// <summary>
/// Agent 연결 코드 형식(11 §4.1). 8자, 혼동 문자(0·O·1·I)를 뺀 32자 집합.
/// 표시는 <c>XXXX-XXXX</c>, 입력은 대문자화·하이픈/공백 제거로 정규화한 뒤 해시한다.
/// </summary>
public static class PairingCodeFormat
{
    /// <summary>코드 문자 집합(32자). 256이 32의 배수이므로 바이트 % 32 매핑에 편향이 없다.</summary>
    public const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    /// <summary>정규화된 코드 길이.</summary>
    public const int Length = 8;

    private const int DisplayGroupLength = 4;
    private const char DisplaySeparator = '-';

    /// <summary>난수 바이트를 문자 집합으로 매핑해 정규화된 코드(하이픈 없음)를 만든다.</summary>
    public static string Create(IRandomSource random)
    {
        ArgumentNullException.ThrowIfNull(random);

        var bytes = random.GetBytes(Length);
        var code = new StringBuilder(Length);
        foreach (var value in bytes)
        {
            code.Append(Alphabet[value % Alphabet.Length]);
        }

        return code.ToString();
    }

    /// <summary>정규화된 코드를 사용자 표시용 <c>XXXX-XXXX</c>로 바꾼다.</summary>
    public static string Display(string code)
    {
        ArgumentNullException.ThrowIfNull(code);
        return $"{code[..DisplayGroupLength]}{DisplaySeparator}{code[DisplayGroupLength..]}";
    }

    /// <summary>사용자 입력을 해시 대상 형식으로 정규화한다(대문자화, 하이픈·공백 제거). null은 빈 문자열.</summary>
    public static string Normalize(string? input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return string.Empty;
        }

        var normalized = new StringBuilder(input.Length);
        foreach (var ch in input)
        {
            if (ch == DisplaySeparator || char.IsWhiteSpace(ch))
            {
                continue;
            }

            normalized.Append(char.ToUpperInvariant(ch));
        }

        return normalized.ToString();
    }
}
