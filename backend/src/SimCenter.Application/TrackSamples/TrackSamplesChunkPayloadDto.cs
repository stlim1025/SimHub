namespace SimCenter.Application.TrackSamples;

/// <summary>
/// <c>TrackSamplesChunk</c> payload(<c>shared/schema/track_samples_chunk.json</c>). <see cref="SessionType"/>은 문자열로 받아 검증기가 판정한다.
/// <see cref="Data"/>는 gzip을 base64로 감싼 값이다.
/// </summary>
public sealed record TrackSamplesChunkPayloadDto(
    string SessionRef,
    int TrackId,
    string? SessionType,
    int Format,
    int SampleRateHz,
    int ChunkIndex,
    bool IsLast,
    int FrameCount,
    int SampleCount,
    string Data,
    int? TrackLengthM = null);
