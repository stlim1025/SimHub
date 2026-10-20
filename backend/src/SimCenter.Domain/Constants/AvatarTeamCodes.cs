namespace SimCenter.Domain.Constants;

/// <summary>
/// 프로필 사진으로 고를 수 있는 팀 코드(14 §4, 2~3자). 실제 팀 로고는 상표라 쓰지 않고, 앱이 팀 색 원 + 이 코드로 그린다.
/// 앱의 같은 목록(<c>app/lib/features/profile/domain/avatar_teams.dart</c>)과 OpenAPI <c>AvatarTeamCode</c> enum과 순서·값을 맞춘다.
/// 불변 상수 목록이라 헌장의 "Global Static 금지"(가변 전역 상태)에 해당하지 않는다.
/// </summary>
public static class AvatarTeamCodes
{
    public const string Mercedes = "MER";
    public const string Ferrari = "FER";
    public const string RedBull = "RBR";
    public const string McLaren = "MCL";
    public const string AstonMartin = "AST";
    public const string Alpine = "ALP";
    public const string Williams = "WIL";
    public const string RacingBulls = "RB";
    public const string Audi = "AUD";
    public const string Haas = "HAA";

    /// <summary>저장 열 길이(가장 긴 코드보다 여유 있게).</summary>
    public const int MaxLength = 8;

    /// <summary>고를 수 있는 코드 전체(화면 표시 순서).</summary>
    public static readonly IReadOnlyList<string> All =
    [
        Mercedes, Ferrari, RedBull, McLaren, AstonMartin, Alpine, Williams, RacingBulls, Audi, Haas,
    ];

    /// <summary>등록된 코드인지(대소문자 구분 — 호출자가 먼저 대문자로 정규화한다).</summary>
    public static bool IsKnown(string code) => All.Contains(code, StringComparer.Ordinal);
}
