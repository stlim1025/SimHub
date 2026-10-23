using System.Buffers.Binary;
using System.IO.Compression;
using SimCenter.Agent.Core.Analysis;
using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Tests;

public class TrackSampleCollectorTests
{
    private const string SessionRef = "S1";
    private const int TrackId = 6;
    private const int Cars = 3;
    private const ushort Tarmac = 0;

    /// <summary>바퀴 4개 중 앞왼쪽만 연석(1)인 노면 묶음.</summary>
    private const ushort FrontLeftRumble = 1;

    private readonly TrackSampleCollector _sut = new();

    private static SessionFrame Session(string sessionRef = SessionRef, SessionType type = SessionType.Race, bool network = false)
        => new(sessionRef, TrackId, type, PacketFormat: 2025, IsNetworkGame: network, TrackLengthM: 4361);

    /// <summary>같은 게임 프레임의 위치·랩 상태·노면 3종을 순서대로 먹인다. 반환은 노면 프레임(마지막)이 낸 이벤트.</summary>
    private IReadOnlyList<TelemetryEvent> Tick(
        uint frameId, int timeMs, ushort[]? surfaces = null, bool[]? onTrack = null, float lapDistance = 100, float gLateral0 = 1)
    {
        var positions = Enumerable.Range(0, Cars)
            .Select(i => new FieldPosition(i * 10.5f, -i * 3.25f, i == 0 ? gLateral0 : 1, -0.5f))
            .ToList();
        var states = Enumerable.Range(0, Cars).Select(i => new FieldLapState(lapDistance + i, onTrack?[i] ?? true, Status: 4)).ToList();
        _sut.Process(new FieldPositionsFrame(SessionRef, frameId, timeMs, positions));
        _sut.Process(new FieldLapStatesFrame(SessionRef, frameId, states));
        var speeds = Enumerable.Range(0, Cars).Select(i => (ushort)(250 + i)).ToList();
        var gears = Enumerable.Range(0, Cars).Select(i => (sbyte)(7 - i)).ToList();
        var throttles = Enumerable.Range(0, Cars).Select(i => (byte)(100 - i)).ToList();
        var brakes = Enumerable.Range(0, Cars).Select(i => (byte)i).ToList();
        var drs = Enumerable.Range(0, Cars).Select(i => i == 0).ToList();
        return _sut.Process(new FieldSurfacesFrame(SessionRef, frameId, surfaces ?? new ushort[Cars], speeds, gears, throttles, brakes, drs));
    }

    private static TrackSamplesChunk End(TrackSampleCollector sut)
        => Assert.IsType<TrackSamplesChunk>(Assert.Single(sut.Process(new EventMarker(SessionRef, SessionBoundary.End))));

    [Fact]
    public void Race_SamplesAllCarsTenTimesASecond_AndSendsOneLastChunkAtSessionEnd()
    {
        _sut.Process(Session());
        for (var i = 0; i < 20; i++)
        {
            Assert.Empty(Tick((uint)i, i * 50)); // 게임이 초당 20번 보낸다
        }

        var chunk = End(_sut);

        Assert.Equal(SessionRef, chunk.SessionRef);
        Assert.Equal(TrackId, chunk.TrackId);
        Assert.Equal(SessionType.Race, chunk.SessionType);
        Assert.Equal(4361, chunk.TrackLengthM);
        Assert.Equal(TrackSampleEncoder.Format, chunk.Format);
        Assert.Equal(TrackSampleCollector.SampleRateHz, chunk.SampleRateHz);
        Assert.Equal(0, chunk.ChunkIndex);
        Assert.True(chunk.IsLast);
        Assert.Equal(10, chunk.FrameCount); // 0, 100, …, 900ms
        Assert.Equal(10 * Cars, chunk.SampleCount);
    }

    [Fact]
    public void SurfaceChangeBetweenSamples_AddsAnExtraSampleForThatCarOnly()
    {
        _sut.Process(Session());
        Tick(0, 0);
        Tick(1, 50, [FrontLeftRumble, Tarmac, Tarmac]); // 고정 표본 사이 — 0번 차만 노면이 바뀌었다

        var chunk = End(_sut);

        Assert.Equal(2, chunk.FrameCount);
        Assert.Equal(Cars + 1, chunk.SampleCount);
        var decoded = Decode(chunk.Data);
        var extra = decoded.Samples[Cars];
        Assert.Equal(0, extra.CarIndex);
        Assert.Equal(FrontLeftRumble, extra.Surface);
        Assert.Equal(4 | TrackSampleEncoder.SurfaceChangeFlag, extra.Status);
        Assert.Equal(50u, decoded.TimesMs[1]);
    }

    [Fact]
    public void WallImpact_GForceSpikeOrDamageRise_AddsFlaggedSample_WithSpeedAndDamage()
    {
        _sut.Process(Session());
        _sut.Process(new FieldDamageFrame(SessionRef, [0, 0, 0]));
        Tick(0, 0);
        Tick(1, 30, gLateral0: 9.6f);                              // 0번 차가 벽에 부딪혀 횡 G가 튄다
        _sut.Process(new FieldDamageFrame(SessionRef, [0, 12, 0])); // 1번 차는 손상이 오른다(벽을 긁었다)
        Tick(2, 60);

        var decoded = Decode(End(_sut).Data);

        Assert.Equal(Cars + 2, decoded.Samples.Count);
        var hit = decoded.Samples[Cars];
        Assert.Equal(0, hit.CarIndex);
        Assert.Equal(4 | TrackSampleEncoder.ImpactFlag, hit.Status);
        Assert.Equal(38, hit.GLatQuarterG);                        // 9.6g / 0.25 반올림
        Assert.Equal(-2, hit.GLongQuarterG);
        Assert.Equal(250, hit.SpeedKph);
        var scrape = decoded.Samples[Cars + 1];
        Assert.Equal(1, scrape.CarIndex);
        Assert.Equal(4 | TrackSampleEncoder.ImpactFlag, scrape.Status);
        Assert.Equal(12, scrape.Damage);
    }

    [Fact]
    public void CarToCarCollision_FlagsBothCarsOnce()
    {
        _sut.Process(Session());
        Tick(0, 0);
        _sut.Process(new FieldCollisionFrame(SessionRef, 1, 2));
        Tick(1, 40);
        Tick(2, 80);

        var decoded = Decode(End(_sut).Data);

        var flagged = decoded.Samples.Where(x => (x.Status & TrackSampleEncoder.CollisionFlag) != 0).ToList();
        Assert.Equal([1, 2], flagged.Select(x => (int)x.CarIndex));
        Assert.Equal(Cars + 2, decoded.Samples.Count);             // 충돌한 두 차만 고정 간격 사이에 하나씩 더
    }

    [Fact]
    public void ReplayColumns_GearPedalsDrsAndTyres_AreRecorded()
    {
        _sut.Process(Session());
        _sut.Process(new FieldStatusFrame(SessionRef, [16, 17, 18], [3, 12, 0]));
        Tick(0, 0);

        var samples = Decode(End(_sut).Data).Samples;

        Assert.Equal([7, 6, 5], samples.Select(x => (int)x.Gear));
        Assert.Equal([100, 99, 98], samples.Select(x => (int)x.Throttle));
        Assert.Equal([0, 1, 2], samples.Select(x => (int)x.Brake));
        Assert.Equal([16, 17, 18], samples.Select(x => (int)x.TyreCompound));
        Assert.Equal([3, 12, 0], samples.Select(x => (int)x.TyreAgeLaps));
        Assert.Equal([TrackSampleEncoder.DrsFlag, 0, 0], samples.Select(x => (int)x.Flags2));
    }

    [Fact]
    public void Overtake_FlagsOvertakerAndOvertaken_WithAnExtraSample()
    {
        _sut.Process(Session());
        Tick(0, 0);
        _sut.Process(new FieldOvertakeFrame(SessionRef, Overtaker: 2, Overtaken: 1));
        Tick(1, 40);

        var samples = Decode(End(_sut).Data).Samples;

        Assert.Equal(Cars + 2, samples.Count);
        Assert.Equal(1, samples[Cars].CarIndex);
        Assert.Equal(TrackSampleEncoder.OvertakenFlag, samples[Cars].Flags2);
        Assert.Equal(2, samples[Cars + 1].CarIndex);
        Assert.Equal(TrackSampleEncoder.OvertookFlag, samples[Cars + 1].Flags2);
    }

    [Fact]
    public void CarsOffTrack_OrBeforeTheLine_AreSkipped()
    {
        _sut.Process(Session());
        Tick(0, 0, onTrack: [true, false, true]);
        Tick(1, 100, lapDistance: -5);

        var chunk = End(_sut);

        Assert.Equal(1, chunk.FrameCount);
        Assert.Equal(Cars - 1, chunk.SampleCount);
    }

    [Theory]
    [InlineData(SessionType.TimeTrial, false)]
    [InlineData(SessionType.Unknown, false)]
    [InlineData(SessionType.Race, true)]
    public void TimeTrial_And_OnlineSessions_AreNotCollected(SessionType type, bool network)
    {
        _sut.Process(Session(type: type, network: network));
        Tick(0, 0);

        Assert.Empty(_sut.Process(new EventMarker(SessionRef, SessionBoundary.End)));
    }

    [Fact]
    public void NewSession_ClosesThePreviousOneWithItsLastChunk()
    {
        _sut.Process(Session());
        Tick(0, 0);

        var events = _sut.Process(Session("S2"));

        var chunk = Assert.IsType<TrackSamplesChunk>(Assert.Single(events));
        Assert.Equal(SessionRef, chunk.SessionRef);
        Assert.True(chunk.IsLast);
    }

    [Fact]
    public void FramesFromDifferentGameFrames_AreNotPaired()
    {
        _sut.Process(Session());
        _sut.Process(new FieldPositionsFrame(SessionRef, 1, 0, [new(0, 0), new(1, 1), new(2, 2)]));
        _sut.Process(new FieldLapStatesFrame(SessionRef, 2, [new(1, true, 4), new(1, true, 4), new(1, true, 4)]));
        _sut.Process(new FieldSurfacesFrame(SessionRef, 2, new ushort[Cars]));

        Assert.Empty(_sut.Process(new EventMarker(SessionRef, SessionBoundary.End)));
    }

    [Fact]
    public void LongSession_SendsChunksAsItGoes_ThenAnEmptyLastChunk()
    {
        var sut = new TrackSampleCollector();
        sut.Process(Session());
        var chunks = new List<TrackSamplesChunk>();
        // 압축 전 크기가 처음으로 조각 기준에 닿는 프레임 수.
        var framesForOneChunk = 1;
        while (TrackSampleEncoder.RawSize(framesForOneChunk, framesForOneChunk * Cars) < TrackSampleCollector.RawChunkBytes)
        {
            framesForOneChunk++;
        }

        for (var i = 0; i < framesForOneChunk; i++)
        {
            var positions = Enumerable.Range(0, Cars).Select(c => new FieldPosition(i * 7.1f + c, i * 3.3f - c)).ToList();
            var states = Enumerable.Range(0, Cars).Select(_ => new FieldLapState(i % 5000, true, 4)).ToList();
            sut.Process(new FieldPositionsFrame(SessionRef, (uint)i, i * 100, positions));
            sut.Process(new FieldLapStatesFrame(SessionRef, (uint)i, states));
            chunks.AddRange(sut.Process(new FieldSurfacesFrame(SessionRef, (uint)i, new ushort[Cars])).Cast<TrackSamplesChunk>());
        }

        Assert.NotEmpty(chunks);
        Assert.All(chunks, c => Assert.False(c.IsLast));
        Assert.All(chunks, c => Assert.True(Convert.FromBase64String(c.Data).Length <= TrackSampleCollector.MaxChunkGzipBytes));
        Assert.Equal(Enumerable.Range(0, chunks.Count), chunks.Select(c => c.ChunkIndex));
        Assert.Equal(framesForOneChunk, chunks.Sum(c => c.FrameCount));

        var last = End(sut);
        Assert.True(last.IsLast);
        Assert.Equal(chunks.Count, last.ChunkIndex);
        Assert.Equal(0, last.FrameCount);
    }

    [Fact]
    public void Encoder_WritesColumnsInContractUnits()
    {
        var frames = new[]
        {
            new TrackSampleFrame(1234, [new TrackSample(5, 100.3f, -12.34f, 56.78f, 0x1234, 9, -40f, 3.1f, 312, 77, -1, 64, 32, 17, 9, 5)]),
        };

        var decoded = Decode(Convert.ToBase64String(TrackSampleEncoder.Encode(frames)));

        Assert.Equal(1234u, decoded.TimesMs[0]);
        var sample = decoded.Samples[0];
        Assert.Equal(5, sample.CarIndex);
        Assert.Equal(401, sample.LapDistanceQuarterM); // 100.3 / 0.25 반올림
        Assert.Equal(-123, sample.XDecimeters);
        Assert.Equal(568, sample.ZDecimeters);
        Assert.Equal(0x1234, sample.Surface);
        Assert.Equal(9, sample.Status);
        Assert.Equal(sbyte.MinValue, sample.GLatQuarterG);          // −40g는 열 범위(±31.75g)에서 잘린다
        Assert.Equal(12, sample.GLongQuarterG);
        Assert.Equal(312, sample.SpeedKph);
        Assert.Equal(77, sample.Damage);
        Assert.Equal(-1, sample.Gear);
        Assert.Equal(64, sample.Throttle);
        Assert.Equal(32, sample.Brake);
        Assert.Equal(17, sample.TyreCompound);
        Assert.Equal(9, sample.TyreAgeLaps);
        Assert.Equal(5, sample.Flags2);
    }

    private sealed record DecodedSample(
        byte CarIndex, ushort LapDistanceQuarterM, int XDecimeters, int ZDecimeters, ushort Surface, byte Status,
        sbyte GLatQuarterG, sbyte GLongQuarterG, ushort SpeedKph, byte Damage,
        sbyte Gear, byte Throttle, byte Brake, byte TyreCompound, byte TyreAgeLaps, byte Flags2);

    private sealed record Decoded(uint[] TimesMs, List<DecodedSample> Samples);

    /// <summary>format 3 디코더(계약 문서 그대로 — 서버가 같은 순서로 읽는다).</summary>
    private static Decoded Decode(string base64)
    {
        using var input = new GZipStream(new MemoryStream(Convert.FromBase64String(base64)), CompressionMode.Decompress);
        using var buffer = new MemoryStream();
        input.CopyTo(buffer);
        var raw = buffer.ToArray();
        var offset = 0;
        var frames = BinaryPrimitives.ReadInt32LittleEndian(raw.AsSpan(offset));
        offset += sizeof(int);
        var times = new uint[frames];
        for (var i = 0; i < frames; i++, offset += sizeof(uint))
        {
            times[i] = BinaryPrimitives.ReadUInt32LittleEndian(raw.AsSpan(offset));
        }

        var total = 0;
        for (var i = 0; i < frames; i++)
        {
            total += raw[offset++];
        }

        var cars = raw.AsSpan(offset, total).ToArray();
        offset += total;
        var dist = new ushort[total];
        for (var i = 0; i < total; i++, offset += sizeof(ushort))
        {
            dist[i] = BinaryPrimitives.ReadUInt16LittleEndian(raw.AsSpan(offset));
        }

        var x = new int[total];
        for (var i = 0; i < total; i++, offset += sizeof(int))
        {
            x[i] = BinaryPrimitives.ReadInt32LittleEndian(raw.AsSpan(offset));
        }

        var z = new int[total];
        for (var i = 0; i < total; i++, offset += sizeof(int))
        {
            z[i] = BinaryPrimitives.ReadInt32LittleEndian(raw.AsSpan(offset));
        }

        var surface = new ushort[total];
        for (var i = 0; i < total; i++, offset += sizeof(ushort))
        {
            surface[i] = BinaryPrimitives.ReadUInt16LittleEndian(raw.AsSpan(offset));
        }

        var status = raw.AsSpan(offset, total).ToArray();
        offset += total;
        var gLat = raw.AsSpan(offset, total).ToArray().Select(b => (sbyte)b).ToArray();
        offset += total;
        var gLong = raw.AsSpan(offset, total).ToArray().Select(b => (sbyte)b).ToArray();
        offset += total;
        var speed = new ushort[total];
        for (var i = 0; i < total; i++, offset += sizeof(ushort))
        {
            speed[i] = BinaryPrimitives.ReadUInt16LittleEndian(raw.AsSpan(offset));
        }

        byte[] Column()
        {
            var column = raw.AsSpan(offset, total).ToArray();
            offset += total;
            return column;
        }

        var damage = Column();
        var gear = Column().Select(b => (sbyte)b).ToArray();
        var throttle = Column();
        var brake = Column();
        var compound = Column();
        var age = Column();
        var flags2 = Column();
        Assert.Equal(raw.Length, offset);

        return new Decoded(times, Enumerable.Range(0, total)
            .Select(i => new DecodedSample(
                cars[i], dist[i], x[i], z[i], surface[i], status[i], gLat[i], gLong[i], speed[i], damage[i],
                gear[i], throttle[i], brake[i], compound[i], age[i], flags2[i]))
            .ToList());
    }
}
