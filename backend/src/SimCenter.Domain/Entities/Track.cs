using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 트랙 마스터 데이터. 게임이 UDP로 주는 정수 트랙 ID를 도메인 트랙에 매핑한다.
/// Migration Seed로 미리 채운다. Unique(GameCode, GameTrackId).
/// </summary>
public class Track : BaseEntity
{
    /// <summary>게임 코드(예: "F1_25"). 게임 중립 유지를 위해 문자열(D-14).</summary>
    public required string GameCode { get; set; }

    /// <summary>게임 UDP가 제공하는 트랙 정수 ID.</summary>
    public int GameTrackId { get; set; }

    public required string Name { get; set; }
}
