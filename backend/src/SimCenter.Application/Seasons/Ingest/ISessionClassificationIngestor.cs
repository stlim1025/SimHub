using SimCenter.Application.Telemetry;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// <c>SessionClassified</c> 이벤트 처리기(12 §6.1~6.2). 변경을 <b>추적만</b> 하고 저장하지 않는다 —
/// <c>ProcessedEvent</c> 추가와 커밋 1회는 <see cref="ITelemetryIngestService"/>가 한다(결과 저장과 멱등 기록을 한 트랜잭션으로).
/// <see cref="ClassificationOutcome.Ignored"/>·<see cref="ClassificationOutcome.Rejected"/>면 아무것도 추적하지 않는다.
/// </summary>
public interface ISessionClassificationIngestor
{
    /// <param name="envelope">Agent가 보낸 이벤트 봉투(<c>type = SessionClassified</c>).</param>
    /// <param name="device">연결에서 인증된 장치. 결과는 장치의 주인(<see cref="AgentDevice.UserId"/>)에게 귀속된다(D-25).</param>
    /// <param name="now">서버 현재 시각(UTC). 생성·수정 시각과 분류 시각 상한 계산에 쓴다.</param>
    /// <param name="cancellationToken">취소 토큰.</param>
    Task<ClassificationOutcome> ApplyAsync(
        TelemetryEnvelopeDto envelope, AgentDevice device, DateTime now, CancellationToken cancellationToken = default);
}
