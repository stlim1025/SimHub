using System.Threading.RateLimiting;
using SimCenter.Api.Common;

namespace SimCenter.Api.RateLimiting;

/// <summary>요청 제한 등록(연결 API 11 §4.4, 이메일 변경 14 §5). ASP.NET Core 내장 Rate Limiting(고정 창)을 쓴다.</summary>
public static class RateLimitingExtensions
{
    /// <summary>원격 IP를 알 수 없을 때(예: 테스트 서버)의 파티션 키.</summary>
    private const string UnknownRemoteIp = "unknown";

    /// <summary>
    /// <see cref="RateLimitPolicies.AgentPair"/>(IP 파티션), <see cref="RateLimitPolicies.PairingCodeIssue"/>·<see cref="RateLimitPolicies.EmailChange"/>(사용자 파티션)를 등록한다.
    /// 한도를 넘으면 429. 파이프라인에는 <c>UseAuthorization()</c> 뒤에 <c>UseRateLimiter()</c>를 추가해야 한다
    /// (사용자 파티션이 인증된 주체를 읽고, 인증 실패 요청이 한도를 소모하지 않도록).
    /// </summary>
    public static IServiceCollection AddSimCenterRateLimiting(this IServiceCollection services)
        => services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

            options.AddPolicy(RateLimitPolicies.AgentPair, context =>
                RateLimitPartition.GetFixedWindowLimiter(GetRemoteIpKey(context), _ => CreateFixedWindow()));

            options.AddPolicy(RateLimitPolicies.PairingCodeIssue, context =>
                RateLimitPartition.GetFixedWindowLimiter(GetUserKey(context), _ => CreateFixedWindow()));

            options.AddPolicy(RateLimitPolicies.EmailChange, context =>
                RateLimitPartition.GetFixedWindowLimiter(GetUserKey(context), _ => CreateFixedWindow()));
        });

    private static FixedWindowRateLimiterOptions CreateFixedWindow() => new()
    {
        PermitLimit = RateLimitPolicies.PermitLimit,
        Window = RateLimitPolicies.Window,
        QueueLimit = 0, // 한도 초과는 대기 없이 즉시 거절한다.
    };

    private static string GetRemoteIpKey(HttpContext context)
        => context.Connection.RemoteIpAddress?.ToString() ?? UnknownRemoteIp;

    /// <summary>사용자 ID 클레임이 있으면 사용자 단위, 없으면 IP 단위로 묶는다(방어적 폴백 — 인증된 요청이면 항상 클레임이 있다).</summary>
    private static string GetUserKey(HttpContext context)
        => context.User.FindUserIdClaim() is { } userId
            ? $"user:{userId}"
            : $"ip:{GetRemoteIpKey(context)}";
}
