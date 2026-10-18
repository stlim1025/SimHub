using System.Text.Json;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 세션의 "마지막 내 랩" 값 읽기(docs/15 §11.3): Engine Wear · Setup · Conditions(날씨). 순수 계산.
/// 마지막 = 랩 번호가 가장 큰 랩(같으면 <c>SetAt</c>이 늦은 것) 중 그 값이 있는 랩.
/// </summary>
public static class LatestLapValues
{
    /// <summary>Engine Wear(%) — <c>details.damage</c> 엔진 부품 + 스냅샷 기어박스·엔진 손상. 아무 값도 없으면 null.</summary>
    public static EngineWearDto? EngineWear(IReadOnlyList<MySessionLap> myLaps)
    {
        var lap = Latest(myLaps).FirstOrDefault(l => l.EngineWear is not null || l.Row.GearboxDamage.HasValue || l.Row.EngineDamage.HasValue);
        if (lap is null)
        {
            return null;
        }

        var wear = lap.EngineWear;
        return new EngineWearDto(
            wear?.Ice,
            wear?.TurboCharger,
            wear?.MguH,
            wear?.MguK,
            wear?.EnergyStore,
            wear?.ControlElectronics,
            lap.Row.GearboxDamage,
            lap.Row.EngineDamage);
    }

    /// <summary>마지막 랩의 <c>details.setup</c> 객체(받은 그대로). 없으면 null.</summary>
    public static JsonElement? Setup(IReadOnlyList<MySessionLap> myLaps)
        => Latest(myLaps).Select(l => l.Setup).FirstOrDefault(s => s.HasValue);

    /// <summary>마지막 랩 스냅샷의 날씨 이름(<c>Weather</c> 열거형 이름). 없으면 null.</summary>
    public static string? Weather(IReadOnlyList<MySessionLap> myLaps)
        => Latest(myLaps).Select(l => l.Row.Weather).FirstOrDefault(w => w.HasValue)?.ToString();

    private static IEnumerable<MySessionLap> Latest(IReadOnlyList<MySessionLap> myLaps)
    {
        ArgumentNullException.ThrowIfNull(myLaps);
        return myLaps.OrderByDescending(l => l.LapNumber).ThenByDescending(l => l.Row.SetAt);
    }
}
