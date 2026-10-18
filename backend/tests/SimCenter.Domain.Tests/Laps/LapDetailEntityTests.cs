using System.Reflection;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Tests.Laps;

/// <summary>랩 상세 저장 엔티티(15 §5, D-43~D-45)의 기본값과 "값이 있는가" 판정.</summary>
public class LapDetailEntityTests
{
    /// <summary>상세의 <c>conditions</c> 영역 열. 나머지 nullable 값 열(팀 제외)은 모두 <c>car</c> 영역이다.</summary>
    private static readonly string[] ConditionProperties =
    [
        nameof(LapSnapshot.Weather),
        nameof(LapSnapshot.AirTempC),
        nameof(LapSnapshot.TrackTempC),
        nameof(LapSnapshot.RainForecastPercent),
    ];

    [Fact]
    public void Track_DisplayInfo_DefaultsToNoCountryAndZeroOrder()
    {
        var track = new Track { GameCode = "F1_25", Name = "Jeddah" };

        Assert.Null(track.CountryCode);
        Assert.Equal(0, track.DisplayOrder);
        Assert.Equal(2, Track.CountryCodeLength);
    }

    [Fact]
    public void Lap_DetailParts_DefaultToNone()
    {
        var lap = new Lap { GameCode = "F1_25" };

        Assert.Null(lap.GameMode);
        Assert.Null(lap.Snapshot);
    }

    [Fact]
    public void LapSnapshot_New_HasNoCarOrConditionData()
    {
        var snapshot = new LapSnapshot();

        Assert.False(snapshot.IsDeleted);
        Assert.Null(snapshot.TeamId);
        Assert.Null(snapshot.Weather);
        Assert.False(snapshot.HasCarData());
        Assert.False(snapshot.HasConditionsData());
    }

    [Fact]
    public void LapSnapshot_TeamOnly_IsNotCarData()
    {
        // 팀은 랩 목록의 TEAM 열(lap.team)로 나가고, 상세의 car 영역 값이 아니다.
        var snapshot = new LapSnapshot { TeamId = 1 };

        Assert.False(snapshot.HasCarData());
        Assert.False(snapshot.HasConditionsData());
    }

    [Fact]
    public void LapSnapshot_EverySingleCarColumn_CountsAsCarData()
    {
        // 열을 더하고 HasCarData에 빠뜨리면 여기서 실패한다.
        var carProperties = ValueProperties()
            .Where(p => p.Name != nameof(LapSnapshot.TeamId) && !ConditionProperties.Contains(p.Name))
            .ToList();
        Assert.Equal(34, carProperties.Count);

        foreach (var property in carProperties)
        {
            var snapshot = new LapSnapshot();
            SetSampleValue(snapshot, property);

            Assert.True(snapshot.HasCarData(), $"{property.Name}이(가) car 값으로 판정되지 않았다.");
            Assert.False(snapshot.HasConditionsData(), $"{property.Name}이(가) conditions 값으로 판정됐다.");
        }
    }

    [Fact]
    public void LapSnapshot_EverySingleConditionColumn_CountsAsConditionsData()
    {
        foreach (var name in ConditionProperties)
        {
            var snapshot = new LapSnapshot();
            SetSampleValue(snapshot, typeof(LapSnapshot).GetProperty(name)!);

            Assert.True(snapshot.HasConditionsData(), $"{name}이(가) conditions 값으로 판정되지 않았다.");
            Assert.False(snapshot.HasCarData(), $"{name}이(가) car 값으로 판정됐다.");
        }
    }

    [Fact]
    public void LapSnapshot_DetailsOnly_CountsAsCarData()
    {
        var snapshot = new LapSnapshot { Details = "{\"setup\":{\"frontWing\":5}}" };

        Assert.True(snapshot.HasCarData());
        Assert.False(snapshot.HasConditionsData());
    }

    [Fact]
    public void GameSession_Details_DefaultsToNull()
    {
        var session = new GameSession { GameCode = "F1_25", SessionKey = "uid:1", SessionRef = "1" };

        Assert.Null(session.Details);
    }

    [Fact]
    public void LapSnapshot_ZeroValues_StillCountAsData()
    {
        // 0은 "값 없음"이 아니다(손상 0%, 기온 0°C).
        var snapshot = new LapSnapshot { FrontLeftWingDamage = 0, AirTempC = 0 };

        Assert.True(snapshot.HasCarData());
        Assert.True(snapshot.HasConditionsData());
    }

    [Fact]
    public void LapTelemetryTrace_Defaults_AreEmpty()
    {
        var trace = new LapTelemetryTrace();

        Assert.False(trace.IsDeleted);
        Assert.Empty(trace.Payload);
        Assert.Equal(0, trace.SampleCount);
    }

    [Fact]
    public void Weather_MatchesGameOrder()
    {
        Assert.Equal(
            new[] { "Clear", "LightCloud", "Overcast", "LightRain", "HeavyRain", "Storm" },
            Enum.GetNames<Weather>());
        Assert.Equal(5, (int)Weather.Storm);
    }

    /// <summary>스냅샷의 nullable 값 열(공통 필드·LapId 제외).</summary>
    private static IEnumerable<PropertyInfo> ValueProperties()
        => typeof(LapSnapshot)
            .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .Where(p => p.CanWrite && Nullable.GetUnderlyingType(p.PropertyType) is not null);

    private static void SetSampleValue(LapSnapshot snapshot, PropertyInfo property)
    {
        var underlying = Nullable.GetUnderlyingType(property.PropertyType)!;
        object value = underlying == typeof(double) ? 1.5d
            : underlying == typeof(int) ? 1
            : Enum.ToObject(underlying, 1);
        property.SetValue(snapshot, value);
    }
}
