namespace SimCenter.Api.RateLimiting;

/// <summary>
/// 요청 제한 정책(연결 API 11 §4.4, 이메일 변경 14 §5). 이름은 <c>[EnableRateLimiting]</c>에서 참조하고,
/// 한도·창은 모든 정책이 공유한다(고정 창 방식, 분당 10회).
/// </summary>
public static class RateLimitPolicies
{
    /// <summary><c>POST /agent/pair</c> — 클라이언트 IP당.</summary>
    public const string AgentPair = "agent-pair";

    /// <summary><c>POST /me/agent-pairing-codes</c> — 사용자당.</summary>
    public const string PairingCodeIssue = "pairing-code-issue";

    /// <summary><c>POST /me/email</c> — 사용자당. 현재 비밀번호를 맞히려는 반복 시도를 늦춘다.</summary>
    public const string EmailChange = "email-change";

    /// <summary>창당 허용 요청 수.</summary>
    public const int PermitLimit = 10;

    /// <summary>고정 창 길이.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(1);
}
