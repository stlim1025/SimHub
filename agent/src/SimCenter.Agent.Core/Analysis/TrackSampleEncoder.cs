using System.Buffers.Binary;
using System.IO.Compression;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>트랙 형상 표본 한 칸(차 한 대의 한 순간).</summary>
/// <param name="Surface">바퀴 4개 노면(4비트 × 4, FL·FR·RL·RR 순, 하위 비트부터).</param>
/// <param name="Status">게임 원시 상태 묶음(하위 5비트) + 표시 비트(<see cref="TrackSampleEncoder.CollisionFlag"/>·<see cref="TrackSampleEncoder.ImpactFlag"/>·<see cref="TrackSampleEncoder.SurfaceChangeFlag"/>).</param>
/// <param name="GLateral">횡 G-force(g).</param>
/// <param name="GLongitudinal">종 G-force(g).</param>
/// <param name="Damage">날개·플로어·디퓨저·사이드포드 손상률(%) 최댓값.</param>
/// <param name="Gear">−1 = R, 0 = N, 1~8.</param>
/// <param name="TyreCompound">보이는 타이어 컴파운드(게임 원시 값, 0 = 모름).</param>
/// <param name="Y">월드 높이(m).</param>
/// <param name="Steer">조향(−100~100, 왼쪽 −).</param>
/// <param name="Rpm">엔진 RPM.</param>
/// <param name="ErsStoreKj">ERS 배터리 잔량(kJ).</param>
/// <param name="Flags2">표시 비트 2(<see cref="TrackSampleEncoder.DrsFlag"/>·<see cref="TrackSampleEncoder.OvertookFlag"/>·<see cref="TrackSampleEncoder.OvertakenFlag"/>).</param>
public readonly record struct TrackSample(
    byte CarIndex,
    float LapDistanceM,
    float X,
    float Z,
    ushort Surface,
    byte Status,
    float GLateral = 0,
    float GLongitudinal = 0,
    ushort SpeedKph = 0,
    byte Damage = 0,
    sbyte Gear = 0,
    byte Throttle = 0,
    byte Brake = 0,
    byte TyreCompound = 0,
    byte TyreAgeLaps = 0,
    byte Flags2 = 0,
    float Y = 0,
    sbyte Steer = 0,
    ushort Rpm = 0,
    ushort ErsStoreKj = 0);

/// <summary>한 순간(게임 프레임)의 표본 묶음.</summary>
public sealed record TrackSampleFrame(int SessionTimeMs, IReadOnlyList<TrackSample> Samples);

/// <summary>
/// 트랙 형상·레이스 리플레이 표본 <c>format 5</c> 인코더(<c>shared/schema/track_samples_chunk.json</c>): 프레임·표본을 열 단위로 모은 little-endian 바이트를 gzip한다.
/// 같은 종류의 값끼리 모아 압축이 잘 되게 한다. format 1 열 뒤에 G-force·속도·손상(format 2), 기어·페달·타이어·표시2(format 3), 높이(format 4), 조향·RPM·ERS 잔량(format 5) 열이 붙는다.
/// </summary>
public static class TrackSampleEncoder
{
    public const int Format = 5;

    /// <summary>차 대 차 충돌이 있었던 차의 표본(상태 bit5).</summary>
    public const byte CollisionFlag = 0x20;

    /// <summary>충격 순간(G 급변·손상 증가) 표본(상태 bit6).</summary>
    public const byte ImpactFlag = 0x40;

    /// <summary>노면이 바뀐 순간 표본(상태 bit7).</summary>
    public const byte SurfaceChangeFlag = 0x80;

    /// <summary>표시 비트 2: DRS 열림(bit0)·이 표본에 추월함(bit1)·이 표본에 추월당함(bit2).</summary>
    public const byte DrsFlag = 0x01;
    public const byte OvertookFlag = 0x02;
    public const byte OvertakenFlag = 0x04;

    /// <summary>랩 거리 단위(m)·좌표 단위(m)·G-force 단위(g).</summary>
    public const float LapDistanceUnitM = 0.25f;
    public const float PositionUnitM = 0.1f;
    public const float GForceUnit = 0.25f;

    /// <summary>
    /// 프레임 1개의 바이트(세션 시간 4 + 차 수 1)·표본 1개의 바이트
    /// (차 1 + 랩 거리 2 + X 4 + Z 4 + 노면 2 + 상태 1 + 횡 G 1 + 종 G 1 + 속도 2 + 손상 1 + 기어 1 + 스로틀 1 + 브레이크 1 + 타이어 1 + 타이어 랩 1 + 표시2 1 + 높이 4 + 조향 1 + RPM 2 + ERS 2).
    /// </summary>
    public const int FrameBytes = 5;
    public const int SampleBytes = 34;

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

        foreach (var s in samples)
        {
            span[offset++] = (byte)ToSByte(s.GLateral / GForceUnit);
        }

        foreach (var s in samples)
        {
            span[offset++] = (byte)ToSByte(s.GLongitudinal / GForceUnit);
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(span[offset..], s.SpeedKph);
            offset += sizeof(ushort);
        }

        foreach (var s in samples)
        {
            span[offset++] = s.Damage;
        }

        foreach (var s in samples)
        {
            span[offset++] = (byte)s.Gear;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.Throttle;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.Brake;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.TyreCompound;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.TyreAgeLaps;
        }

        foreach (var s in samples)
        {
            span[offset++] = s.Flags2;
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteInt32LittleEndian(span[offset..], ToInt32(s.Y / PositionUnitM));
            offset += sizeof(int);
        }

        foreach (var s in samples)
        {
            span[offset++] = (byte)s.Steer;
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(span[offset..], s.Rpm);
            offset += sizeof(ushort);
        }

        foreach (var s in samples)
        {
            BinaryPrimitives.WriteUInt16LittleEndian(span[offset..], s.ErsStoreKj);
            offset += sizeof(ushort);
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

    private static sbyte ToSByte(float value)
        => float.IsFinite(value) ? (sbyte)Math.Clamp(MathF.Round(value), sbyte.MinValue, sbyte.MaxValue) : (sbyte)0;
}
