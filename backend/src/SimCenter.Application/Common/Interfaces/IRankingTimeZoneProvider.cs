namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 랭킹 기간(일/월/연) 경계 계산에 쓰는 타임존 제공 포트(D-8, D-27).
/// 개인 모드에서는 매장(Store) 대신 서버 설정(Ranking:TimeZoneId)이 단일 출처다.
/// </summary>
public interface IRankingTimeZoneProvider
{
    /// <summary>랭킹 기간 경계에 사용하는 IANA 타임존 ID(예: Asia/Seoul).</summary>
    string TimeZoneId { get; }
}
