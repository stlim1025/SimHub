using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Constants;

namespace SimCenter.Api.Controllers;

/// <summary>랭킹 조회 엔드포인트(04-api-design §3.7). 기본 경로 /api/v1/rankings.</summary>
[ApiController]
[Route("api/v1/rankings")]
[Authorize]
public sealed class RankingsController(IRankingService rankingService) : ControllerBase
{
    /// <summary>트랙·기간별 TOP10(Time Trial·랭킹적격만). period 미지정 시 monthly(D-8a).</summary>
    [HttpGet]
    [ProducesResponseType(typeof(RankingSnapshotDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<RankingSnapshotDto>> GetRankings(
        [FromQuery] Guid trackId,
        [FromQuery] string? period,
        [FromQuery] string? gameCode,
        [FromQuery] DateOnly? date,
        CancellationToken cancellationToken)
    {
        if (trackId == Guid.Empty)
        {
            throw new ValidationException("trackId", "trackId는 필수입니다.");
        }

        var parsedPeriod = ParsePeriod(period);
        var game = string.IsNullOrWhiteSpace(gameCode) ? GameCodes.F1_25 : gameCode.Trim();

        var result = await rankingService.GetRankingAsync(trackId, game, parsedPeriod, date, cancellationToken);
        return Ok(result);
    }

    private static RankingPeriod ParsePeriod(string? period)
    {
        if (string.IsNullOrWhiteSpace(period))
        {
            return RankingPeriod.Monthly; // D-8a 기본값.
        }

        if (!Enum.TryParse<RankingPeriod>(period.Trim(), ignoreCase: true, out var parsed))
        {
            throw new ValidationException("period", "period는 daily/monthly/yearly 중 하나여야 합니다.");
        }

        return parsed;
    }
}
