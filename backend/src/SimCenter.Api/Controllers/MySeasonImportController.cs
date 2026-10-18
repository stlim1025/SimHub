using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Seasons.Import;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 시즌 가져오기 엔드포인트(docs/15 §12, D-55). 기본 경로 /api/v1/me/seasons/import. 사용자 JWT로만 — 자기 계정에 넣는다.
/// 형식 오류는 400(줄 번호), 이미 가져온 시즌은 409.
/// </summary>
[ApiController]
[Route("api/v1/me/seasons/import")]
[Authorize]
[RequestSizeLimit(MaxRequestBytes)]
public sealed class MySeasonImportController(ISeasonImportService importService) : ControllerBase
{
    /// <summary>본문 상한(바이트): 마크다운 최대 길이 × UTF-8 3바이트 + JSON 여유. 서비스의 길이 검사보다 먼저 거른다.</summary>
    private const long MaxRequestBytes = (ISeasonImportService.MaxMarkdownLength * 3L) + 64 * 1024;

    /// <summary>붙여넣은 마크다운을 해석해 만들 결과를 돌려준다(저장하지 않음).</summary>
    [HttpPost("preview")]
    [ProducesResponseType(typeof(SeasonImportPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<SeasonImportPreviewDto>> Preview(
        [FromBody] SeasonImportRequest request, CancellationToken cancellationToken)
    {
        var result = await importService.PreviewAsync(User.GetRequiredUserId(), request, cancellationToken);
        return Ok(result);
    }

    /// <summary>시즌을 만들고 연결할 기록 세션을 옮긴다. 만든 시즌 Id를 돌려준다.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(SeasonImportResultDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<SeasonImportResultDto>> Import(
        [FromBody] SeasonImportRequest request, CancellationToken cancellationToken)
    {
        var result = await importService.ImportAsync(User.GetRequiredUserId(), request, cancellationToken);
        return Created($"/api/v1/me/seasons/{result.SeasonId}", result);
    }
}
