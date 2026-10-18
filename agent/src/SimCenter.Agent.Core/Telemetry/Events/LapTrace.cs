namespace SimCenter.Agent.Core.Telemetry.Events;

/// <summary>
/// 1랩 거리 기준 텔레메트리 트레이스 — LapFinished <c>trace</c>(D-45, docs/15 §3.3·§4.3). i번째 칸 = 랩 거리 i × <see cref="ResolutionM"/>m.
/// 7채널 정수 배열은 모두 같은 길이다: <c>timeMs</c>(랩 시작부터) · <c>speedKph</c> · <c>throttle</c>(0~100) · <c>brake</c>(0~100) ·
/// <c>steer</c>(−100~100) · <c>gear</c>(−1~8, 0=N, −1=R) · <c>rpm</c>.
/// <see cref="Extra"/>(D-49, docs/15 §8)는 이름 붙은 채널 묶음 <c>{ 이름: number[] }</c>이다 — 7채널과 같은 길이·같은 칸, 값은 유한 숫자(소수 둘째 자리까지).
/// 채널 목록·단위는 <c>shared/telemetry/f1_25_udp_spec.md</c> 카탈로그가 정한다. 없으면 null.
/// wire 모양을 계약 그대로 두려고 계산 속성은 두지 않는다(공개 속성은 모두 직렬화된다).
/// </summary>
public sealed record LapTrace(
    int ResolutionM,
    IReadOnlyList<int> TimeMs,
    IReadOnlyList<int> SpeedKph,
    IReadOnlyList<int> Throttle,
    IReadOnlyList<int> Brake,
    IReadOnlyList<int> Steer,
    IReadOnlyList<int> Gear,
    IReadOnlyList<int> Rpm,
    IReadOnlyDictionary<string, IReadOnlyList<double>>? Extra = null)
{
    private const int DownsampleFactor = 2;

    /// <summary>
    /// 표본을 하나 걸러 버려(0, 2, 4 … 칸만 남김) 해상도를 두 배로 낮춘 새 트레이스. 봉투 한도를 넘을 때 싱크가 쓴다(5m → 10m → 20m).
    /// 남긴 칸 j의 거리 = 2j × 옛 해상도 = j × 새 해상도라 거리 축이 그대로 맞는다. extra 채널도 같은 칸을 남긴다. 원본은 바꾸지 않는다.
    /// </summary>
    public LapTrace Downsample() => new(
        ResolutionM * DownsampleFactor,
        KeepEveryOther(TimeMs),
        KeepEveryOther(SpeedKph),
        KeepEveryOther(Throttle),
        KeepEveryOther(Brake),
        KeepEveryOther(Steer),
        KeepEveryOther(Gear),
        KeepEveryOther(Rpm),
        Extra?.ToDictionary(channel => channel.Key, channel => (IReadOnlyList<double>)KeepEveryOther(channel.Value), StringComparer.Ordinal));

    private static T[] KeepEveryOther<T>(IReadOnlyList<T> channel)
    {
        var kept = new T[(channel.Count + DownsampleFactor - 1) / DownsampleFactor];
        for (var i = 0; i < kept.Length; i++)
        {
            kept[i] = channel[i * DownsampleFactor];
        }

        return kept;
    }
}
