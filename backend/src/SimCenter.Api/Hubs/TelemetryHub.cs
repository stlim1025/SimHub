using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using SimCenter.Application.Telemetry;
using SimCenter.Infrastructure.Identity;

namespace SimCenter.Api.Hubs;

/// <summary>
/// Agent → Backend 텔레메트리 인입 Hub(05-signalr-design §2). Agent API Key 스킴으로만 접속 가능(D-21).
/// 단일 진입점 <see cref="SubmitEvent"/> + Ack/Reject 응답. 세션 매칭은 인증된 RigCode를 신뢰한다.
/// </summary>
[Authorize(AuthenticationSchemes = AgentApiKeyDefaults.Scheme)]
public sealed class TelemetryHub : Hub
{
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
    /// </summary>
    public async Task<IngestResult> SubmitEvent(TelemetryEnvelopeDto envelope)
    {
        var rigCode = Context.User?.FindFirst(AgentApiKeyDefaults.RigCodeClaim)?.Value;
        if (string.IsNullOrEmpty(rigCode))
        {
            return IngestResult.Reject("인증된 좌석 정보가 없습니다.");
        }

        var result = await _ingest.IngestAsync(envelope, rigCode, Context.ConnectionAborted);

        if (!result.Acknowledged)
        {
            _logger.LogWarning("이벤트 Reject rig={Rig} eventId={EventId} reason={Reason}",
                rigCode, envelope.EventId, result.RejectReason);
        }

        return result;
    }
}
