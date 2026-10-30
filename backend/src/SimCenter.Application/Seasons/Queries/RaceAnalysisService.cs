using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Application.Seasons.Queries.Detail;
using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>내 레이스의 심층 분석(구간별 타이어 부담·입력·배터리, 타이어로 본 전략, 페이스 기준들).</summary>
public interface IRaceAnalysisService
{
    /// <summary>남의 세션·없는 세션·레이스가 아닌 세션·내 차 기록 없음은 모두 <see cref="NotFoundException"/>.</summary>
    Task<RaceAnalysisDto> GetMyRaceAnalysisAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default);
}

/// <summary>
/// <see cref="IRaceAnalysisService"/> 구현. 세션 상세와 같은 내 랩(랩 번호마다 마지막 저장)의 트레이스와 세션의 모든 차 표본을 읽어
/// <see cref="RaceAnalysisBuilder"/>에 넘긴다. 풀 수 없는 트레이스·표본 조각은 경고만 남기고 건너뛴다.
/// </summary>
public sealed class RaceAnalysisService : IRaceAnalysisService
{
    private const string NotFoundMessage = "이 세션은 분석할 레이스 기록이 없습니다.";

    private readonly IGameSessionQueryRepository _sessions;
    private readonly ISessionDetailQueryRepository _details;
    private readonly ITrackSampleChunkRepository _chunks;
    private readonly ILogger<RaceAnalysisService> _logger;

    public RaceAnalysisService(
        IGameSessionQueryRepository sessions,
        ISessionDetailQueryRepository details,
        ITrackSampleChunkRepository chunks,
        ILogger<RaceAnalysisService> logger)
    {
        _sessions = sessions;
        _details = details;
        _chunks = chunks;
        _logger = logger;
    }

    public async Task<RaceAnalysisDto> GetMyRaceAnalysisAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetMineDetailAsync(userId, sessionId, cancellationToken)
            ?? throw new NotFoundException("세션을 찾을 수 없습니다.");
        if (session.SessionType != SessionType.Race)
        {
            throw new NotFoundException(NotFoundMessage);
        }

        var results = session.Results
            .Where(r => !r.IsDeleted)
            .OrderBy(r => r.Position > 0 ? r.Position : int.MaxValue)
            .ThenBy(r => r.CarIndex)
            .ToList();
        var lapRows = await _details.GetMySessionLapsAsync(userId, session.GameCode, session.TrackId, session.SessionKey, cancellationToken);
        var myLaps = lapRows.Select(MySessionLap.From).ToList();
        var playerCarIndex = results.Where(r => r.IsPlayer).OrderBy(r => r.CarIndex).FirstOrDefault()?.CarIndex
            ?? myLaps.Select(l => l.PlayerCarIndex).FirstOrDefault(c => c.HasValue);

        var latest = SessionLapsBuilder.LatestByLapNumber(myLaps);
        var lapNumbers = latest.Values.ToDictionary(l => l.Row.LapId, l => l.LapNumber);
        var traceRows = await _details.GetMyLapTracesAsync(userId, lapNumbers.Keys.ToList(), cancellationToken);
        var traces = new List<RaceTraceLap>();
        foreach (var row in traceRows)
        {
            try
            {
                traces.Add(new RaceTraceLap(lapNumbers[row.LapId], row.ResolutionM, LapTraceCodec.Decode(row.Payload)));
            }
            catch (InvalidDataException ex)
            {
                _logger.LogWarning(ex, "Skipping undecodable lap trace {LapId}", row.LapId);
            }
        }

        var stored = await _chunks.ListForSessionAsync(userId, session.SessionRef, cancellationToken);
        var chunks = new List<DecodedTrackSamples>();
        foreach (var chunk in stored)
        {
            try
            {
                chunks.Add(TrackSampleDecoder.Decode(chunk.Payload, chunk.Format));
            }
            catch (FormatException ex)
            {
                _logger.LogWarning(ex, "Skipping undecodable track sample chunk {SessionRef}#{ChunkIndex}", chunk.SessionRef, chunk.ChunkIndex);
            }
        }

        var trackLength = stored.Count > 0 && stored.Max(c => c.TrackLengthM) is > 0 and var length ? (double?)length : null;
        return RaceAnalysisBuilder.Build(
                session, results, SessionHistory.Parse(session.Details), playerCarIndex, myLaps, traces, chunks, trackLength)
            ?? throw new NotFoundException(NotFoundMessage);
    }
}
