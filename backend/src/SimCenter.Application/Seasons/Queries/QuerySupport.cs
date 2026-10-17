namespace SimCenter.Application.Seasons.Queries;

/// <summary>드라이버 표시 이름 규칙(12 §7.2): 이름이 없으면 <c>Car {carIndex+1}</c>.</summary>
internal static class DriverLabels
{
    public static string Name(string? driverName, int carIndex)
        => string.IsNullOrWhiteSpace(driverName) ? $"Car {carIndex + 1}" : driverName;
}

/// <summary>
/// 점수 합계 변환. 점수는 검증에서 0 이상 <c>int</c>만 거르므로 큰 값이 여러 번 더해지면 <c>int</c>를 넘을 수 있다.
/// 합계는 항상 <c>long</c>으로 구해 정렬에 쓰고(순서가 틀어지지 않게), 화면 값(DTO)만 <c>int</c> 상한으로 자른다.
/// </summary>
internal static class PointTotals
{
    public static int ToInt(long total) => (int)Math.Clamp(total, int.MinValue, int.MaxValue);
}

/// <summary>
/// 목록 조회의 페이지 보정(<c>RankingService.GetMyLapsAsync</c>와 같은 규칙): page &lt; 1 → 1, pageSize &lt; 1 → 기본값, 최대 초과 → 최대.
/// 건너뛸 개수는 <c>long</c>으로 계산해 <c>int</c> 상한으로 자른다 — 아주 큰 page가 오버플로로 음수 오프셋이 되어 DB 오류가 되지 않게.
/// </summary>
internal readonly record struct PageWindow(int Page, int PageSize, int Skip)
{
    public static PageWindow Resolve(int page, int pageSize, int defaultPageSize, int maxPageSize)
    {
        var resolvedPage = page < 1 ? 1 : page;

        var resolvedSize = pageSize;
        if (resolvedSize < 1)
        {
            resolvedSize = defaultPageSize;
        }
        else if (resolvedSize > maxPageSize)
        {
            resolvedSize = maxPageSize;
        }

        var skip = (long)(resolvedPage - 1) * resolvedSize;
        return new PageWindow(resolvedPage, resolvedSize, (int)Math.Min(skip, int.MaxValue));
    }
}
