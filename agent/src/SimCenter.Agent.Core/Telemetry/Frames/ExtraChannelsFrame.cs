namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 플레이어 차의 순간 값 묶음 — 트레이스 <c>extra</c> 채널(D-49, docs/15 §8)의 원천. 이름 → 값(이미 채널 단위로 바꾼 값).
/// Core는 이름의 뜻을 모른다: 채널 목록·단위는 매퍼와 <c>shared/telemetry/f1_25_udp_spec.md</c> 카탈로그가 정한다.
/// 같은 이름이 여러 프레임에서 오면 가장 최근 값이 이긴다. 유한하지 않은 값은 기록기가 버린다(앞 값 유지).
/// </summary>
public sealed record ExtraChannelsFrame(
    string SessionRef,
    IReadOnlyDictionary<string, double> Channels) : ITelemetryFrame;
