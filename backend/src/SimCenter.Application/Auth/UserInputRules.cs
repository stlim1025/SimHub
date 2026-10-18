using System.Net.Mail;
using SimCenter.Application.Common.Exceptions;

namespace SimCenter.Application.Auth;

/// <summary>
/// 가입과 프로필 변경이 함께 쓰는 사용자 입력 규칙(이메일 정규화·형식, 표시 이름 길이). 같은 규칙을 한 곳에 둔다(14 §5).
/// </summary>
public static class UserInputRules
{
    public const int MaxEmailLength = 256;
    public const int MinDisplayNameLength = 1;
    public const int MaxDisplayNameLength = 50;

    /// <summary>다른 계정이 이미 쓰는 이메일(가입·이메일 변경 공통, 409).</summary>
    public const string EmailInUseMessage = "이미 사용 중인 이메일입니다.";

    /// <summary>앞뒤 공백을 지우고 소문자로 바꾼다(null은 빈 문자열).</summary>
    public static string NormalizeEmail(string? email) => (email ?? string.Empty).Trim().ToLowerInvariant();

    /// <summary>정규화된 이메일이 비었거나 형식이 틀리면 오류 메시지, 맞으면 null.</summary>
    public static string? EmailError(string normalizedEmail)
    {
        if (string.IsNullOrWhiteSpace(normalizedEmail))
        {
            return "이메일은 필수입니다.";
        }

        if (normalizedEmail.Length > MaxEmailLength || !MailAddress.TryCreate(normalizedEmail, out _))
        {
            return "이메일 형식이 올바르지 않습니다.";
        }

        return null;
    }

    /// <summary>정규화된 이메일을 검증한다. 틀리면 <paramref name="field"/> 필드의 <see cref="ValidationException"/>.</summary>
    public static void ValidateEmail(string normalizedEmail, string field)
    {
        if (EmailError(normalizedEmail) is { } error)
        {
            throw new ValidationException(field, error);
        }
    }

    /// <summary>표시 이름을 trim한다. 길이가 1~50자가 아니면 오류 메시지를 함께 돌려준다.</summary>
    public static (string Trimmed, string? Error) CheckDisplayName(string? displayName)
    {
        var trimmed = (displayName ?? string.Empty).Trim();
        var error = trimmed.Length is < MinDisplayNameLength or > MaxDisplayNameLength
            ? $"표시 이름은 {MinDisplayNameLength}~{MaxDisplayNameLength}자여야 합니다."
            : null;
        return (trimmed, error);
    }

    /// <summary>trim한 표시 이름. 길이가 틀리면 <paramref name="field"/> 필드의 <see cref="ValidationException"/>.</summary>
    public static string ValidateDisplayName(string? displayName, string field)
    {
        var (trimmed, error) = CheckDisplayName(displayName);
        if (error is not null)
        {
            throw new ValidationException(field, error);
        }

        return trimmed;
    }
}
