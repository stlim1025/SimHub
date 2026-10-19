namespace SimCenter.Api.Startup;

/// <summary>
/// CORS 등록(16 §4.4, D-56). 기본 정책 하나만 두고 파이프라인은 <c>UseCors()</c>로 그 정책을 쓴다.
/// - Development: Flutter 웹 dev 실행을 위해 루프백 오리진만 반사 허용(기존 동작).
/// - 그 외: <c>Cors:AllowedOrigins</c>에 적힌 오리진(GitHub Pages)만 허용. 설정이 없으면 정책을 두지 않아 CORS를 열지 않는다(동일 오리진만).
/// 와일드카드는 쓰지 않는다. SignalR negotiate를 위해 자격 증명을 허용한다.
/// </summary>
public static class CorsSetup
{
    /// <summary>허용 오리진 목록 설정 키(문자열 배열).</summary>
    public const string AllowedOriginsKey = "Cors:AllowedOrigins";

    public static IServiceCollection AddSimCenterCors(
        this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        if (environment.IsDevelopment())
        {
            return services.AddCors(options => options.AddDefaultPolicy(policy =>
                policy.SetIsOriginAllowed(origin => Uri.TryCreate(origin, UriKind.Absolute, out var uri) && uri.IsLoopback)
                    .AllowAnyHeader()
                    .AllowAnyMethod()
                    .AllowCredentials()));
        }

        // 오리진은 경로가 없으므로 끝의 '/'를 떼어 브라우저가 보내는 Origin 값과 정확히 맞춘다.
        var origins = (configuration.GetSection(AllowedOriginsKey).Get<string[]>() ?? [])
            .Where(origin => !string.IsNullOrWhiteSpace(origin))
            .Select(origin => origin.Trim().TrimEnd('/'))
            .ToArray();

        return services.AddCors(options =>
        {
            if (origins.Length > 0)
            {
                options.AddDefaultPolicy(policy => policy.WithOrigins(origins)
                    .AllowAnyHeader()
                    .AllowAnyMethod()
                    .AllowCredentials());
            }
        });
    }
}
