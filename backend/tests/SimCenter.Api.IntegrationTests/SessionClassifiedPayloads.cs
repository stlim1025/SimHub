namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// <c>SessionClassified</c> 이벤트 payload(shared/schema/session_classified.json) 빌더. 통합 테스트 공용(익명 객체 → camelCase JSON).
/// </summary>
internal static class SessionClassifiedPayloads
{
    /// <summary>시드 트랙 Silverstone의 게임 트랙 ID.</summary>
    public const int SeedTrackId = 7;

    /// <summary>두 번째 시드 트랙 Spa의 게임 트랙 ID(같은 키·다른 트랙 시나리오용).</summary>
    public const int OtherSeedTrackId = 10;

    /// <summary>모든 payload가 쓰는 게임 세션 UID(<c>SessionUID</c>).</summary>
    public const string SessionRef = "1844674407370955161";

    private static readonly string[] VisualCompounds = ["Soft", "Medium", "Hard", "Intermediate", "Wet"];

    /// <summary>
    /// 커리어 모드(<c>DriverCareer</c>) 세션 순위표 payload. 차는 <c>carIndex</c> 0부터 <paramref name="carCount"/>대,
    /// 순위는 <c>carIndex + 1</c>이다. 드라이버 이름은 <c>"{namePrefix} {carIndex}"</c>이고 플레이어 차만 게임 드라이버 ID가 없다.
    /// 스틴트의 실제 컴파운드 라벨은 <paramref name="actualCompound"/>(기본 null이면 스틴트마다 <c>C0</c>~<c>C5</c>)다.
    /// 점수는 <paramref name="awardsPoints"/>가 true면 <c>max(0, 25 - 3 × carIndex)</c>, false면 전부 0(예선 등)이다.
    /// <paramref name="playerCarIndex"/>가 차 범위 밖(예: -1)이면 플레이어 차가 없는 순위표다.
    /// </summary>
    public static object Build(
        int carCount,
        int stintsPerCar,
        long seasonLink,
        long weekendLink,
        long sessionLink,
        string sessionKind = "Race",
        string sessionType = "Race",
        int playerCarIndex = 0,
        int trackId = SeedTrackId,
        string namePrefix = "DRIVER",
        string? actualCompound = null,
        bool awardsPoints = true)
    {
        var results = Enumerable.Range(0, carCount)
            .Select(carIndex => BuildResult(
                carIndex, stintsPerCar, carIndex == playerCarIndex, namePrefix, actualCompound, awardsPoints))
            .ToArray();

        return new
        {
            sessionRef = SessionRef,
            trackId,
            sessionType,
            sessionKind,
            gameMode = "DriverCareer",
            seasonLinkId = seasonLink,
            weekendLinkId = weekendLink,
            sessionLinkId = sessionLink,
            totalLaps = 15,
            aiDifficulty = 85,
            isNetworkGame = false,
            results,
        };
    }

    private static object BuildResult(
        int carIndex, int stintsPerCar, bool isPlayer, string namePrefix, string? actualCompound, bool awardsPoints)
    {
        var tyreStints = Enumerable.Range(1, stintsPerCar)
            .Select(stint => new
            {
                endLap = stint * 5,
                visualCompound = VisualCompounds[stint % VisualCompounds.Length],
                actualCompound = actualCompound ?? $"C{stint % 6}",
            })
            .ToArray();

        return new
        {
            carIndex,
            isPlayer,
            position = carIndex + 1,
            gridPosition = carIndex + 1,
            numLaps = 15,
            points = awardsPoints ? Math.Max(0, 25 - (carIndex * 3)) : 0,
            numPitStops = stintsPerCar,
            numPenalties = 0,
            resultStatus = "Finished",
            bestLapTimeMs = 81000 + (carIndex * 37),
            totalRaceTimeMs = 2_400_000 + (carIndex * 1500),
            penaltiesTimeMs = 0,
            driverName = $"{namePrefix} {carIndex}",
            gameDriverId = isPlayer ? (int?)null : carIndex,
            teamId = carIndex % 10,
            raceNumber = carIndex + 1,
            isAiControlled = !isPlayer,
            tyreStints,
        };
    }
}
