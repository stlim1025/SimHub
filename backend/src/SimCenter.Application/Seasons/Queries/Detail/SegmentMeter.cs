namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>한 랩·한 구간의 측정값(<see cref="SegmentMeter.Measure"/>). 바퀴 배열은 앞왼·앞오·뒤왼·뒤오, 채널이 없으면 null.</summary>
internal sealed record SegmentLap(
    int TimeMs,
    double[]? WheelWorkJ,
    double SteerPct,
    double? UndersteerDeg,
    double? LockupM,
    double? WheelspinM,
    double TrailBrakeM,
    double ThrottleSteerM,
    double BrakeM,
    double? KerbM,
    double[]? PeakSurfaceTempC,
    int MinSpeedKph,
    int EndSpeedKph,
    double? HarvestJ,
    double? DeployJ,
    double? OvertakeM,
    double? NoDeployM,
    double? StoreEndJ,
    double? EmptyM,
    double LiftM = 0,
    double? FastOvertakeM = null);

/// <summary>한 랩 전체의 타이어 값: 바퀴별 마찰 일(J)·최고 표면 온도·평균 속 온도(°C). 채널이 없으면 null.</summary>
internal sealed record LapTyreLoad(double[]? WheelWorkJ, double[]? PeakSurfaceTempC, double[]? InnerTempC);

/// <summary>
/// 랩 트레이스 측정(순수 계산). 타이어 부담 = 바퀴 마찰 일(J) = Σ(|횡력|·|tan 슬립각| + |종력|·|슬립률|)·표본 간격 —
/// 타이어가 미끄러지며 노면에 한 일이라 마모·발열과 함께 간다(실제 레이스에서 랩·바퀴별 마모와 상관 0.8).
/// 입력 판정: 앞 바퀴 슬립률 ≤ <see cref="LockupSlipPct"/>%면 락업, 스로틀 ≥ <see cref="WheelspinThrottlePct"/>%에서 뒤 바퀴 슬립률 ≥
/// <see cref="WheelspinSlipPct"/>%면 휠스핀, 브레이크 ≥ <see cref="TrailBrakePct"/>%에 조향 ≥ <see cref="TrailSteerPct"/>%면 브레이크 밟은 채 조향,
/// 스로틀 ≥ <see cref="FullThrottlePct"/>%에 조향 ≥ <see cref="ThrottleSteerPct"/>%면 풀 스로틀로 조향, 노면 1(럼블)이면 연석,
/// 스로틀 &lt; <see cref="LiftThrottlePct"/>%면 완전히 뗀 것(브레이크 포함 — 회수가 크게 일어나는 상태),
/// Overtake 모드로 <see cref="FastSpeedKph"/>km/h 이상 달린 거리(같은 배터리로 버는 시간이 가장 적은 사용).
/// 시간·배터리는 표본과 바로 앞 표본 사이 변화를 더한다(구간에 들어서는 한 칸 포함, 랩 첫 표본은 짝이 없다).
/// 배터리 채움·씀 = 잔량이 늘어난·줄어든 양의 합 — 다른 차들(<see cref="FieldErsProfile"/>, 표본에 잔량만 있다)과 같은 기준으로 견주려고
/// 게임의 랩 누적 회수·배포 채널 대신 잔량 변화를 쓴다.
/// </summary>
internal static class SegmentMeter
{
    private const double LockupSlipPct = -12;
    private const double WheelspinSlipPct = 8;
    private const int WheelspinThrottlePct = 50;
    private const int TrailBrakePct = 10;
    private const int TrailSteerPct = 15;
    private const int FullThrottlePct = 80;
    private const int ThrottleSteerPct = 20;
    private const int RumbleSurface = 1;
    private const int LiftThrottlePct = 5;
    private const int FastSpeedKph = 280;

    /// <summary>코너링 중으로 볼 횡 G(언더스티어는 이 표본만 본다).</summary>
    private const double CorneringLateralG = 1.5;

    /// <summary>스핀 같은 큰 슬립각에서 tan이 튀지 않게 자르는 각(°).</summary>
    private const double MaxSlipAngleDeg = 45;

    private const double PercentScale = 100;
    private const double DegreesPerRadian = 180;

    /// <summary>ERS 배포 모드 None·Overtake(게임 원시 값), 배터리 용량(J)과 거의 바닥으로 볼 비율.</summary>
    private const int DeployModeNone = 0;
    private const int DeployModeOvertake = 3;
    private const double ErsCapacityJ = 4_000_000;
    private const double EmptyStoreFraction = 0.05;

    private const int FrontLeft = 0;
    private const int FrontRight = 1;
    private const int RearLeft = 2;
    private const int RearRight = 3;

    public static SegmentLap Measure(RaceTraceLap lap, SegmentRange segment)
    {
        ArgumentNullException.ThrowIfNull(lap);
        ArgumentNullException.ThrowIfNull(segment);

        var c = lap.Channels;
        var resolution = lap.ResolutionM;
        var lateralForce = TraceChannelNames.WheelChannels(lap, TraceChannelNames.LateralForce);
        var longitudinalForce = TraceChannelNames.WheelChannels(lap, TraceChannelNames.LongitudinalForce);
        var slipAngle = TraceChannelNames.WheelChannels(lap, TraceChannelNames.SlipAngle);
        var slipRatio = TraceChannelNames.WheelChannels(lap, TraceChannelNames.SlipRatio);
        var surfaceTemp = TraceChannelNames.WheelChannels(lap, TraceChannelNames.SurfaceTemp);
        var surface = TraceChannelNames.WheelChannels(lap, TraceChannelNames.Surface);
        var lateralG = lap.Extra(TraceChannelNames.LateralG);
        var store = lap.Extra(TraceChannelNames.ErsStore);
        var mode = lap.Extra(TraceChannelNames.ErsDeployMode);
        var hasWork = lateralForce is not null && longitudinalForce is not null && slipAngle is not null && slipRatio is not null;
        var wheelCount = TraceChannelNames.Wheels.Length;

        var work = hasWork ? new double[wheelCount] : null;
        var peak = surfaceTemp is null ? null : Enumerable.Repeat(double.MinValue, wheelCount).ToArray();
        double time = 0, steer = 0, understeer = 0, lockup = 0, wheelspin = 0, trail = 0, throttleSteer = 0, braking = 0, kerb = 0;
        double harvest = 0, deploy = 0, overtake = 0, fastOvertake = 0, noDeploy = 0, empty = 0, lift = 0;
        int samples = 0, cornering = 0, minSpeed = int.MaxValue, endIndex = -1;

        foreach (var (from, to) in segment.Runs(lap.Count))
        {
            for (var i = from; i <= to; i++)
            {
                if (i > 0)
                {
                    time += c.TimeMs[i] - c.TimeMs[i - 1];
                    if (store is not null)
                    {
                        var change = store[i] - store[i - 1];
                        harvest += Math.Max(0, change);
                        deploy += Math.Max(0, -change);
                    }
                }

                samples++;
                steer += Math.Abs(c.Steer[i]);
                minSpeed = Math.Min(minSpeed, c.SpeedKph[i]);
                endIndex = i;
                if (c.Throttle[i] < LiftThrottlePct)
                {
                    lift += resolution;
                }
                if (c.Brake[i] >= TrailBrakePct)
                {
                    braking += resolution;
                    if (Math.Abs(c.Steer[i]) >= TrailSteerPct)
                    {
                        trail += resolution;
                    }
                }

                if (c.Throttle[i] >= FullThrottlePct && Math.Abs(c.Steer[i]) >= ThrottleSteerPct)
                {
                    throttleSteer += resolution;
                }

                if (work is not null)
                {
                    for (var w = 0; w < wheelCount; w++)
                    {
                        var angle = Math.Clamp(slipAngle![w][i], -MaxSlipAngleDeg, MaxSlipAngleDeg) * Math.PI / DegreesPerRadian;
                        work[w] += (Math.Abs(lateralForce![w][i] * Math.Tan(angle))
                                    + Math.Abs(longitudinalForce![w][i] * slipRatio![w][i] / PercentScale)) * resolution;
                    }
                }

                if (slipRatio is not null)
                {
                    if (Math.Min(slipRatio[FrontLeft][i], slipRatio[FrontRight][i]) <= LockupSlipPct && c.Brake[i] > 0)
                    {
                        lockup += resolution;
                    }

                    if (c.Throttle[i] >= WheelspinThrottlePct && Math.Max(slipRatio[RearLeft][i], slipRatio[RearRight][i]) >= WheelspinSlipPct)
                    {
                        wheelspin += resolution;
                    }
                }

                if (slipAngle is not null && lateralG is not null && Math.Abs(lateralG[i]) >= CorneringLateralG)
                {
                    understeer += (Math.Abs(slipAngle[FrontLeft][i]) + Math.Abs(slipAngle[FrontRight][i])
                                   - Math.Abs(slipAngle[RearLeft][i]) - Math.Abs(slipAngle[RearRight][i])) / 2;
                    cornering++;
                }

                if (surface is not null && surface.Any(s => (int)s[i] == RumbleSurface))
                {
                    kerb += resolution;
                }

                if (peak is not null)
                {
                    for (var w = 0; w < wheelCount; w++)
                    {
                        peak[w] = Math.Max(peak[w], surfaceTemp![w][i]);
                    }
                }

                if (mode is not null)
                {
                    overtake += (int)mode[i] == DeployModeOvertake ? resolution : 0;
                    fastOvertake += (int)mode[i] == DeployModeOvertake && c.SpeedKph[i] >= FastSpeedKph ? resolution : 0;
                    noDeploy += (int)mode[i] == DeployModeNone ? resolution : 0;
                }

                if (store is not null && store[i] < ErsCapacityJ * EmptyStoreFraction)
                {
                    empty += resolution;
                }
            }
        }

        if (samples == 0)
        {
            return new SegmentLap(0, null, 0, null, null, null, 0, 0, 0, null, null, 0, 0, null, null, null, null, null, null);
        }

        var hasErs = store is not null;
        return new SegmentLap(
            (int)Math.Round(time),
            work,
            steer / samples,
            cornering == 0 ? null : understeer / cornering,
            slipRatio is null ? null : lockup,
            slipRatio is null ? null : wheelspin,
            trail,
            throttleSteer,
            braking,
            surface is null ? null : kerb,
            peak,
            minSpeed,
            c.SpeedKph[endIndex],
            hasErs ? harvest : null,
            hasErs ? deploy : null,
            mode is null ? null : overtake,
            mode is null ? null : noDeploy,
            store?[endIndex],
            store is null ? null : empty,
            lift,
            mode is null ? null : fastOvertake);
    }

    /// <summary>랩 전체의 바퀴별 마찰 일·최고 표면 온도·평균 속 온도.</summary>
    public static LapTyreLoad LapTyres(RaceTraceLap lap)
    {
        ArgumentNullException.ThrowIfNull(lap);
        var measured = Measure(lap, new SegmentRange(0, IsCorner: false, 0, lap.Count - 1));
        var inner = TraceChannelNames.WheelChannels(lap, TraceChannelNames.InnerTemp);
        return new LapTyreLoad(
            measured.WheelWorkJ,
            measured.PeakSurfaceTempC,
            inner?.Select(values => values.Length == 0 ? 0 : values.Average()).ToArray());
    }
}
