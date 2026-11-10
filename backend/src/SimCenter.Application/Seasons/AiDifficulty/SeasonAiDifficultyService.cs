using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;

namespace SimCenter.Application.Seasons.AiDifficulty;

/// <summary>내 시즌의 AI 난이도 가이드(시즌 상세 AI 탭). 남의 시즌·없는 시즌은 404.</summary>
public interface ISeasonAiDifficultyService
{
    Task<SeasonAiDifficultyDto> GetAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default);
}

/// <summary>
/// 시즌 주말·예선/레이스 결과·내 랩 날씨·내 타임트라이얼 랩을 읽어 <see cref="AiDifficultyCalculator"/>로 계산한다.
/// 쿼리는 시즌·주말·결과·날씨·TT 각 1회다(세션마다 따로 읽지 않는다).
/// </summary>
public sealed class SeasonAiDifficultyService : ISeasonAiDifficultyService
{
    private readonly ISeasonQueryRepository _seasons;
    private readonly IAiDifficultyQueryRepository _queries;

    public SeasonAiDifficultyService(ISeasonQueryRepository seasons, IAiDifficultyQueryRepository queries)
    {
        _seasons = seasons;
        _queries = queries;
    }

    public async Task<SeasonAiDifficultyDto> GetAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
    {
        var season = await _seasons.GetMineAsync(userId, seasonId, cancellationToken)
            ?? throw new NotFoundException("시즌을 찾을 수 없습니다.");

        var weekends = await _seasons.GetWeekendRowsAsync([season.Id], cancellationToken);
        var rows = await _queries.GetPaceRowsAsync(season.Id, cancellationToken);
        var sessionKeys = rows.Select(r => r.SessionKey).Distinct().ToList();
        var weather = await _queries.GetMyLapWeatherAsync(userId, sessionKeys, cancellationToken);
        var trackIds = weekends.Select(w => w.TrackId).Distinct().ToList();
        var timeTrial = await _queries.GetMyTimeTrialLapsAsync(userId, season.GameCode, trackIds, cancellationToken);

        return AiDifficultyCalculator.Calculate(
            season.GameCode, weekends, RoundNumbering.Assign(weekends), rows, weather, timeTrial);
    }
}
