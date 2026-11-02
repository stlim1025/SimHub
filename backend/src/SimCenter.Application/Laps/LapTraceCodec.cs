using System.IO.Compression;
using System.Text.Json;

namespace SimCenter.Application.Laps;

/// <summary>
/// 트레이스 7채널(같은 길이의 정수 배열, 15 §3.3)과 추가 채널 맵(<see cref="Extra"/>, D-49 — 같은 길이의 실수 배열, 없으면 null).
/// 저장 형식이자 조회 응답의 재료다. extra 이전에 저장된 blob은 <see cref="Extra"/>가 null로 복원된다.
/// </summary>
public sealed record LapTraceChannels(
    int[] TimeMs,
    int[] SpeedKph,
    int[] Throttle,
    int[] Brake,
    int[] Steer,
    int[] Gear,
    int[] Rpm,
    IReadOnlyDictionary<string, double[]>? Extra = null);

/// <summary>
/// 트레이스 저장 형식(D-45, D-18): 7채널 JSON(camelCase)을 gzip한 바이트(<c>lap_telemetry_traces.payload</c>, bytea).
/// 랩 1개당 약 10~15KB(5m 기준, 추가 채널이 있으면 더 크다). 인코딩 전에 검증을 마친 값만 넣는다.
/// 채널 이름(딕셔너리 키)은 받은 그대로 둔다(camelCase로 바꾸지 않는다).
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

    /// <summary>
    /// 기본 7채널과 <paramref name="extraChannels"/>에 든 추가 채널만 푼다 — 랩 수십 개를 한꺼번에 읽을 때 쓰지 않는 추가 채널(100여 개) 배열을 만들지 않는다.
    /// 고른 추가 채널이 하나도 없으면 <see cref="LapTraceChannels.Extra"/>는 null.
    /// </summary>
    /// <exception cref="InvalidDataException">gzip·JSON이 깨졌거나 기본 채널이 빠졌을 때(저장 데이터 손상).</exception>
    public static LapTraceChannels Decode(byte[] payload, IReadOnlySet<string> extraChannels)
    {
        ArgumentNullException.ThrowIfNull(payload);
        ArgumentNullException.ThrowIfNull(extraChannels);

        using var input = new MemoryStream(payload);
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        using var json = new MemoryStream();
        gzip.CopyTo(json);
        try
        {
            return ReadSelected(json.ToArray(), extraChannels);
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            throw new InvalidDataException("트레이스 JSON을 읽지 못했습니다.", ex);
        }
    }

    private static LapTraceChannels ReadSelected(byte[] json, IReadOnlySet<string> extraChannels)
    {
        var reader = new Utf8JsonReader(json);
        var basic = new Dictionary<string, int[]>(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, double[]>? extra = null;
        if (!reader.Read() || reader.TokenType != JsonTokenType.StartObject)
        {
            throw new JsonException("트레이스는 객체여야 합니다.");
        }

        while (reader.Read() && reader.TokenType == JsonTokenType.PropertyName)
        {
            var name = reader.GetString()!;
            reader.Read();
            if (string.Equals(name, nameof(LapTraceChannels.Extra), StringComparison.OrdinalIgnoreCase)
                && reader.TokenType == JsonTokenType.StartObject)
            {
                while (reader.Read() && reader.TokenType == JsonTokenType.PropertyName)
                {
                    var channel = reader.GetString()!;
                    reader.Read();
                    if (extraChannels.Contains(channel) && reader.TokenType == JsonTokenType.StartArray)
                    {
                        (extra ??= new Dictionary<string, double[]>())[channel] = ReadDoubles(ref reader);
                    }
                    else
                    {
                        reader.Skip();
                    }
                }
            }
            else if (reader.TokenType == JsonTokenType.StartArray)
            {
                basic[name] = ReadInts(ref reader);
            }
            else
            {
                reader.Skip();
            }
        }

        int[] Basic(string name) => basic.TryGetValue(name, out var values) ? values : null!;
        var channels = new LapTraceChannels(
            Basic(nameof(LapTraceChannels.TimeMs)),
            Basic(nameof(LapTraceChannels.SpeedKph)),
            Basic(nameof(LapTraceChannels.Throttle)),
            Basic(nameof(LapTraceChannels.Brake)),
            Basic(nameof(LapTraceChannels.Steer)),
            Basic(nameof(LapTraceChannels.Gear)),
            Basic(nameof(LapTraceChannels.Rpm)),
            extra);
        return IsComplete(channels) ? channels : throw new InvalidDataException("트레이스 채널이 빠졌습니다.");
    }

    private static int[] ReadInts(ref Utf8JsonReader reader)
    {
        var values = new List<int>();
        while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
        {
            values.Add(reader.GetInt32());
        }

        return values.ToArray();
    }

    private static double[] ReadDoubles(ref Utf8JsonReader reader)
    {
        var values = new List<double>();
        while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
        {
            values.Add(reader.GetDouble());
        }

        return values.ToArray();
    }

    private static bool IsComplete(LapTraceChannels? c)
        => c is { TimeMs: not null, SpeedKph: not null, Throttle: not null, Brake: not null, Steer: not null, Gear: not null, Rpm: not null };
}
