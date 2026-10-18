namespace SimCenter.Domain.Enums;

/// <summary>
/// 앱 화면 테마(프로필 설정, 14 §3). <see cref="System"/>은 기기(브라우저·OS)의 밝기 설정을 따른다.
/// DB·API에는 이름 문자열로 저장한다.
/// </summary>
public enum ThemePreference
{
    System = 0,
    Light = 1,
    Dark = 2,
}
