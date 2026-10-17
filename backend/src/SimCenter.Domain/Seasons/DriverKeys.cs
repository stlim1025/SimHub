namespace SimCenter.Domain.Seasons;

/// <summary>
/// 시즌 안의 드라이버 식별 키(D-32): 플레이어 → 게임 드라이버 ID → 이름+차 번호 → 세션 한정 차 키.
/// 순수 함수 — 상태 없음.
/// </summary>
public static class DriverKeys
{
    /// <summary>플레이어(내 차)의 고정 키.</summary>
    public const string Player = "player";

    private const string DriverPrefix = "driver:";
    private const string NamePrefix = "name:";
    private const string CarPrefix = "car:";
    private const char RaceNumberSeparator = '#';

    /// <summary>
    /// 드라이버 키를 만든다. 이름은 앞뒤 공백을 지우고 <c>ToUpperInvariant</c>로 정규화하며,
    /// 이름이 비었거나 공백뿐이면 이름 키를 쓰지 않고 이 세션 안에서만 유효한 차 키로 떨어진다.
    /// </summary>
    public static string Build(bool isPlayer, int? gameDriverId, string? name, int? raceNumber, string sessionRef, int carIndex)
    {
        if (isPlayer)
        {
            return Player;
        }

        if (gameDriverId is { } driverId)
        {
            return $"{DriverPrefix}{driverId}";
        }

        var normalizedName = name?.Trim().ToUpperInvariant();
        if (!string.IsNullOrEmpty(normalizedName))
        {
            return $"{NamePrefix}{normalizedName}{RaceNumberSeparator}{raceNumber}";
        }

        return $"{CarPrefix}{sessionRef}:{carIndex}";
    }
}
