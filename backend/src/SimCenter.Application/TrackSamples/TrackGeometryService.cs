using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 트랙 형상 응답(<c>GET /api/v1/tracks/{trackId}/geometry</c>). 배열 칸 i = 랩 거리 i × <paramref name="ResolutionM"/>.
/// X·Z는 레이싱 라인(차들이 달린 위치의 중앙값), 띠는 그 선에서 차들이 달린 왼쪽·오른쪽 끝(m), 연석은 그 쪽을 밟은 적이 있는지.
/// </summary>
/// <param name="Y">높이(m). 높이를 모으지 못했으면 null.</param>
/// <param name="PitX">피트 레인 선(입구 → 출구, 월드 X·Z·높이). 피트 레인 표본이 모자라면 셋 다 null.</param>
/// <param name="EdgeLeftM">레이싱 라인에서 아스팔트 가장자리까지(m): 네 바퀴가 모두 아스팔트에 있던 차의 바깥 바퀴가 닿은 가장 먼 자리. 표본이 없는 칸은 0.</param>
/// <param name="KerbOuterLeftM">연석을 밟은 차의 바깥 바퀴가 닿은 가장 먼 자리(m) = 연석 바깥 끝. 없으면 0.</param>
/// <param name="ReachLeftM">차 몸체가 닿은 가장 먼 자리(m): 코스를 벗어난 차, 멈춘 차까지 모두. 방호벽은 이보다 바깥이다.</param>
public sealed record TrackGeometryResponse(
    Guid TrackId,
    string GameCode,
    double ResolutionM,
    int SessionCount,
    int SampleCount,
    IReadOnlyList<double> X,
    IReadOnlyList<double> Z,
    IReadOnlyList<double>? Y,
    IReadOnlyList<double> BandLeftM,
    IReadOnlyList<double> BandRightM,
    IReadOnlyList<bool> KerbLeft,
    IReadOnlyList<bool> KerbRight,
    IReadOnlyList<double>? PitX = null,
    IReadOnlyList<double>? PitZ = null,
    IReadOnlyList<double>? PitY = null,
    IReadOnlyList<double>? EdgeLeftM = null,
    IReadOnlyList<double>? EdgeRightM = null,
    IReadOnlyList<double>? KerbOuterLeftM = null,
    IReadOnlyList<double>? KerbOuterRightM = null,
    IReadOnlyList<double>? ReachLeftM = null,
    IReadOnlyList<double>? ReachRightM = null);

/// <summary>모든 오프라인 세션의 전체 차 표본으로 트랙 형상을 만든다.</summary>
public interface ITrackGeometryService
{
    /// <summary>표본이 없거나 모자라면 <see cref="NotFoundException"/>.</summary>
    Task<TrackGeometryResponse> GetAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default);
}

/// <summary>
/// <see cref="ITrackGeometryService"/> 구현. 풀 수 없는 조각은 경고만 남기고 건너뛴다.
/// 조각 버전이 지난번과 같으면 <see cref="TrackGeometryCache"/>에 둔 응답을 그대로 돌려준다.
/// </summary>
public sealed class TrackGeometryService : ITrackGeometryService
{
    private const string NoSamplesMessage = "이 트랙의 표본이 아직 없습니다.";

    /// <summary>응답 소수 자리(1cm).</summary>
    private const int Digits = 2;

    private readonly ITrackSampleChunkRepository _chunks;
    private readonly TrackGeometryCache _cache;
    private readonly ILogger<TrackGeometryService> _logger;

    public TrackGeometryService(ITrackSampleChunkRepository chunks, TrackGeometryCache cache, ILogger<TrackGeometryService> logger)
    {
        _chunks = chunks;
        _cache = cache;
        _logger = logger;
    }

    public async Task<TrackGeometryResponse> GetAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default)
    {
        var version = await _chunks.GetTrackVersionAsync(trackId, gameCode, cancellationToken);
        if (version is not null && _cache.Get(trackId, gameCode, version) is { } cached)
        {
            return cached;
        }

        var stored = await _chunks.ListForTrackAsync(trackId, gameCode, cancellationToken);
        var decoded = new List<DecodedTrackSamples>();
        foreach (var chunk in stored)
        {
            try
            {
                decoded.Add(TrackSampleDecoder.Decode(chunk.Payload, chunk.Format));
            }
            catch (FormatException ex)
            {
                _logger.LogWarning(ex, "Skipping undecodable track sample chunk {SessionRef}#{ChunkIndex}", chunk.SessionRef, chunk.ChunkIndex);
            }
        }

        var geometry = TrackGeometryBuilder.Build(decoded) ?? throw new NotFoundException(NoSamplesMessage);
        var response = new TrackGeometryResponse(
            trackId,
            gameCode,
            geometry.ResolutionM,
            stored.Select(c => c.SessionRef).Distinct().Count(),
            geometry.SampleCount,
            Round(geometry.X),
            Round(geometry.Z),
            geometry.Y is null ? null : Round(geometry.Y),
            Round(geometry.BandLeftM),
            Round(geometry.BandRightM),
            geometry.KerbLeft,
            geometry.KerbRight,
            geometry.PitX is null ? null : Round(geometry.PitX),
            geometry.PitZ is null ? null : Round(geometry.PitZ),
            geometry.PitY is null ? null : Round(geometry.PitY),
            Round(geometry.EdgeLeftM),
            Round(geometry.EdgeRightM),
            Round(geometry.KerbOuterLeftM),
            Round(geometry.KerbOuterRightM),
            Round(geometry.ReachLeftM),
            Round(geometry.ReachRightM));
        if (version is not null)
        {
            _cache.Set(trackId, gameCode, version, response);
            _logger.LogInformation(
                "Built track geometry {TrackId}/{GameCode} from {ChunkCount} chunks", trackId, gameCode, version.ChunkCount);
        }

        return response;
    }

    private static double[] Round(double[] values) => Array.ConvertAll(values, v => Math.Round(v, Digits));
}
