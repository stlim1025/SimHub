using System.Buffers;
using System.Text.Json;
using SimCenter.Application.Common;

namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// <c>SessionClassified</c>의 선택 필드 <c>lapHistory</c>(전 차량 랩별 기록, Session History 11)·<c>lapPositions</c>(랩별 순위, Lap Positions 15)를
/// 세션의 추가 기록 묶음(<c>GameSession.Details</c>, jsonb)으로 만든다(D-49, 15 §8). 모양은 보지 않고 받은 그대로 담는다(P8 세션 상세의 재료).
/// 저장할 수 없는 묶음은 버린다 — 순위표 저장은 막지 않는다.
/// </summary>
public static class SessionDetailsCapture
{
    /// <summary>묶음 원문 한도. 허브 메시지 한도(1MiB)와 같다 — 그보다 큰 값은 애초에 들어올 수 없다.</summary>
    public const int MaxBytes = 1024 * 1024;

    private const string LapHistoryName = "lapHistory";
    private const string LapPositionsName = "lapPositions";

    /// <summary>둘 다 없으면 null(사유 없음). 저장할 수 없으면 null과 사유.</summary>
    public static string? Build(JsonElement? lapHistory, JsonElement? lapPositions, out string? rejectReason)
    {
        rejectReason = null;
        var history = Present(lapHistory);
        var positions = Present(lapPositions);
        if (history is null && positions is null)
        {
            return null;
        }

        var buffer = new ArrayBufferWriter<byte>();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            WriteIfPresent(writer, LapHistoryName, history);
            WriteIfPresent(writer, LapPositionsName, positions);
            writer.WriteEndObject();
        }

        using var document = JsonDocument.Parse(buffer.WrittenMemory);
        return JsonbText.TryCaptureObject(document.RootElement, MaxBytes, out rejectReason);
    }

    private static JsonElement? Present(JsonElement? value)
        => value is { ValueKind: not (JsonValueKind.Null or JsonValueKind.Undefined) } json ? json : null;

    private static void WriteIfPresent(Utf8JsonWriter writer, string name, JsonElement? value)
    {
        if (value is { } json)
        {
            writer.WritePropertyName(name);
            json.WriteTo(writer);
        }
    }
}
