using SimCenter.Agent.Core.Telemetry;
using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 트랙 형상 표본 수집기(헌장 Agent Rules 예외, <c>docs/Track-Envelope-From-All-Cars-2026-10-23.html</c>).
/// 오프라인 연습·예선·레이스에서 모든 차의 위치·랩 거리·노면을 같은 게임 프레임끼리 짝지어 초당 <see cref="SampleRateHz"/>번 표본으로 쌓고,
/// 그 사이에 어느 차의 노면이 바뀌면 그 차 표본을 하나 더 넣는다(연석 접촉은 짧아서 고정 빈도로는 놓친다).
/// 쌓인 표본이 <see cref="RawChunkBytes"/>를 넘거나 세션이 끝나면 <see cref="TrackSamplesChunk"/>를 낸다.
/// 패킷 원본은 보내지 않는다. 상태 저장이므로 스레드 안전하지 않다(파이프라인이 순차 처리).
/// </summary>
public sealed class TrackSampleCollector : ITelemetryAnalyzer
{
    /// <summary>고정 표본 빈도(초당).</summary>
    public const int SampleRateHz = 10;

    /// <summary>쌓인 표본의 압축 전 크기가 이만큼이면 조각을 낸다.</summary>
    public const int RawChunkBytes = 1_200_000;

    /// <summary>조각 gzip 본문 상한. 넘으면 프레임을 반으로 나눠 다시 만든다(봉투 768KiB 안에 base64로 들어가는 크기).</summary>
    public const int MaxChunkGzipBytes = 512 * 1024;

    /// <summary>한 프레임에 실을 수 있는 차 수(차 수 열이 1바이트).</summary>
    private const int MaxCarsPerFrame = byte.MaxValue;

    private const int MillisecondsPerSecond = 1000;

    /// <summary>고정 표본 간격 허용 오차(ms) — 게임이 정확히 100ms마다 보내지 않아도 표본이 건너뛰지 않게.</summary>
    private const int SampleIntervalToleranceMs = 5;

    private static readonly SessionType[] CollectedSessionTypes = [SessionType.Practice, SessionType.Qualifying, SessionType.Race];

    private readonly List<TrackSampleFrame> _buffer = [];
    private readonly Dictionary<int, ushort> _lastSurface = [];

    private SessionFrame? _session;
    private bool _collecting;
    private FieldPositionsFrame? _positions;
    private FieldLapStatesFrame? _lapStates;
    private int? _lastBaseMs;
    private int _bufferedSamples;
    private int _nextChunkIndex;

    private static int SampleIntervalMs => MillisecondsPerSecond / SampleRateHz;

    public IReadOnlyList<TelemetryEvent> Process(ITelemetryFrame frame)
    {
        switch (frame)
        {
            case SessionFrame session:
                return OnSession(session);
            case FieldPositionsFrame positions when IsCurrent(positions):
                _positions = positions;
                break;
            case FieldLapStatesFrame lapStates when IsCurrent(lapStates):
                _lapStates = lapStates;
                break;
            case FieldSurfacesFrame surfaces when IsCurrent(surfaces):
                return OnSurfaces(surfaces);
            case EventMarker { Kind: SessionBoundary.End } marker when IsCurrent(marker):
                var events = Flush(isLast: true);
                _collecting = false;
                return events;
        }

        return Array.Empty<TelemetryEvent>();
    }

    private bool IsCurrent(ITelemetryFrame frame) => _collecting && frame.SessionRef == _session?.SessionRef;

    private IReadOnlyList<TelemetryEvent> OnSession(SessionFrame session)
    {
        if (_session?.SessionRef == session.SessionRef)
        {
            // Session 패킷은 초당 2회 온다 — 맥락(트랙 길이 등)만 갱신한다. 끝난 세션을 다시 모으지는 않는다.
            _session = session;
            return Array.Empty<TelemetryEvent>();
        }

        // 세션이 바뀌면 앞 세션을 마지막 조각으로 닫고 새로 시작한다.
        var events = Flush(isLast: true);
        _session = session;
        _collecting = CollectedSessionTypes.Contains(session.SessionType) && !session.IsNetworkGame;
        _positions = null;
        _lapStates = null;
        _lastSurface.Clear();
        _lastBaseMs = null;
        _nextChunkIndex = 0;
        return events;
    }

    private IReadOnlyList<TelemetryEvent> OnSurfaces(FieldSurfacesFrame surfaces)
    {
        var positions = _positions;
        var lapStates = _lapStates;
        if (positions is null || lapStates is null || positions.FrameId != surfaces.FrameId || lapStates.FrameId != surfaces.FrameId)
        {
            return Array.Empty<TelemetryEvent>();
        }

        var timeMs = positions.SessionTimeMs;
        // 플래시백으로 시간이 되돌아가면 고정 표본 기준도 다시 잡는다.
        var isBase = _lastBaseMs is not { } last || timeMs < last || timeMs - last >= SampleIntervalMs - SampleIntervalToleranceMs;
        var cars = Math.Min(MaxCarsPerFrame, Math.Min(surfaces.Surfaces.Count, Math.Min(positions.Cars.Count, lapStates.Cars.Count)));
        var samples = new List<TrackSample>();
        for (var car = 0; car < cars; car++)
        {
            var surface = surfaces.Surfaces[car];
            var changed = _lastSurface.TryGetValue(car, out var previous) && previous != surface;
            _lastSurface[car] = surface;

            var lap = lapStates.Cars[car];
            if (!lap.IsOnTrack || lap.LapDistanceM < 0 || !(isBase || changed))
            {
                continue;
            }

            var position = positions.Cars[car];
            var status = isBase ? lap.Status : (byte)(lap.Status | TrackSampleEncoder.SurfaceChangeFlag);
            samples.Add(new TrackSample((byte)car, lap.LapDistanceM, position.X, position.Z, surface, status));
        }

        if (isBase)
        {
            _lastBaseMs = timeMs;
        }

        if (samples.Count == 0)
        {
            return Array.Empty<TelemetryEvent>();
        }

        _buffer.Add(new TrackSampleFrame(timeMs, samples));
        _bufferedSamples += samples.Count;
        return TrackSampleEncoder.RawSize(_buffer.Count, _bufferedSamples) >= RawChunkBytes
            ? Flush(isLast: false)
            : Array.Empty<TelemetryEvent>();
    }

    /// <summary>
    /// 쌓인 표본을 조각으로 낸다. 마지막 조각인데 쌓인 표본이 없으면, 앞서 조각을 보낸 세션에만 빈 마지막 조각을 보낸다
    /// (서버가 세션이 끝났음을 알게). 한 번도 보내지 않은 세션은 아무것도 내지 않는다.
    /// </summary>
    private IReadOnlyList<TelemetryEvent> Flush(bool isLast)
    {
        var session = _session;
        if (session is null || !_collecting || (_buffer.Count == 0 && (!isLast || _nextChunkIndex == 0)))
        {
            return Array.Empty<TelemetryEvent>();
        }

        var events = new List<TelemetryEvent>();
        var pieces = Split(_buffer.ToList());
        for (var i = 0; i < pieces.Count; i++)
        {
            var (frames, gzip) = pieces[i];
            events.Add(new TrackSamplesChunk(
                session.SessionRef,
                session.TrackId,
                session.SessionType,
                session.TrackLengthM,
                TrackSampleEncoder.Format,
                SampleRateHz,
                _nextChunkIndex++,
                IsLast: isLast && i == pieces.Count - 1,
                FrameCount: frames.Count,
                SampleCount: frames.Sum(f => f.Samples.Count),
                Data: Convert.ToBase64String(gzip)));
        }

        _buffer.Clear();
        _bufferedSamples = 0;
        return events;
    }

    /// <summary>프레임들을 gzip이 <see cref="MaxChunkGzipBytes"/> 안에 들어가는 조각들로 나눈다(넘으면 반씩 나눈다).</summary>
    private static List<(IReadOnlyList<TrackSampleFrame> Frames, byte[] Gzip)> Split(IReadOnlyList<TrackSampleFrame> frames)
    {
        var gzip = TrackSampleEncoder.Encode(frames);
        if (gzip.Length <= MaxChunkGzipBytes || frames.Count <= 1)
        {
            return [(frames, gzip)];
        }

        var half = frames.Count / 2;
        var result = Split(frames.Take(half).ToList());
        result.AddRange(Split(frames.Skip(half).ToList()));
        return result;
    }
}
