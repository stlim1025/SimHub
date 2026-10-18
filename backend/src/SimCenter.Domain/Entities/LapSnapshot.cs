using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 랩 끝의 차량·날씨 스냅샷(15 §4.2·§5, D-44). Lap과 1:0..1(Unique LapId), 랩과 같은 트랜잭션으로 한 번만 저장한다(불변).
/// 모든 값 열은 nullable이다 — Agent가 받지 못한 값, 검증에서 버린 영역(차량 또는 날씨)은 null로 남는다.
/// 바퀴 4개 값은 평평한 열 4개로 둔다(<c>TyreWearEndFrontLeft</c> …). 퍼센트는 0~100, 연료 kg, ERS J(배터리 최대 4MJ).
/// </summary>
public class LapSnapshot : BaseEntity
{
    public Guid LapId { get; set; }

    /// <summary>게임 팀 ID. 이름·색은 <c>TeamCatalog</c>(D-33)가 푼다. 상세의 car 영역 값이 아니라 랩의 팀이다.</summary>
    public int? TeamId { get; set; }

    // ── 타이어 ──
    public int? VisualTyreCompound { get; set; }
    public int? ActualTyreCompound { get; set; }
    public int? TyreAgeLaps { get; set; }

    public double? TyreWearStartFrontLeft { get; set; }
    public double? TyreWearStartFrontRight { get; set; }
    public double? TyreWearStartRearLeft { get; set; }
    public double? TyreWearStartRearRight { get; set; }

    public double? TyreWearEndFrontLeft { get; set; }
    public double? TyreWearEndFrontRight { get; set; }
    public double? TyreWearEndRearLeft { get; set; }
    public double? TyreWearEndRearRight { get; set; }

    public double? TyreDamageFrontLeft { get; set; }
    public double? TyreDamageFrontRight { get; set; }
    public double? TyreDamageRearLeft { get; set; }
    public double? TyreDamageRearRight { get; set; }

    public double? BrakeDamageFrontLeft { get; set; }
    public double? BrakeDamageFrontRight { get; set; }
    public double? BrakeDamageRearLeft { get; set; }
    public double? BrakeDamageRearRight { get; set; }

    // ── 손상(%) ──
    public int? FrontLeftWingDamage { get; set; }
    public int? FrontRightWingDamage { get; set; }
    public int? RearWingDamage { get; set; }
    public int? FloorDamage { get; set; }
    public int? DiffuserDamage { get; set; }
    public int? SidepodDamage { get; set; }
    public int? GearboxDamage { get; set; }
    public int? EngineDamage { get; set; }

    // ── 연료(kg)·ERS(J) ──
    public double? FuelStartKg { get; set; }
    public double? FuelEndKg { get; set; }
    public double? FuelRemainingLaps { get; set; }
    public double? ErsStoreStartJ { get; set; }
    public double? ErsStoreEndJ { get; set; }
    public double? ErsDeployedJ { get; set; }
    public double? ErsHarvestedJ { get; set; }

    // ── 날씨 ──
    public Weather? Weather { get; set; }
    public int? AirTempC { get; set; }
    public int? TrackTempC { get; set; }
    public int? RainForecastPercent { get; set; }

    /// <summary>상세의 car 영역 값(팀 제외)이 하나라도 있는지. 없으면 상세의 <c>car</c>는 null이다.</summary>
    public bool HasCarData() => CarValues().Any(value => value.HasValue);

    /// <summary>날씨 영역 값이 하나라도 있는지. 없으면 상세의 <c>conditions</c>는 null이다.</summary>
    public bool HasConditionsData()
        => Weather.HasValue || AirTempC.HasValue || TrackTempC.HasValue || RainForecastPercent.HasValue;

    private IEnumerable<double?> CarValues()
    {
        yield return VisualTyreCompound;
        yield return ActualTyreCompound;
        yield return TyreAgeLaps;
        yield return TyreWearStartFrontLeft;
        yield return TyreWearStartFrontRight;
        yield return TyreWearStartRearLeft;
        yield return TyreWearStartRearRight;
        yield return TyreWearEndFrontLeft;
        yield return TyreWearEndFrontRight;
        yield return TyreWearEndRearLeft;
        yield return TyreWearEndRearRight;
        yield return TyreDamageFrontLeft;
        yield return TyreDamageFrontRight;
        yield return TyreDamageRearLeft;
        yield return TyreDamageRearRight;
        yield return BrakeDamageFrontLeft;
        yield return BrakeDamageFrontRight;
        yield return BrakeDamageRearLeft;
        yield return BrakeDamageRearRight;
        yield return FrontLeftWingDamage;
        yield return FrontRightWingDamage;
        yield return RearWingDamage;
        yield return FloorDamage;
        yield return DiffuserDamage;
        yield return SidepodDamage;
        yield return GearboxDamage;
        yield return EngineDamage;
        yield return FuelStartKg;
        yield return FuelEndKg;
        yield return FuelRemainingLaps;
        yield return ErsStoreStartJ;
        yield return ErsStoreEndJ;
        yield return ErsDeployedJ;
        yield return ErsHarvestedJ;
    }
}
