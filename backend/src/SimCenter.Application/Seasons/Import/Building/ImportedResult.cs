using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Import.Building;

/// <summary>
/// 가져온 세션의 결과 한 줄을 만드는 중간 값(D-55). 문서마다 아는 칸만 채우고, 저장할 때 <see cref="SimCenter.Domain.Entities.SessionResult"/>로 바꾼다.
/// </summary>
internal sealed class ImportedResult(RosterDriver driver)
{
    public RosterDriver Driver { get; } = driver;

    public int? Position { get; set; }

    public ResultStatus Status { get; set; } = ResultStatus.Finished;

    public int? Points { get; set; }

    public int? BestLapTimeMs { get; set; }

    public int? GapMs { get; set; }

    public int NumLaps { get; set; }

    public int NumPitStops { get; set; }

    public IReadOnlyList<(int EndLap, TyreCompound Compound)> Stints { get; set; } = [];
}

/// <summary>레이스 포인트 표(D-55): 인게임 순위표에는 라운드별 포인트가 없어 순위로 계산한다(표시용 — Standings는 TOT 기준).</summary>
internal static class ImportPoints
{
    private static readonly int[] Race = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];
    private static readonly int[] Sprint = [8, 7, 6, 5, 4, 3, 2, 1];

    public static int For(int position, ResultStatus status, bool isSprint)
    {
        var table = isSprint ? Sprint : Race;
        return status == ResultStatus.Finished && position >= 1 && position <= table.Length ? table[position - 1] : 0;
    }
}
