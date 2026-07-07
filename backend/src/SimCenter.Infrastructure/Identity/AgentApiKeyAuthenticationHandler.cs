using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Identity;

/// <summary>Agent API Key 인증 스킴 상수(D-21).</summary>
public static class AgentApiKeyDefaults
{
    public const string Scheme = "AgentApiKey";

    /// <summary>Agent가 키를 실어 보내는 헤더(.NET SignalR 클라이언트가 핸드셰이크에 첨부).</summary>
    public const string HeaderName = "X-Agent-Key";

    /// <summary>인증 성공 시 연결에 귀속되는 좌석 코드 클레임.</summary>
    public const string RigCodeClaim = "rigCode";
}

/// <summary>
/// TelemetryHub 전용 인증 핸들러. 요청의 API Key를 SHA-256 해시해 SimRig를 특정하고,
/// 연결에 RigCode 클레임을 귀속한다. 세션 매칭은 엔벨로프가 아닌 이 값을 신뢰한다(위조 방지).
/// </summary>
public sealed class AgentApiKeyAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public AgentApiKeyAuthenticationHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var key = ExtractKey();
        if (string.IsNullOrWhiteSpace(key))
        {
            return AuthenticateResult.NoResult();
        }

        var hasher = Context.RequestServices.GetRequiredService<IApiKeyHasher>();
        var rigs = Context.RequestServices.GetRequiredService<ISimRigRepository>();

        var rig = await rigs.GetByApiKeyHashAsync(hasher.Hash(key), Context.RequestAborted);
        if (rig is null)
        {
            return AuthenticateResult.Fail("유효하지 않은 Agent 키입니다.");
        }

        var claims = new[]
        {
            new Claim(AgentApiKeyDefaults.RigCodeClaim, rig.RigCode),
            new Claim(ClaimTypes.NameIdentifier, rig.Id.ToString()),
        };
        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name);
        return AuthenticateResult.Success(ticket);
    }

    private string? ExtractKey()
    {
        if (Request.Headers.TryGetValue(AgentApiKeyDefaults.HeaderName, out var header))
        {
            var value = header.ToString();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        // 커스텀 헤더를 못 싣는 전송 대비 쿼리 폴백(SignalR access_token 관례).
        var token = Request.Query["access_token"].ToString();
        return string.IsNullOrWhiteSpace(token) ? null : token;
    }
}
