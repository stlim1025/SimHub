using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Api.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Rankings;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Api.Controllers;

/// <summary>
/// 내 세션 조회 엔드포인트(12 §7.1). 기본 경로 /api/v1/me/sessions.
/// 남의 세션·없는 세션은 같은 404다(D-34). Id가 GUID가 아니면 라우트가 맞지 않아 404다.
/// </summary>
[ApiController]
[Route("api/v1/me/sessions")]
[Authorize]
public sealed class MySessionsController(ISessionQueryService sessionService) : ControllerBase
{
    private const string SessionTypeField = "sessionType";
    private const string SessionTypeError = "sessionType는 Practice/Qualifying/Race 중 하나여야 합니다.";

    /// <summary>
    /// 내 세션 목록(분류 시각 내림차순). sessionType = Practice|Qualifying|Race(대소문자 무시, 생략하면 전체).
    /// pageSize 기본 20, 최대 100.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<SessionSummaryDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedResult<SessionSummaryDto>>> GetMySessions(
        [FromQuery] string? sessionType,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = ISessionQueryService.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var parsedSessionType = ParseSessionType(sessionType);

        var result = await sessionService.GetMySessionsAsync(
            User.GetRequiredUserId(), parsedSessionType, page, pageSize, cancellationToken);
        return Ok(result);
    }

    /// <summary>내 세션 상세(헤더 + 결과). 남의 세션이거나 없으면 404.</summary>
    [HttpGet("{sessionId:guid}")]
    [ProducesResponseType(typeof(SessionDetailDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<SessionDetailDto>> GetMySession(Guid sessionId, CancellationToken cancellationToken)
    {
        var result = await sessionService.GetMySessionAsync(User.GetRequiredUserId(), sessionId, cancellationToken);
        return Ok(result);
    }

    /// <summary>
    /// 명시적 이름 목록(Practice·Qualifying·Race, 대소문자 무시)만 받는다. 비어 있으면 필터 없음.
    /// <c>Enum.TryParse</c>는 숫자 문자열("4")과 TimeTrial까지 받아들이므로 쓰지 않는다.
    /// </summary>
    private static SessionType? ParseSessionType(string? sessionType)
    {
        if (string.IsNullOrWhiteSpace(sessionType))
        {
            return null;
        }

        var name = sessionType.Trim();

        if (name.Equals(nameof(SessionType.Practice), StringComparison.OrdinalIgnoreCase))
        {
            return SessionType.Practice;
        }

        if (name.Equals(nameof(SessionType.Qualifying), StringComparison.OrdinalIgnoreCase))
        {
            return SessionType.Qualifying;
        }

        if (name.Equals(nameof(SessionType.Race), StringComparison.OrdinalIgnoreCase))
        {
            return SessionType.Race;
        }

        throw new ValidationException(SessionTypeField, SessionTypeError);
    }
}
