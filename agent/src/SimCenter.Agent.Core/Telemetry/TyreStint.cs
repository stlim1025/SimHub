namespace SimCenter.Agent.Core.Telemetry;

/// <summary>
/// 타이어 스틴트 1개(P7). <paramref name="EndLap"/>은 이 스틴트가 끝나는 랩 번호,
/// <paramref name="ActualCompound"/>는 게임 고유 라벨(예: "C3", "Inter") — 알 수 없으면 null.
/// </summary>
public sealed record TyreStint(int EndLap, TyreCompound VisualCompound, string? ActualCompound);
