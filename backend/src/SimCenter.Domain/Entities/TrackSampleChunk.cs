using SimCenter.Domain.Common;
using SimCenter.Domain.Enums;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 트랙 형상 계산용 표본 조각(<c>TrackSamplesChunk</c>, 헌장 Agent Rules 예외). 오프라인 세션 하나의 모든 차 위치·랩 거리·노면을
/// 추린 표본이 여러 조각으로 나뉘어 온다. 받은 그대로(gzip, <c>shared/schema/track_samples_chunk.json</c> format) 보관해
/// 계산 기준이 바뀌어도 다시 계산할 수 있게 한다(불변). 장치·세션·순번이 같은 조각은 한 번만 저장한다.
/// </summary>
public class TrackSampleChunk : BaseEntity
{
    /// <summary>세션 식별자(SessionUID) 최대 길이.</summary>
    public const int SessionRefMaxLength = 32;

    /// <summary>보낸 장치(D-26).</summary>
    public Guid AgentDeviceId { get; set; }

    /// <summary>장치 주인(D-25).</summary>
    public Guid UserId { get; set; }

    public Guid TrackId { get; set; }

    public string GameCode { get; set; } = string.Empty;

    public string SessionRef { get; set; } = string.Empty;

    public SessionType SessionType { get; set; }

    /// <summary>세션 안 조각 순번(0부터).</summary>
    public int ChunkIndex { get; set; }

    /// <summary>세션의 마지막 조각.</summary>
    public bool IsLast { get; set; }

    /// <summary>표본 배치 버전.</summary>
    public int Format { get; set; }

    public int SampleRateHz { get; set; }

    public int FrameCount { get; set; }

    public int SampleCount { get; set; }

    /// <summary>트랙 길이(m). 모르면 null.</summary>
    public int? TrackLengthM { get; set; }

    /// <summary>gzip(열 배치 표본).</summary>
    public byte[] Payload { get; set; } = [];
}
