using SimCenter.Application.Laps;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 세션 표본에서 다른 차의 랩 하나를 내 랩 트레이스와 같은 모양(5m 간격 채널)으로 복원한다(순수 계산).
/// 결승선은 랩 거리가 트랙 길이 끝에서 0 근처로 떨어지는 곳이고, 통과 시각은 앞뒤 표본 사이에서 거리로 보간한다.
/// 그 차의 베스트 랩 타임(순위표)이 있으면 그와 가장 가까운 랩을 고르고, 랩 끝 표본이 없으면(피트로 들어가 표본이 끊김)
/// 베스트 랩 타임에 끝나도록 마지막 구간을 잇는다. 조향·RPM·ERS는 그 열이 있는 표본(format 5)일 때만 채운다.
/// </summary>
public static class FieldLapBuilder
{
    public const int ResolutionM = 5;

    /// <summary>이보다 길게 표본이 끊기면 같은 주행이 아니다(차고·관전 등).</summary>
    private const int MaxGapMs = 2000;

    /// <summary>끝난 랩의 시간이 베스트 랩 타임과 이 안이어야 그 랩으로 본다.</summary>
    private const int MaxLapTimeDifferenceMs = 1000;

    /// <summary>끝이 없는 랩은 트랙 길이의 이 비율 이상 표본이 있어야 쓴다.</summary>
    private const double MinOpenLapCoverage = 0.9;

    /// <summary>랩 하나에 이보다 표본이 적으면 복원하지 않는다.</summary>
    private const int MinLapSamples = 20;

    /// <summary>끝 표본이 없는 랩의 남은 시간 어림: km/h → m/s, 너무 느린 마지막 속도의 하한(m/s), ms.</summary>
    private const double KphPerMetresPerSecond = 3.6;
    private const double MinSpeedMetresPerSecond = 1;
    private const double MillisecondsPerSecond = 1000;

    /// <summary>ERS kJ → 트레이스 채널(J).</summary>
    private const double JoulesPerKilojoule = 1000;

    private const string WorldPosXChannel = "worldPosX";
    private const string WorldPosYChannel = "worldPosY";
    private const string WorldPosZChannel = "worldPosZ";
    private const string ErsStoreChannel = "ersStoreEnergy";
    private const string ErsDeployedChannel = "ersDeployedThisLap";
    private const int PositionDigits = 1;

    private readonly record struct Point(
        double TimeMs, double DistanceM, double X, double Z, double? Y,
        double Speed, int Gear, double Throttle, double Brake, double? Steer, double? Rpm, double? ErsKj);

    /// <summary>
    /// 그 차의 표본이 없거나 쓸 만한 랩이 없으면 null. [bestLapTimeMs]는 모르면 null(끝난 랩 가운데 가장 빠른 랩).
    /// [trackLengthM]은 게임이 알려 준 트랙 길이(모르면 표본 가운데 가장 먼 랩 거리 — 결승선 직전 표본까지라 조금 짧다).
    /// </summary>
    public static LapTraceChannels? Build(
        IReadOnlyList<DecodedTrackSamples> chunks, int carIndex, int? bestLapTimeMs, double? trackLengthM = null)
    {
        var trackLength = trackLengthM ?? chunks.SelectMany(c => c.LapDistanceM).DefaultIfEmpty(0).Max();
        if (trackLength <= ResolutionM)
        {
            return null;
        }

        var samples = new List<Point>();
        foreach (var chunk in chunks)
        {
            for (var i = 0; i < chunk.Count; i++)
            {
                if (chunk.CarIndex[i] != carIndex)
                {
                    continue;
                }

                samples.Add(new Point(
                    chunk.TimeMs[i],
                    chunk.LapDistanceM[i],
                    chunk.X[i],
                    chunk.Z[i],
                    chunk.Y?[i],
                    chunk.SpeedKph?[i] ?? 0,
                    chunk.Gear?[i] ?? 0,
                    chunk.Throttle?[i] ?? 0,
                    chunk.Brake?[i] ?? 0,
                    chunk.Steer?[i],
                    chunk.Rpm?[i],
                    chunk.ErsStoreKj?[i]));
            }
        }

        samples.Sort((a, b) => a.TimeMs.CompareTo(b.TimeMs));
        var lap = ChooseLap(samples, trackLength, bestLapTimeMs);
        return lap is null ? null : Resample(lap, trackLength);
    }

    /// <summary>결승선 통과마다 랩 하나: 통과 지점(거리 0, 시간 0)부터 다음 통과(거리 = 트랙 길이)까지의 점들. 가장 맞는 랩을 고른다.</summary>
    private static List<Point>? ChooseLap(List<Point> samples, double trackLength, int? bestLapTimeMs)
    {
        (List<Point> Points, double Score)? best = null;
        var crossings = new List<(int Index, double TimeMs, Point Line)>();
        for (var k = 1; k < samples.Count; k++)
        {
            var before = samples[k - 1];
            var after = samples[k];
            if (before.DistanceM - after.DistanceM > trackLength / 2 && after.TimeMs - before.TimeMs <= MaxGapMs)
            {
                var toLine = trackLength - before.DistanceM;
                var span = toLine + after.DistanceM;
                var t = span <= 0 ? 0 : toLine / span;
                crossings.Add((k, Lerp(before.TimeMs, after.TimeMs, t), Interpolate(before, after, t)));
            }
        }

        for (var c = 0; c < crossings.Count; c++)
        {
            var (start, startMs, line) = crossings[c];
            var points = new List<Point> { line with { TimeMs = 0, DistanceM = 0 } };
            var end = start;
            for (; end < samples.Count; end++)
            {
                if (end > start && (samples[end].TimeMs - samples[end - 1].TimeMs > MaxGapMs
                                    || samples[end - 1].DistanceM - samples[end].DistanceM > trackLength / 2))
                {
                    break;
                }

                // 랩 안에서 거리가 뒤로 가는 표본(되돌아감·튐)은 건너뛴다.
                if (samples[end].DistanceM > points[^1].DistanceM)
                {
                    points.Add(samples[end] with { TimeMs = samples[end].TimeMs - startMs });
                }
            }

            if (points.Count < MinLapSamples)
            {
                continue;
            }

            var finished = c + 1 < crossings.Count && crossings[c + 1].Index == end;
            double score;
            if (finished)
            {
                var lapTimeMs = crossings[c + 1].TimeMs - startMs;
                if (bestLapTimeMs is { } target && Math.Abs(lapTimeMs - target) > MaxLapTimeDifferenceMs)
                {
                    continue;
                }

                score = bestLapTimeMs is { } goal ? Math.Abs(lapTimeMs - goal) : lapTimeMs;
                points.Add(crossings[c + 1].Line with { TimeMs = lapTimeMs, DistanceM = trackLength });
            }
            else
            {
                // 끝 표본이 없는 랩: 베스트 랩 타임을 알고, 거의 다 달렸고, 마지막 속도로 남은 거리를 달리면
                // 그 시간 언저리에 끝나야 베스트 랩으로 본다(인랩·느린 랩에 베스트 랩 타임을 덧붙이지 않게).
                if (bestLapTimeMs is not { } target
                    || points[^1].DistanceM < trackLength * MinOpenLapCoverage
                    || points[^1].TimeMs >= target)
                {
                    continue;
                }

                var lastSpeedMs = Math.Max(points[^1].Speed / KphPerMetresPerSecond, MinSpeedMetresPerSecond);
                var predictedMs = points[^1].TimeMs + (trackLength - points[^1].DistanceM) / lastSpeedMs * MillisecondsPerSecond;
                if (Math.Abs(predictedMs - target) > MaxLapTimeDifferenceMs)
                {
                    continue;
                }

                // 끝난 랩이 맞으면 그쪽을 먼저 고른다.
                score = MaxLapTimeDifferenceMs + (trackLength - points[^1].DistanceM);
                points.Add(points[^1] with { TimeMs = target, DistanceM = trackLength, X = line.X, Z = line.Z, Y = line.Y });
            }

            if (best is null || score < best.Value.Score)
            {
                best = (points, score);
            }
        }

        return best?.Points;
    }

    /// <summary>점들을 거리 0, 5, 10, …m에서 다시 뽑는다(앞뒤 점 선형 보간, 기어는 앞 점).</summary>
    private static LapTraceChannels Resample(List<Point> points, double trackLength)
    {
        var count = (int)Math.Floor(trackLength / ResolutionM) + 1;
        var time = new int[count];
        var speed = new int[count];
        var throttle = new int[count];
        var brake = new int[count];
        var steer = new int[count];
        var gear = new int[count];
        var rpm = new int[count];
        var x = new double[count];
        var y = new double[count];
        var z = new double[count];
        var ers = new double[count];
        var deployed = new double[count];
        var hasY = points.All(p => p.Y.HasValue);
        var hasErs = points.All(p => p.ErsKj.HasValue);

        var segment = 0;
        for (var i = 0; i < count; i++)
        {
            var distance = (double)i * ResolutionM;
            while (segment < points.Count - 2 && points[segment + 1].DistanceM < distance)
            {
                segment++;
            }

            var a = points[segment];
            var b = points[segment + 1];
            var span = b.DistanceM - a.DistanceM;
            var t = span <= 0 ? 0 : Math.Clamp((distance - a.DistanceM) / span, 0, 1);
            var p = Interpolate(a, b, t);
            time[i] = (int)Math.Round(p.TimeMs);
            speed[i] = (int)Math.Round(p.Speed);
            throttle[i] = (int)Math.Round(p.Throttle);
            brake[i] = (int)Math.Round(p.Brake);
            steer[i] = (int)Math.Round(p.Steer ?? 0);
            gear[i] = a.Gear;
            rpm[i] = (int)Math.Round(p.Rpm ?? 0);
            x[i] = Math.Round(p.X, PositionDigits);
            y[i] = Math.Round(p.Y ?? 0, PositionDigits);
            z[i] = Math.Round(p.Z, PositionDigits);
            ers[i] = Math.Round((p.ErsKj ?? 0) * JoulesPerKilojoule);
            // 이번 랩 배포량 ≈ 잔량이 줄어든 만큼의 합(회수와 겹치는 구간은 순감만 센다).
            deployed[i] = i == 0 ? 0 : deployed[i - 1] + Math.Max(0, ers[i - 1] - ers[i]);
        }

        var extra = new Dictionary<string, double[]>
        {
            [WorldPosXChannel] = x,
            [WorldPosZChannel] = z,
        };
        if (hasY)
        {
            extra[WorldPosYChannel] = y;
        }

        if (hasErs)
        {
            extra[ErsStoreChannel] = ers;
            extra[ErsDeployedChannel] = deployed;
        }

        return new LapTraceChannels(time, speed, throttle, brake, steer, gear, rpm, extra);
    }

    private static Point Interpolate(Point a, Point b, double t) => new(
        Lerp(a.TimeMs, b.TimeMs, t),
        Lerp(a.DistanceM, b.DistanceM, t),
        Lerp(a.X, b.X, t),
        Lerp(a.Z, b.Z, t),
        a.Y is { } ay && b.Y is { } by ? Lerp(ay, by, t) : a.Y ?? b.Y,
        Lerp(a.Speed, b.Speed, t),
        t < 1 ? a.Gear : b.Gear,
        Lerp(a.Throttle, b.Throttle, t),
        Lerp(a.Brake, b.Brake, t),
        a.Steer is { } asr && b.Steer is { } bsr ? Lerp(asr, bsr, t) : a.Steer ?? b.Steer,
        a.Rpm is { } ar && b.Rpm is { } br ? Lerp(ar, br, t) : a.Rpm ?? b.Rpm,
        a.ErsKj is { } ae && b.ErsKj is { } be ? Lerp(ae, be, t) : a.ErsKj ?? b.ErsKj);

    private static double Lerp(double a, double b, double t) => a + (b - a) * t;
}
