using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.TrackSamples;

/// <summary>
/// 트랙 형상 응답(<c>GET /api/v1/tracks/{trackId}/geometry</c>). 배열 칸 i = 랩 거리 i × <paramref name="ResolutionM"/>.
/// X·Z는 레이싱 라인(차들이 달린 위치의 중앙값), 띠는 그 선에서 차들이 달린 왼쪽·오른쪽 끝(m), 연석은 그 쪽을 밟은 적이 있는지.
/// </summary>
/// <param name="Y">높이(m). 높이를 모으지 못했으면 null.</param>
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
    IReadOnlyList<bool> KerbRight);

/// <summary>모든 오프라인 세션의 전체 차 표본으로 트랙 형상을 만든다.</summary>
public interface ITrackGeometryService
{
    /// <summary>표본이 없거나 모자라면 <see cref="NotFoundException"/>.</summary>
    Task<TrackGeometryResponse> GetAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default);
}

/// <summary><see cref="ITrackGeometryService"/> 구현. 풀 수 없는 조각은 경고만 남기고 건너뛴다.</summary>
public sealed class TrackGeometryService : ITrackGeometryService
{
    private const string NoSamplesMessage = "이 트랙의 표본이 아직 없습니다.";

    /// <summary>응답 소수 자리(1cm).</summary>
    private const int Digits = 2;

    private readonly ITrackSampleChunkRepository _chunks;
    private readonly ILogger<TrackGeometryService> _logger;

    public TrackGeometryService(ITrackSampleChunkRepository chunks, ILogger<TrackGeometryService> logger)
    {
        _chunks = chunks;
        _logger = logger;
    }

    public async Task<TrackGeometryResponse> GetAsync(Guid trackId, string gameCode, CancellationToken cancellationToken = default)
    {
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
        return new TrackGeometryResponse(
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
            geometry.KerbRight);
    }

    private static double[] Round(double[] values) => Array.ConvertAll(values, v => Math.Round(v, Digits));
}
