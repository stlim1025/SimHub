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
    private const string SessionField = "session";

    /// <summary>게임의 트랙(캘린더 순, 리버스 포함)과 조건별 셋업 수. gameCode 생략 시 F1_25.</summary>
    [HttpGet("tracks")]
    [ProducesResponseType(typeof(IReadOnlyList<SetupTrackDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<IReadOnlyList<SetupTrackDto>>> GetTracks(
        [FromQuery] string? gameCode, CancellationToken cancellationToken)
        => Ok(await setupService.GetTracksAsync(GameCodeQuery.ParseOptional(gameCode) ?? GameCodes.F1_25, cancellationToken));

    /// <summary>
    /// 트랙·조건(Dry|Wet, 생략 시 Dry)·세션 종류(TimeTrial|Race|Qualifying, 생략 시 Dry는 TimeTrial·Wet은 Race)의 셋업 목록(순위 순).
    /// 트랙이 없으면 404. 젖은 노면에는 타임 트라이얼이 없다(400).
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(SetupListResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SetupListResponse>> GetSetups(
        [FromQuery] Guid trackId, [FromQuery] string? condition, [FromQuery] string? session, CancellationToken cancellationToken)
    {
        if (trackId == Guid.Empty)
        {
            throw new ValidationException("trackId", "trackId는 필수입니다.");
        }

        var parsedCondition = ParseCondition(condition);
        return Ok(await setupService.GetListAsync(trackId, parsedCondition, ParseSession(session, parsedCondition), cancellationToken));
    }

    /// <summary>셋업 상세(값 묶음 포함). 없으면 404.</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(SetupDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SetupDetailDto>> GetSetup(Guid id, CancellationToken cancellationToken)
        => Ok(await setupService.GetDetailAsync(id, cancellationToken));

    private static string ParseSession(string? session, string condition)
    {
        if (string.IsNullOrWhiteSpace(session))
        {
            return SetupSessions.DefaultFor(condition);
        }

        var parsed = SetupSessions.Normalize(session);
        return parsed is not null && SetupSessions.For(condition).Contains(parsed)
            ? parsed
            : throw new ValidationException(SessionField,
                $"session은 {string.Join('/', SetupSessions.For(condition).Select(s => s.Replace(" ", string.Empty, StringComparison.Ordinal)))} 중 하나여야 합니다.");
    }

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
