using System.Text.Json;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Telemetry;

/// <summary>
/// TelemetryHub로 인입되는 이벤트 봉투(shared/schema/telemetry_envelope.json, camelCase 계약).
/// Payload는 type별로 상이하므로 raw JSON으로 받아 type에 따라 해석한다(OCP).
/// 보낸 장치는 봉투가 아니라 연결의 인증 정보(장치 키)로 정한다(D-26).
/// </summary>
public sealed record TelemetryEnvelopeDto(
    Guid EventId,
    string GameCode,
    DateTime OccurredAt,
    string Type,
    JsonElement Payload);

/// <summary>
/// LapFinished payload(05/06 계약). 랭킹 적격 판정에 필요한 근거와, 세션 연결 키(<c>Lap.SessionKey</c>, 12 §4.6)를 만드는 선택 필드를 담는다.
/// <see cref="GameMode"/>부터는 옛 Agent가 보내지 않는 선택 필드다(누락 시 기본값). <see cref="GameMode"/>는 문자열로 받아 모르는 값을 거부하지 않는다.
/// <see cref="Car"/>·<see cref="Conditions"/>·<see cref="Trace"/>(15 §4.3)는 raw JSON으로만 받는다 — 안의 모양이 틀려도 랩 파싱이
/// 실패하지 않게 하고, <c>LapDetailExtractor</c>가 따로 해석·검증해 틀린 영역만 버린다(랩은 절대 거부하지 않는다).
/// </summary>
public sealed record LapFinishedPayloadDto(
    string SessionRef,
    int LapNumber,
    int LapTimeMs,
    IReadOnlyList<SectorDto> Sectors,
    bool IsValid,
    bool IsOutOrInLap,
    int TrackId,
    SessionType SessionType,
    string? GameMode = null,
    long SeasonLinkId = 0,
    long WeekendLinkId = 0,
    long SessionLinkId = 0,
    JsonElement? Car = null,
    JsonElement? Conditions = null,
    JsonElement? Trace = null);

/// <summary>단일 섹터(가변 섹터, D-7).</summary>
public sealed record SectorDto(int SectorNumber, int SectorTimeMs);

/// <summary>
/// 인입 처리 결과. Ack=처리/무시 완료(Outbox flush), Reject=영구 무효(Outbox 폐기).
/// 단, 연결 해제 Reject(<see cref="TelemetryIngestService.RevokedDeviceReason"/>)는 Agent가 보관하고 업로드를 멈춘다(11 §6.4).
/// </summary>
public sealed record IngestResult(bool Acknowledged, string? RejectReason)
{
    public static IngestResult Ack() => new(true, null);

    public static IngestResult Reject(string reason) => new(false, reason);
}
