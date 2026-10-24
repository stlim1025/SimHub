using SimCenter.Application.Seasons.Import;

namespace SimCenter.Application.Seasons.Queries;

/// <summary>
/// 가져온 스탠딩 기준선(D-55)이 기록 세션을 어디까지 담고 있는지 점수로 정한다. 순수 함수 — 상태 없음.
/// <para>
/// 기준선은 어느 한 시점의 순위표라, 그 전에 끝난 기록 세션의 점수는 이미 들어 있고 그 뒤 세션은 들어 있지 않다.
/// 가져온 뒤에 기록된 세션은 들어 있을 수 없지만, 가져오기 전에 기록된 세션이 다 들어 있다고도 할 수 없다 —
/// 순위표를 찍은 뒤 레이스를 하나 더 하고 나서 가져올 수 있다.
/// 그래서 점수가 있는 기록 세션(<see cref="SessionPositions.CountsForPoints"/>) 중 가져오기 전 것(<c>ClassifiedAt ≤ importedAt</c>)을
/// 시각 순으로 놓고, 앞에서 k개를 기준선에 넣었을 때 드라이버마다 (가져온 세션 점수 + 넣은 세션 점수)와 기준선 점수의 차 합이
/// 가장 작은 k를 고른다. 차가 같으면 큰 k(가져온 시각 기준에 가까운 쪽)다.
/// 가져온 세션이 기준선을 다 설명하지 못해도(요약만 가져옴, 빠진 스프린트) 모자란 쪽은 k를 늘릴수록 줄어 들어 있다고 본다.
/// 넘치는 쪽(넣으면 기준선보다 점수가 커짐)이 생길 때만 k가 줄어든다.
/// </para>
/// </summary>
public static class BaselineCoverage
{
    /// <param name="rows">계산 대상 행(드라이버 키는 <see cref="DriverAliasing"/>로 묶인 키). <c>IsImported</c> = 가져온 세션의 행.</param>
    /// <param name="baseline">가져온 드라이버 기준값.</param>
    /// <param name="keyByEntry">기준선 순번 → 묶인 드라이버 키(<see cref="DriverAliasing.Apply"/>의 결과).</param>
    /// <param name="importedAt">가져온 시각(UTC). 그 뒤에 기록된 세션은 후보가 아니다. null이면 기록 세션이 하나도 들어 있지 않다고 본다.</param>
    /// <returns>기준선에 든 기록 세션의 행까지 <c>IsImported</c>로 표시한 행(입력 순서 유지).</returns>
    public static IReadOnlyList<SeasonResultRow> Mark(
        IReadOnlyList<SeasonResultRow> rows,
        IReadOnlyList<ImportedDriverPoints> baseline,
        IReadOnlyDictionary<int, string> keyByEntry,
        DateTime? importedAt)
    {
        ArgumentNullException.ThrowIfNull(rows);
        ArgumentNullException.ThrowIfNull(baseline);
        ArgumentNullException.ThrowIfNull(keyByEntry);

        var recorded = rows
            .Where(r => !r.IsImported && SessionPositions.CountsForPoints(r.SessionType) && importedAt is { } at && r.ClassifiedAt <= at)
            .GroupBy(r => r.SessionId)
            .Select(g => g.First())
            .OrderBy(r => r.ClassifiedAt)
            .ThenBy(r => r.SessionId)
            .Select(r => (r.SessionId, r.ClassifiedAt))
            .ToList();
        if (recorded.Count == 0 || keyByEntry.Count == 0)
        {
            return rows;
        }

        var count = Choose(rows, baseline, keyByEntry, recorded.Select(s => s.SessionId).ToList());
        if (count == 0)
        {
            return rows;
        }

        var inBaseline = recorded.Take(count).Select(s => s.SessionId).ToHashSet();
        return rows.Select(r => !r.IsImported && inBaseline.Contains(r.SessionId) ? r with { IsImported = true } : r).ToList();
    }

    /// <summary>앞에서 몇 개의 기록 세션이 기준선에 들었는지(0 ~ <paramref name="recorded"/> 개수).</summary>
    private static int Choose(
        IReadOnlyList<SeasonResultRow> rows,
        IReadOnlyList<ImportedDriverPoints> baseline,
        IReadOnlyDictionary<int, string> keyByEntry,
        List<Guid> recorded)
    {
        var entries = keyByEntry.ToList();
        var keys = entries.Select(e => e.Value).ToHashSet(StringComparer.Ordinal);
        var sessionIndex = recorded.Select((id, i) => (id, i)).ToDictionary(x => x.id, x => x.i);

        // 드라이버 키마다: 가져온 세션 점수 합, 기록 세션마다의 점수.
        var importedPoints = new Dictionary<string, long>(StringComparer.Ordinal);
        var recordedPoints = new Dictionary<string, long[]>(StringComparer.Ordinal);
        foreach (var row in rows.Where(r => keys.Contains(r.DriverKey) && SessionPositions.CountsForPoints(r.SessionType)))
        {
            if (row.IsImported)
            {
                importedPoints[row.DriverKey] = importedPoints.GetValueOrDefault(row.DriverKey) + row.Points;
            }
            else if (sessionIndex.TryGetValue(row.SessionId, out var index))
            {
                if (!recordedPoints.TryGetValue(row.DriverKey, out var perSession))
                {
                    recordedPoints[row.DriverKey] = perSession = new long[recorded.Count];
                }

                perSession[index] += row.Points;
            }
        }

        // 기준선 순번마다 지금 k에서의 예상 점수(가져온 세션 + 앞 k개 기록 세션).
        var predicted = entries.ToDictionary(e => e.Key, e => importedPoints.GetValueOrDefault(e.Value));
        long Error() => entries.Sum(e => Math.Abs(baseline[e.Key].Points - predicted[e.Key]));

        var bestCount = 0;
        var bestError = Error();
        for (var k = 1; k <= recorded.Count; k++)
        {
            foreach (var (entry, key) in entries)
            {
                if (recordedPoints.TryGetValue(key, out var perSession))
                {
                    predicted[entry] += perSession[k - 1];
                }
            }

            var error = Error();
            if (error <= bestError)
            {
                bestCount = k;
                bestError = error;
            }
        }

        return bestCount;
    }
}
