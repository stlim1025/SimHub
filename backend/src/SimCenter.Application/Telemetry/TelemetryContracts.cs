using System.Text.Json;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Telemetry;

/// <summary>
/// TelemetryHub로 인입되는 이벤트 봉투(shared/schema/telemetry_envelope.json, camelCase 계약).
/// Payload는 type별로 상이하므로 raw JSON으로 받아 type에 따라 해석한다(OCP).
/// </summary>
public sealed record TelemetryEnvelopeDto(
    Guid EventId,
    string RigCode,
    string GameCode,
    DateTime OccurredAt,
    string Type,
    JsonElement Payload);

/// <summary>LapFinished payload(05/06 계약). 랭킹 적격 판정에 필요한 근거만 담는다.</summary>
public sealed record LapFinishedPayloadDto(
    string SessionRef,
    int LapNumber,
    int LapTimeMs,
    IReadOnlyList<SectorDto> Sectors,
    bool IsValid,
    bool IsOutOrInLap,
    int TrackId,
    SessionType SessionType);

/// <summary>단일 섹터(가변 섹터, D-7).</summary>
public sealed record SectorDto(int SectorNumber, int SectorTimeMs);

/// <summary>인입 처리 결과. Ack=처리/무시 완료(Outbox flush), Reject=영구 무효(Outbox 폐기).</summary>
public sealed record IngestResult(bool Acknowledged, string? RejectReason)
{
    public static IngestResult Ack() => new(true, null);

    public static IngestResult Reject(string reason) => new(false, reason);
}
