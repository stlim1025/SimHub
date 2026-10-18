namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 시즌 가져오기 유스케이스(docs/15 §12, D-55). 형식 오류는 <c>ValidationException</c>(400, 줄 번호 포함),
/// 이미 가져온 시즌은 <c>ConflictException</c>(409, 덮어쓰지 않음)이다.
/// </summary>
public interface ISeasonImportService
{
    /// <summary>붙여넣은 마크다운 최대 길이(문자). 세션 내보내기 수십 개를 넉넉히 담는다.</summary>
    const int MaxMarkdownLength = 2_000_000;

    /// <summary>저장하지 않고 만들 결과를 돌려준다.</summary>
    Task<SeasonImportPreviewDto> PreviewAsync(Guid userId, SeasonImportRequest request, CancellationToken cancellationToken = default);

    /// <summary>시즌을 만들고 연결할 기록 세션을 옮긴다(한 트랜잭션).</summary>
    Task<SeasonImportResultDto> ImportAsync(Guid userId, SeasonImportRequest request, CancellationToken cancellationToken = default);
}
