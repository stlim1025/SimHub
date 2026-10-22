namespace SimCenter.Application.Setups.Refresh;

/// <summary>출처 셋업 목록 페이지의 트랙 링크 한 건.</summary>
/// <param name="Slug">주소의 트랙 조각(<c>australia</c>).</param>
/// <param name="Name">표시 이름(국가, 예: "United States (Miami)").</param>
/// <param name="CircuitName">서킷 이름. 없으면 null.</param>
public sealed record SetupTrackLink(string Slug, string Name, string? CircuitName);

/// <summary>트랙·조건별 셋업 순위표의 한 줄. 작성자(출처 사용자 이름)는 개인정보라 담지 않는다.</summary>
public sealed record SetupListRow(
    int Rank,
    string SourceId,
    string SourceUrl,
    string? TeamName,
    string? SessionType,
    int LapTimeMs);

/// <summary>셋업 상세 페이지에서 읽은 값. 읽지 못한 칸은 null.</summary>
public sealed record SetupDetail(
    string? TeamName,
    string? SessionType,
    int? LapTimeMs,
    string? Condition,
    string? Steering,
    DateOnly? SetOn,
    IReadOnlyList<SetupSectionDto> Sections);

/// <summary>
/// 공개 셋업 출처(F1Laps) 읽기 포트. 구현은 요청마다 간격을 두고, 실패(네트워크·HTTP 오류·페이지 구조 변경)는 예외로 알린다.
/// </summary>
public interface ISetupSource
{
    /// <summary>게임의 셋업 트랙 목록.</summary>
    Task<IReadOnlyList<SetupTrackLink>> GetTracksAsync(string gameCode, CancellationToken cancellationToken = default);

    /// <summary>트랙·조건의 셋업 순위표(출처가 보여 주는 순서).</summary>
    Task<IReadOnlyList<SetupListRow>> GetRankingAsync(
        string gameCode, string slug, string condition, CancellationToken cancellationToken = default);

    /// <summary>셋업 상세.</summary>
    Task<SetupDetail> GetDetailAsync(string sourceUrl, CancellationToken cancellationToken = default);
}
