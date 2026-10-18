using F1Game.UDP.Data;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// 트레이스 extra 채널 묶음을 만드는 지역 빌더(D-49, docs/15 §8). 채널 하나 = 한 줄 — 채널을 더할 때는 <see cref="F1ExtraChannels"/>에 한 줄을 더한다.
/// 값은 지정한 소수 자리로 반올림한다(Core가 다시 둘째 자리로 자르고 유한하지 않은 값은 버린다). 바퀴 4개는 이름 끝에 <c>FL·FR·RL·RR</c>를 붙인다 —
/// 라이브러리 <c>Tyres&lt;T&gt;</c>가 UDP 순서(RL·RR·FL·FR)를 이름으로 풀어 두므로 여기서도 이름으로 옮긴다.
/// 만든 사전은 프레임에 그대로 실려 나가므로 <see cref="Build"/> 뒤에는 쓰지 않는다(한 번 쓰고 버리는 빌더).
/// </summary>
internal sealed class ChannelBag
{
    /// <summary>기본 소수 자리(계약 상한, docs/15 §8).</summary>
    public const int DefaultDecimals = 2;

    private readonly Dictionary<string, double> _channels = new(StringComparer.Ordinal);

    public ChannelBag Add(string name, double value, int decimals = DefaultDecimals)
    {
        _channels[name] = Math.Round(value, decimals, MidpointRounding.AwayFromZero);
        return this;
    }

    public ChannelBag Add(string name, bool value) => Add(name, value ? 1 : 0);

    /// <summary>바퀴 4개 값 — <c>{name}FL</c> · <c>FR</c> · <c>RL</c> · <c>RR</c>.</summary>
    public ChannelBag AddWheels<T>(string name, Tyres<T> wheels, Func<T, double> toValue, int decimals = DefaultDecimals)
        where T : unmanaged
    {
        Add(name + WheelSuffix.FrontLeft, toValue(wheels.FrontLeft), decimals);
        Add(name + WheelSuffix.FrontRight, toValue(wheels.FrontRight), decimals);
        Add(name + WheelSuffix.RearLeft, toValue(wheels.RearLeft), decimals);
        return Add(name + WheelSuffix.RearRight, toValue(wheels.RearRight), decimals);
    }

    public IReadOnlyDictionary<string, double> Build() => _channels;
}

/// <summary>바퀴 이름 접미사(extra 채널·details 공통, docs/15 §8).</summary>
internal static class WheelSuffix
{
    public const string FrontLeft = "FL";
    public const string FrontRight = "FR";
    public const string RearLeft = "RL";
    public const string RearRight = "RR";
}
