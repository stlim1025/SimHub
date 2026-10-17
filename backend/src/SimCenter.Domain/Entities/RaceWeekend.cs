using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 그랑프리 주말(한 시즌 안의 한 트랙 방문, D-29). 키 = (SeasonId, WeekendLinkId).
/// 라운드 번호는 저장하지 않는다 — 시즌 안에서 <see cref="FirstSessionAt"/>, Id 순서로 조회 시 계산한다.
/// </summary>
public class RaceWeekend : BaseEntity
{
    public Guid SeasonId { get; set; }
    public Season? Season { get; set; }

    /// <summary>게임의 주말 링크 식별자(0 아님).</summary>
    public long WeekendLinkId { get; set; }

    /// <summary>처음 받은 세션의 트랙.</summary>
    public Guid TrackId { get; set; }
    public Track? Track { get; set; }

    /// <summary>받은 세션의 분류 시각 최소값(UTC). 라운드 순서 기준.</summary>
    public DateTime FirstSessionAt { get; set; }

    /// <summary>
    /// 새 세션의 분류 시각이 더 이르면 <see cref="FirstSessionAt"/>을 앞당기고 <see cref="BaseEntity.UpdatedAt"/>을 <paramref name="now"/>로 바꾼다.
    /// 그렇지 않으면 아무것도 바꾸지 않는다.
    /// </summary>
    public void Touch(DateTime classifiedAt, DateTime now)
    {
        if (classifiedAt >= FirstSessionAt)
        {
            return;
        }

        FirstSessionAt = classifiedAt;
        UpdatedAt = now;
    }
}
