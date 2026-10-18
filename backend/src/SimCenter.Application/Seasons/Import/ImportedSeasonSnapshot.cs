using System.Text.Json;

namespace SimCenter.Application.Seasons.Import;

/// <summary>가져온 스탠딩의 드라이버 한 줄(D-55). <see cref="IsPlayer"/> = 플레이어("You *"·인게임 Player). 팀은 인게임 표에서만 안다.</summary>
public sealed record ImportedDriverPoints(string Name, int Points, bool IsPlayer, int? TeamId = null);

/// <summary>가져온 컨스트럭터 기준값 한 줄(인게임 Constructor Standings, D-55).</summary>
public sealed record ImportedConstructorPoints(int TeamId, int Points);

/// <summary>
/// <c>Season.ImportedStandings</c>(jsonb)에 담는 스냅샷(docs/15 §12, D-55). 시즌 이름은 같은 시즌을 두 번 가져오는지(409) 볼 때 쓴다.
/// <see cref="Source"/> = 기준값을 준 문서(<c>InGame</c> 또는 <c>F1Laps</c>). <see cref="Constructors"/>가 비면 컨스트럭터는 드라이버 팀별 합이다.
/// </summary>
public sealed record ImportedSeasonSnapshot(
    string Title,
    string PlayerName,
    string? TeamName,
    string Source,
    IReadOnlyList<ImportedDriverPoints> Drivers,
    IReadOnlyList<ImportedConstructorPoints>? Constructors = null)
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    public string ToJson() => JsonSerializer.Serialize(this, Options);

    /// <summary>저장된 JSON → 스냅샷. 비었거나 읽을 수 없으면 null(기준선 없이 계산한다).</summary>
    public static ImportedSeasonSnapshot? TryRead(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            var snapshot = JsonSerializer.Deserialize<ImportedSeasonSnapshot>(json, Options);
            return snapshot?.Drivers is null ? null : snapshot;
        }
        catch (JsonException)
        {
            // 깨진 스냅샷이면 기준선 없이 기록된 결과만으로 계산한다(조회를 실패시키지 않는다).
            return null;
        }
    }
}
