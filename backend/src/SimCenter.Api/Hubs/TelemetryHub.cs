using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using SimCenter.Application.Telemetry;
using SimCenter.Infrastructure.Identity;

namespace SimCenter.Api.Hubs;

/// <summary>
/// Agent → Backend 텔레메트리 인입 Hub(05-signalr-design §2). Agent 장치 키 스킴으로만 접속 가능(D-26).
/// 단일 진입점 <see cref="SubmitEvent"/> + Ack/Reject 응답. 랩 귀속은 연결에서 인증된 장치(<c>deviceId</c>)를 신뢰한다.
/// </summary>
[Authorize(AuthenticationSchemes = AgentApiKeyDefaults.Scheme)]
public sealed class TelemetryHub : Hub
{
    /// <summary>
    /// 허브가 받는 메시지 하나의 최대 크기(1MiB, D-49). 한도를 넘는 메시지는 Reject가 아니라 <b>연결 종료</b>라 Agent가 같은 Outbox 항목을
    /// 끝없이 재시도하게 되므로(12 §0) 한도를 명시한다(기본 32KB에 기대지 않는다).
    /// D-49(텔레메트리 전부 수집)로 LapFinished가 트레이스 추가 채널(<c>trace.extra</c>)·<c>car.details</c>를, SessionClassified가
    /// 랩별 기록·순위를 실어 64KiB(이전 값)를 넘을 수 있어 1MiB로 올렸다. Agent는 전송 전에 768KiB로 제한하고, 넘으면 트레이스 해상도를
    /// 10m → 20m → 트레이스 제거 순으로 낮춘다(15 §8).
    /// </summary>
    public const long MaxMessageBytes = MaxMessageMebibytes * BytesPerMebibyte;

    private const long MaxMessageMebibytes = 1;
    private const long BytesPerMebibyte = 1024 * 1024;

    /// <summary>연결에 유효한 <c>deviceId</c> 클레임이 없을 때의 Reject 사유.</summary>
    private const string MissingDeviceReason = "인증된 장치 정보가 없습니다.";

    private readonly ITelemetryIngestService _ingest;
    private readonly ILogger<TelemetryHub> _logger;

    public TelemetryHub(ITelemetryIngestService ingest, ILogger<TelemetryHub> logger)
    {
        _ingest = ingest;
        _logger = logger;
    }

    /// <summary>
    /// 모든 도메인 이벤트의 단일 인입점. 처리 결과(Ack/Reject)를 반환값으로 돌려준다(요청/응답).
    /// Ack·Reject 모두 Agent는 Outbox에서 flush하며, 재전송은 응답 없음(네트워크 장애)일 때만.
    /// 예외: 연결 해제 Reject(<see cref="TelemetryIngestService.RevokedDeviceReason"/>)는 Agent가 항목을 보관하고 업로드를 멈춘다(11 §6.4).
    /// </summary>
    public async Task<IngestResult> SubmitEvent(TelemetryEnvelopeDto envelope)
    {
        var deviceClaim = Context.User?.FindFirst(AgentApiKeyDefaults.DeviceIdClaim)?.Value;
        if (!Guid.TryParse(deviceClaim, out var deviceId))
        {
            _logger.LogWarning("장치 클레임 없음 — 이벤트 Reject eventId={EventId}", envelope.EventId);
            return IngestResult.Reject(MissingDeviceReason);
        }

        var result = await _ingest.IngestAsync(envelope, deviceId, Context.ConnectionAborted);

        if (!result.Acknowledged)
        {
            _logger.LogWarning("이벤트 Reject device={Device} eventId={EventId} reason={Reason}",
                deviceId, envelope.EventId, result.RejectReason);
        }

        return result;
    }
}
