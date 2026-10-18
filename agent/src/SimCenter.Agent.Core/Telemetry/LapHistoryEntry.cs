namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 차 1대의 랩 1개 기록(F1 Session History 패킷의 랩 칸, D-49 docs/15 §8). 시간은 밀리초(분 단위 칸은 매퍼가 합산), 0 = 아직 없음.
/// 유효 플래그는 랩·섹터별(게임의 비트 플래그를 매퍼가 푼다).
/// </summary>
public sealed record LapHistoryEntry(
    int LapNumber,
    int LapTimeMs,
    int Sector1TimeMs,
    int Sector2TimeMs,
    int Sector3TimeMs,
    bool LapValid,
    bool Sector1Valid,
    bool Sector2Valid,
    bool Sector3Valid);
