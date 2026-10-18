using SimCenter.Application.Seasons.Import;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 가져온 시즌(docs/15 §12, D-55)의 드라이버 맞추기. 순수 함수 — 상태 없음.
/// 가져온 결과("Lando NORRIS")와 게임 기록("NORRIS", <c>driver:{id}</c>)은 <c>DriverKey</c>가 달라 한 드라이버가 두 줄로 갈라진다.
/// 기준선 드라이버마다 이름이 맞는(전체 이름 → 성) 기록 드라이버들을 한 키(가장 최근 결과의 키)로 묶어 행의 키를 바꾼다.
/// </summary>
public static class DriverAliasing
{
    /// <param name="selection">계산 대상 선별 결과.</param>
    /// <param name="baseline">가져온 드라이버 기준값.</param>
    /// <param name="keyByEntry">기준선 순번 → 묶인 키(플레이어는 항상 <c>player</c>, 못 맞춘 드라이버는 없음).</param>
    public static SeasonSelection Apply(
        SeasonSelection selection, IReadOnlyList<ImportedDriverPoints> baseline, out IReadOnlyDictionary<int, string> keyByEntry)
    {
        ArgumentNullException.ThrowIfNull(selection);
        ArgumentNullException.ThrowIfNull(baseline);

        var groups = selection.CountedRows
            .Where(r => !r.IsPlayer)
            .GroupBy(r => r.DriverKey)
            .Select(g => (Key: g.Key, Latest: g.OrderByDescending(r => r.ClassifiedAt).ThenByDescending(r => r.SessionId).First()))
            .ToList();

        var claimed = new HashSet<string>(StringComparer.Ordinal);
        var membersByEntry = new Dictionary<int, List<(string Key, SeasonResultRow Latest)>>();
        Claim(baseline, groups, claimed, membersByEntry, DriverNameMatcher.IsFullMatch);
        Claim(baseline, groups, claimed, membersByEntry, DriverNameMatcher.IsSurnameMatch);

        var keys = new Dictionary<int, string>();
        var canonical = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var i = 0; i < baseline.Count; i++)
        {
            if (baseline[i].IsPlayer)
            {
                keys[i] = DriverKeys.Player;
                continue;
            }

            if (!membersByEntry.TryGetValue(i, out var members))
            {
                continue;
            }

            var key = members.OrderByDescending(m => m.Latest.ClassifiedAt).ThenByDescending(m => m.Latest.SessionId).First().Key;
            keys[i] = key;
            foreach (var member in members)
            {
                canonical[member.Key] = key;
            }
        }

        keyByEntry = keys;
        if (canonical.Count == 0)
        {
            return selection;
        }

        var rows = selection.CountedRows
            .Select(r => canonical.TryGetValue(r.DriverKey, out var key) && key != r.DriverKey ? r with { DriverKey = key } : r)
            .ToList();
        return selection with { CountedRows = rows };
    }

    /// <summary>기준선 드라이버마다(앞 단계에서 묶인 드라이버에도 더한다), 아직 안 묶인 기록 드라이버 중 <paramref name="matches"/>가 맞는 것을 모두 묶는다.</summary>
    private static void Claim(
        IReadOnlyList<ImportedDriverPoints> baseline,
        List<(string Key, SeasonResultRow Latest)> groups,
        HashSet<string> claimed,
        Dictionary<int, List<(string Key, SeasonResultRow Latest)>> membersByEntry,
        Func<string?, string?, bool> matches)
    {
        for (var i = 0; i < baseline.Count; i++)
        {
            if (baseline[i].IsPlayer)
            {
                continue;
            }

            var found = groups.Where(g => !claimed.Contains(g.Key) && matches(baseline[i].Name, g.Latest.DriverName)).ToList();
            if (found.Count == 0)
            {
                continue;
            }

            if (membersByEntry.TryGetValue(i, out var existing))
            {
                existing.AddRange(found);
            }
            else
            {
                membersByEntry[i] = found;
            }

            foreach (var group in found)
            {
                claimed.Add(group.Key);
            }
        }
    }
}
