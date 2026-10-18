using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 내 스틴트 1개의 랩 범위(docs/15 §11.3). 첫 스틴트는 1랩부터, 다음 스틴트는 이전 <c>EndLap + 1</c>부터 자기 <c>EndLap</c>까지.
/// </summary>
public sealed record StintSpan(int StintNumber, int StartLap, int EndLap, string VisualCompound, bool IsLast)
{
    /// <summary>끝 랩 미기록 값.</summary>
    private const int UnsetEndLap = 0;

    /// <summary>UDP uint8 "없음" 값(255) — 이 이상이면 열린 끝.</summary>
    private const int OpenEndLapMarker = 255;

    /// <summary>열린 끝 스틴트의 끝 랩(기록이 있는 마지막 랩까지 이어진다).</summary>
    public const int OpenEnd = int.MaxValue;

    public bool Contains(int lapNumber) => lapNumber >= StartLap && lapNumber <= EndLap;

    /// <summary>활성 스틴트를 번호 순서로 범위로 바꾼다. 끝 랩이 앞 스틴트보다 작거나 같은(깨진) 스틴트는 건너뛴다.</summary>
    public static IReadOnlyList<StintSpan> From(SessionResult? result)
    {
        if (result is null)
        {
            return [];
        }

        var stints = result.TyreStints.Where(s => !s.IsDeleted).OrderBy(s => s.StintNumber).ToList();
        var spans = new List<StintSpan>();
        var previousEnd = 0;
        for (var i = 0; i < stints.Count; i++)
        {
            var stint = stints[i];
            // 게임은 진행 중(마지막) 스틴트 끝 랩을 0이나 255로 보낼 때가 있다 → 열린 끝으로 본다(docs/15 §11.3).
            var isLastStint = i == stints.Count - 1;
            var endLap = isLastStint && (stint.EndLap == UnsetEndLap || stint.EndLap >= OpenEndLapMarker) ? OpenEnd : stint.EndLap;
            if (endLap <= previousEnd)
            {
                continue;
            }

            spans.Add(new StintSpan(stint.StintNumber, previousEnd + 1, endLap, stint.VisualCompound.ToString(), IsLast: false));
            previousEnd = endLap;
        }

        if (spans.Count > 0)
        {
            spans[^1] = spans[^1] with { IsLast = true };
        }

        return spans;
    }

    /// <summary>그 랩의 컴파운드. 마지막 스틴트 끝을 넘은 랩은 마지막 스틴트로 본다. 스틴트가 없으면 null.</summary>
    public static string? CompoundAt(IReadOnlyList<StintSpan> spans, int lapNumber)
    {
        if (spans.Count == 0)
        {
            return null;
        }

        return (spans.FirstOrDefault(s => s.Contains(lapNumber)) ?? spans[^1]).VisualCompound;
    }

    /// <summary>스틴트가 바뀐 랩(마지막이 아닌 스틴트의 끝 랩 = 피트에 들어간 랩)인지.</summary>
    public static bool IsPitLap(IReadOnlyList<StintSpan> spans, int lapNumber)
        => spans.Any(s => !s.IsLast && s.EndLap == lapNumber);
}
