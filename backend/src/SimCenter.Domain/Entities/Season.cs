using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 시즌(커리어·그랑프리 모드의 한 시즌, D-29). 키 = (UserId, GameCode, SeasonLinkId) — 같은 사용자의 같은 게임 링크 식별자는 한 시즌이다.
/// 기록된 세션의 분류 시각 범위(<see cref="FirstSessionAt"/>~<see cref="LastSessionAt"/>)만 들고 있고,
/// 라운드 번호는 저장하지 않는다(조회 시 <see cref="RaceWeekend.FirstSessionAt"/> 순서로 계산).
/// </summary>
public class Season : BaseEntity
{
    public Guid UserId { get; set; }

    /// <summary>게임 코드(예: "F1_25").</summary>
    public required string GameCode { get; set; }

    /// <summary>게임의 시즌 링크 식별자(0 아님).</summary>
    public long SeasonLinkId { get; set; }

    /// <summary>처음 받은 세션의 게임 모드.</summary>
    public GameMode GameMode { get; set; }

    /// <summary>받은 세션의 분류 시각 최소값(UTC).</summary>
    public DateTime FirstSessionAt { get; set; }

    /// <summary>받은 세션의 분류 시각 최대값(UTC).</summary>
    public DateTime LastSessionAt { get; set; }

    /// <summary>가져온 출처(docs/15 §12, D-55 — 예: "F1Laps"). 게임에서 기록된 시즌이면 null.</summary>
    public string? ImportedFrom { get; set; }

    /// <summary>가져온 시각(UTC). 가져온 시즌이 아니면 null.</summary>
    public DateTime? ImportedAt { get; set; }

    /// <summary>
    /// 가져온 스탠딩 스냅샷 JSON(jsonb, D-55): 제목·플레이어 이름·팀·드라이버별 포인트.
    /// Standings 기준선이 된다 — 가져온 뒤 기록된(가져온 것이 아닌) 세션의 포인트만 더한다. 가져온 시즌이 아니면 null.
    /// </summary>
    public string? ImportedStandings { get; set; }

    public ICollection<RaceWeekend> Weekends { get; set; } = new List<RaceWeekend>();

    /// <summary>
    /// 새 세션의 분류 시각으로 범위를 넓힌다. 범위가 실제로 넓어질 때만 <see cref="BaseEntity.UpdatedAt"/>을 <paramref name="now"/>로 바꾼다.
    /// </summary>
    public void Touch(DateTime classifiedAt, DateTime now)
    {
        var widened = false;
        if (classifiedAt < FirstSessionAt)
        {
            FirstSessionAt = classifiedAt;
            widened = true;
        }

        if (classifiedAt > LastSessionAt)
        {
            LastSessionAt = classifiedAt;
            widened = true;
        }

        if (widened)
        {
            UpdatedAt = now;
        }
    }
}
