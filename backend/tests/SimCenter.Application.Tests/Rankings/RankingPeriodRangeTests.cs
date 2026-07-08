using SimCenter.Application.Rankings;

namespace SimCenter.Application.Tests.Rankings;

/// <summary>
/// 기간 경계 순수 계산 검증. 기준 타임존 = Asia/Seoul(UTC+9, DST 없음).
/// 로컬 자정을 UTC로 환산하면 전일 15:00Z가 된다.
/// </summary>
public class RankingPeriodRangeTests
{
    private const string Seoul = "Asia/Seoul";

    [Fact]
    public void Daily_ComputesLocalMidnightBoundaries_InUtc()
    {
        var range = RankingPeriodRange.For(RankingPeriod.Daily, new DateOnly(2026, 7, 6), Seoul);

        Assert.Equal(new DateTime(2026, 7, 5, 15, 0, 0, DateTimeKind.Utc), range.FromUtc);
        Assert.Equal(new DateTime(2026, 7, 6, 15, 0, 0, DateTimeKind.Utc), range.ToUtc);
        Assert.Equal("2026-07-06", range.PeriodKey);
    }

    [Fact]
    public void Monthly_SpansWholeLocalMonth()
    {
        var range = RankingPeriodRange.For(RankingPeriod.Monthly, new DateOnly(2026, 7, 15), Seoul);

        Assert.Equal(new DateTime(2026, 6, 30, 15, 0, 0, DateTimeKind.Utc), range.FromUtc);
        Assert.Equal(new DateTime(2026, 7, 31, 15, 0, 0, DateTimeKind.Utc), range.ToUtc);
        Assert.Equal("2026-07", range.PeriodKey);
    }

    [Fact]
    public void Yearly_SpansWholeLocalYear()
    {
        var range = RankingPeriodRange.For(RankingPeriod.Yearly, new DateOnly(2026, 7, 15), Seoul);

        Assert.Equal(new DateTime(2025, 12, 31, 15, 0, 0, DateTimeKind.Utc), range.FromUtc);
        Assert.Equal(new DateTime(2026, 12, 31, 15, 0, 0, DateTimeKind.Utc), range.ToUtc);
        Assert.Equal("2026", range.PeriodKey);
    }

    [Fact]
    public void LocalToday_ConvertsUtcNowToStoreLocalDate()
    {
        // 2026-07-06 20:00Z → 서울 2026-07-07 05:00 → 로컬 날짜 07-07.
        var today = RankingPeriodRange.LocalToday(Seoul, new DateTime(2026, 7, 6, 20, 0, 0, DateTimeKind.Utc));

        Assert.Equal(new DateOnly(2026, 7, 7), today);
    }
}
