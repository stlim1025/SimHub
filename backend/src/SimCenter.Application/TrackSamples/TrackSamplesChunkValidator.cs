using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;

namespace SimCenter.Application.TrackSamples;

/// <summary><c>TrackSamplesChunk</c> payload 검증. 실패는 영구 무효(Reject)다.</summary>
public static class TrackSamplesChunkValidator
{
    /// <summary>지원하는 표본 배치 버전.</summary>
    public const int SupportedFormat = 1;

    /// <summary>gzip 본문 최대 크기(바이트). 봉투 한도(768KiB) 안에 base64로 들어가는 크기.</summary>
    public const int MaxPayloadBytes = 576 * 1024;

    public const int MinSampleRateHz = 1;
    public const int MaxSampleRateHz = 60;

    /// <summary>세션당 조각 순번 상한(레이스 하나에 수십 조각이면 충분하다).</summary>
    public const int MaxChunkIndex = 10_000;

    /// <summary>조각 하나의 프레임·표본 수 상한.</summary>
    public const int MaxCount = 10_000_000;

    /// <summary>트랙 길이 상한(m).</summary>
    public const int MaxTrackLengthM = 20_000;

    private const char Nul = '\0';
    private const byte GzipMagic1 = 0x1f;
    private const byte GzipMagic2 = 0x8b;

    private static readonly SessionType[] CollectedSessionTypes = [SessionType.Practice, SessionType.Qualifying, SessionType.Race];

    /// <param name="payload">받은 payload.</param>
    /// <param name="sessionType">통과하면 세션 종류.</param>
    /// <param name="gzip">통과하면 base64를 푼 gzip 본문.</param>
    /// <returns>통과하면 null, 아니면 실패 상세 문구.</returns>
    public static string? Validate(TrackSamplesChunkPayloadDto payload, out SessionType sessionType, out byte[] gzip)
    {
        ArgumentNullException.ThrowIfNull(payload);
        sessionType = SessionType.Unknown;
        gzip = [];

        if (string.IsNullOrWhiteSpace(payload.SessionRef)
            || payload.SessionRef.Length > TrackSampleChunk.SessionRefMaxLength
            || payload.SessionRef.Contains(Nul))
        {
            return $"sessionRef: NUL 없는 1~{TrackSampleChunk.SessionRefMaxLength}자여야 합니다";
        }

        if (!Enum.TryParse(payload.SessionType, ignoreCase: false, out sessionType) || !CollectedSessionTypes.Contains(sessionType))
        {
            return "sessionType: Practice·Qualifying·Race만 받습니다";
        }

        if (payload.Format != SupportedFormat)
        {
            return $"format: {SupportedFormat}만 지원합니다";
        }

        if (payload.SampleRateHz is < MinSampleRateHz or > MaxSampleRateHz)
        {
            return $"sampleRateHz: {MinSampleRateHz}~{MaxSampleRateHz}이어야 합니다";
        }

        if (payload.ChunkIndex is < 0 or > MaxChunkIndex)
        {
            return $"chunkIndex: 0~{MaxChunkIndex}이어야 합니다";
        }

        if (payload.FrameCount is < 0 or > MaxCount || payload.SampleCount is < 0 or > MaxCount)
        {
            return $"frameCount·sampleCount: 0~{MaxCount}이어야 합니다";
        }

        if (payload.TrackLengthM is < 0 or > MaxTrackLengthM)
        {
            return $"trackLengthM: 0~{MaxTrackLengthM}이어야 합니다";
        }

        try
        {
            gzip = Convert.FromBase64String(payload.Data ?? string.Empty);
        }
        catch (FormatException)
        {
            return "data: base64가 아닙니다";
        }

        if (gzip.Length < 2 || gzip[0] != GzipMagic1 || gzip[1] != GzipMagic2)
        {
            return "data: gzip이 아닙니다";
        }

        if (gzip.Length > MaxPayloadBytes)
        {
            return $"data: {MaxPayloadBytes}바이트를 넘습니다";
        }

        return null;
    }
}
