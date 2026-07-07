using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Telemetry;

/// <summary>
/// 텔레메트리 인입 유스케이스. MVP는 <c>LapFinished</c>만 영속화하고 나머지 이벤트는 Ack만 한다(YAGNI).
/// 처리 순서: 멱등체크 → (LapFinished면) payload 파싱 → 세션매칭 → Track매핑 → 랭킹적격 판정 → Lap 저장.
/// 활성 세션이 없으면 드롭+Ack(D-22), 영구 무효(파싱/트랙 실패)는 Reject.
/// </summary>
public sealed class TelemetryIngestService : ITelemetryIngestService
{
    private const string LapFinishedType = "LapFinished";

    private static readonly JsonSerializerOptions PayloadOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly IProcessedEventRepository _processed;
    private readonly ISimRigRepository _rigs;
    private readonly IDrivingSessionRepository _sessions;
    private readonly ITrackRepository _tracks;
    private readonly ILapRepository _laps;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;
    private readonly ILogger<TelemetryIngestService> _logger;

    public TelemetryIngestService(
        IProcessedEventRepository processed,
        ISimRigRepository rigs,
        IDrivingSessionRepository sessions,
        ITrackRepository tracks,
        ILapRepository laps,
        IUnitOfWork unitOfWork,
        IIdGenerator idGenerator,
        IClock clock,
        ILogger<TelemetryIngestService> logger)
    {
        _processed = processed;
        _rigs = rigs;
        _sessions = sessions;
        _tracks = tracks;
        _laps = laps;
        _unitOfWork = unitOfWork;
        _idGenerator = idGenerator;
        _clock = clock;
        _logger = logger;
    }

    public async Task<IngestResult> IngestAsync(TelemetryEnvelopeDto envelope, string authenticatedRigCode, CancellationToken cancellationToken = default)
    {
        // 1. 멱등: 이미 처리한 eventId면 즉시 Ack(effectively-once).
        if (await _processed.ExistsAsync(envelope.EventId, cancellationToken))
        {
            return IngestResult.Ack();
        }

        // 2. MVP는 LapFinished만 저장. 그 외 유효 이벤트는 무시하되 Ack.
        if (!string.Equals(envelope.Type, LapFinishedType, StringComparison.Ordinal))
        {
            _logger.LogDebug("비저장 이벤트 {Type} rig={Rig} eventId={EventId}", envelope.Type, authenticatedRigCode, envelope.EventId);
            return IngestResult.Ack();
        }

        LapFinishedPayloadDto? payload;
        try
        {
            payload = envelope.Payload.Deserialize<LapFinishedPayloadDto>(PayloadOptions);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "LapFinished payload 파싱 실패 eventId={EventId}", envelope.EventId);
            return IngestResult.Reject("LapFinished payload 파싱 실패");
        }

        if (payload is null)
        {
            return IngestResult.Reject("LapFinished payload가 비어 있습니다.");
        }

        // 3. 세션 매칭: 인증된 좌석의 활성 세션. 없으면 귀속 불가 → 드롭+Ack(D-22).
        var rig = await _rigs.GetByRigCodeAsync(authenticatedRigCode, cancellationToken);
        if (rig is null)
        {
            return IngestResult.Reject("인증된 좌석을 찾을 수 없습니다.");
        }

        var session = await _sessions.GetActiveByRigAsync(rig.Id, cancellationToken);
        if (session is null)
        {
            _logger.LogWarning("활성 체크인 세션 없음 — 랩 드롭 rig={Rig} eventId={EventId}", authenticatedRigCode, envelope.EventId);
            return IngestResult.Ack();
        }

        // 4. Track 매핑. 없으면 영구 무효(시드 누락) → Reject.
        var track = await _tracks.GetByGameTrackIdAsync(envelope.GameCode, payload.TrackId, cancellationToken);
        if (track is null)
        {
            _logger.LogWarning("Track 매핑 없음 gameCode={GameCode} trackId={TrackId} eventId={EventId}",
                envelope.GameCode, payload.TrackId, envelope.EventId);
            return IngestResult.Reject($"트랙 매핑 없음(gameCode={envelope.GameCode}, trackId={payload.TrackId})");
        }

        // 5. 랭킹 적격 판정(Backend 일원화, D-15): 유효 && 아웃/인랩 아님 && TimeTrial.
        var isRankingEligible = payload.IsValid
            && !payload.IsOutOrInLap
            && payload.SessionType == SessionType.TimeTrial;

        var now = _clock.UtcNow;
        var lap = new Lap
        {
            Id = _idGenerator.NewId(),
            DrivingSessionId = session.Id,
            UserId = session.UserId,
            TrackId = track.Id,
            GameCode = envelope.GameCode,
            SessionType = payload.SessionType,
            LapNumber = payload.LapNumber,
            LapTimeMs = payload.LapTimeMs,
            IsValid = payload.IsValid,
            IsInvalidatedManually = false,
            IsRankingEligible = isRankingEligible,
            SetAt = envelope.OccurredAt,
            CreatedAt = now,
            Sectors = payload.Sectors
                .Select(s => new LapSector
                {
                    Id = _idGenerator.NewId(),
                    SectorNumber = s.SectorNumber,
                    SectorTimeMs = s.SectorTimeMs,
                    CreatedAt = now,
                })
                .ToList(),
        };

        await _laps.AddAsync(lap, cancellationToken);
        await _processed.AddAsync(new ProcessedEvent
        {
            EventId = envelope.EventId,
            EventType = envelope.Type,
            ProcessedAt = now,
        }, cancellationToken);

        // 6. Lap + 멱등 기록을 한 트랜잭션으로 커밋.
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "랩 저장 rig={Rig} user={User} track={Track} lapMs={LapMs} eligible={Eligible} eventId={EventId}",
            authenticatedRigCode, session.UserId, track.Name, lap.LapTimeMs, isRankingEligible, envelope.EventId);

        return IngestResult.Ack();
    }
}
