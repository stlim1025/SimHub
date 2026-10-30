using SimCenter.Application.TrackSamples;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 레이스 심층 분석 조립(순수 계산). 깨끗한 랩은 레이스 총평(<see cref="RaceReviewBuilder"/>)과 같다.
/// 트레이스가 있는 깨끗한 랩 중 가장 빠른 랩으로 구간을 나누고(<see cref="RaceSegments"/>) 스틴트마다 구간별 주행을(<see cref="RaceDrivingAnalyzer"/>),
/// 다른 차 표본으로 구간별 배터리를(<see cref="FieldErsProfile"/>), 스냅샷 타이어 상태로 전략을(<see cref="RaceStrategyAnalyzer"/>),
/// 세션 기록으로 랩마다 페이스 기준을(<see cref="RacePaceAnalyzer"/>) 낸다. 레이스가 아니거나 내 차·내 랩 기록을 모르면 null.
/// </summary>
public static class RaceAnalysisBuilder
{
    private const string CornerKind = "Corner";
    private const string StraightKind = "Straight";

    public static RaceAnalysisDto? Build(
        GameSession session,
        IReadOnlyList<SessionResult> results,
        SessionHistory history,
        int? playerCarIndex,
        IReadOnlyList<MySessionLap> myLaps,
        IReadOnlyList<RaceTraceLap> traces,
        IReadOnlyList<DecodedTrackSamples> fieldChunks,
        double? trackLengthM)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(results);
        ArgumentNullException.ThrowIfNull(history);
        ArgumentNullException.ThrowIfNull(myLaps);
        ArgumentNullException.ThrowIfNull(traces);
        ArgumentNullException.ThrowIfNull(fieldChunks);

        if (session.SessionType != SessionType.Race || playerCarIndex is not { } me)
        {
            return null;
        }

        var cars = results.Select(r => RaceReviewBuilder.CarRace.Of(r, history)).ToList();
        var mine = cars.FirstOrDefault(c => c.Result.CarIndex == me);
        if (mine is null || mine.Laps.Count == 0)
        {
            return null;
        }

        var byLap = traces.GroupBy(t => t.LapNumber).ToDictionary(g => g.Key, g => g.Last());
        var reference = mine.Clean
            .Where(l => byLap.ContainsKey(l.LapNumber))
            .OrderBy(l => l.LapTimeMs)
            .ThenBy(l => l.LapNumber)
            .Select(l => byLap[l.LapNumber])
            .FirstOrDefault();
        IReadOnlyList<SegmentRange> segments = reference is null ? [] : RaceSegments.Detect(reference);
        (IReadOnlyList<RaceStintDrivingDto> Stints, double? WearPctPerMj) driving = segments.Count == 0
            ? ([], null)
            : RaceDrivingAnalyzer.Build(mine, byLap, segments, SessionLapsBuilder.LatestByLapNumber(myLaps));
        var length = trackLengthM ?? (reference is null ? 0 : (reference.Count - 1) * reference.ResolutionM);

        return new RaceAnalysisDto(
            (int)Math.Round(length),
            reference?.LapNumber,
            reference is null ? [] : segments.Select(s => ToDto(s, reference)).ToList(),
            driving.Stints,
            driving.WearPctPerMj,
            reference is null ? [] : FieldErsProfile.Build(fieldChunks, me, segments, reference.ResolutionM, reference.Count, length),
            RaceStrategyAnalyzer.Build(mine, myLaps, session.TotalLaps),
            RacePaceAnalyzer.Build(mine, cars));
    }

    /// <summary>구간 → 응답(표본 번호 × 간격 = 랩 거리, 기준 랩의 최저 속도 지점).</summary>
    private static RaceSegmentDto ToDto(SegmentRange segment, RaceTraceLap reference)
    {
        var resolution = reference.ResolutionM;
        var apex = segment.Runs(reference.Count)
            .SelectMany(run => Enumerable.Range(run.From, run.To - run.From + 1))
            .DefaultIfEmpty(segment.Start)
            .MinBy(i => i < reference.Count ? reference.Channels.SpeedKph[i] : int.MaxValue);
        return new RaceSegmentDto(
            segment.Index,
            segment.IsCorner ? CornerKind : StraightKind,
            segment.Start * resolution,
            segment.End * resolution,
            apex * resolution,
            apex < reference.Count ? reference.Channels.SpeedKph[apex] : 0);
    }
}
