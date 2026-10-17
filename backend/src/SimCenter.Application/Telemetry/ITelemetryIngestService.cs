namespace SimCenter.Application.Telemetry;

/// <summary>텔레메트리 이벤트 인입 유스케이스(멱등→장치 확인→저장). 전송/인증은 Api(Hub)가 담당.</summary>
public interface ITelemetryIngestService
{
    /// <param name="envelope">Agent가 보낸 이벤트 봉투.</param>
    /// <param name="authenticatedDeviceId">연결에서 인증된 Agent 장치 ID(봉투 값이 아닌 신뢰 원천, D-26).</param>
    /// <param name="cancellationToken">취소 토큰.</param>
    Task<IngestResult> IngestAsync(TelemetryEnvelopeDto envelope, Guid authenticatedDeviceId, CancellationToken cancellationToken = default);
}
