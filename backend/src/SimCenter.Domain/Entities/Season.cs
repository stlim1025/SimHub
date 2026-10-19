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
    /// <summary>사용자가 붙인 시즌 이름의 최대 길이(앞뒤 공백 제거 후).</summary>
    public const int NameMaxLength = 60;

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

    /// <summary>사용자가 붙인 표시 이름. null이면 기본 이름(모드·시즌 번호)을 쓴다.</summary>
    public string? Name { get; set; }

    /// <summary>사용자가 시즌을 완료로 표시한 시각(UTC). 진행 중이면 null.</summary>
    public DateTime? CompletedAt { get; set; }

    public ICollection<RaceWeekend> Weekends { get; set; } = new List<RaceWeekend>();

    /// <summary>표시 이름을 바꾼다. <paramref name="name"/>은 정규화된 값(공백 제거·빈 값은 null)이어야 한다.</summary>
    public void Rename(string? name, DateTime now)
    {
        Name = name;
        UpdatedAt = now;
    }

    /// <summary>완료로 표시한다. 이미 완료면 처음 시각을 그대로 둔다(수정 시각만 바꾼다).</summary>
    public void MarkCompleted(DateTime now)
    {
        CompletedAt ??= now;
        UpdatedAt = now;
    }

    /// <summary>완료 표시를 지운다(다시 진행 중).</summary>
    public void Reopen(DateTime now)
    {
        CompletedAt = null;
        UpdatedAt = now;
    }

    /// <summary>시즌을 지운다(soft delete). 주말·세션은 그대로 두고, 시즌 조회에서만 빠진다.</summary>
    public void SoftDelete(DateTime now)
    {
        IsDeleted = true;
        UpdatedAt = now;
    }

    /// <summary>지운 시즌을 되살린다 — 같은 시즌 링크의 세션이 다시 들어올 때(이름·완료 표시는 그대로).</summary>
    public void Restore(DateTime now)
    {
        IsDeleted = false;
        UpdatedAt = now;
    }

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
