using System.Buffers.Binary;
using System.IO.Compression;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 푼 표본 조각 하나(<c>shared/schema/track_samples_chunk.json</c>). 배열은 모두 표본 순서(같은 칸 = 같은 표본)이고,
/// 그 format에 없는 열은 null이다.
/// </summary>
/// <param name="TimeMs">표본마다 세션 경과 시간(ms, 그 표본이 든 프레임의 시간).</param>
/// <param name="LapDistanceM">현재 랩에서 달린 거리(m).</param>
/// <param name="X">월드 X(m).</param>
/// <param name="Z">월드 Z(m).</param>
/// <param name="Surface">바퀴 4개 노면(4비트 × 4, FL·FR·RL·RR 순, 하위 비트부터).</param>
/// <param name="SpeedKph">format 2부터.</param>
/// <param name="Gear">format 3부터(−1 = R, 0 = N).</param>
/// <param name="Throttle">format 3부터(%).</param>
/// <param name="Brake">format 3부터(%).</param>
/// <param name="TyreCompound">format 3부터(보이는 컴파운드, 게임 원시 값).</param>
/// <param name="Y">format 4부터(월드 높이, m).</param>
/// <param name="Steer">format 5부터(−100~100, 왼쪽 −).</param>
/// <param name="Rpm">format 5부터.</param>
/// <param name="ErsStoreKj">format 5부터(ERS 배터리 잔량 kJ).</param>
public sealed record DecodedTrackSamples(
    int Format,
    int[] TimeMs,
    byte[] CarIndex,
    float[] LapDistanceM,
    float[] X,
    float[] Z,
    ushort[] Surface,
    byte[] Status,
    ushort[]? SpeedKph,
    sbyte[]? Gear,
    byte[]? Throttle,
    byte[]? Brake,
    byte[]? TyreCompound,
    float[]? Y,
    sbyte[]? Steer,
    ushort[]? Rpm,
    ushort[]? ErsStoreKj)
{
    public int Count => CarIndex.Length;
}

/// <summary>
/// 트랙 형상·레이스 리플레이 표본 조각(gzip, 열 배치 little-endian) 디코더. format 1~5를 읽는다.
/// 형식이 맞지 않으면(<see cref="FormatException"/>) 그 조각을 건너뛰도록 호출자에게 알린다.
/// </summary>
public static class TrackSampleDecoder
{
    /// <summary>읽을 수 있는 가장 높은 format.</summary>
    public const int MaxFormat = 5;

    /// <summary>열 단위.</summary>
    private const float LapDistanceUnitM = 0.25f;
    private const float PositionUnitM = 0.1f;

    /// <summary>풀었을 때 크기 한도(조각은 Agent에서 약 1.2MB에 끊긴다 — 압축 폭탄 방어).</summary>
    private const int MaxRawBytes = 16 * 1024 * 1024;

    private const int CopyBufferBytes = 81920;

    public static DecodedTrackSamples Decode(byte[] gzip, int format)
    {
        if (format is < 1 or > MaxFormat)
        {
            throw new FormatException($"지원하지 않는 표본 format {format}");
        }

        var reader = new ColumnReader(Decompress(gzip));
        var frameCount = reader.Int32();
        if (frameCount < 0)
        {
            throw new FormatException("프레임 수가 음수입니다.");
        }

        var frameTimes = reader.UInt32s(frameCount);
        var perFrame = reader.Bytes(frameCount);
        var total = perFrame.Sum(c => (int)c);
        var times = new int[total];
        for (int f = 0, k = 0; f < frameCount; f++)
        {
            for (var c = 0; c < perFrame[f]; c++)
            {
                times[k++] = (int)Math.Min(frameTimes[f], int.MaxValue);
            }
        }

        var car = reader.Bytes(total);
        var distance = Array.ConvertAll(reader.UInt16s(total), v => v * LapDistanceUnitM);
        var x = Array.ConvertAll(reader.Int32s(total), v => v * PositionUnitM);
        var z = Array.ConvertAll(reader.Int32s(total), v => v * PositionUnitM);
        var surface = reader.UInt16s(total);
        var status = reader.Bytes(total);

        ushort[]? speed = null;
        sbyte[]? gear = null;
        byte[]? throttle = null;
        byte[]? brake = null;
        byte[]? tyre = null;
        float[]? y = null;
        sbyte[]? steer = null;
        ushort[]? rpm = null;
        ushort[]? ers = null;
        if (format >= 2)
        {
            reader.Skip(total); // 횡 G
            reader.Skip(total); // 종 G
            speed = reader.UInt16s(total);
            reader.Skip(total); // 손상
        }

        if (format >= 3)
        {
            gear = reader.SBytes(total);
            throttle = reader.Bytes(total);
            brake = reader.Bytes(total);
            tyre = reader.Bytes(total);
            reader.Skip(total); // 타이어 랩
            reader.Skip(total); // 표시2
        }

        if (format >= 4)
        {
            y = Array.ConvertAll(reader.Int32s(total), v => v * PositionUnitM);
        }

        if (format >= 5)
        {
            steer = reader.SBytes(total);
            rpm = reader.UInt16s(total);
            ers = reader.UInt16s(total);
        }

        if (!reader.AtEnd)
        {
            throw new FormatException("표본 열 뒤에 남는 바이트가 있습니다.");
        }

        return new DecodedTrackSamples(
            format, times, car, distance, x, z, surface, status, speed, gear, throttle, brake, tyre, y, steer, rpm, ers);
    }

    private static byte[] Decompress(byte[] gzip)
    {
        try
        {
            using var input = new GZipStream(new MemoryStream(gzip), CompressionMode.Decompress);
            using var output = new MemoryStream();
            var buffer = new byte[CopyBufferBytes];
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                if (output.Length + read > MaxRawBytes)
                {
                    throw new FormatException("풀어 보니 표본 조각이 너무 큽니다.");
                }

                output.Write(buffer, 0, read);
            }

            return output.ToArray();
        }
        catch (InvalidDataException ex)
        {
            throw new FormatException("gzip이 아닙니다.", ex);
        }
    }

    /// <summary>열 배치 바이트를 앞에서부터 읽는다(모자라면 <see cref="FormatException"/>).</summary>
    private sealed class ColumnReader(byte[] raw)
    {
        private int _offset;

        public bool AtEnd => _offset == raw.Length;

        public int Int32() => BinaryPrimitives.ReadInt32LittleEndian(Take(sizeof(int)));

        public void Skip(int count) => Take(count);

        public byte[] Bytes(int count) => Take(count).ToArray();

        public sbyte[] SBytes(int count) => Array.ConvertAll(Bytes(count), b => unchecked((sbyte)b));

        public uint[] UInt32s(int count) => Read(count, sizeof(uint), BinaryPrimitives.ReadUInt32LittleEndian);

        public ushort[] UInt16s(int count) => Read(count, sizeof(ushort), BinaryPrimitives.ReadUInt16LittleEndian);

        public int[] Int32s(int count) => Read(count, sizeof(int), BinaryPrimitives.ReadInt32LittleEndian);

        private delegate T SpanReader<out T>(ReadOnlySpan<byte> span);

        private T[] Read<T>(int count, int size, SpanReader<T> read)
        {
            // 망가진 조각은 개수가 터무니없이 클 수 있다 — 곱이 넘치기 전에 남은 길이와 견준다.
            if ((long)count * size > raw.Length - _offset)
            {
                throw new FormatException("표본 열이 모자랍니다.");
            }

            var span = Take(count * size);
            var values = new T[count];
            for (var i = 0; i < count; i++)
            {
                values[i] = read(span.Slice(i * size, size));
            }

            return values;
        }

        private ReadOnlySpan<byte> Take(int count)
        {
            if (count < 0 || (long)_offset + count > raw.Length)
            {
                throw new FormatException("표본 열이 모자랍니다.");
            }

            var span = raw.AsSpan(_offset, count);
            _offset += count;
            return span;
        }
    }
}
