using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Constants;

/// <summary>
/// 새 사용자(와 마이그레이션 전 기존 사용자)의 프로필 설정 기본값(14 §3). 엔티티 초기값과 마이그레이션 백필이 같은 값을 쓴다.
/// </summary>
public static class UserProfileDefaults
{
    public const bool ShowOnLeaderboard = true;
    public const string PreferredGame = GameCodes.F1_25;
    public const ControllerType Controller = ControllerType.Wheel;
    public const ConsolePlatform Console = ConsolePlatform.Pc;
    public const UnitSystem Units = UnitSystem.Metric;
    public const string TimeZoneId = "Asia/Seoul";
    public const ThemePreference Theme = ThemePreference.System;

    /// <summary>타임존 ID 저장 열 길이(가장 긴 IANA ID도 담는다).</summary>
    public const int TimeZoneIdMaxLength = 64;
}
