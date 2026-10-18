using F1Game.UDP.Data;
using F1Game.UDP.Packets;

namespace SimCenter.Agent.Infrastructure.Mapping;

/// <summary>
/// Session 패킷의 날씨 예보 샘플에서 "비 예보"(LapFinished <c>conditions.rainForecastPercent</c>)를 고른다(docs/15 §3.1):
/// 현재 세션 종류의 샘플 중 <c>TimeOffset &gt; 0</c>(앞으로)인 가장 이른 샘플의 비 확률. 없으면 그 세션 종류의 첫 샘플, 그것도 없으면 null.
/// 샘플 수(<c>NumWeatherForecastSamples</c>)를 넘는 칸은 쓰레기라 보지 않는다.
/// </summary>
internal static class RainForecast
{
    public static int? Select(SessionDataPacket packet)
    {
        var slots = packet.WeatherForecastSamples.AsReadOnlySpan();
        var count = Math.Min((int)packet.NumWeatherForecastSamples, slots.Length);

        WeatherForecastSample? first = null;
        WeatherForecastSample? earliestFuture = null;
        foreach (var sample in slots[..count])
        {
            if (sample.SessionType != packet.SessionType)
            {
                continue;
            }

            first ??= sample;
            if (sample.TimeOffset > 0 && (earliestFuture is null || sample.TimeOffset < earliestFuture.Value.TimeOffset))
            {
                earliestFuture = sample;
            }
        }

        return (earliestFuture ?? first)?.RainPercentage;
    }
}
