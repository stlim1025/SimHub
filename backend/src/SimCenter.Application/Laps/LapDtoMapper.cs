using System.Text.Json;
using SimCenter.Application.Common;
using SimCenter.Application.Rankings;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Laps;

/// <summary>
/// 랩 읽기 행·스냅샷 → API DTO(15 §4.2). 내 랩 목록(<c>RankingService</c>)과 랩 상세(<see cref="LapQueryService"/>)가 같은 규칙을 쓴다.
/// </summary>
public static class LapDtoMapper
{
    public static LapDto ToLapDto(LapRow row)
    {
        ArgumentNullException.ThrowIfNull(row);

        return new LapDto(
            row.LapId,
            row.TrackName,
            row.GameCode,
            row.SessionType.ToString(),
            row.LapTimeMs,
            row.Sectors,
            row.IsValid,
            row.IsRankingEligible,
            row.SetAt,
            row.LapNumber,
            row.GameMode,
            ToTeam(row.GameCode, row.TeamId),
            row.Weather?.ToString(),
            row.HasTrace);
    }

    /// <summary>팀 ID가 없으면(스냅샷 없음·팀 모름) null — 목록의 TEAM 열은 <c>-</c>다. 있으면 카탈로그 이름·색(모르는 ID는 <c>Team {id}</c>).</summary>
    public static TeamRefDto? ToTeam(string gameCode, int? teamId)
    {
        if (teamId is not { } id)
        {
            return null;
        }

        var team = TeamCatalog.Resolve(gameCode, id);
        return new TeamRefDto(team.Name, team.Color);
    }

    /// <summary>스냅샷의 차량 영역. 스냅샷이 없거나 차량 값이 하나도 없으면 null.</summary>
    public static LapCarSnapshotDto? ToCar(LapSnapshot? s)
    {
        if (s is null || !s.HasCarData())
        {
            return null;
        }

        return new LapCarSnapshotDto(
            s.TeamId,
            s.VisualTyreCompound,
            s.ActualTyreCompound,
            s.TyreAgeLaps,
            ToWheels(s.TyreWearStartFrontLeft, s.TyreWearStartFrontRight, s.TyreWearStartRearLeft, s.TyreWearStartRearRight),
            ToWheels(s.TyreWearEndFrontLeft, s.TyreWearEndFrontRight, s.TyreWearEndRearLeft, s.TyreWearEndRearRight),
            ToWheels(s.TyreDamageFrontLeft, s.TyreDamageFrontRight, s.TyreDamageRearLeft, s.TyreDamageRearRight),
            ToWheels(s.BrakeDamageFrontLeft, s.BrakeDamageFrontRight, s.BrakeDamageRearLeft, s.BrakeDamageRearRight),
            s.FrontLeftWingDamage,
            s.FrontRightWingDamage,
            s.RearWingDamage,
            s.FloorDamage,
            s.DiffuserDamage,
            s.SidepodDamage,
            s.GearboxDamage,
            s.EngineDamage,
            s.FuelStartKg,
            s.FuelEndKg,
            s.FuelRemainingLaps,
            s.ErsStoreStartJ,
            s.ErsStoreEndJ,
            s.ErsDeployedJ,
            s.ErsHarvestedJ,
            ToDetails(s.Details));
    }

    /// <summary>jsonb 원문 → JSON 값(받은 그대로). 원문은 인입 때 객체임을 확인했고 DB가 문법을 보장한다.</summary>
    private static JsonElement? ToDetails(string? details)
    {
        if (details is null)
        {
            return null;
        }

        using var document = JsonDocument.Parse(details);
        return document.RootElement.Clone();
    }

    /// <summary>스냅샷의 날씨 영역. 스냅샷이 없거나 날씨 값이 하나도 없으면 null.</summary>
    public static LapConditionsDto? ToConditions(LapSnapshot? s)
        => s is null || !s.HasConditionsData()
            ? null
            : new LapConditionsDto(s.Weather?.ToString(), s.AirTempC, s.TrackTempC, s.RainForecastPercent);

    /// <summary>비교 대상 행 → DTO(D-51). 이름 규칙은 호출자(<see cref="LapQueryService"/>)가 정한다.</summary>
    public static LapComparisonDto ToComparison(
        LapRow row, string kind, bool isMine, string? displayName, IReadOnlyList<string> appliedFilters)
    {
        ArgumentNullException.ThrowIfNull(row);

        return new LapComparisonDto(
            kind,
            row.LapId,
            row.LapTimeMs,
            row.Sectors,
            row.SetAt,
            row.HasTrace,
            isMine,
            displayName,
            ToTeam(row.GameCode, row.TeamId),
            row.SessionType.ToString(),
            appliedFilters,
            row.VisualTyreCompound);
    }

    /// <summary>바퀴 4개 값이 모두 있을 때만 묶음을 만든다(인입 검증이 묶음 단위로 받으므로 보통 모두 있거나 모두 없다).</summary>
    private static WheelValuesDto? ToWheels(double? frontLeft, double? frontRight, double? rearLeft, double? rearRight)
        => frontLeft is { } fl && frontRight is { } fr && rearLeft is { } rl && rearRight is { } rr
            ? new WheelValuesDto(fl, fr, rl, rr)
            : null;
}
