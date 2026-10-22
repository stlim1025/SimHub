using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 외부(F1Laps) 공개 셋업 상위 N개 중 한 건. (GameCode, TrackId, Condition) 묶음 단위로 갱신 때마다 통째로 맞춘다 —
/// 새 목록에 있는 셋업은 순위·목록 값을 고치고, 빠진 셋업은 soft delete, 다시 들어온 셋업은 되살린다(같은 SourceId 행 재사용).
/// 상세(<see cref="Sections"/>)는 SourceId별로 한 번만 받아 둔다. 작성자(출처 사용자 이름)는 개인정보라 저장하지 않는다.
/// </summary>
public class CommunitySetup : BaseEntity
{
    /// <summary>출처: F1Laps.</summary>
    public const string SourceF1Laps = "F1Laps";

    public const int SourceMaxLength = 20;
    public const int SourceIdMaxLength = 64;
    public const int SourceUrlMaxLength = 300;
    public const int TeamNameMaxLength = 100;
    public const int SessionTypeMaxLength = 50;
    public const int SteeringMaxLength = 20;

    /// <summary>게임 코드(트랙의 게임과 같다).</summary>
    public required string GameCode { get; set; }

    public Guid TrackId { get; set; }
    public Track? Track { get; set; }

    /// <summary>노면 조건(<c>SetupConditions.Dry</c>/<c>Wet</c>).</summary>
    public required string Condition { get; set; }

    /// <summary>출처 목록의 순위(1부터).</summary>
    public int Rank { get; set; }

    /// <summary>출처 이름(<see cref="SourceF1Laps"/>).</summary>
    public required string Source { get; set; }

    /// <summary>출처의 셋업 식별자(F1Laps UUID 문자열).</summary>
    public required string SourceId { get; set; }

    /// <summary>원문 셋업 페이지 주소.</summary>
    public required string SourceUrl { get; set; }

    /// <summary>팀 이름(출처 표기 그대로). 모르면 null.</summary>
    public string? TeamName { get; set; }

    /// <summary>세션 종류(출처 표기 그대로, 예: "Time Trial"). 모르면 null.</summary>
    public string? SessionType { get; set; }

    /// <summary>랩타임(밀리초).</summary>
    public int LapTimeMs { get; set; }

    /// <summary>조향 장치(Wheel/Pad). 모르면 null.</summary>
    public string? Steering { get; set; }

    /// <summary>셋업을 기록한 날짜(출처 표기를 읽은 값). 읽지 못하면 null.</summary>
    public DateOnly? SetOn { get; set; }

    /// <summary>셋업 값 묶음 JSON(jsonb): <c>[{"title","items":[{"label","value"}]}]</c> — 출처 표기 그대로.</summary>
    public required string Sections { get; set; }

    /// <summary>출처 목록을 마지막으로 성공적으로 읽은 시각(UTC).</summary>
    public DateTime FetchedAt { get; set; }
}
