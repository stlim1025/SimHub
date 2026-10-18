using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Laps.Ingest;

/// <summary>
/// LapFinished의 선택 영역(<c>car</c>·<c>conditions</c>·<c>trace</c>, 15 §4.3)을 해석·검증해 저장할 엔티티로 만든다(15 §5, D-44, D-45).
/// 영역은 raw JSON으로 받아 따로 해석한다 — 모양이 틀려도 랩 파싱이 실패하지 않게 한다.
/// 해석·검증에 실패한 영역은 <b>그 영역만</b> 버리고 경고 로그를 남긴다. 랩은 절대 거부하지 않는다(랩 기록이 본체, 나머지는 덤).
/// </summary>
public sealed class LapDetailExtractor
{
    public const string CarPart = "car";
    public const string ConditionsPart = "conditions";
    public const string TracePart = "trace";

    private static readonly JsonSerializerOptions PartOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly IIdGenerator _idGenerator;
    private readonly ILogger<LapDetailExtractor> _logger;

    public LapDetailExtractor(IIdGenerator idGenerator, ILogger<LapDetailExtractor> logger)
    {
        _idGenerator = idGenerator;
        _logger = logger;
    }

    /// <summary>
    /// 차량·날씨 스냅샷. 두 영역 중 맞는 영역만 담는다. 남는 값이 없으면(둘 다 없거나 버림) null — 행을 만들지 않는다.
    /// </summary>
    public LapSnapshot? BuildSnapshot(Guid eventId, JsonElement? car, JsonElement? conditions, Guid lapId, DateTime now)
    {
        var carPart = ParseValid<LapCarPayload>(eventId, CarPart, car, LapSnapshotValidator.Validate);
        var conditionsPart = ParseValid<LapConditionsPayload>(eventId, ConditionsPart, conditions, LapSnapshotValidator.Validate);
        if (carPart is null && conditionsPart is null)
        {
            return null;
        }

        var snapshot = new LapSnapshot { Id = _idGenerator.NewId(), LapId = lapId, CreatedAt = now };
        if (carPart is not null)
        {
            ApplyCar(snapshot, carPart);
        }

        if (conditionsPart is not null)
        {
            ApplyConditions(eventId, snapshot, conditionsPart);
        }

        var hasValues = snapshot.TeamId.HasValue || snapshot.HasCarData() || snapshot.HasConditionsData();
        return hasValues ? snapshot : null;
    }

    /// <summary>텔레메트리 트레이스. 없거나 틀리면 null.</summary>
    public LapTelemetryTrace? BuildTrace(Guid eventId, JsonElement? trace, Guid lapId, DateTime now)
    {
        var part = ParseValid<LapTracePayload>(eventId, TracePart, trace, LapTraceValidator.Validate);
        if (part is null)
        {
            return null;
        }

        var channels = new LapTraceChannels(
            part.TimeMs!, part.SpeedKph!, part.Throttle!, part.Brake!, part.Steer!, part.Gear!, part.Rpm!);

        return new LapTelemetryTrace
        {
            Id = _idGenerator.NewId(),
            LapId = lapId,
            ResolutionM = part.ResolutionM!.Value,
            SampleCount = channels.TimeMs.Length,
            Payload = LapTraceCodec.Encode(channels),
            CreatedAt = now,
        };
    }

    /// <summary>영역 하나를 해석하고 검증한다. 없으면(null·JSON null) 조용히 null, 틀리면 경고 후 null.</summary>
    private T? ParseValid<T>(Guid eventId, string part, JsonElement? element, Func<T, IReadOnlyList<string>> validate)
        where T : class
    {
        if (element is not { } json || json.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return null;
        }

        if (json.ValueKind != JsonValueKind.Object)
        {
            LogDiscarded(eventId, part, $"객체가 아닙니다({json.ValueKind})");
            return null;
        }

        T? parsed;
        try
        {
            parsed = json.Deserialize<T>(PartOptions);
        }
        catch (JsonException ex)
        {
            LogDiscarded(eventId, part, $"해석 실패: {ex.Message}");
            return null;
        }

        IReadOnlyList<string> errors = parsed is null ? ["비어 있습니다"] : validate(parsed);
        if (errors.Count > 0)
        {
            LogDiscarded(eventId, part, string.Join("; ", errors));
            return null;
        }

        return parsed;
    }

    private void LogDiscarded(Guid eventId, string part, string reason)
        => _logger.LogWarning(
            "LapFinished {Part} 버림(랩은 저장) eventId={EventId} reason={Reason}", part, eventId, reason);

    private static void ApplyCar(LapSnapshot s, LapCarPayload car)
    {
        s.TeamId = car.TeamId;
        s.VisualTyreCompound = car.VisualTyreCompound;
        s.ActualTyreCompound = car.ActualTyreCompound;
        s.TyreAgeLaps = car.TyreAgeLaps;
        (s.TyreWearStartFrontLeft, s.TyreWearStartFrontRight, s.TyreWearStartRearLeft, s.TyreWearStartRearRight) = Split(car.TyreWearStart);
        (s.TyreWearEndFrontLeft, s.TyreWearEndFrontRight, s.TyreWearEndRearLeft, s.TyreWearEndRearRight) = Split(car.TyreWearEnd);
        (s.TyreDamageFrontLeft, s.TyreDamageFrontRight, s.TyreDamageRearLeft, s.TyreDamageRearRight) = Split(car.TyreDamage);
        (s.BrakeDamageFrontLeft, s.BrakeDamageFrontRight, s.BrakeDamageRearLeft, s.BrakeDamageRearRight) = Split(car.BrakeDamage);
        s.FrontLeftWingDamage = car.FrontLeftWingDamage;
        s.FrontRightWingDamage = car.FrontRightWingDamage;
        s.RearWingDamage = car.RearWingDamage;
        s.FloorDamage = car.FloorDamage;
        s.DiffuserDamage = car.DiffuserDamage;
        s.SidepodDamage = car.SidepodDamage;
        s.GearboxDamage = car.GearboxDamage;
        s.EngineDamage = car.EngineDamage;
        s.FuelStartKg = car.FuelStartKg;
        s.FuelEndKg = car.FuelEndKg;
        s.FuelRemainingLaps = car.FuelRemainingLaps;
        s.ErsStoreStartJ = car.ErsStoreStartJ;
        s.ErsStoreEndJ = car.ErsStoreEndJ;
        s.ErsDeployedJ = car.ErsDeployedJ;
        s.ErsHarvestedJ = car.ErsHarvestedJ;
    }

    /// <summary>날씨 이름은 enum 이름만 받는다. 모르는 이름은 날씨만 비우고(경고 없이 디버그 로그) 나머지는 저장한다.</summary>
    private void ApplyConditions(Guid eventId, LapSnapshot s, LapConditionsPayload conditions)
    {
        if (EnumNames.TryParse<Weather>(conditions.Weather, out var weather))
        {
            s.Weather = weather;
        }
        else if (conditions.Weather is not null)
        {
            _logger.LogDebug("모르는 날씨 값은 저장하지 않음 eventId={EventId} weather={Weather}", eventId, conditions.Weather);
        }

        s.AirTempC = conditions.AirTempC;
        s.TrackTempC = conditions.TrackTempC;
        s.RainForecastPercent = conditions.RainForecastPercent;
    }

    private static (double?, double?, double?, double?) Split(WheelValuesPayload? wheels)
        => wheels is null
            ? (null, null, null, null)
            : (wheels.FrontLeft, wheels.FrontRight, wheels.RearLeft, wheels.RearRight);
}
