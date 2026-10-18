using SimCenter.Domain.Common;

namespace SimCenter.Domain.Entities;

/// <summary>
/// 1랩 텔레메트리 트레이스(15 §3.3·§5, D-45). Lap과 1:0..1(Unique LapId), 랩과 같은 트랜잭션으로 한 번만 저장한다(불변).
/// 거리 기준 표본 7채널(timeMs·speedKph·throttle·brake·steer·gear·rpm)의 JSON을 gzip한 <see cref="Payload"/>(bytea, D-18)로 둔다.
/// 크기 때문에 <c>Lap</c>에 내비게이션을 두지 않는다 — 랩 목록·상세가 실수로 불러오지 않게 FK만 건다.
/// </summary>
public class LapTelemetryTrace : BaseEntity
{
    public Guid LapId { get; set; }

    /// <summary>표본 간격(m). 기본 5, 크기 한도를 넘으면 Agent가 10·20으로 낮춘다.</summary>
    public int ResolutionM { get; set; }

    /// <summary>채널마다 같은 표본 수.</summary>
    public int SampleCount { get; set; }

    /// <summary>gzip(JSON 7개 배열). 보존 기간 무기한.</summary>
    public byte[] Payload { get; set; } = [];
}
