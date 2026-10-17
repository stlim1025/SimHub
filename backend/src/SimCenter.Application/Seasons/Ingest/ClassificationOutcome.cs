namespace SimCenter.Application.Seasons.Ingest;

/// <summary>
/// 세션 순위표 처리 결과(12 §6.1). <see cref="Stored"/>·<see cref="Ignored"/>는 Ack, <see cref="Rejected"/>는 Reject로 이어진다.
/// 닫힌 계층 — 아래 세 가지뿐이다.
/// </summary>
public abstract record ClassificationOutcome
{
    private ClassificationOutcome()
    {
    }

    /// <summary>저장할 변경을 추적했다(신규 또는 병합). 저장 호출은 호출자의 몫이다.</summary>
    /// <param name="SessionKey">저장된 세션의 키.</param>
    /// <param name="IsNew">새 세션이면 true, 같은 키의 기존 세션에 병합했으면 false.</param>
    public sealed record Stored(string SessionKey, bool IsNew) : ClassificationOutcome;

    /// <summary>변경 없음(Time Trial, 늦게 온 옛 결과…). 아무것도 추적하지 않았다.</summary>
    public sealed record Ignored(string Reason) : ClassificationOutcome;

    /// <summary>영구 무효(파싱·검증·트랙 매핑 실패). 아무것도 추적하지 않았다.</summary>
    public sealed record Rejected(string Reason) : ClassificationOutcome;
}
