namespace SimCenter.Application.Profile;

/// <summary>
/// 사용자 타임존 ID 검증(14 §5). 이 서버가 찾을 수 있는 <b>IANA</b> ID만 받는다 —
/// Windows ID("Korea Standard Time")는 OS마다 달라 저장하지 않는다.
/// </summary>
public static class IanaTimeZones
{
    public static bool IsValid(string? timeZoneId)
        => !string.IsNullOrWhiteSpace(timeZoneId)
            && TimeZoneInfo.TryFindSystemTimeZoneById(timeZoneId, out var zone)
            && zone.HasIanaId;
}
