using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Tests.Seasons;

/// <summary>조회 계산기·서비스 테스트가 함께 쓰는 입력 행 생성 도우미(식별자·시각을 짧게 쓰기 위한 것).</summary>
internal static class SeasonTestRows
{
    public static readonly DateTime Day = new(2026, 3, 1, 0, 0, 0, DateTimeKind.Utc);

    /// <summary>번호로 만든 결정적 Guid(정렬 비교가 번호 순서와 같다).</summary>
    public static Guid Id(int number) => new(number, 0, 0, new byte[8]);

    /// <summary><see cref="Day"/>에서 <paramref name="hours"/>시간 뒤.</summary>
    public static DateTime At(double hours) => Day.AddHours(hours);

    public static SeasonResultRow Row(
        int session,
        int weekend,
        string driverKey,
        int position,
        int points,
        SessionType type = SessionType.Race,
        SessionKind kind = SessionKind.Race,
        double hours = 0,
        string? name = null,
        int carIndex = 0,
        int? teamId = 1,
        bool isPlayer = false,
        bool isAi = true,
        ResultStatus status = ResultStatus.Finished,
        int season = 1)
        => new(
            Id(season), Id(weekend), Id(session), type, kind, At(hours),
            driverKey, name ?? driverKey.ToUpperInvariant(), carIndex, teamId, isPlayer, isAi, position, status, points);

    /// <summary>이름이 없는(null) 행.</summary>
    public static SeasonResultRow Unnamed(int session, int weekend, string driverKey, int position, int points, int carIndex, double hours = 0)
        => Row(session, weekend, driverKey, position, points, hours: hours, carIndex: carIndex) with { DriverName = null };
}
