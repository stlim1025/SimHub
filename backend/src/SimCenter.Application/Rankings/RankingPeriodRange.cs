namespace SimCenter.Application.Rankings;

/// <summary>
/// 랭킹 기간의 UTC 경계 구간 [FromUtc, ToUtc) 와 표시용 키. 순수 계산(프레임워크 무의존)이라 단위 테스트 가능.
/// 경계는 매장 로컬 타임존의 자정 기준으로 잡은 뒤 UTC로 변환한다(D-8).
/// </summary>
public sealed record RankingPeriodRange(DateTime FromUtc, DateTime ToUtc, string PeriodKey)
{
    /// <summary>주어진 기간·로컬 기준일·타임존으로 UTC 경계 구간을 계산한다.</summary>
    public static RankingPeriodRange For(RankingPeriod period, DateOnly localDate, string timeZoneId)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);

        var (localStart, localEnd, key) = period switch
        {
            RankingPeriod.Daily => (
                localDate,
                localDate.AddDays(1),
                localDate.ToString("yyyy-MM-dd")),
            RankingPeriod.Monthly => (
                new DateOnly(localDate.Year, localDate.Month, 1),
                new DateOnly(localDate.Year, localDate.Month, 1).AddMonths(1),
                localDate.ToString("yyyy-MM")),
            RankingPeriod.Yearly => (
                new DateOnly(localDate.Year, 1, 1),
                new DateOnly(localDate.Year, 1, 1).AddYears(1),
                localDate.ToString("yyyy")),
            _ => throw new ArgumentOutOfRangeException(nameof(period), period, "알 수 없는 랭킹 기간입니다."),
        };

        return new RankingPeriodRange(
            ToUtcMidnight(localStart, tz),
            ToUtcMidnight(localEnd, tz),
            key);
    }

    /// <summary>매장 로컬 타임존 기준의 "오늘" 날짜(기간 기본 기준일 계산용).</summary>
    public static DateOnly LocalToday(string timeZoneId, DateTime utcNow)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);
        var local = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc), tz);
        return DateOnly.FromDateTime(local);
    }

    private static DateTime ToUtcMidnight(DateOnly localDate, TimeZoneInfo tz)
    {
        var localMidnight = DateTime.SpecifyKind(localDate.ToDateTime(TimeOnly.MinValue), DateTimeKind.Unspecified);
        return TimeZoneInfo.ConvertTimeToUtc(localMidnight, tz);
    }
}
