namespace SimCenter.Application.Rankings;

/// <summary>랭킹 집계 기간(D-8). 실시간 브로드캐스트 기본값은 <see cref="Monthly"/>(D-8a).</summary>
public enum RankingPeriod
{
    Daily,
    Monthly,
    Yearly,
}
