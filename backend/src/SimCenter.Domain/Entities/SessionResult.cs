using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 세션 최종 순위표에서 차 1대의 결과(P7). 키 = (GameSessionId, CarIndex).
/// 컬렉션에서 <c>Remove</c>·<c>Clear</c>하지 않는다 — 필수 FK + Cascade라 EF가 실제 삭제를 한다. 지우기는 항상 <see cref="SoftDelete"/>.
/// <see cref="BaseEntity.UpdatedAt"/>은 자동으로 채워지지 않으니 바꾸는 쪽이 <c>now</c>를 직접 넣는다.
/// </summary>
public class SessionResult : BaseEntity
{
    public Guid GameSessionId { get; set; }

    /// <summary>세션 안의 차 번호(0부터).</summary>
    public int CarIndex { get; set; }

    public int Position { get; set; }
    public int GridPosition { get; set; }
    public int NumLaps { get; set; }
    public int Points { get; set; }
    public int NumPitStops { get; set; }
    public int NumPenalties { get; set; }

    public ResultStatus ResultStatus { get; set; }

    /// <summary>베스트 랩(밀리초). 0 = 기록 없음.</summary>
    public int BestLapTimeMs { get; set; }

    /// <summary>총 레이스 시간(밀리초, 패널티 제외). 0 = 없음.</summary>
    public int TotalRaceTimeMs { get; set; }

    /// <summary>패널티 시간(밀리초).</summary>
    public int PenaltiesTimeMs { get; set; }

    /// <summary>시즌 안의 드라이버 식별 키(D-32, <c>DriverKeys.Build</c>).</summary>
    public required string DriverKey { get; set; }

    /// <summary>드라이버 이름. 참가자 정보가 없으면 null(표시는 "Car {carIndex+1}").</summary>
    public string? DriverName { get; set; }

    /// <summary>게임 드라이버 ID. 사람(네트워크) 드라이버면 null.</summary>
    public int? GameDriverId { get; set; }

    /// <summary>게임 팀 ID.</summary>
    public int? TeamId { get; set; }

    public int? RaceNumber { get; set; }

    public bool IsAiControlled { get; set; }
    public bool IsPlayer { get; set; }

    public ICollection<SessionResultTyreStint> TyreStints { get; set; } = new List<SessionResultTyreStint>();

    /// <summary>
    /// <paramref name="source"/>의 값 필드를 모두 복사하고 <see cref="BaseEntity.UpdatedAt"/>을 <paramref name="now"/>로 바꾼다.
    /// 정체성(Id·GameSessionId·CreatedAt)·삭제 상태(IsDeleted)·스틴트 컬렉션은 건드리지 않는다.
    /// </summary>
    public void CopyValuesFrom(SessionResult source, DateTime now)
    {
        ArgumentNullException.ThrowIfNull(source);

        CarIndex = source.CarIndex;
        Position = source.Position;
        GridPosition = source.GridPosition;
        NumLaps = source.NumLaps;
        Points = source.Points;
        NumPitStops = source.NumPitStops;
        NumPenalties = source.NumPenalties;
        ResultStatus = source.ResultStatus;
        BestLapTimeMs = source.BestLapTimeMs;
        TotalRaceTimeMs = source.TotalRaceTimeMs;
        PenaltiesTimeMs = source.PenaltiesTimeMs;
        DriverKey = source.DriverKey;
        DriverName = source.DriverName;
        GameDriverId = source.GameDriverId;
        TeamId = source.TeamId;
        RaceNumber = source.RaceNumber;
        IsAiControlled = source.IsAiControlled;
        IsPlayer = source.IsPlayer;
        UpdatedAt = now;
    }

    /// <summary>
    /// 활성 스틴트를 모두 soft delete하고(<c>UpdatedAt = now</c>) <paramref name="stints"/>를 새 스틴트로 붙인다.
    /// 컬렉션에서 아무것도 빼지 않는다. 붙이는 스틴트의 <see cref="SessionResultTyreStint.SessionResultId"/>는 이 결과의 Id로 맞춘다.
    /// </summary>
    public void ReplaceTyreStints(IEnumerable<SessionResultTyreStint> stints, DateTime now)
    {
        ArgumentNullException.ThrowIfNull(stints);

        var incoming = stints.ToList();
        SoftDeleteActiveStints(now);

        foreach (var stint in incoming)
        {
            stint.SessionResultId = Id;
            TyreStints.Add(stint);
        }
    }

    /// <summary>
    /// 이 결과와 활성 스틴트를 soft delete한다(<c>UpdatedAt = now</c>). 이미 지워진 결과는 그대로 둔다.
    /// </summary>
    public void SoftDelete(DateTime now)
    {
        if (IsDeleted)
        {
            return;
        }

        IsDeleted = true;
        UpdatedAt = now;
        SoftDeleteActiveStints(now);
    }

    private void SoftDeleteActiveStints(DateTime now)
    {
        foreach (var stint in TyreStints.Where(s => !s.IsDeleted))
        {
            stint.IsDeleted = true;
            stint.UpdatedAt = now;
        }
    }
}
