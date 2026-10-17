namespace SimCenter.Application.Rankings;

/// <summary>내 랩 목록 정렬 기준(11 §8). REST 쿼리 <c>sort=recent|fastest</c>(대소문자 무시).</summary>
public enum MyLapsSort
{
    /// <summary>최근 순(SetAt 내림차순). 기본값.</summary>
    Recent,

    /// <summary>빠른 순: 유효 랩 우선, 랩타임 오름차순, 동타임은 먼저 세운 기록 우선. 무효 랩은 맨 뒤.</summary>
    Fastest,
}
