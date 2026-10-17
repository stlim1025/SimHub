namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>최종 순위표의 차 1대(F1 Final Classification 패킷의 carIndex 칸). 시간은 모두 밀리초.</summary>
public sealed record ClassificationRow(
    int CarIndex,
    int Position,
    int GridPosition,
    int NumLaps,
    int Points,
    int NumPitStops,
    int NumPenalties,
    ResultStatus ResultStatus,
    int BestLapTimeMs,
    int TotalRaceTimeMs,
    int PenaltiesTimeMs,
    IReadOnlyList<TyreStint> TyreStints);

/// <summary>최종 순위표 프레임(F1 Final Classification 패킷 매핑, 세션 끝). 빈 그리드 칸은 매퍼가 이미 뺀 상태다.</summary>
public sealed record ClassificationFrame(
    string SessionRef,
    int PlayerCarIndex,
    IReadOnlyList<ClassificationRow> Rows) : ITelemetryFrame;
