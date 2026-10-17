using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Rankings;
using SimCenter.Application.Rankings.Notifications;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Telemetry;

/// <summary>
/// 텔레메트리 인입 유스케이스(11 §5). <c>LapFinished</c>만 영속화하고 나머지 이벤트는 Ack만 한다(YAGNI).
/// 처리 순서: 멱등 → 장치 확인 → LastSeenAt → 유형 → payload 파싱 → 트랙 매핑 → 랭킹 적격 → PB → 저장 → 브로드캐스트.
/// 랩은 연결된 장치의 주인에게 귀속한다(D-25). 해제된 장치·영구 무효(파싱/트랙 실패)는 Reject.
/// </summary>
public sealed class TelemetryIngestService : ITelemetryIngestService
{
    /// <summary>장치가 없거나 연결 해제된 경우의 Reject 사유(Agent가 그대로 기록한다).</summary>
    public const string RevokedDeviceReason = "연결이 해제된 장치입니다.";

    /// <summary>
    /// <see cref="AgentDevice.LastSeenAt"/> 쓰기 최소 간격. 이벤트마다 장치 행을 갱신하지 않도록,
    /// 값이 없거나 이 간격 이상 지났을 때만 기록한다.
    /// </summary>
    public static readonly TimeSpan LastSeenWriteInterval = TimeSpan.FromMinutes(1);

    private const string LapFinishedType = "LapFinished";

    private static readonly JsonSerializerOptions PayloadOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly IProcessedEventRepository _processed;
    private readonly IAgentDeviceRepository _devices;
    private readonly ITrackRepository _tracks;
    private readonly ILapRepository _laps;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIdGenerator _idGenerator;
    private readonly IClock _clock;
    private readonly IRankingService _ranking;
    private readonly IRankingNotifier _notifier;
    private readonly ILogger<TelemetryIngestService> _logger;

    public TelemetryIngestService(
        IProcessedEventRepository processed,
        IAgentDeviceRepository devices,
        ITrackRepository tracks,
        ILapRepository laps,
        IUnitOfWork unitOfWork,
        IIdGenerator idGenerator,
        IClock clock,
        IRankingService ranking,
        IRankingNotifier notifier,
        ILogger<TelemetryIngestService> logger)
    {
        _processed = processed;
        _devices = devices;
        _tracks = tracks;
        _laps = laps;
        _unitOfWork = unitOfWork;
        _idGenerator = idGenerator;
        _clock = clock;
        _ranking = ranking;
        _notifier = notifier;
        _logger = logger;
    }

    public async Task<IngestResult> IngestAsync(TelemetryEnvelopeDto envelope, Guid authenticatedDeviceId, CancellationToken cancellationToken = default)
    {
        // 1. 멱등: 이미 처리한 eventId면 즉시 Ack(effectively-once). 해제 전에 처리된 이벤트의 재전송도 Ack로 끝난다.
        if (await _processed.ExistsAsync(envelope.EventId, cancellationToken))
        {
            return IngestResult.Ack();
        }

        // 2. 장치 확인: 연결 후 해제됐을 수 있으므로 이벤트마다 다시 조회한다(이미 열린 연결로 계속 보내는 것을 막는다).
        var device = await _devices.GetByIdAsync(authenticatedDeviceId, cancellationToken);
        if (device is null)
        {
            _logger.LogWarning("없거나 연결 해제된 장치의 이벤트 device={Device} eventId={EventId}", authenticatedDeviceId, envelope.EventId);
            return IngestResult.Reject(RevokedDeviceReason);
        }

        // 3. 마지막 수신 시각(모든 유형). 실제 저장은 아래 반환 경로에서 한 번만 한다.
        var now = _clock.UtcNow;
        var lastSeenChanged = TouchLastSeen(device, now);

        // 4. LapFinished만 저장. 그 외 유효 이벤트는 무시하되 Ack.
        if (!string.Equals(envelope.Type, LapFinishedType, StringComparison.Ordinal))
        {
            _logger.LogDebug("비저장 이벤트 {Type} device={Device} eventId={EventId}", envelope.Type, device.Id, envelope.EventId);
            return await FinishWithoutLapAsync(IngestResult.Ack(), lastSeenChanged, cancellationToken);
        }

        // 5. payload 파싱. 실패는 영구 무효 → Reject.
        var payload = TryParseLapFinished(envelope, out var parseError);
        if (payload is null)
        {
            return await FinishWithoutLapAsync(IngestResult.Reject(parseError), lastSeenChanged, cancellationToken);
        }

        return await IngestLapAsync(envelope, payload, device, now, lastSeenChanged, cancellationToken);
    }

    /// <summary>
    /// <see cref="AgentDevice.LastSeenAt"/>이 없거나 <see cref="LastSeenWriteInterval"/> 이상 지났으면 지금 시각으로 바꾼다.
    /// </summary>
    /// <returns>값을 바꿨으면 true(저장 필요).</returns>
    private static bool TouchLastSeen(AgentDevice device, DateTime now)
    {
        if (device.LastSeenAt is { } lastSeen && now - lastSeen < LastSeenWriteInterval)
        {
            return false;
        }

        device.LastSeenAt = now;
        return true;
    }

    /// <summary>랩을 저장하지 않는 반환 경로. LastSeenAt이 바뀌었을 때만 한 번 저장한다.</summary>
    private async Task<IngestResult> FinishWithoutLapAsync(IngestResult result, bool lastSeenChanged, CancellationToken cancellationToken)
    {
        if (lastSeenChanged)
        {
            await _unitOfWork.SaveChangesAsync(cancellationToken);
        }

        return result;
    }

    /// <summary>LapFinished payload를 해석한다. 실패하면 null과 Reject 사유를 돌려준다.</summary>
    private LapFinishedPayloadDto? TryParseLapFinished(TelemetryEnvelopeDto envelope, out string rejectReason)
    {
        try
        {
            var payload = envelope.Payload.Deserialize<LapFinishedPayloadDto>(PayloadOptions);
            rejectReason = payload is null ? "LapFinished payload가 비어 있습니다." : string.Empty;
            return payload;
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "LapFinished payload 파싱 실패 eventId={EventId}", envelope.EventId);
            rejectReason = "LapFinished payload 파싱 실패";
            return null;
        }
    }

    /// <summary>트랙 매핑 → 랭킹 적격 → PB 판정 → 저장(랩 + 멱등 기록 + LastSeenAt 한 커밋) → 브로드캐스트.</summary>
    private async Task<IngestResult> IngestLapAsync(
        TelemetryEnvelopeDto envelope, LapFinishedPayloadDto payload, AgentDevice device, DateTime now, bool lastSeenChanged,
        CancellationToken cancellationToken)
    {
        // 6. Track 매핑. 없으면 영구 무효(시드 누락) → Reject.
        var track = await _tracks.GetByGameTrackIdAsync(envelope.GameCode, payload.TrackId, cancellationToken);
        if (track is null)
        {
            _logger.LogWarning("Track 매핑 없음 gameCode={GameCode} trackId={TrackId} eventId={EventId}",
                envelope.GameCode, payload.TrackId, envelope.EventId);
            return await FinishWithoutLapAsync(
                IngestResult.Reject($"트랙 매핑 없음(gameCode={envelope.GameCode}, trackId={payload.TrackId})"),
                lastSeenChanged, cancellationToken);
        }

        var lap = CreateLap(envelope, payload, device, track.Id, now);

        // 7. PB 판정: 저장 커밋 전에 이전 최고(랭킹적격)를 조회한다. 현재 랩은 아직 미저장이라 자기비교가 없다.
        int? previousBestMs = null;
        var isPersonalBest = false;
        if (lap.IsRankingEligible)
        {
            var previousBest = await _laps.GetPersonalBestLapAsync(lap.UserId, lap.TrackId, lap.GameCode, cancellationToken);
            previousBestMs = previousBest?.LapTimeMs;
            isPersonalBest = previousBest is null || lap.LapTimeMs < previousBest.LapTimeMs;
        }

        // 8. Lap + 멱등 기록 + 장치 LastSeenAt을 한 트랜잭션으로 커밋.
        await _laps.AddAsync(lap, cancellationToken);
        await _processed.AddAsync(new ProcessedEvent
        {
            EventId = envelope.EventId,
            EventType = envelope.Type,
            ProcessedAt = now,
        }, cancellationToken);
        await _unitOfWork.SaveChangesAsync(cancellationToken);

        _logger.LogInformation(
            "랩 저장 device={Device} user={User} track={Track} lapMs={LapMs} eligible={Eligible} eventId={EventId}",
            device.Id, lap.UserId, track.Name, lap.LapTimeMs, lap.IsRankingEligible, envelope.EventId);

        // 9. 실시간 브로드캐스트(커밋 이후 best-effort). 랩은 이미 저장됐으므로 실패해도 Ack를 유지한다.
        //    Agent 연결 취소와 앱 브로드캐스트를 분리하기 위해 CancellationToken.None을 사용한다.
        await BroadcastAsync(lap, isPersonalBest, previousBestMs);

        return IngestResult.Ack();
    }

    /// <summary>
    /// 장치 주인에게 귀속된 랩을 만든다. 랭킹 적격은 Backend가 일원화해 판정한다(D-15):
    /// 유효 &amp;&amp; 아웃/인랩 아님 &amp;&amp; TimeTrial.
    /// </summary>
    private Lap CreateLap(TelemetryEnvelopeDto envelope, LapFinishedPayloadDto payload, AgentDevice device, Guid trackId, DateTime now)
        => new()
        {
            Id = _idGenerator.NewId(),
            AgentDeviceId = device.Id,
            UserId = device.UserId,
            TrackId = trackId,
            GameCode = envelope.GameCode,
            SessionType = payload.SessionType,
            LapNumber = payload.LapNumber,
            LapTimeMs = payload.LapTimeMs,
            IsValid = payload.IsValid,
            IsInvalidatedManually = false,
            IsRankingEligible = payload.IsValid && !payload.IsOutOrInLap && payload.SessionType == SessionType.TimeTrial,
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

    /// <summary>
    /// 저장된 랩에 대한 실시간 이벤트를 발행한다(05 §3). 유효 랩→LapRecorded, PB 갱신→PersonalBestAchieved(user 그룹),
    /// 랭킹적격→월별 TOP N 재조회 후 RankingUpdated(track 그룹, D-8a). 어떤 실패도 Ack에 영향을 주지 않는다.
    /// </summary>
    private async Task BroadcastAsync(Lap lap, bool isPersonalBest, int? previousBestMs)
    {
        try
        {
            if (lap.IsValid)
            {
                await _notifier.LapRecordedAsync(new LapRecordedNotice(
                    lap.Id, lap.UserId, lap.TrackId, lap.SessionType.ToString(), lap.LapTimeMs, lap.IsValid, lap.IsRankingEligible));
            }

            if (isPersonalBest)
            {
                await _notifier.PersonalBestAchievedAsync(
                    new PersonalBestNotice(lap.UserId, lap.TrackId, lap.LapTimeMs, previousBestMs));
            }

            if (lap.IsRankingEligible)
            {
                var snapshot = await _ranking.GetRankingAsync(lap.TrackId, lap.GameCode, RankingPeriod.Monthly, date: null);
                await _notifier.RankingUpdatedAsync(snapshot);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "랩 저장 후 브로드캐스트 실패 lapId={LapId} track={TrackId}", lap.Id, lap.TrackId);
        }
    }
}
