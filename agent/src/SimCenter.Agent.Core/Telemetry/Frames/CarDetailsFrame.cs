namespace SimCenter.Agent.Core.Telemetry.Frames;

/// <summary>
/// 이름 붙은 상세 값 묶음 1개 — 랩 스냅샷 <c>car.details</c>(D-49, docs/15 §8)의 원천. <paramref name="Section"/>(예: <c>setup</c>·<c>damage</c>·<c>status</c>)마다
/// 가장 최근 묶음이 이긴다. Core는 묶음 안의 뜻을 모른다 — 키는 camelCase, 값은 숫자·불리언·문자열·null, 또는 그런 값의 사전·목록이다
/// (그 밖의 형과 유한하지 않은 숫자는 랩 끝에 null로 다듬는다). 키·뜻은 매퍼와 <c>shared/telemetry/f1_25_udp_spec.md</c> §7이 정한다.
/// </summary>
public sealed record CarDetailsFrame(
    string SessionRef,
    string Section,
    IReadOnlyDictionary<string, object?> Values) : ITelemetryFrame;
