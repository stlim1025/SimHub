using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Commands;
using SimCenter.Application.Seasons.Queries;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 내 시즌 조회·관리 엔드포인트(12 §7.1). 기본 경로 /api/v1/me/seasons.
/// 남의 시즌·없는 시즌·지운 시즌은 같은 404다(D-34). Id가 GUID가 아니면 라우트가 맞지 않아 404다.
/// 오류는 ExceptionHandlingMiddleware가 RFC 7807로 바꾼다(검증 400 · 없음 404).
/// </summary>
[ApiController]
[Route("api/v1/me/seasons")]
[Authorize]
public sealed class MySeasonsController(ISeasonQueryService seasonService, ISeasonCommandService seasonCommands) : ControllerBase
{
    /// <summary>내 시즌 목록(마지막 세션 시각 내림차순). pageSize 기본 20, 최대 20. gameCode(선택)가 있으면 그 게임의 시즌만.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<SeasonSummaryDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedResult<SeasonSummaryDto>>> GetMySeasons(
        [FromQuery] string? gameCode,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = ISeasonQueryService.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var result = await seasonService.GetMySeasonsAsync(
            User.GetRequiredUserId(), page, pageSize, GameCodeQuery.ParseOptional(gameCode), cancellationToken);
        return Ok(result);
    }

    /// <summary>내 시즌 상세(헤더 + 라운드 + Standings). 남의 시즌이거나 없으면 404.</summary>
    [HttpGet("{seasonId:guid}")]
    [ProducesResponseType(typeof(SeasonDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SeasonDetailDto>> GetMySeason(Guid seasonId, CancellationToken cancellationToken)
    {
        var result = await seasonService.GetMySeasonAsync(User.GetRequiredUserId(), seasonId, cancellationToken);
        return Ok(result);
    }

    /// <summary>시즌 이름을 바꾼다. 빈 값·null이면 기본 이름으로 되돌린다. 60자 초과는 400.</summary>
    [HttpPut("{seasonId:guid}/name")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RenameMySeason(Guid seasonId, RenameSeasonRequest request, CancellationToken cancellationToken)
    {
        await seasonCommands.RenameAsync(User.GetRequiredUserId(), seasonId, request, cancellationToken);
        return NoContent();
    }

    /// <summary>시즌 완료 표시를 켜거나 끈다(<c>completed</c>). 이미 완료면 처음 완료 시각을 유지한다.</summary>
    [HttpPut("{seasonId:guid}/completion")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SetMySeasonCompletion(
        Guid seasonId, SetSeasonCompletionRequest request, CancellationToken cancellationToken)
    {
        await seasonCommands.SetCompletedAsync(User.GetRequiredUserId(), seasonId, request, cancellationToken);
        return NoContent();
    }

    /// <summary>시즌을 지운다(soft delete). 세션은 남고, 이후 목록·상세에서 빠진다.</summary>
    [HttpDelete("{seasonId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DeleteMySeason(Guid seasonId, CancellationToken cancellationToken)
    {
        await seasonCommands.DeleteAsync(User.GetRequiredUserId(), seasonId, cancellationToken);
        return NoContent();
    }
}
