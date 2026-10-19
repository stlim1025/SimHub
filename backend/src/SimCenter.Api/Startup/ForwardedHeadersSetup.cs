using System.Net;
using Microsoft.AspNetCore.HttpOverrides;

namespace SimCenter.Api.Startup;

/// <summary>
/// 프록시 헤더 등록(16 §4.3, D-58). 같은 PC의 Tailscale Funnel이 HTTPS를 받아 루프백으로 넘기므로,
/// 루프백에서 온 <c>X-Forwarded-For</c>·<c>X-Forwarded-Proto</c>만 믿는다.
/// For는 IP당 요청 제한이 실제 클라이언트별로 나뉘게 하고, Proto는 HTTPS 리다이렉트가 반복되지 않게 한다.
/// 다른 곳에서 온 헤더는 무시한다 — 믿으면 <c>X-Forwarded-For</c> 위조로 요청 제한을 우회할 수 있다(11 §9 배포 메모).
/// 파이프라인에는 맨 앞에 <c>UseForwardedHeaders()</c>를 추가해야 한다(요청 로그·요청 제한·리다이렉트가 바뀐 값을 보도록).
/// </summary>
public static class ForwardedHeadersSetup
{
    public static IServiceCollection AddSimCenterForwardedHeaders(this IServiceCollection services)
        => services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

            // 기본값(127.0.0.0/8 대역 + ::1)에 기대지 않고 신뢰 대상을 루프백 두 주소로 고정한다.
            options.KnownIPNetworks.Clear();
            options.KnownProxies.Clear();
            options.KnownProxies.Add(IPAddress.Loopback);
            options.KnownProxies.Add(IPAddress.IPv6Loopback);
        });
}
