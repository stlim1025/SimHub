using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Setups;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.Controllers;

/// <summary>커뮤니티 셋업(F1Laps 공개 셋업 상위 10) 조회. 기본 경로 /api/v1/setups.</summary>
[ApiController]
[Route("api/v1/setups")]
[Authorize]
public sealed class SetupsController(ICommunitySetupService setupService) : ControllerBase
{
    private const string ConditionField = "condition";

    /// <summary>게임의 트랙(캘린더 순, 리버스 포함)과 조건별 셋업 수. gameCode 생략 시 F1_25.</summary>
    [HttpGet("tracks")]
    [ProducesResponseType(typeof(IReadOnlyList<SetupTrackDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<SetupTrackDto>>> GetTracks(
        [FromQuery] string? gameCode, CancellationToken cancellationToken)
        => Ok(await setupService.GetTracksAsync(GameCodeQuery.ParseOptional(gameCode) ?? GameCodes.F1_25, cancellationToken));

    /// <summary>트랙·조건(Dry|Wet, 생략 시 Dry)의 셋업 목록(순위 순). 트랙이 없으면 404.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(SetupListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SetupListResponse>> GetSetups(
        [FromQuery] Guid trackId, [FromQuery] string? condition, CancellationToken cancellationToken)
    {
        if (trackId == Guid.Empty)
        {
            throw new ValidationException("trackId", "trackId는 필수입니다.");
        }

        return Ok(await setupService.GetListAsync(trackId, ParseCondition(condition), cancellationToken));
    }

    /// <summary>셋업 상세(값 묶음 포함). 없으면 404.</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(SetupDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SetupDetailDto>> GetSetup(Guid id, CancellationToken cancellationToken)
        => Ok(await setupService.GetDetailAsync(id, cancellationToken));

    private static string ParseCondition(string? condition)
    {
        if (string.IsNullOrWhiteSpace(condition))
        {
            return SetupConditions.Dry;
        }

        return SetupConditions.Normalize(condition)
            ?? throw new ValidationException(ConditionField, $"condition은 {string.Join('/', SetupConditions.All)} 중 하나여야 합니다.");
    }
}
