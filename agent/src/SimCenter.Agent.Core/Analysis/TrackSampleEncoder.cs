using System.Buffers.Binary;
using System.IO.Compression;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>트랙 형상 표본 한 칸(차 한 대의 한 순간).</summary>
/// <param name="Surface">바퀴 4개 노면(4비트 × 4, FL·FR·RL·RR 순, 하위 비트부터).</param>
/// <param name="Status">게임 원시 상태 묶음. 최상위 비트(<see cref="TrackSampleEncoder.SurfaceChangeFlag"/>)는 노면 변화로 더한 표본 표시.</param>
public readonly record struct TrackSample(byte CarIndex, float LapDistanceM, float X, float Z, ushort Surface, byte Status);

/// <summary>한 순간(게임 프레임)의 표본 묶음.</summary>
public sealed record TrackSampleFrame(int SessionTimeMs, IReadOnlyList<TrackSample> Samples);

/// <summary>
/// 트랙 형상 표본 <c>format 1</c> 인코더(<c>shared/schema/track_samples_chunk.json</c>): 프레임·표본을 열 단위로 모은 little-endian 바이트를 gzip한다.
/// 같은 종류의 값끼리 모아 압축이 잘 되게 한다.
/// </summary>
public static class TrackSampleEncoder
{
    public const int Format = 1;

    /// <summary>노면 변화로 더한 표본 표시(상태 바이트 최상위 비트).</summary>
    public const byte SurfaceChangeFlag = 0x80;

    /// <summary>랩 거리 단위(m)·좌표 단위(m).</summary>
    public const float LapDistanceUnitM = 0.25f;
    public const float PositionUnitM = 0.1f;

    /// <summary>프레임 1개의 바이트(세션 시간 4 + 차 수 1)·표본 1개의 바이트(차 1 + 랩 거리 2 + X 4 + Z 4 + 노면 2 + 상태 1).</summary>
    public const int FrameBytes = 5;
    public const int SampleBytes = 14;

    private const int HeaderBytes = 4;

    /// <summary>프레임들의 압축 전 크기(바이트).</summary>
    public static int RawSize(int frameCount, int sampleCount) => HeaderBytes + frameCount * FrameBytes + sampleCount * SampleBytes;

    /// <summary>프레임들을 열 배치 바이트로 만들어 gzip한다.</summary>
    public static byte[] Encode(IReadOnlyList<TrackSampleFrame> frames)
    {
        var samples = frames.SelectMany(f => f.Samples).ToList();
        var raw = new byte[RawSize(frames.Count, samples.Count)];
        var span = raw.AsSpan();
        var offset = 0;

        BinaryPrimitives.WriteInt32LittleEndian(span[offset..], frames.Count);
        offset += HeaderBytes;
        foreach (var frame in frames)
        {
            BinaryPrimitives.WriteUInt32LittleEndian(span[offset..], (uint)Math.Max(0, frame.SessionTimeMs));
            offset += sizeof(uint);
        }

        foreach (var frame in frames)
        {
            span[offset++] = (byte)frame.Samples.Count;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.CarIndex;
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(span[offset..], ToUInt16(s.LapDistanceM / LapDistanceUnitM));
            offset += sizeof(ushort);
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteInt32LittleEndian(span[offset..], ToInt32(s.X / PositionUnitM));
            offset += sizeof(int);
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteInt32LittleEndian(span[offset..], ToInt32(s.Z / PositionUnitM));
            offset += sizeof(int);
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(span[offset..], s.Surface);
            offset += sizeof(ushort);
        }

        foreach (var s in samples)
        {
            span[offset++] = s.Status;
        }

        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Optimal))
        {
            gzip.Write(raw);
        }

        return output.ToArray();
    }

    private static ushort ToUInt16(float value)
        => float.IsFinite(value) ? (ushort)Math.Clamp(MathF.Round(value), ushort.MinValue, ushort.MaxValue) : (ushort)0;

    private static int ToInt32(float value)
        => float.IsFinite(value) ? (int)Math.Clamp(Math.Round((double)value), int.MinValue, int.MaxValue) : 0;
}
