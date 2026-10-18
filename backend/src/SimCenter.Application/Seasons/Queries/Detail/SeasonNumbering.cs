using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>내 시즌 1건의 번호 매기기 재료(첫 세션 시각 순서).</summary>
public sealed record SeasonOrderRow(Guid SeasonId, string GameCode, GameMode GameMode, DateTime FirstSessionAt);

/// <summary>
/// 시즌 번호(세션 목록의 "Driver Career Season 1", docs/15 §11.2·§11.4 D-53·D-54). 순수 계산.
/// 같은 게임·같은 모드의 내 시즌을 첫 세션 시각 오름차순(같으면 Id)으로 세어 1부터 매긴다 — 모드마다 따로 센다.
/// </summary>
public static class SeasonNumbering
{
    public static IReadOnlyDictionary<Guid, int> Assign(IEnumerable<SeasonOrderRow> seasons)
    {
        ArgumentNullException.ThrowIfNull(seasons);

        var numbers = new Dictionary<Guid, int>();
        foreach (var group in seasons.GroupBy(s => (s.GameCode, s.GameMode)))
        {
            var number = 0;
            foreach (var season in group.OrderBy(s => s.FirstSessionAt).ThenBy(s => s.SeasonId))
            {
                numbers[season.SeasonId] = ++number;
            }
        }

        return numbers;
    }

    public static int? Of(IReadOnlyDictionary<Guid, int> numbers, Guid? seasonId)
        => seasonId is { } id && numbers.TryGetValue(id, out var number) ? number : null;
}
