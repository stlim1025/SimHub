using System.IO.Compression;
using System.Text.Json;

namespace SimCenter.Application.Laps;

/// <summary>트레이스 7채널(같은 길이의 정수 배열, 15 §3.3). 저장 형식이자 조회 응답의 재료다.</summary>
public sealed record LapTraceChannels(
    int[] TimeMs,
    int[] SpeedKph,
    int[] Throttle,
    int[] Brake,
    int[] Steer,
    int[] Gear,
    int[] Rpm);

/// <summary>
/// 트레이스 저장 형식(D-45, D-18): 7채널 JSON(camelCase)을 gzip한 바이트(<c>lap_telemetry_traces.payload</c>, bytea).
/// 랩 1개당 약 10~15KB(5m 기준). 인코딩 전에 검증을 마친 값만 넣는다.
/// </summary>
public static class LapTraceCodec
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    public static byte[] Encode(LapTraceChannels channels)
    {
        ArgumentNullException.ThrowIfNull(channels);

        using var buffer = new MemoryStream();
        using (var gzip = new GZipStream(buffer, CompressionLevel.Optimal, leaveOpen: true))
        {
            JsonSerializer.Serialize(gzip, channels, Options);
        }

        return buffer.ToArray();
    }

    /// <exception cref="InvalidDataException">gzip·JSON이 깨졌거나 채널이 빠졌을 때(저장 데이터 손상).</exception>
    public static LapTraceChannels Decode(byte[] payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        try
        {
            using var input = new MemoryStream(payload);
            using var gzip = new GZipStream(input, CompressionMode.Decompress);
            var channels = JsonSerializer.Deserialize<LapTraceChannels>(gzip, Options);
            return IsComplete(channels)
                ? channels!
                : throw new InvalidDataException("트레이스 채널이 빠졌습니다.");
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException("트레이스 JSON을 읽지 못했습니다.", ex);
        }
    }

    private static bool IsComplete(LapTraceChannels? c)
        => c is { TimeMs: not null, SpeedKph: not null, Throttle: not null, Brake: not null, Steer: not null, Gear: not null, Rpm: not null };
}
