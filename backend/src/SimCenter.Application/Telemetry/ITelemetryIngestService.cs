namespace SimCenter.Application.Telemetry;

/// <summary>텔레메트리 이벤트 인입 유스케이스(멱등→세션매칭→저장). 전송/인증은 Api(Hub)가 담당.</summary>
public interface ITelemetryIngestService
{
    /// <param name="authenticatedRigCode">연결에서 인증된 좌석 코드(엔벨로프 값이 아닌 신뢰 원천, D-21).</param>
    Task<IngestResult> IngestAsync(TelemetryEnvelopeDto envelope, string authenticatedRigCode, CancellationToken cancellationToken = default);
}
