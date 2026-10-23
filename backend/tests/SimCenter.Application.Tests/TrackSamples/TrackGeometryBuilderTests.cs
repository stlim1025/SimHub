using SimCenter.Application.TrackSamples;
using static SimCenter.Application.Tests.TrackSamples.TrackSamplePayloads;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>표본 디코더(format 1~5 열 배치)와 표본 → 트랙 형상 계산.</summary>
public sealed class TrackGeometryBuilderTests
{
    /// <summary>합성 서킷: 반지름 100m 원을 반시계로 돈다(진행 방향 왼쪽 = 원 안쪽).</summary>
    private const double Radius = 100;
    private static readonly double LapLength = 2 * Math.PI * Radius;

    /// <summary>네 바퀴 모두 연석(1)·잔디(7).</summary>
    private const ushort Rumble = 0x1111;
    private const ushort Grass = 0x7777;

    [Fact]
    public void Decode_Format5_ReadsEveryColumnInContractUnits()
    {
        var gzip = Encode([[new Sample(3, 100.3, -12.34, 56.78, 0x1234, 312, -7.86, -42, 11_234, 3_210)]], frameTimeMs: 1234);

        var decoded = TrackSampleDecoder.Decode(gzip, format: 5);

        Assert.Equal(1, decoded.Count);
        Assert.Equal(1234, decoded.TimeMs[0]);
        Assert.Equal(3, decoded.CarIndex[0]);
        Assert.Equal(100.25f, decoded.LapDistanceM[0]);   // 0.25m 단위
        Assert.Equal(-12.3f, decoded.X[0], 3);
        Assert.Equal(56.8f, decoded.Z[0], 3);
        Assert.Equal(0x1234, decoded.Surface[0]);
        Assert.Equal(312, decoded.SpeedKph![0]);
        Assert.Equal(-7.9f, decoded.Y![0], 3);
        Assert.Equal(-42, decoded.Steer![0]);
        Assert.Equal(11_234, decoded.Rpm![0]);
        Assert.Equal(3_210, decoded.ErsStoreKj![0]);
    }

    [Fact]
    public void Decode_NotGzipOrShortColumns_ThrowsFormatException()
    {
        Assert.Throws<FormatException>(() => TrackSampleDecoder.Decode([1, 2, 3, 4], format: 1));
        var format5 = Encode([[new Sample(0, 1, 1, 1)]]);
        Assert.Throws<FormatException>(() => TrackSampleDecoder.Decode(format5, format: 4)); // 열이 남는다
        Assert.Throws<FormatException>(() => TrackSampleDecoder.Decode(format5, format: 6));
    }

    [Fact]
    public void Build_LineBandKerbsAndHeight_FromAllCars()
    {
        // 차 3대가 2m마다 표본: 0번은 반지름 100(레이싱 라인), 1번은 안쪽 2m(왼쪽), 2번은 바깥 1.5m(오른쪽).
        // 100~120m 구간에서 1번이 연석을 밟고, 400~420m 구간에서 2번이 연석을 밟는다. 높이는 랩 거리 × 0.01.
        var frames = new List<Sample[]>();
        for (var d = 0.0; d < LapLength; d += 2)
        {
            var angle = d / Radius;
            Sample At(byte car, double radius, ushort surface) => new(
                car, d, radius * Math.Cos(angle), radius * Math.Sin(angle), surface, Y: d * 0.01);
            frames.Add([
                At(0, Radius, 0),
                At(1, Radius - 2, d is >= 100 and < 120 ? Rumble : (ushort)0),
                At(2, Radius + 1.5, d is >= 400 and < 420 ? Rumble : (ushort)0),
            ]);
        }

        var geometry = TrackGeometryBuilder.Build([TrackSampleDecoder.Decode(Encode(frames), format: 5)])!;

        var bin = 30; // 150m
        var binAngle = bin * TrackGeometryBuilder.ResolutionM / Radius;
        Assert.InRange(geometry.X[bin] - Radius * Math.Cos(binAngle), -0.5, 0.5);   // 칸 i = 랩 거리 i × 5m
        Assert.InRange(geometry.Z[bin] - Radius * Math.Sin(binAngle), -0.5, 0.5);
        // 선은 세 차 표본의 중앙값이라 레이싱 라인(반지름 100)에서 조금 비켜날 수 있다.
        Assert.InRange(geometry.BandLeftM[bin], 1.7, 2.3);
        Assert.InRange(geometry.BandRightM[bin], 1.2, 1.8);
        Assert.Equal(1.5, geometry.Y![bin], 0);
        Assert.True(geometry.KerbLeft[22]);      // 110m: 안쪽(왼쪽) 연석
        Assert.False(geometry.KerbRight[22]);
        Assert.True(geometry.KerbRight[82]);     // 410m: 바깥(오른쪽) 연석
        Assert.False(geometry.KerbLeft[82]);
        Assert.False(geometry.KerbLeft[bin] || geometry.KerbRight[bin]);
    }

    [Fact]
    public void Build_SlowAndOffTrackSamples_DoNotWidenTheBand()
    {
        var frames = new List<Sample[]>();
        for (var d = 0.0; d < LapLength; d += 2)
        {
            var angle = d / Radius;
            frames.Add([
                new Sample(0, d, Radius * Math.Cos(angle), Radius * Math.Sin(angle)),
                // 잔디 위(노면 7)로 10m 밖, 멈춘 차(속도 0)로 20m 안.
                new Sample(1, d, (Radius + 10) * Math.Cos(angle), (Radius + 10) * Math.Sin(angle), Grass),
                new Sample(2, d, (Radius - 20) * Math.Cos(angle), (Radius - 20) * Math.Sin(angle), SpeedKph: 0),
            ]);
        }

        var geometry = TrackGeometryBuilder.Build([TrackSampleDecoder.Decode(Encode(frames), format: 5)])!;

        Assert.All(geometry.BandRightM, w => Assert.True(w < 1));
        Assert.All(geometry.BandLeftM, w => Assert.True(w < 1));
    }

    [Fact]
    public void Build_TooFewSamples_ReturnsNull()
        => Assert.Null(TrackGeometryBuilder.Build([TrackSampleDecoder.Decode(Encode([[new Sample(0, 500, 1, 1)]]), format: 5)]));
}
