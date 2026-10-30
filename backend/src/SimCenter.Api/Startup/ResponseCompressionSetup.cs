using System.IO.Compression;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.ResponseCompression;

namespace SimCenter.Api.Startup;

/// <summary>
/// 응답 압축(brotli·gzip). 운영은 Tailscale Funnel 중계를 거쳐 나가 응답 크기가 곧 대기 시간이다 — 랩 트레이스 한 개가 압축 없이 약 500KB,
/// gzip이면 약 1/4이다. 압축은 <c>/api</c> 아래 GET 응답만 한다: 로그인·토큰 갱신·Agent 연결처럼 비밀 값을 돌려주는 응답은 POST이고,
/// HTTPS에서 비밀이 든 응답을 압축하면 길이로 내용을 추측하는 공격(BREACH)에 노출될 수 있어서다. SignalR(<c>/hubs</c>)도 건드리지 않는다.
/// 파이프라인에는 응답 본문을 쓰는 미들웨어보다 앞에 <see cref="UseSimCenterResponseCompression"/>을 둔다.
/// </summary>
public static class ResponseCompressionSetup
{
    private const string ApiPathPrefix = "/api";

    public static IServiceCollection AddSimCenterResponseCompression(this IServiceCollection services)
    {
        // 기본은 HTTPS 응답을 압축하지 않는다(EnableForHttps = false) — 아래 미들웨어가 GET API 응답만 골라 켠다.
        services.AddResponseCompression(options =>
        {
            options.Providers.Add<BrotliCompressionProvider>();
            options.Providers.Add<GzipCompressionProvider>();
        });

        // 가장 빠른 수준: 트레이스는 반복이 많아 이 수준으로도 충분히 줄고, 상시 켜 둔 PC의 CPU를 아낀다.
        services.Configure<BrotliCompressionProviderOptions>(options => options.Level = CompressionLevel.Fastest);
        services.Configure<GzipCompressionProviderOptions>(options => options.Level = CompressionLevel.Fastest);
        return services;
    }

    public static IApplicationBuilder UseSimCenterResponseCompression(this IApplicationBuilder app)
    {
        // 압축 미들웨어가 요청마다 IHttpsCompressionFeature를 붙이므로, HTTPS 압축을 켜는 건 그 뒤에서 해야 한다.
        app.UseResponseCompression();
        return app.Use((context, next) =>
        {
            if (HttpMethods.IsGet(context.Request.Method)
                && context.Request.Path.StartsWithSegments(ApiPathPrefix, StringComparison.OrdinalIgnoreCase)
                && context.Features.Get<IHttpsCompressionFeature>() is { } feature)
            {
                feature.Mode = HttpsCompressionMode.Compress;
            }

            return next(context);
        });
    }
}
