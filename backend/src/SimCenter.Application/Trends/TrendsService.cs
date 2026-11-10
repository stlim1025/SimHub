using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.Trends;

/// <summary>내 성과 추세(Trends 화면).</summary>
public interface ITrendsService
{
    /// <summary><paramref name="gameCode"/>가 있으면 그 게임의 세션·랩만.</summary>
    Task<TrendsDto> GetAsync(Guid userId, string? gameCode, CancellationToken cancellationToken = default);
}

/// <summary>내 예선·레이스 결과, 내 랩, 트랙 이름을 읽어 <see cref="TrendsCalculator"/>로 계산한다(쿼리 3회).</summary>
public sealed class TrendsService : ITrendsService
{
    private readonly ITrendsQueryRepository _queries;
    private readonly ITrackRepository _tracks;

    public TrendsService(ITrendsQueryRepository queries, ITrackRepository tracks)
    {
        _queries = queries;
        _tracks = tracks;
    }

    public async Task<TrendsDto> GetAsync(Guid userId, string? gameCode, CancellationToken cancellationToken = default)
    {
        var rows = await _queries.GetMyResultRowsAsync(userId, gameCode, cancellationToken);
        var laps = await _queries.GetMyLapsAsync(userId, gameCode, cancellationToken);
        var tracks = (await _tracks.GetAllAsync(cancellationToken))
            .ToDictionary(t => t.Id, t => new TrendTrackLabel(t.Name, t.CountryCode));

        return TrendsCalculator.Calculate(rows, laps, tracks);
    }
}
