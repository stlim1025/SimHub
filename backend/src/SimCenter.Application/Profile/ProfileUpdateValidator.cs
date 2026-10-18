using SimCenter.Application.Auth;
using SimCenter.Application.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Profile;

/// <summary>검증·정규화를 마친 프로필 값(<see cref="ProfileUpdateValidator.Validate"/> 결과).</summary>
public sealed record ValidatedProfile(
    string DisplayName,
    bool ShowOnLeaderboard,
    string? AvatarTeam,
    string PreferredGame,
    ControllerType Controller,
    ConsolePlatform Console,
    UnitSystem Units,
    string TimeZoneId,
    ThemePreference Theme);

/// <summary>
/// <see cref="UpdateProfileRequest"/>를 필드별로 검증한다(14 §5). 틀린 필드를 모두 모아 한 번의 <see cref="ValidationException"/>(400)으로 알린다.
/// 표시 이름 규칙은 가입과 같다(<see cref="UserInputRules"/>). 순수 함수라 단위 테스트로 검증한다.
/// </summary>
public static class ProfileUpdateValidator
{
    public const string DisplayNameField = "displayName";
    public const string ShowOnLeaderboardField = "showOnLeaderboard";
    public const string AvatarTeamField = "avatarTeam";
    public const string PreferredGameField = "preferredGame";
    public const string ControllerField = "controller";
    public const string ConsoleField = "console";
    public const string UnitsField = "units";
    public const string TimeZoneIdField = "timeZoneId";
    public const string ThemeField = "theme";

    private const string RequiredMessage = "필수 항목입니다.";
    private const string UnknownValueMessage = "지원하지 않는 값입니다.";
    private const string UnknownTimeZoneMessage = "알 수 없는 타임존입니다(IANA ID, 예: Asia/Seoul).";

    public static ValidatedProfile Validate(UpdateProfileRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var errors = new Dictionary<string, string[]>();

        var (displayName, displayNameError) = UserInputRules.CheckDisplayName(request.DisplayName);
        AddError(errors, DisplayNameField, displayNameError);
        AddError(errors, ShowOnLeaderboardField, request.ShowOnLeaderboard is null ? RequiredMessage : null);

        var avatarTeam = NormalizeAvatarTeam(request.AvatarTeam);
        AddError(errors, AvatarTeamField,
            avatarTeam is null || AvatarTeamCodes.IsKnown(avatarTeam) ? null : UnknownValueMessage);

        var preferredGame = (request.PreferredGame ?? string.Empty).Trim().ToUpperInvariant();
        AddError(errors, PreferredGameField, CodeError(preferredGame, GameCodes.IsSupported(preferredGame)));

        var controller = ParseEnum<ControllerType>(errors, ControllerField, request.Controller);
        var console = ParseEnum<ConsolePlatform>(errors, ConsoleField, request.Console);
        var units = ParseEnum<UnitSystem>(errors, UnitsField, request.Units);
        var theme = ParseEnum<ThemePreference>(errors, ThemeField, request.Theme);

        var timeZoneId = (request.TimeZoneId ?? string.Empty).Trim();
        AddError(errors, TimeZoneIdField, TimeZoneError(timeZoneId));

        if (errors.Count > 0)
        {
            throw new ValidationException("Validation failed.", errors);
        }

        return new ValidatedProfile(
            displayName, request.ShowOnLeaderboard!.Value, avatarTeam, preferredGame,
            controller, console, units, timeZoneId, theme);
    }

    /// <summary>빈 값·공백은 "사진 없음"(null), 그 외는 trim + 대문자.</summary>
    private static string? NormalizeAvatarTeam(string? avatarTeam)
        => string.IsNullOrWhiteSpace(avatarTeam) ? null : avatarTeam.Trim().ToUpperInvariant();

    private static string? CodeError(string value, bool known)
        => value.Length == 0 ? RequiredMessage : known ? null : UnknownValueMessage;

    private static string? TimeZoneError(string timeZoneId)
    {
        if (timeZoneId.Length == 0)
        {
            return RequiredMessage;
        }

        return timeZoneId.Length <= UserProfileDefaults.TimeZoneIdMaxLength && IanaTimeZones.IsValid(timeZoneId)
            ? null
            : UnknownTimeZoneMessage;
    }

    private static TEnum ParseEnum<TEnum>(Dictionary<string, string[]> errors, string field, string? value)
        where TEnum : struct, Enum
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            AddError(errors, field, RequiredMessage);
            return default;
        }

        if (!EnumNames.TryParse<TEnum>(value.Trim(), out var parsed))
        {
            AddError(errors, field, UnknownValueMessage);
        }

        return parsed;
    }

    private static void AddError(Dictionary<string, string[]> errors, string field, string? error)
    {
        if (error is not null)
        {
            errors[field] = [error];
        }
    }
}
