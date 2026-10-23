using System.Buffers.Binary;
using System.IO.Compression;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>테스트용 표본 조각 만들기(계약 format 5 그대로).</summary>
internal static class TrackSamplePayloads
{
    /// <summary>합성 표본 한 개(계약 단위 그대로).</summary>
    internal sealed record Sample(
        byte Car, double DistanceM, double X, double Z, ushort Surface = 0, ushort SpeedKph = 200, double Y = 0,
        sbyte Steer = 0, ushort Rpm = 0, ushort ErsKj = 0);

    /// <summary>계약(<c>shared/schema/track_samples_chunk.json</c>) format 5 그대로 열 배치 → gzip.</summary>
    internal static byte[] Encode(IReadOnlyList<Sample[]> frames, int frameTimeMs = 0)
    {
        var samples = frames.SelectMany(f => f).ToList();
        using var raw = new MemoryStream();
        void Int32(int v)
        {
            Span<byte> b = stackalloc byte[sizeof(int)];
            BinaryPrimitives.WriteInt32LittleEndian(b, v);
            raw.Write(b);
        }

        void UInt16(int v)
        {
            Span<byte> b = stackalloc byte[sizeof(ushort)];
            BinaryPrimitives.WriteUInt16LittleEndian(b, (ushort)v);
            raw.Write(b);
        }

        void Byte(int v) => raw.WriteByte(unchecked((byte)v));

        Int32(frames.Count);
        for (var f = 0; f < frames.Count; f++)
        {
            Int32(frameTimeMs + f * 100);
        }

        foreach (var f in frames)
        {
            Byte(f.Length);
        }

        samples.ForEach(s => Byte(s.Car));
        samples.ForEach(s => UInt16((int)Math.Round(s.DistanceM / 0.25)));
        samples.ForEach(s => Int32((int)Math.Round(s.X / 0.1)));
        samples.ForEach(s => Int32((int)Math.Round(s.Z / 0.1)));
        samples.ForEach(s => UInt16(s.Surface));
        samples.ForEach(_ => Byte(0));             // 상태
        samples.ForEach(_ => Byte(0));             // 횡 G
        samples.ForEach(_ => Byte(0));             // 종 G
        samples.ForEach(s => UInt16(s.SpeedKph));
        samples.ForEach(_ => Byte(0));             // 손상
        samples.ForEach(_ => Byte(7));             // 기어
        samples.ForEach(_ => Byte(100));           // 스로틀
        samples.ForEach(_ => Byte(0));             // 브레이크
        samples.ForEach(_ => Byte(16));            // 타이어
        samples.ForEach(_ => Byte(1));             // 타이어 랩
        samples.ForEach(_ => Byte(0));             // 표시2
        samples.ForEach(s => Int32((int)Math.Round(s.Y / 0.1)));
        samples.ForEach(s => Byte(s.Steer));
        samples.ForEach(s => UInt16(s.Rpm));
        samples.ForEach(s => UInt16(s.ErsKj));

        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Fastest))
        {
            gzip.Write(raw.ToArray());
        }

        return output.ToArray();
    }
}
