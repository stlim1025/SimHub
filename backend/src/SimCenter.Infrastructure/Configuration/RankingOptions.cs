namespace SimCenter.Infrastructure.Configuration;

/// <summary>
/// 랭킹 설정(appsettings "Ranking" 섹션). 기간 경계 타임존은 서버 설정으로 고정한다(D-27).
/// </summary>
public sealed class RankingOptions
{
    public const string SectionName = "Ranking";

    /// <summary>랭킹 일/월/연 경계 계산에 쓰는 IANA 타임존 ID.</summary>
    public string TimeZoneId { get; set; } = "Asia/Seoul";
}
