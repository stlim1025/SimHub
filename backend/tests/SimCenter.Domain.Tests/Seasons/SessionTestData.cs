using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Tests.Seasons;

/// <summary>세션·결과·스틴트 테스트 데이터 빌더(테스트 전용).</summary>
internal static class SessionTestData
{
    public static GameSession NewSession(params SessionResult[] results)
    {
        var session = new GameSession
        {
            Id = Guid.NewGuid(),
            GameCode = "F1_25",
            SessionKey = "uid:999",
            SessionRef = "999",
        };
        foreach (var result in results)
        {
            result.GameSessionId = session.Id;
            session.Results.Add(result);
        }

        return session;
    }

    /// <summary>값은 carIndex·position에서 파생해 서로 다른 결과를 구별할 수 있게 한다.</summary>
    public static SessionResult NewResult(int carIndex, int position, DateTime createdAt, int stintCount = 0)
    {
        var result = new SessionResult
        {
            Id = Guid.NewGuid(),
            CreatedAt = createdAt,
            CarIndex = carIndex,
            Position = position,
            GridPosition = position,
            DriverKey = $"driver:{carIndex}",
            DriverName = $"DRIVER {carIndex}",
            ResultStatus = ResultStatus.Finished,
        };
        for (var stintNumber = 1; stintNumber <= stintCount; stintNumber++)
        {
            result.TyreStints.Add(NewStint(result.Id, stintNumber, createdAt));
        }

        return result;
    }

    public static SessionResultTyreStint NewStint(Guid sessionResultId, int stintNumber, DateTime createdAt) => new()
    {
        Id = Guid.NewGuid(),
        CreatedAt = createdAt,
        SessionResultId = sessionResultId,
        StintNumber = stintNumber,
        EndLap = stintNumber * 10,
        VisualCompound = TyreCompound.Medium,
        ActualCompound = "C3",
    };
}
