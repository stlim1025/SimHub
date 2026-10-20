using System.Text.Json;
using SimCenter.Domain.Constants;

namespace SimCenter.Application.Common;

/// <summary>
/// 인입 이벤트의 실제 게임 코드를 고른다(옛 Agent 안전망). 옛 Agent는 2026 시즌팩을 달려도 항상 <see cref="GameCodes.F1_25"/>를 보내므로,
/// F1 25로 온 이벤트에 2026 팀 ID(<see cref="GameEditions.Is2026TeamId(int)"/>)가 있으면 <see cref="GameCodes.F1_26"/>로 바꾼다.
/// 그 밖의 게임 코드는 그대로 둔다. 순수 함수 — 상태 없음.
/// </summary>
public static class GameEditionResolver
{
    private const string TeamIdProperty = "teamId";

    /// <summary>랩: 랩 끝 차량(<c>car.teamId</c>)이 2026 팀이면 F1 26.</summary>
    public static string ForLap(string envelopeGameCode, JsonElement? car)
        => envelopeGameCode == GameCodes.F1_25 && GameEditions.Is2026TeamId(ReadTeamId(car))
            ? GameCodes.F1_26
            : envelopeGameCode;

    /// <summary>세션 결과: 순위표에 2026 팀이 한 대라도 있으면 F1 26.</summary>
    public static string ForClassification(string envelopeGameCode, IEnumerable<int?>? teamIds)
        => envelopeGameCode == GameCodes.F1_25 && teamIds is not null && teamIds.Any(GameEditions.Is2026TeamId)
            ? GameCodes.F1_26
            : envelopeGameCode;

    /// <summary><c>car</c> 객체의 정수 <c>teamId</c>(대소문자 무시). 없거나 모양이 틀리면 null.</summary>
    private static int? ReadTeamId(JsonElement? car)
    {
        if (car is not { ValueKind: JsonValueKind.Object } obj)
        {
            return null;
        }

        foreach (var property in obj.EnumerateObject())
        {
            if (string.Equals(property.Name, TeamIdProperty, StringComparison.OrdinalIgnoreCase)
                && property.Value.ValueKind == JsonValueKind.Number
                && property.Value.TryGetInt32(out var teamId))
            {
                return teamId;
            }
        }

        return null;
    }
}
