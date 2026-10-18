using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using static SimCenter.Application.Tests.Seasons.SeasonTestRows;

namespace SimCenter.Application.Tests.Seasons.SessionDetail;

/// <summary>
/// 세션 상세 빌더 테스트 입력(docs/15 §11). JSON은 Agent가 실제로 보내는 키 모양(f1_25_udp_spec §7·§8,
/// <c>F1DetailSections</c>·<c>F1GameEvents</c>·<c>SessionDetailsCapture</c>)을 그대로 따른다.
/// </summary>
internal static class SessionDetailSamples
{
    /// <summary><c>GameSession.Details</c>: 차 0(나)·차 1의 랩 기록(3랩째는 진행 중 = 0) + 랩별 순위.</summary>
    public const string SessionDetailsJson = """
        {
          "lapHistory": [
            { "carIndex": 0, "laps": [
              { "lapNumber": 1, "lapTimeMs": 98412, "sector1TimeMs": 33801, "sector2TimeMs": 34190, "sector3TimeMs": 30421, "lapValid": true, "sector1Valid": true, "sector2Valid": true, "sector3Valid": true },
              { "lapNumber": 2, "lapTimeMs": 92044, "sector1TimeMs": 30903, "sector2TimeMs": 31870, "sector3TimeMs": 29271, "lapValid": true, "sector1Valid": true, "sector2Valid": true, "sector3Valid": true },
              { "lapNumber": 3, "lapTimeMs": 91500, "sector1TimeMs": 30700, "sector2TimeMs": 31900, "sector3TimeMs": 28900, "lapValid": false, "sector1Valid": true, "sector2Valid": false, "sector3Valid": true },
              { "lapNumber": 4, "lapTimeMs": 0, "sector1TimeMs": 30000, "sector2TimeMs": 0, "sector3TimeMs": 0, "lapValid": true, "sector1Valid": true, "sector2Valid": true, "sector3Valid": true }
            ] },
            { "carIndex": 1, "laps": [
              { "lapNumber": 1, "lapTimeMs": 97000, "sector1TimeMs": 33000, "sector2TimeMs": 34000, "sector3TimeMs": 30000, "lapValid": true, "sector1Valid": true, "sector2Valid": true, "sector3Valid": true }
            ] }
          ],
          "lapPositions": [
            { "lapNumber": 1, "positions": [5, 1, 2, 3, 4, 6] },
            { "lapNumber": 2, "positions": [3, 1, 2, 4, 5, 6] },
            { "lapNumber": 3, "positions": [4, 1, 2, 3, 5, 6] }
          ]
        }
        """;

    /// <summary>
    /// 스냅샷 <c>details</c>(D-49) 한 건: setup·damage·lapData·participant·events(PENA 둘 + 중복 하나 + 다른 코드).
    /// </summary>
    public static string SnapshotDetailsJson(int pitStatus = 0, int iceWear = 12) => $$"""
        {
          "setup": { "frontWing": 8, "rearWing": 6, "onThrottle": 70, "offThrottle": 55, "brakeBias": 56, "tyrePressure": { "FL": 23.5, "FR": 23.5, "RL": 21.5, "RR": 21.5 }, "fuelLoad": 12.4 },
          "damage": { "tyreBlisters": { "FL": 0, "FR": 0, "RL": 0, "RR": 0 }, "drsFault": false, "ersFault": false,
                      "engineMguhWear": 9, "engineEsWear": 7, "engineCeWear": 6, "engineIceWear": {{iceWear}}, "engineMgukWear": 8, "engineTcWear": 10,
                      "engineBlown": false, "engineSeized": false },
          "status": { "tractionControl": 0, "antiLockBrakes": 0 },
          "session": { "weather": 1, "aiDifficulty": 90 },
          "participant": { "carIndex": 0, "teamId": 221, "name": "Player" },
          "lapData": { "carIndex": 0, "carPosition": 4, "currentLapNum": 2, "pitStatus": {{pitStatus}}, "numPitStops": 0 },
          "events": [
            { "code": "OVTK", "lapTimeMs": 1200, "details": { "overtakingVehicleIndex": 0, "beingOvertakenVehicleIndex": 3 } },
            { "code": "PENA", "lapTimeMs": 15000, "details": { "penaltyType": 5, "infringementType": 4, "vehicleIndex": 0, "otherVehicleIndex": 3, "timeS": 255, "lapNumber": 2, "placesGained": 255 } },
            { "code": "PENA", "lapTimeMs": 15010, "details": { "penaltyType": 5, "infringementType": 4, "vehicleIndex": 0, "otherVehicleIndex": 3, "timeS": 255, "lapNumber": 2, "placesGained": 255 } },
            { "code": "PENA", "lapTimeMs": 42000, "details": { "penaltyType": 4, "infringementType": 7, "vehicleIndex": 1, "otherVehicleIndex": 255, "timeS": 5, "lapNumber": 2, "placesGained": 255 } }
          ]
        }
        """;

    public static SessionLapRow LapRow(
        int lapNumber,
        int lapTimeMs,
        bool isValid = true,
        string? details = null,
        double? wear = null,
        Weather? weather = null,
        int? gearbox = null,
        int? engine = null,
        double setAtHours = 0)
        => new(
            Id(3000 + lapNumber), lapNumber, lapTimeMs, isValid, At(setAtHours == 0 ? lapNumber : setAtHours),
            [30_000, 31_000, lapTimeMs - 61_000], details, weather,
            wear, wear, wear is null ? null : wear + 2, wear is null ? null : wear + 2,
            gearbox, engine);

    public static MySessionLap Lap(
        int lapNumber, int lapTimeMs, bool isValid = true, string? details = null, double? wear = null, int? gearbox = null, int? engine = null)
        => MySessionLap.From(LapRow(lapNumber, lapTimeMs, isValid, details, wear, gearbox: gearbox, engine: engine));

    public static SessionResult Result(
        int carIndex, int position, int grid, bool isPlayer = false, string? name = null, int? teamId = 221, params (int EndLap, TyreCompound Compound)[] stints)
        => new()
        {
            Id = Id(1000 + carIndex),
            CarIndex = carIndex,
            Position = position,
            GridPosition = grid,
            DriverKey = isPlayer ? "player" : $"driver:{carIndex}",
            DriverName = name,
            TeamId = teamId,
            IsPlayer = isPlayer,
            TyreStints = stints
                .Select((s, i) => new SessionResultTyreStint { Id = Id(2000 + i), StintNumber = i + 1, EndLap = s.EndLap, VisualCompound = s.Compound })
                .ToList(),
        };
}
