using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 트랙 마스터 데이터. 게임이 UDP로 주는 정수 트랙 ID를 도메인 트랙에 매핑한다.
/// Migration Seed로 미리 채운다. Unique(GameCode, GameTrackId).
/// </summary>
public class Track : BaseEntity
{
    /// <summary>국가 코드 길이(ISO 3166-1 alpha-2).</summary>
    public const int CountryCodeLength = 2;

    /// <summary>게임 코드(예: "F1_25"). 게임 중립 유지를 위해 문자열(D-14).</summary>
    public required string GameCode { get; set; }

    /// <summary>게임 UDP가 제공하는 트랙 정수 ID.</summary>
    public int GameTrackId { get; set; }

    public required string Name { get; set; }

    /// <summary>국기 표시용 국가 코드(ISO 3166-1 alpha-2 대문자, D-43). 모르면 null. 시드가 매번 맞춘다.</summary>
    public string? CountryCode { get; set; }

    /// <summary>트랙 메뉴 순서(D-43: F1 25 캘린더 → 리버스 → Madrid → 옛 트랙). 시드가 매번 맞춘다.</summary>
    public int DisplayOrder { get; set; }
}
