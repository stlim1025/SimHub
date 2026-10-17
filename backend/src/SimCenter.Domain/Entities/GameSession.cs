using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 게임 세션 1건의 최종 순위표(P7, D-28). 키 = (UserId, GameCode, SessionKey) — <c>SessionKeys.For</c> 규칙(D-29).
/// 시즌 대상이 아닌 세션(또는 키 충돌로 대체 키를 쓴 세션)은 <see cref="SeasonId"/>·<see cref="RaceWeekendId"/>가 null이다.
/// </summary>
public class GameSession : BaseEntity
{
    public Guid UserId { get; set; }

    /// <summary>
    /// 마지막으로 결과를 보낸 장치. FK만 둔다 — <c>Lap.AgentDevice</c>의 soft-delete inner join 함정을 피하려고 내비게이션은 두지 않는다.
    /// </summary>
    public Guid AgentDeviceId { get; set; }

    /// <summary>시즌 대상이 아니면 null.</summary>
    public Guid? SeasonId { get; set; }

    /// <summary>시즌 대상이 아니면 null.</summary>
    public Guid? RaceWeekendId { get; set; }

    public required string GameCode { get; set; }

    /// <summary>세션 키(D-29). 사용자·게임 안에서 unique(삭제 제외).</summary>
    public required string SessionKey { get; set; }

    /// <summary>원본 링크 값(0 가능).</summary>
    public long SeasonLinkId { get; set; }

    /// <summary>원본 링크 값(0 가능).</summary>
    public long WeekendLinkId { get; set; }

    /// <summary>원본 링크 값(0 가능).</summary>
    public long SessionLinkId { get; set; }

    /// <summary>결과를 받은 게임 세션 UID(<c>SessionUID</c>).</summary>
    public required string SessionRef { get; set; }

    public Guid TrackId { get; set; }
    public Track? Track { get; set; }

    /// <summary>세션 유형(Practice·Qualifying·Race…).</summary>
    public SessionType SessionType { get; set; }

    /// <summary>세션 상세 종류(Practice1, Qualifying2, SprintShootout1, Race2…).</summary>
    public SessionKind SessionKind { get; set; }

    public GameMode GameMode { get; set; }

    public int TotalLaps { get; set; }
    public int AiDifficulty { get; set; }
    public bool IsNetworkGame { get; set; }

    /// <summary>순위표가 확정된 시각(UTC).</summary>
    public DateTime ClassifiedAt { get; set; }

    public ICollection<SessionResult> Results { get; set; } = new List<SessionResult>();

    /// <summary>
    /// 재분류 결과를 carIndex별로 제자리 병합한다(§4.5).
    /// <list type="number">
    /// <item>같은 carIndex의 활성 행이 있으면 값을 덮어쓰고 활성 스틴트는 soft delete한 뒤 새 스틴트를 붙인다.</item>
    /// <item>새 순위표에 없는 carIndex의 활성 행은 스틴트까지 soft delete한다.</item>
    /// <item>새 carIndex는 새 행으로 추가한다.</item>
    /// </list>
    /// 이미 지워진 행은 건드리지 않고(같은 carIndex의 새 행은 새로 붙는다) 컬렉션에서 아무것도 빼지 않는다.
    /// 같은 carIndex에 새 행을 만들지 않으므로, 필터 unique index 아래서 한 번의 SaveChanges가 INSERT-UPDATE 순서 때문에 실패하지 않는다.
    /// 중복 carIndex는 인입 검증이 거르지만, 방어적으로 같은 carIndex는 마지막 항목만 쓴다.
    /// </summary>
    public void ReplaceResults(IReadOnlyList<SessionResult> incoming, DateTime now)
    {
        ArgumentNullException.ThrowIfNull(incoming);

        var incomingByCar = new Dictionary<int, SessionResult>();
        foreach (var result in incoming)
        {
            incomingByCar[result.CarIndex] = result;
        }

        var mergedCars = new HashSet<int>();
        foreach (var row in Results.Where(r => !r.IsDeleted).ToList())
        {
            if (incomingByCar.TryGetValue(row.CarIndex, out var replacement) && mergedCars.Add(row.CarIndex))
            {
                row.CopyValuesFrom(replacement, now);
                row.ReplaceTyreStints(replacement.TyreStints, now);
            }
            else
            {
                row.SoftDelete(now);
            }
        }

        foreach (var result in incomingByCar.Values.Where(r => !mergedCars.Contains(r.CarIndex)))
        {
            result.GameSessionId = Id;
            foreach (var stint in result.TyreStints)
            {
                stint.SessionResultId = result.Id;
            }

            Results.Add(result);
        }
    }
}
