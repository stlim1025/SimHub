using System.Text.Json;
using System.Text.Json.Nodes;
using SimCenter.Application.Seasons.Queries.Detail;

namespace SimCenter.Application.Seasons.Import;

/// <summary>가져온 세션 순위표의 간격(레이스: F1Laps Gap 그대로, 1위 0).</summary>
public sealed record ImportedGap(int CarIndex, int GapMs);

/// <summary>가져온 벌칙(차 미상). 번호는 <c>PenaltyCatalog</c> 역매핑(모르면 null, 이름은 받은 그대로).</summary>
public sealed record ImportedPenalty(int Lap, string Penalty, string Infringement, int? PenaltyType, int? InfringementType);

/// <summary>가져온 세션의 내 랩 표시 보정: 그 랩의 타이어(F1Laps 표 그대로)와 피트 여부.</summary>
public sealed record ImportedLapMark(int LapNumber, string? VisualCompound, bool Pit);

/// <summary>
/// 가져온 세션의 <c>GameSession.Details</c> 안 <c>imported</c> 객체(docs/15 §12, D-55). 랩·순위는 Agent와 같은
/// <c>lapHistory</c>·<c>lapPositions</c>로 두어 §11 조립기(<see cref="SessionLapsBuilder"/>)가 그대로 읽고,
/// 랩 엔티티가 없어 조립기가 못 찾는 값(셋업·피트·타이어·간격·최고 랩·벌칙)만 여기에 둔다.
/// </summary>
public sealed record ImportedSessionDetails(
    string Source,
    JsonElement? Setup,
    IReadOnlyList<ImportedLapMark> LapMarks,
    IReadOnlyList<ImportedGap> Gaps,
    int? FastestLapCarIndex,
    IReadOnlyList<ImportedPenalty> Penalties)
{
    private const string ImportedKey = "imported";

    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// Details JSON을 만든다: <c>{lapHistory:[{carIndex, laps}], lapPositions:[{lapNumber, positions}], imported:{…}}</c>.
    /// <paramref name="positions"/>는 랩 번호 → 내 순위(내 차 칸에만 값, 나머지 0).
    /// </summary>
    public string ToDetailsJson(int playerCarIndex, IReadOnlyList<HistoryLap> myLaps, IReadOnlyDictionary<int, int> positions)
    {
        var root = new JsonObject();
        if (myLaps.Count > 0)
        {
            var laps = new JsonArray();
            foreach (var lap in myLaps)
            {
                laps.Add(new JsonObject
                {
                    ["lapNumber"] = lap.LapNumber,
                    ["lapTimeMs"] = lap.LapTimeMs,
                    ["sector1TimeMs"] = lap.Sector1TimeMs,
                    ["sector2TimeMs"] = lap.Sector2TimeMs,
                    ["sector3TimeMs"] = lap.Sector3TimeMs,
                    ["lapValid"] = lap.LapValid,
                });
            }

            root["lapHistory"] = new JsonArray(new JsonObject { ["carIndex"] = playerCarIndex, ["laps"] = laps });
        }

        if (positions.Count > 0)
        {
            var rows = new JsonArray();
            foreach (var (lapNumber, position) in positions.OrderBy(p => p.Key))
            {
                var cells = new JsonArray();
                for (var car = 0; car <= playerCarIndex; car++)
                {
                    cells.Add(car == playerCarIndex ? position : 0);
                }

                rows.Add(new JsonObject { ["lapNumber"] = lapNumber, ["positions"] = cells });
            }

            root["lapPositions"] = rows;
        }

        root[ImportedKey] = JsonSerializer.SerializeToNode(this, Options);
        return root.ToJsonString();
    }

    /// <summary>Details에서 <c>imported</c>를 읽는다. 없거나 깨졌으면 null(게임에서 기록된 세션).</summary>
    public static ImportedSessionDetails? TryRead(string? detailsJson)
    {
        using var document = JsonReads.ParseObject(detailsJson);
        if (document is null || JsonReads.Object(document.RootElement, ImportedKey) is not { } imported)
        {
            return null;
        }

        try
        {
            return imported.Deserialize<ImportedSessionDetails>(Options);
        }
        catch (JsonException)
        {
            // 깨진 묶음은 없는 것으로 본다 — 세션 상세의 나머지 카드는 그대로 보인다(JsonReads와 같은 방침).
            return null;
        }
    }
}
