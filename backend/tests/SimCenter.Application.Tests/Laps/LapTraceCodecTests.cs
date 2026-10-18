using System.IO.Compression;
using System.Text;
using SimCenter.Application.Laps;

namespace SimCenter.Application.Tests.Laps;

/// <summary>트레이스 저장 형식(D-45): 7채널 JSON gzip — 원래 값으로 그대로 돌아와야 한다.</summary>
public class LapTraceCodecTests
{
    private static readonly byte[] GzipMagic = [0x1F, 0x8B];

    [Fact]
    public void EncodeThenDecode_RestoresEveryChannel()
    {
        var channels = SpaLikeTrace();

        var restored = LapTraceCodec.Decode(LapTraceCodec.Encode(channels));

        Assert.Equal(channels.TimeMs, restored.TimeMs);
        Assert.Equal(channels.SpeedKph, restored.SpeedKph);
        Assert.Equal(channels.Throttle, restored.Throttle);
        Assert.Equal(channels.Brake, restored.Brake);
        Assert.Equal(channels.Steer, restored.Steer);
        Assert.Equal(channels.Gear, restored.Gear);
        Assert.Equal(channels.Rpm, restored.Rpm);
    }

    [Fact]
    public void Encode_IsGzip_AndSmallForALongLap()
    {
        // 5m 기준 가장 긴 Spa(약 7km, 1,400칸). 압축 후 문서의 예상(약 10~15KB)보다 넉넉히 작아야 한다.
        var payload = LapTraceCodec.Encode(SpaLikeTrace());

        Assert.Equal(GzipMagic, payload.Take(2));
        Assert.True(payload.Length < 20 * 1024, $"압축 크기 {payload.Length}B");
    }

    [Fact]
    public void Decode_CorruptBytes_ThrowsInvalidData()
    {
        Assert.Throws<InvalidDataException>(() => LapTraceCodec.Decode([1, 2, 3, 4]));
    }

    [Fact]
    public void Decode_GzipJsonWithoutChannels_ThrowsInvalidData()
    {
        Assert.Throws<InvalidDataException>(() => LapTraceCodec.Decode(Gzip("{\"timeMs\":[1,2]}")));
        Assert.Throws<InvalidDataException>(() => LapTraceCodec.Decode(Gzip("not json")));
    }

    private static byte[] Gzip(string text)
    {
        using var buffer = new MemoryStream();
        using (var gzip = new GZipStream(buffer, CompressionLevel.Optimal, leaveOpen: true))
        {
            gzip.Write(Encoding.UTF8.GetBytes(text));
        }

        return buffer.ToArray();
    }

    private static LapTraceChannels SpaLikeTrace()
    {
        const int samples = 1_400;
        var random = new Random(25);
        int[] Series(int min, int max) => Enumerable.Range(0, samples).Select(_ => random.Next(min, max + 1)).ToArray();

        return new LapTraceChannels(
            Enumerable.Range(0, samples).Select(i => i * 75).ToArray(),
            Series(80, 330),
            Series(0, 100),
            Series(0, 100),
            Series(-100, 100),
            Series(-1, 8),
            Series(4_000, 12_500));
    }
}
