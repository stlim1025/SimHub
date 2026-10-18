using SimCenter.Agent.Core.Telemetry.Frames;

namespace SimCenter.Agent.Core.Analysis;

/// <summary>
/// 트레이스 <c>extra</c> 채널 기록(D-49, docs/15 §8). <see cref="ExtraChannelsFrame"/>마다 채널별 <b>최신 값</b>을 갱신하고,
/// <see cref="LapTraceRecorder"/>가 칸에 표본을 쓸 때 그 순간의 최신 값 묶음을 같은 칸에 찍어 둔다(<see cref="Capture"/>) — 기존 7채널과 같은 칸·같은 덮어쓰기.
/// 만들 때(<see cref="Build"/>) 채널마다 빈 칸(아직 값을 모르던 칸 포함)은 앞 값, 맨 앞은 첫 값으로 채우고, 한 칸도 값이 없는 채널은 뺀다.
/// 값은 소수 둘째 자리로 반올림하고 유한하지 않은 값은 버린다(앞 값 유지). 이름은 <c>^[A-Za-z0-9]{1,40}$</c>, 채널은 150개까지 — 백엔드 검증과 같다.
/// 최신 값은 랩을 넘어 유지하고(<see cref="ClearSamples"/>는 칸만 비운다) 세션이 바뀌면 <see cref="Reset"/>으로 모두 잊는다. 상태 저장이라 스레드 안전하지 않다.
/// </summary>
public sealed class TraceExtraChannels
{
    /// <summary>채널 수 상한(백엔드 검증, docs/15 §8). 넘는 새 채널은 버린다.</summary>
    public const int MaxChannels = 150;

    /// <summary>채널 이름 길이 상한(백엔드 검증 <c>^[A-Za-z0-9]{1,40}$</c>).</summary>
    public const int MaxNameLength = 40;

    private const int Decimals = 2;

    private readonly Dictionary<string, int> _indexByName = new(StringComparer.Ordinal);
    private readonly List<string> _names = [];
    private readonly double[] _latest = new double[MaxChannels];   // NaN = 아직 모름
    private readonly double[]?[] _buckets;

    public TraceExtraChannels(int maxSamples)
    {
        _buckets = new double[]?[maxSamples];
        Array.Fill(_latest, double.NaN);
    }

    /// <summary>채널 최신 값을 갱신한다. 유한하지 않은 값·잘못된 이름·상한을 넘는 새 채널은 버린다.</summary>
    public void Update(IReadOnlyDictionary<string, double> channels)
    {
        foreach (var (name, value) in channels)
        {
            if (!double.IsFinite(value) || IndexOf(name) is not int index)
            {
                continue;
            }

            _latest[index] = Math.Round(value, Decimals, MidpointRounding.AwayFromZero);
        }
    }

    /// <summary>지금 최신 값 묶음을 칸 <paramref name="bucket"/>에 덮어쓴다. 아는 채널이 없으면 아무것도 하지 않는다.</summary>
    public void Capture(int bucket)
    {
        var count = _names.Count;
        if (count == 0)
        {
            return;
        }

        var sample = _buckets[bucket];
        if (sample is null || sample.Length != count)
        {
            sample = new double[count];
            _buckets[bucket] = sample;
        }

        Array.Copy(_latest, sample, count);
    }

    /// <summary>칸 0 ~ <paramref name="length"/> − 1로 채널 배열을 만든다. 값이 있는 채널이 없으면 null.</summary>
    public IReadOnlyDictionary<string, IReadOnlyList<double>>? Build(int length)
    {
        var channels = new Dictionary<string, IReadOnlyList<double>>(StringComparer.Ordinal);
        for (var channel = 0; channel < _names.Count; channel++)
        {
            if (BuildChannel(channel, length) is { } values)
            {
                channels[_names[channel]] = values;
            }
        }

        return channels.Count == 0 ? null : channels;
    }

    /// <summary>칸 0 ~ <paramref name="lastFilled"/>의 묶음을 비운다(최신 값은 유지 — 다음 랩도 같은 차 상태에서 이어진다).</summary>
    public void ClearSamples(int lastFilled) => Array.Clear(_buckets, 0, lastFilled + 1);

    /// <summary>채널 이름·최신 값까지 모두 잊는다(세션 변경). 칸은 <see cref="ClearSamples"/>로 따로 비운다.</summary>
    public void Reset()
    {
        _indexByName.Clear();
        _names.Clear();
        Array.Fill(_latest, double.NaN);
    }

    private int? IndexOf(string name)
    {
        if (_indexByName.TryGetValue(name, out var known))
        {
            return known;
        }

        if (_names.Count >= MaxChannels || !IsValidName(name))
        {
            return null;
        }

        var index = _names.Count;
        _names.Add(name);
        _indexByName[name] = index;
        return index;
    }

    private static bool IsValidName(string name) =>
        name.Length is > 0 and <= MaxNameLength && name.All(char.IsAsciiLetterOrDigit);

    private double[]? BuildChannel(int channel, int length)
    {
        if (FirstValue(channel, length) is not double current)
        {
            return null;
        }

        var values = new double[length];
        for (var i = 0; i < length; i++)
        {
            current = ValueAt(i, channel) ?? current;
            values[i] = current;
        }

        return values;
    }

    private double? FirstValue(int channel, int length)
    {
        for (var i = 0; i < length; i++)
        {
            if (ValueAt(i, channel) is double value)
            {
                return value;
            }
        }

        return null;
    }

    private double? ValueAt(int bucket, int channel)
    {
        var sample = _buckets[bucket];
        return sample is not null && channel < sample.Length && !double.IsNaN(sample[channel]) ? sample[channel] : null;
    }
}
