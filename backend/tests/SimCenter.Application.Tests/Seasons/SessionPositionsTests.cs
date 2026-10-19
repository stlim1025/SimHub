using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Seasons;

/// <summary>
/// 스프린트 주말 판정(docs/12 §8.4): 본 레이스(Race2)나 스프린트 슛아웃이 있으면 스프린트 주말이다.
/// 슛아웃은 스프린트 주말에만 있으므로, 본 레이스를 달리기 전에도 그 주말의 Race를 스프린트로 볼 수 있다.
/// </summary>
public class SessionPositionsTests
{
    [Theory]
    [InlineData(new[] { SessionKind.Practice1, SessionKind.SprintShootout1, SessionKind.Race }, true)]   // 본 레이스 전 스프린트
    [InlineData(new[] { SessionKind.OneShotSprintShootout, SessionKind.Race }, true)]
    [InlineData(new[] { SessionKind.ShortSprintShootout }, true)]
    [InlineData(new[] { SessionKind.Race, SessionKind.Race2 }, true)]                                    // 기존 규칙 유지
    [InlineData(new[] { SessionKind.Qualifying3, SessionKind.Race }, false)]                             // 일반 주말
    [InlineData(new[] { SessionKind.Race }, false)]
    [InlineData(new SessionKind[0], false)]
    public void IsSprintWeekend_Race2OrSprintShootout(SessionKind[] weekendKinds, bool expected)
        => Assert.Equal(expected, SessionPositions.IsSprintWeekend(weekendKinds));
}
