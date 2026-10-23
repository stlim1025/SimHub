using System.Text.Json;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// <c>TrackSamplesChunk</c> 처리기: 파싱 → 검증 → 트랙 매핑 → 이미 받은 조각인지 → 조각 행 추적.
/// 표본은 받은 그대로(gzip) 보관하고 여기서 풀지 않는다 — 트랙 형상 계산은 따로 한다.
/// </summary>
public sealed class TrackSamplesIngestor : ITrackSamplesIngestor
{
    private const string ParseFailedReason = "TrackSamplesChunk payload 파싱 실패";
    private const string EmptyPayloadReason = "TrackSamplesChunk payload가 비어 있습니다.";
    private const string ValidationFailedPrefix = "TrackSamplesChunk 검증 실패: ";

    private static readonly JsonSerializerOptions PayloadOptions = new(JsonSerializerDefaults.Web);

    private readonly ITrackRepository _tracks;
    private readonly ITrackSampleChunkRepository _chunks;
    private readonly IIdGenerator _idGenerator;
    private readonly ILogger<TrackSamplesIngestor> _logger;

    public TrackSamplesIngestor(
        ITrackRepository tracks,
        ITrackSampleChunkRepository chunks,
        IIdGenerator idGenerator,
        ILogger<TrackSamplesIngestor> logger)
    {
        _tracks = tracks;
        _chunks = chunks;
        _idGenerator = idGenerator;
        _logger = logger;
    }

    public async Task<string?> ApplyAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken cancellationToken = default)
    {
        TrackSamplesChunkPayloadDto? payload;
        try
        {
            payload = envelope.Payload.Deserialize<TrackSamplesChunkPayloadDto>(PayloadOptions);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "TrackSamplesChunk payload 파싱 실패 eventId={EventId}", envelope.EventId);
            return ParseFailedReason;
        }

        if (payload is null)
        {
            return EmptyPayloadReason;
        }

        var error = TrackSamplesChunkValidator.Validate(payload, out var sessionType, out var gzip);
        if (error is not null)
        {
            _logger.LogWarning("TrackSamplesChunk 검증 실패 {Error} eventId={EventId}", error, envelope.EventId);
            return ValidationFailedPrefix + error;
        }

        var track = await _tracks.GetByGameTrackIdAsync(envelope.GameCode, payload.TrackId, cancellationToken);
        if (track is null)
        {
            _logger.LogWarning("TrackSamplesChunk 트랙 매핑 없음 gameCode={GameCode} trackId={TrackId} eventId={EventId}",
                envelope.GameCode, payload.TrackId, envelope.EventId);
            return $"트랙 매핑 없음(gameCode={envelope.GameCode}, trackId={payload.TrackId})";
        }

        // 같은 조각이 다른 eventId로 다시 와도(재설치한 Agent의 재전송 등) 한 번만 저장한다.
        if (await _chunks.ExistsAsync(device.Id, payload.SessionRef, payload.ChunkIndex, cancellationToken))
        {
            return null;
        }

        await _chunks.AddAsync(new TrackSampleChunk
        {
            Id = _idGenerator.NewId(),
            AgentDeviceId = device.Id,
            UserId = device.UserId,
            TrackId = track.Id,
            GameCode = envelope.GameCode,
            SessionRef = payload.SessionRef,
            SessionType = sessionType,
            ChunkIndex = payload.ChunkIndex,
            IsLast = payload.IsLast,
            Format = payload.Format,
            SampleRateHz = payload.SampleRateHz,
            FrameCount = payload.FrameCount,
            SampleCount = payload.SampleCount,
            TrackLengthM = payload.TrackLengthM,
            Payload = gzip,
            CreatedAt = now,
        }, cancellationToken);

        _logger.LogInformation(
            "트랙 표본 조각 device={Device} track={Track} session={Session} chunk={Chunk} last={IsLast} samples={Samples} bytes={Bytes}",
            device.Id, track.Name, payload.SessionRef, payload.ChunkIndex, payload.IsLast, payload.SampleCount, gzip.Length);
        return null;
    }
}
