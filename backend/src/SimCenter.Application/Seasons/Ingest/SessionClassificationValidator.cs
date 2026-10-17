namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// <c>SessionClassified</c> payload 검증(12 §6.2-2). 순수 함수 — 상태 없음.
/// DB 열 제약에 걸릴 수 있는 값은 모두 여기서 거른다: 저장 시점의 예외는 허브 오류로 Agent에 돌아가 같은 항목이 끝없이 재시도되기 때문이다(12 §0).
/// 한도는 게임이 실제로 보낼 수 있는 값(F1 25: 최대 24대·8스틴트)보다 약간 넉넉하다.
/// </summary>
public static class SessionClassificationValidator
{
    public const int MaxClassificationEntries = 32;
    public const int MaxTyreStints = 8;
    public const int MaxDriverNameLength = 64;
    public const int MaxSessionRefLength = 32;
    public const int MaxActualCompoundLength = 10;

    private const char Nul = '\0';
    private const int MaxPlayers = 1;
    private const int MinPosition = 1;
    private const int MaxCarIndex = MaxClassificationEntries - 1;

    /// <returns>통과하면 null, 아니면 실패 상세 문구.</returns>
    public static string? Validate(SessionClassifiedPayloadDto payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        if (string.IsNullOrWhiteSpace(payload.SessionRef) || payload.SessionRef.Length > MaxSessionRefLength)
        {
            return $"sessionRef: 1~{MaxSessionRefLength}자여야 합니다";
        }

        // PostgreSQL 텍스트 열은 NUL(0x00)을 저장하지 못한다(22021) — SessionRef·SessionKey·DriverKey로 흘러가므로 여기서 거른다.
        if (payload.SessionRef.Contains(Nul))
        {
            return "sessionRef: NUL 문자를 포함할 수 없습니다";
        }

        var results = payload.Results;
        if (results is null)
        {
            return "results: 필요합니다";
        }

        if (results.Count < 1 || results.Count > MaxClassificationEntries)
        {
            return $"results: 1~{MaxClassificationEntries}개여야 합니다(현재 {results.Count})";
        }

        return ValidateResults(results);
    }

    private static string? ValidateResults(IReadOnlyList<ClassifiedResultDto> results)
    {
        var seenCars = new HashSet<int>();
        var playerCount = 0;

        for (var i = 0; i < results.Count; i++)
        {
            var row = results[i];
            if (row is null)
            {
                return $"results[{i}]: null일 수 없습니다";
            }

            if (row.CarIndex < 0 || row.CarIndex > MaxCarIndex)
            {
                return $"results[{i}].carIndex: 0~{MaxCarIndex}여야 합니다";
            }

            if (!seenCars.Add(row.CarIndex))
            {
                return $"carIndex 중복({row.CarIndex})";
            }

            if (row.IsPlayer && ++playerCount > MaxPlayers)
            {
                return $"results[{i}].isPlayer: 플레이어 차는 최대 {MaxPlayers}대여야 합니다";
            }

            var rowError = ValidateRow(row, i);
            if (rowError is not null)
            {
                return rowError;
            }
        }

        return null;
    }

    private static string? ValidateRow(ClassifiedResultDto row, int index)
    {
        if (row.Position < MinPosition || row.Position > MaxClassificationEntries)
        {
            return $"results[{index}].position: {MinPosition}~{MaxClassificationEntries}여야 합니다";
        }

        var negativeField = FindNegativeField(row);
        if (negativeField is not null)
        {
            return $"results[{index}].{negativeField}: 0 이상이어야 합니다";
        }

        if (row.DriverName is { Length: > MaxDriverNameLength })
        {
            return $"results[{index}].driverName: {MaxDriverNameLength}자 이하여야 합니다";
        }

        // 이름 키("name:{NAME}#{raceNumber}")가 열 길이를 넘지 않도록 음수 차 번호를 거른다.
        if (row.RaceNumber is < 0)
        {
            return $"results[{index}].raceNumber: 0 이상이어야 합니다";
        }

        return ValidateStints(row.TyreStints, index);
    }

    private static string? FindNegativeField(ClassifiedResultDto row)
    {
        foreach (var (field, value) in new (string Field, int Value)[]
                 {
                     ("gridPosition", row.GridPosition),
                     ("numLaps", row.NumLaps),
                     ("points", row.Points),
                     ("numPitStops", row.NumPitStops),
                     ("numPenalties", row.NumPenalties),
                     ("bestLapTimeMs", row.BestLapTimeMs),
                     ("totalRaceTimeMs", row.TotalRaceTimeMs),
                     ("penaltiesTimeMs", row.PenaltiesTimeMs),
                 })
        {
            if (value < 0)
            {
                return field;
            }
        }

        return null;
    }

    /// <summary>스틴트 목록 검증. <c>null</c>은 빈 목록으로 본다.</summary>
    private static string? ValidateStints(IReadOnlyList<TyreStintDto>? stints, int rowIndex)
    {
        if (stints is null)
        {
            return null;
        }

        if (stints.Count > MaxTyreStints)
        {
            return $"results[{rowIndex}].tyreStints: 최대 {MaxTyreStints}개여야 합니다(현재 {stints.Count})";
        }

        for (var i = 0; i < stints.Count; i++)
        {
            var stint = stints[i];
            if (stint is null)
            {
                return $"results[{rowIndex}].tyreStints[{i}]: null일 수 없습니다";
            }

            if (stint.EndLap < 0)
            {
                return $"results[{rowIndex}].tyreStints[{i}].endLap: 0 이상이어야 합니다";
            }

            if (stint.ActualCompound is { Length: > MaxActualCompoundLength })
            {
                return $"results[{rowIndex}].tyreStints[{i}].actualCompound: {MaxActualCompoundLength}자 이하여야 합니다";
            }
        }

        return null;
    }
}
