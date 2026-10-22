using SimCenter.Application.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Rankings;

namespace SimCenter.Application.TrackOverviews;

/// <summary>트랙 개요(트랙 정보·내 통계·Time Trial 상위·내 최고 랩·지도용 랩) 조회.</summary>
public interface ITrackOverviewService
{
    /// <summary>트랙이 없으면 <see cref="NotFoundException"/>.</summary>
    Task<TrackOverviewResponse> GetAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default);
}

/// <summary><see cref="ITrackOverviewService"/> 구현.</summary>
public sealed class TrackOverviewService : ITrackOverviewService
{
    private const int TopTimeTrialCount = 3;
    private const int MyBestLapCount = 10;

    /// <summary>지도 채널을 찾으려고 풀어 보는 트레이스 수 한도(빠른 랩부터).</summary>
    private const int MapCandidateCount = 10;

    /// <summary>트랙 지도에 쓰는 월드 위치 추가 채널(<c>shared/telemetry/f1_25_udp_spec.md</c>).</summary>
    private const string WorldPosXChannel = "worldPosX";
    private const string WorldPosZChannel = "worldPosZ";

    private readonly ITrackRepository _tracks;
    private readonly ITrackOverviewQueryRepository _queries;

    public TrackOverviewService(ITrackRepository tracks, ITrackOverviewQueryRepository queries)
    {
        _tracks = tracks;
        _queries = queries;
    }

    public async Task<TrackOverviewResponse> GetAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default)
    {
        var track = await _tracks.GetByIdAsync(trackId, cancellationToken)
            ?? throw new NotFoundException("트랙을 찾을 수 없습니다.");
        var facts = TrackCatalog.Find(track.GameCode, track.GameTrackId);

        var stats = await _queries.GetMyStatsAsync(userId, trackId, cancellationToken);
        var top = await _queries.GetTopTimeTrialAsync(trackId, track.GameCode, TopTimeTrialCount, cancellationToken);
        var myBest = await _queries.GetMyBestLapsAsync(userId, trackId, MyBestLapCount, cancellationToken);
        var traced = await _queries.GetMyTracedLapsAsync(userId, trackId, MapCandidateCount, cancellationToken);

        return new TrackOverviewResponse(
            new TrackOverviewTrackDto(
                track.Id, track.Name, track.CountryCode, track.GameCode,
                facts?.CircuitName, facts?.GrandPrixName, facts?.LengthKm, facts?.F1LapRecord),
            new TrackMyStatsDto(
                stats.LapCount,
                stats.SessionCount,
                stats.BestLapMs,
                stats.BestTimeTrialLapMs,
                stats.AverageLapMs is { } average ? (int)Math.Round(average, MidpointRounding.AwayFromZero) : null,
                stats.AverageAiDifficulty is { } ai ? Math.Round(ai, 1, MidpointRounding.AwayFromZero) : null),
            top.Select((row, index) => new TrackTopLapDto(
                    index + 1,
                    RankingPrivacy.DisplayNameFor(new RankingLapRow(row.UserId, row.DisplayName, row.LapTimeMs, default, row.ShowOnLeaderboard)),
                    TeamName(track.GameCode, row.TeamId),
                    row.LapTimeMs,
                    row.LapId))
                .ToList(),
            myBest.Select(row => new TrackMyLapDto(
                    row.LapId, row.LapTimeMs, row.SessionType.ToString(), TeamName(track.GameCode, row.TeamId), row.IsValid, row.SetAt))
                .ToList(),
            traced.FirstOrDefault(HasWorldPositions)?.LapId);
    }

    private static string? TeamName(string gameCode, int? teamId)
        => teamId is null ? null : TeamCatalog.Resolve(gameCode, teamId).Name;

    /// <summary>트레이스에 월드 위치(X·Z) 채널이 비어 있지 않게 있는가. 깨진 blob은 없는 것으로 본다.</summary>
    private static bool HasWorldPositions(TrackTracedLapRow row)
    {
        try
        {
            var extra = LapTraceCodec.Decode(row.Payload).Extra;
            return extra is not null
                && extra.TryGetValue(WorldPosXChannel, out var x) && x is { Length: > 0 }
                && extra.TryGetValue(WorldPosZChannel, out var z) && z is { Length: > 0 };
        }
        catch (InvalidDataException)
        {
            return false;
        }
    }
}
