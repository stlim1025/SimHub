using SimCenter.Application.TrackSamples;
using static SimCenter.Application.Tests.TrackSamples.TrackSamplePayloads;

namespace SimCenter.Application.Tests.TrackSamples;

/// <summary>세션 표본 → 다른 차의 베스트 랩 트레이스(5m 간격) 복원.</summary>
public sealed class FieldLapBuilderTests
{
    /// <summary>합성 서킷: 길이 600m 원. 표본은 프레임 100ms마다(Encode 규칙), 차는 프레임마다 5m(50m/s) → 한 랩 12초.</summary>
    private const double TrackLength = 600;
    private const double StepM = 5;
    private const int LapMs = 12_000;
    private static readonly double Radius = TrackLength / (2 * Math.PI);

    /// <summary>[car]가 출발선 30m 앞에서 출발해 [distanceM]만큼 달린다. 다른 차 하나(9번)는 섞여 있기만 하다.</summary>
    private static DecodedTrackSamples Drive(double distanceM, byte car = 4)
    {
        var frames = new List<Sample[]>();
        for (var travelled = 0.0; travelled <= distanceM; travelled += StepM)
        {
            var lapDistance = (TrackLength - 30 + travelled) % TrackLength;
            var angle = lapDistance / Radius;
            frames.Add([
                new Sample(car, lapDistance, Radius * Math.Cos(angle), Radius * Math.Sin(angle), SpeedKph: 180,
                    Y: lapDistance * 0.01, Steer: -20, Rpm: 11_500, ErsKj: (ushort)(3_000 - travelled)),
                new Sample(9, 100, 1, 1),
            ]);
        }

        return TrackSampleDecoder.Decode(Encode(frames), format: 5);
    }

    [Fact]
    public void FinishedLap_ClosestToBestLapTime_IsResampledEvery5m()
    {
        var channels = FieldLapBuilder.Build([Drive(TrackLength * 2 + 60)], carIndex: 4, bestLapTimeMs: LapMs, TrackLength)!;

        Assert.Equal(121, channels.TimeMs.Length);            // 0 ~ 600m, 5m 간격
        Assert.Equal(0, channels.TimeMs[0]);
        Assert.InRange(channels.TimeMs[60], 5_990, 6_010);   // 300m = 6초
        Assert.InRange(channels.TimeMs[^1], 11_990, 12_010);
        Assert.All(channels.SpeedKph, v => Assert.Equal(180, v));
        Assert.All(channels.Steer, v => Assert.Equal(-20, v));
        Assert.All(channels.Rpm, v => Assert.Equal(11_500, v));
        var angle = 300 / Radius;
        Assert.InRange(channels.Extra!["worldPosX"][60] - Radius * Math.Cos(angle), -0.2, 0.2); // 위치는 0.1m 단위
        Assert.Equal(3, channels.Extra["worldPosY"][60], 0);
        Assert.True(channels.Extra["ersStoreEnergy"][0] > channels.Extra["ersStoreEnergy"][^1]); // 랩 동안 쓴 만큼 줄었다
        Assert.True(channels.Extra["ersDeployedThisLap"][^1] > 0);
    }

    [Fact]
    public void OpenLap_NearlyComplete_EndsAtBestLapTime()
    {
        // 결승선 통과 뒤 570m(95%)까지만 표본이 있다(피트로 들어가 끊김). 베스트 랩은 12.5초.
        var channels = FieldLapBuilder.Build([Drive(30 + 570)], carIndex: 4, bestLapTimeMs: 12_500, TrackLength)!;

        Assert.Equal(12_500, channels.TimeMs[^1]);
        Assert.InRange(channels.TimeMs[100], 9_990, 10_010); // 500m = 10초(표본 구간 그대로)
    }

    [Fact]
    public void NoLapNearBestLapTime_OrNoSamples_ReturnsNull()
    {
        Assert.Null(FieldLapBuilder.Build([Drive(TrackLength * 2 + 60)], carIndex: 4, bestLapTimeMs: 20_000, TrackLength));
        Assert.Null(FieldLapBuilder.Build([Drive(TrackLength * 2 + 60)], carIndex: 7, bestLapTimeMs: LapMs, TrackLength));
        Assert.Null(FieldLapBuilder.Build([Drive(TrackLength * 0.5)], carIndex: 4, bestLapTimeMs: LapMs, TrackLength));
    }
}
