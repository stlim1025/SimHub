using SimCenter.Application.Common;
using SimCenter.Application.Seasons.Import;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 가져온 세션(docs/15 §12, D-55)의 세션 상세 보정. 순수 계산.
/// <list type="bullet">
/// <item>Laps: 타이어·피트는 F1Laps 랩 표 그대로(스틴트 경계로 추정하지 않는다).</item>
/// <item>Penalties: F1Laps 표는 차를 알려 주지 않아 드라이버 미상(차 번호 −1, "Unknown")으로 보인다.</item>
/// </list>
/// </summary>
public static class ImportedDetailOverlay
{
    /// <summary>벌칙 대상 차를 모를 때의 차 번호.</summary>
    public const int UnknownCarIndex = -1;

    private const string UnknownDriverName = "Unknown";

    public static IReadOnlyList<SessionLapDto> Laps(IReadOnlyList<SessionLapDto> laps, ImportedSessionDetails imported)
    {
        ArgumentNullException.ThrowIfNull(laps);
        ArgumentNullException.ThrowIfNull(imported);

        var marks = imported.LapMarks.GroupBy(m => m.LapNumber).ToDictionary(g => g.Key, g => g.Last());
        return laps
            .Select(lap => marks.TryGetValue(lap.LapNumber, out var mark)
                ? lap with { VisualCompound = mark.VisualCompound ?? lap.VisualCompound, InPit = mark.Pit }
                : lap)
            .ToList();
    }

    public static IReadOnlyList<SessionPenaltyDto> Penalties(ImportedSessionDetails imported)
    {
        ArgumentNullException.ThrowIfNull(imported);

        return imported.Penalties
            .OrderBy(p => p.Lap)
            .Select(p => new SessionPenaltyDto(
                p.Lap,
                UnknownCarIndex,
                UnknownDriverName,
                IsPlayer: false,
                TeamCatalog.FallbackColor,
                p.InfringementType is { } infringement ? PenaltyCatalog.InfringementName(infringement) : p.Infringement,
                p.PenaltyType is { } penalty ? PenaltyCatalog.PenaltyName(penalty) : p.Penalty,
                TimeS: null,
                p.InfringementType,
                p.PenaltyType))
            .ToList();
    }
}
