using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Queries;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.TrackSamples;

/// <summary>내 레이스 세션의 하이라이트(모든 차 표본에서 고른 주요 장면).</summary>
public interface IHighlightsService
{
    /// <summary>
    /// 내 하이라이트·레이스 하이라이트 두 묶음. 남의 세션·없는 세션·레이스가 아닌 세션·표본 없음은 모두 <see cref="NotFoundException"/>.
    /// </summary>
    Task<HighlightsResponse> GetHighlightsAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default);
}

/// <summary>
/// <see cref="IHighlightsService"/> 구현. 레이스 도중 저장했다가 이어 달리면 게임 세션 UID가 바뀌어 표본이 두 세션으로 나뉜다 —
/// 순위표 없는 같은 트랙·게임 레이스 표본 세션 중 시간이 이어지는 것(앞 조각 끝 + 여유 ≥ 이번 조각 시작 &gt; 앞 조각 시작)을 앞에 붙인다.
/// 풀 수 없는 조각은 경고만 남기고 건너뛴다.
/// </summary>
public sealed class HighlightsService : IHighlightsService
{
    private const string NotFoundMessage = "이 세션의 하이라이트를 만들 표본이 없습니다.";

    /// <summary>이어 달린 조각으로 볼 시간 여유(ms)·이어 달린 조각이 시작할 수 있는 가장 이른 세션 시간(ms).</summary>
    private const int ResumeGapToleranceMs = 5_000;
    private const int MinResumeStartMs = 60_000;

    /// <summary>앞 조각 후보 수 한도·찾을 기간(이어 달리기는 보통 며칠 안).</summary>
    private const int MaxResumeCandidates = 10;
    private static readonly TimeSpan ResumeLookback = TimeSpan.FromDays(14);

    /// <summary>표본이 결승보다 이만큼(ms) 일찍 끊긴 리타이어 차는 거기서 멈춘 것으로 본다.</summary>
    private const int EarlyEndMs = 30_000;

    private readonly IGameSessionQueryRepository _sessions;
    private readonly ISessionQueryService _sessionQuery;
    private readonly ISessionDetailQueryRepository _sessionDetail;
    private readonly ITrackSampleChunkRepository _chunks;
    private readonly ILogger<HighlightsService> _logger;

    public HighlightsService(
        IGameSessionQueryRepository sessions,
        ISessionQueryService sessionQuery,
        ISessionDetailQueryRepository sessionDetail,
        ITrackSampleChunkRepository chunks,
        ILogger<HighlightsService> logger)
    {
        _sessions = sessions;
        _sessionQuery = sessionQuery;
        _sessionDetail = sessionDetail;
        _chunks = chunks;
        _logger = logger;
    }

    public async Task<HighlightsResponse> GetHighlightsAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessions.GetMineDetailAsync(userId, sessionId, cancellationToken)
            ?? throw new NotFoundException("세션을 찾을 수 없습니다.");
        if (session.SessionType != SessionType.Race)
        {
            throw new NotFoundException(NotFoundMessage);
        }

        var stored = await _chunks.ListForSessionAsync(userId, session.SessionRef, cancellationToken);
        var current = Decode(stored);
        if (current.Count == 0)
        {
            throw new NotFoundException(NotFoundMessage);
        }

        var parts = new List<List<DecodedTrackSamples>> { current };
        await PrependResumedPartsAsync(userId, session.SessionRef, session.TrackId, session.GameCode, parts, cancellationToken);

        var timeline = RaceTimeline.Build(parts.SelectMany(p => p).ToList());
        if (timeline.Cars.Count == 0)
        {
            throw new NotFoundException(NotFoundMessage);
        }

        double length = stored.Max(c => c.TrackLengthM) is > 0 and var known
            ? known
            : timeline.Cars.Values.SelectMany(s => s).Max(s => s.LapDistanceM);

        var detail = await _sessionQuery.GetMySessionAsync(userId, sessionId, cancellationToken);
        var cars = detail.Results
            .Select(r => new HighlightCarDto(r.CarIndex, r.Name, r.TeamColor, r.IsPlayer, r.Position))
            .ToList();
        var player = cars.FirstOrDefault(c => c.IsPlayer)?.CarIndex;

        var laps = await _sessionDetail.GetMySessionLapsAsync(userId, session.GameCode, session.TrackId, session.SessionKey, cancellationToken);
        var (flags, retirements) = RaceControlEvents.Build(
            laps.Select(l => new PlayerLapEvents(l.LapNumber, l.LapTimeMs, l.SnapshotDetails)).ToList(),
            player is { } me ? timeline.CrossingsOf(me, length) : [],
            timeline.EndMs);

        // 리타이어 이벤트를 못 받은 리타이어 차는 표본이 끊긴 곳에서 멈춘 것으로.
        var allRetirements = retirements.ToList();
        foreach (var result in detail.Results.Where(r => r.ResultStatus is nameof(ResultStatus.Retired) or nameof(ResultStatus.DidNotFinish)))
        {
            if (allRetirements.Any(r => r.CarIndex == result.CarIndex)
                || !timeline.Cars.TryGetValue(result.CarIndex, out var samples) || samples.Count == 0)
            {
                continue;
            }

            var lastMs = samples[^1].TimeMs;
            if (lastMs < timeline.EndMs - EarlyEndMs)
            {
                allRetirements.Add(new RaceRetirement(result.CarIndex, lastMs));
            }
        }

        return HighlightsBuilder.Build(session.Id, session.TotalLaps, timeline, length, cars, flags, allRetirements);
    }

    /// <summary>순위표 없는 앞 조각 중 시간이 이어지는 것을 차례로 [parts] 앞에 붙인다.</summary>
    private async Task PrependResumedPartsAsync(
        Guid userId, string sessionRef, Guid trackId, string gameCode, List<List<DecodedTrackSamples>> parts,
        CancellationToken cancellationToken)
    {
        if (await _chunks.FirstReceivedAtAsync(userId, sessionRef, cancellationToken) is not { } received)
        {
            return;
        }

        var candidates = await _chunks.ListUnclassifiedSessionsAsync(
            userId, trackId, gameCode, SessionType.Race, received, cancellationToken);
        var earliest = parts[0].Min(MinTime);
        foreach (var candidate in candidates.Where(c => c.FirstReceivedAt > received - ResumeLookback).Take(MaxResumeCandidates))
        {
            if (earliest < MinResumeStartMs)
            {
                return;
            }

            var decoded = Decode(await _chunks.ListForSessionAsync(userId, candidate.SessionRef, cancellationToken));
            if (decoded.Count == 0)
            {
                continue;
            }

            var from = decoded.Min(MinTime);
            var to = decoded.Max(MaxTime);
            if (from < earliest && earliest <= to + ResumeGapToleranceMs)
            {
                parts.Insert(0, decoded);
                earliest = from;
            }
        }
    }

    private static int MinTime(DecodedTrackSamples chunk) => chunk.TimeMs.Min();

    private static int MaxTime(DecodedTrackSamples chunk) => chunk.TimeMs.Max();

    /// <summary>표본이 있는 조각만 푼다(빈 조각은 뺀다).</summary>
    private List<DecodedTrackSamples> Decode(IReadOnlyList<StoredTrackSampleChunk> stored)
    {
        var decoded = new List<DecodedTrackSamples>();
        foreach (var chunk in stored)
        {
            try
            {
                var samples = TrackSampleDecoder.Decode(chunk.Payload, chunk.Format);
                if (samples.Count > 0)
                {
                    decoded.Add(samples);
                }
            }
            catch (FormatException ex)
            {
                _logger.LogWarning(ex, "Skipping undecodable track sample chunk {SessionRef}#{ChunkIndex}", chunk.SessionRef, chunk.ChunkIndex);
            }
        }

        return decoded;
    }
}
