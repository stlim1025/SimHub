using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Laps;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.TrackOverviews;

/// <summary>이론상 최고 랩의 구간 하나(배터리 kJ, 배터리를 따지지 않으면 null).</summary>
public sealed record TheoreticalSegmentDto(
    int Index,
    int StartM,
    int EndM,
    Guid LapId,
    DateTime LapSetAt,
    int TimeMs,
    int BestLapTimeMs,
    double? DeployKj,
    double? HarvestKj,
    double? BestLapDeployKj,
    double? BestLapHarvestKj);

/// <summary>
/// 한 조건(세션 종류 + 컴파운드)의 이론상 최고 랩. <see cref="VisualTyreCompound"/> = F1 UDP 보이는 컴파운드 번호(모르면 null).
/// <see cref="TheoreticalMs"/> = 배터리 한도를 지킨 값, <see cref="UnlimitedMs"/> = 배터리를 무시한 구간 최고 기록의 합.
/// </summary>
public sealed record TheoreticalBestGroupDto(
    string SessionType,
    int? VisualTyreCompound,
    int LapCount,
    int LapLengthM,
    Guid BestLapId,
    int BestLapMs,
    int TheoreticalMs,
    int UnlimitedMs,
    bool HasBattery,
    IReadOnlyList<TheoreticalSegmentDto> Segments);

/// <summary>트랙의 이론상 최고 랩들(Time Trial 먼저, 같은 세션 종류 안에서는 빠른 순). 계산할 랩이 없으면 빈 목록.</summary>
public sealed record TheoreticalBestResponse(IReadOnlyList<TheoreticalBestGroupDto> Groups);

/// <summary>트랙의 이론상 최고 랩 조회.</summary>
public interface ITheoreticalBestService
{
    /// <summary>트랙이 없으면 <see cref="NotFoundException"/>.</summary>
    Task<TheoreticalBestResponse> GetAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default);
}

/// <summary>
/// <see cref="ITheoreticalBestService"/> 구현. 한 랩 승부인 Time Trial·예선만 계산한다 — 레이스는 랩마다 연료·타이어가 달라 여러 랩을 잇는 값이 뜻이 없다.
/// 조건 = 세션 종류 + 보이는 컴파운드, 비(약한 비 이상)·인터·웨트 랩은 뺀다. 조건마다 빠른 랩 <see cref="LapsPerGroup"/>개까지만 푼다
/// (구간 최고 기록은 거의 빠른 랩들에서 나온다). 배터리 한도는 읽은 모든 랩에서 함께 잰다(게임 규정은 조건과 무관하다).
/// </summary>
public sealed class TheoreticalBestService : ITheoreticalBestService
{
    private const int LapsPerGroup = 40;
    private const int IntermediateCompound = 7;
    private const int WetCompound = 8;
    private const double JoulesPerKj = 1000;
    private const int KjDecimals = 1;

    private static readonly SessionType[] OneLapSessions = [SessionType.TimeTrial, SessionType.Qualifying];

    private readonly ITrackRepository _tracks;
    private readonly ITrackOverviewQueryRepository _queries;

    public TheoreticalBestService(ITrackRepository tracks, ITrackOverviewQueryRepository queries)
    {
        _tracks = tracks;
        _queries = queries;
    }

    public async Task<TheoreticalBestResponse> GetAsync(Guid userId, Guid trackId, CancellationToken cancellationToken = default)
    {
        _ = await _tracks.GetByIdAsync(trackId, cancellationToken)
            ?? throw new NotFoundException("트랙을 찾을 수 없습니다.");

        var facts = await _queries.GetMyTracedLapFactsAsync(userId, trackId, OneLapSessions, cancellationToken);
        var groups = facts
            .Where(f => f.Weather is null or < Weather.LightRain && f.VisualTyreCompound is not (IntermediateCompound or WetCompound))
            .GroupBy(f => (f.SessionType, f.VisualTyreCompound))
            .Select(g => (g.Key, Laps: Pick(g)))
            .ToList();
        if (groups.Count == 0)
        {
            return new TheoreticalBestResponse([]);
        }

        var factsById = groups.SelectMany(g => g.Laps).DistinctBy(f => f.LapId).ToDictionary(f => f.LapId);
        var payloads = await _queries.GetTracePayloadsAsync(factsById.Keys.ToList(), cancellationToken);
        var decoded = new Dictionary<Guid, TheoreticalLap>();
        foreach (var row in payloads)
        {
            if (!factsById.TryGetValue(row.LapId, out var fact))
            {
                continue;
            }

            try
            {
                decoded[row.LapId] = new TheoreticalLap(
                    fact.LapId, fact.LapTimeMs, fact.IsValid, fact.SetAt, fact.ResolutionM,
                    LapTraceCodec.Decode(row.Payload, TheoreticalBestCalculator.RequiredExtraChannels));
            }
            catch (InvalidDataException)
            {
                // 깨진 트레이스는 재료에서 뺀다.
            }
        }

        var budget = TheoreticalBestCalculator.MeasureBudget(decoded.Values);
        var results = new List<TheoreticalBestGroupDto>();
        foreach (var (key, laps) in groups)
        {
            var material = laps.Where(f => decoded.ContainsKey(f.LapId)).Select(f => decoded[f.LapId]).ToList();
            if (TheoreticalBestCalculator.Compute(material, budget) is { } result)
            {
                results.Add(ToDto(key.SessionType, key.VisualTyreCompound, result));
            }
        }

        return new TheoreticalBestResponse(results
            .OrderBy(g => g.SessionType == nameof(SessionType.TimeTrial) ? 0 : 1)
            .ThenBy(g => g.TheoreticalMs)
            .ToList());
    }

    /// <summary>빠른 랩 <see cref="LapsPerGroup"/>개. 그 안에 유효 랩이 없으면 가장 빠른 유효 랩을 더한다(비교 기준).</summary>
    private static List<TrackTracedLapFactRow> Pick(IEnumerable<TrackTracedLapFactRow> laps)
    {
        var ordered = laps.OrderBy(f => f.LapTimeMs).ThenBy(f => f.SetAt).ToList();
        var picked = ordered.Take(LapsPerGroup).ToList();
        if (!picked.Any(f => f.IsValid) && ordered.FirstOrDefault(f => f.IsValid) is { } valid)
        {
            picked.Add(valid);
        }

        return picked;
    }

    private static TheoreticalBestGroupDto ToDto(SessionType sessionType, int? compound, TheoreticalBestResult result)
        => new(
            sessionType.ToString(),
            compound,
            result.LapCount,
            result.LapLengthM,
            result.BestLapId,
            result.BestLapMs,
            result.TheoreticalMs,
            result.UnlimitedMs,
            result.HasBattery,
            result.Segments
                .Select(s => new TheoreticalSegmentDto(
                    s.Index, s.StartM, s.EndM, s.LapId, s.LapSetAt, s.TimeMs, s.BestLapTimeMs,
                    Kj(s.DeployJ), Kj(s.HarvestJ), Kj(s.BestLapDeployJ), Kj(s.BestLapHarvestJ)))
                .ToList());

    private static double? Kj(double? joules)
        => joules is { } j ? Math.Round(j / JoulesPerKj, KjDecimals, MidpointRounding.AwayFromZero) : null;
}
