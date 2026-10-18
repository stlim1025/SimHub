using SimCenter.Agent.Core.Telemetry.Events;
using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 1랩 거리 기준 트레이스 기록기(D-45, docs/15 §3.3). <see cref="LapAnalyzer"/>가 Lap Data마다 <see cref="UpdatePosition"/>으로 현재 거리·시간을 알려 주고,
/// Car Telemetry마다 <see cref="Record"/>로 칸 <c>floor(거리 / 5m)</c>에 표본을 <b>덮어쓴다</b>(플래시백으로 되돌아가 다시 달리면 나중 값이 이긴다).
/// 랩이 바뀌면 <see cref="Flush"/>로 LapFinished에 실을 트레이스를 만들고 비운다. 상태 저장이라 스레드 안전하지 않다(분석기와 같다).
/// </summary>
public sealed class LapTraceRecorder
{
    /// <summary>표본 간격(m).</summary>
    public const int DefaultResolutionM = 5;

    /// <summary>칸 수 상한 = 백엔드 검증의 배열 길이 상한(docs/15 §5). 이 칸을 넘는 거리(쓰레기 값)는 버린다.</summary>
    public const int MaxSamples = 5_000;

    private const int MinSamples = 2;            // 백엔드 검증의 배열 길이 하한(docs/15 §5)
    private const double MinFilledRatio = 0.5;   // 채워진 칸이 이보다 적으면 트레이스를 보내지 않는다(§3.3)
    private const float PercentScale = 100f;     // 페달 0~1 · 스티어 −1~1 → 정수 퍼센트

    // 채널 범위 = 백엔드 검증 범위(docs/15 §5). 깨진 표본 하나 때문에 트레이스 전체가 버려지지 않게 다듬는다.
    private const int MaxTimeMs = 3_600_000;
    private const int MaxSpeedKph = 500;
    private const int MaxPedalPercent = 100;
    private const int MinSteerPercent = -100;
    private const int MaxSteerPercent = 100;
    private const int ReverseGear = -1;
    private const int TopGear = 8;
    private const int MaxRpm = 25_000;

    private readonly TraceSample?[] _buckets = new TraceSample?[MaxSamples];
    private int _lastFilled = -1;
    private int _filledCount;
    private int? _currentBucket;   // null = 위치 모름(아직 Lap Data 없음, 음수 거리, 이전 랩 프레임)
    private int _currentLapTimeMs;

    /// <summary>가장 최근 Lap Data의 거리·시간. 음수(출발선 전)·NaN·상한 밖 거리면 위치를 모르는 것으로 둔다.</summary>
    public void UpdatePosition(float lapDistanceM, int currentLapTimeMs)
    {
        _currentBucket = ToBucket(lapDistanceM);
        _currentLapTimeMs = currentLapTimeMs;
    }

    /// <summary>위치를 모르는 상태로 둔다 — 다음 <see cref="UpdatePosition"/> 전까지 표본을 버린다.</summary>
    public void ClearPosition() => _currentBucket = null;

    /// <summary>현재 위치의 칸에 표본을 덮어쓴다. 위치를 모르면 버린다.</summary>
    public void Record(CarTelemetryFrame frame)
    {
        if (_currentBucket is not int bucket)
        {
            return;
        }

        if (_buckets[bucket] is null)
        {
            _filledCount++;
        }

        _buckets[bucket] = ToSample(frame, _currentLapTimeMs);
        _lastFilled = Math.Max(_lastFilled, bucket);
    }

    /// <summary>
    /// 지금까지의 표본으로 트레이스를 만들고 버퍼·위치를 비운다. 길이 = 채워진 마지막 칸 + 1, 빈 칸은 앞 값(맨 앞이 비면 첫 값)으로 채운다.
    /// 칸이 2개 미만이거나 채워진 칸이 50% 미만이면 null.
    /// </summary>
    public LapTrace? Flush()
    {
        var trace = Build();
        Clear();
        return trace;
    }

    /// <summary>표본·위치를 모두 버린다(세션 변경 등).</summary>
    public void Clear()
    {
        Array.Clear(_buckets, 0, _lastFilled + 1);
        _lastFilled = -1;
        _filledCount = 0;
        _currentBucket = null;
    }

    private LapTrace? Build()
    {
        var length = _lastFilled + 1;
        if (length < MinSamples || _filledCount < length * MinFilledRatio)
        {
            return null;
        }

        var time = new int[length];
        var speed = new int[length];
        var throttle = new int[length];
        var brake = new int[length];
        var steer = new int[length];
        var gear = new int[length];
        var rpm = new int[length];

        var current = FirstFilled();
        for (var i = 0; i < length; i++)
        {
            current = _buckets[i] ?? current;
            (time[i], speed[i], throttle[i], brake[i], steer[i], gear[i], rpm[i]) = current;
        }

        return new LapTrace(DefaultResolutionM, time, speed, throttle, brake, steer, gear, rpm);
    }

    private TraceSample FirstFilled()
    {
        foreach (var sample in _buckets)
        {
            if (sample is { } filled)
            {
                return filled;
            }
        }

        throw new InvalidOperationException("채워진 칸이 없는데 트레이스를 만들려 했습니다.");
    }

    private static int? ToBucket(float lapDistanceM)
    {
        if (!float.IsFinite(lapDistanceM) || lapDistanceM < 0f)
        {
            return null;
        }

        var bucket = Math.Floor(lapDistanceM / DefaultResolutionM);
        return bucket < MaxSamples ? (int)bucket : null;
    }

    private static TraceSample ToSample(CarTelemetryFrame frame, int currentLapTimeMs) => new(
        TimeMs: Math.Clamp(currentLapTimeMs, 0, MaxTimeMs),
        SpeedKph: Math.Clamp(frame.SpeedKph, 0, MaxSpeedKph),
        Throttle: ToPercent(frame.Throttle, 0, MaxPedalPercent),
        Brake: ToPercent(frame.Brake, 0, MaxPedalPercent),
        Steer: ToPercent(frame.Steer, MinSteerPercent, MaxSteerPercent),
        Gear: Math.Clamp(frame.Gear, ReverseGear, TopGear),
        Rpm: Math.Clamp(frame.EngineRpm, 0, MaxRpm));

    /// <summary>비율(0~1, −1~1) → 정수 퍼센트(사사오입). NaN은 0.</summary>
    private static int ToPercent(float ratio, int min, int max)
    {
        if (float.IsNaN(ratio))
        {
            return 0;
        }

        var percent = MathF.Round(ratio * PercentScale, MidpointRounding.AwayFromZero);
        return (int)Math.Clamp(percent, min, max);
    }

    /// <summary>한 칸의 표본(이미 트레이스 정수 단위).</summary>
    private readonly record struct TraceSample(int TimeMs, int SpeedKph, int Throttle, int Brake, int Steer, int Gear, int Rpm);
}
