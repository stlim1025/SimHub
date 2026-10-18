using F1Game.UDP.Data;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// <c>car.details</c> 묶음 하나를 만드는 지역 빌더(D-49, docs/15 §8). 값 하나 = 한 줄. 열거형은 게임 원시 정수로 싣고(뜻은 F1 25 UDP 스펙),
/// 실수는 그대로 넘긴다(Core가 셋째 자리 반올림·유한하지 않으면 null). 바퀴 4개는 <see cref="ChannelBag"/>와 같은 접미사(FL·FR·RL·RR)를 붙인다.
/// 만든 사전은 프레임에 그대로 실려 나가므로 <see cref="Build"/> 뒤에는 쓰지 않는다(한 번 쓰고 버리는 빌더).
/// </summary>
internal sealed class DetailBag
{
    private readonly Dictionary<string, object?> _values = new(StringComparer.Ordinal);

    public DetailBag Add(string key, object? value)
    {
        _values[key] = value;
        return this;
    }

    public DetailBag AddWheels<T>(string key, Tyres<T> wheels, Func<T, object?> toValue)
        where T : unmanaged
    {
        Add(key + WheelSuffix.FrontLeft, toValue(wheels.FrontLeft));
        Add(key + WheelSuffix.FrontRight, toValue(wheels.FrontRight));
        Add(key + WheelSuffix.RearLeft, toValue(wheels.RearLeft));
        return Add(key + WheelSuffix.RearRight, toValue(wheels.RearRight));
    }

    public IReadOnlyDictionary<string, object?> Build() => _values;
}
