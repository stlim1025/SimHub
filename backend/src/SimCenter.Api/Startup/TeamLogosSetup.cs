using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.FileProviders;

namespace SimCenter.Api.Startup;

/// <summary>
/// 팀 로고 정적 파일(D-48). 로고는 상표라 저장소·앱 번들에 넣지 않고, 서버 PC의 폴더(<c>TeamLogos:Directory</c>)에서
/// <c>/team-logos/{코드}.png</c>로 내보낸다. PNG만, 익명 접근, 하루 캐시.
/// 설정이 없거나 폴더가 없으면 아무것도 내보내지 않는다(앱은 팀 색 원 + 코드로 대신 그린다).
/// CORS 헤더가 붙도록 파이프라인에서 <c>UseCors()</c> 뒤에 둔다(Flutter 웹 CanvasKit은 이미지를 XHR로 읽는다).
/// </summary>
public static class TeamLogosSetup
{
    /// <summary>로고 폴더 설정 키(절대 경로).</summary>
    public const string DirectoryKey = "TeamLogos:Directory";

    /// <summary>로고 URL 경로 접두사.</summary>
    public const string RequestPath = "/team-logos";

    private const string PngExtension = ".png";
    private const string PngContentType = "image/png";

    /// <summary>브라우저 캐시 기간. 로고는 거의 바뀌지 않는다.</summary>
    private static readonly TimeSpan CacheDuration = TimeSpan.FromDays(1);

    /// <summary>설정된 로고 폴더가 있으면 정적 파일 미들웨어를 붙인다. 없으면 로그만 남기고 그대로 둔다.</summary>
    public static WebApplication UseTeamLogos(this WebApplication app)
    {
        ArgumentNullException.ThrowIfNull(app);

        var logger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger(typeof(TeamLogosSetup));
        var directory = app.Configuration[DirectoryKey];
        if (string.IsNullOrWhiteSpace(directory))
        {
            logger.LogInformation("Team logos disabled: {Key} is not set", DirectoryKey);
            return app;
        }

        if (!Path.IsPathRooted(directory) || !Directory.Exists(directory))
        {
            logger.LogWarning("Team logos disabled: directory {Directory} ({Key}) does not exist or is not absolute", directory, DirectoryKey);
            return app;
        }

        // PNG만 알려진 형식으로 두고 그 밖의 확장자는 내보내지 않는다(ServeUnknownFileTypes = false).
        var contentTypes = new FileExtensionContentTypeProvider(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { [PngExtension] = PngContentType });
        var cacheControl = $"public, max-age={(int)CacheDuration.TotalSeconds}";

        app.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(directory),
            RequestPath = RequestPath,
            ContentTypeProvider = contentTypes,
            ServeUnknownFileTypes = false,
            OnPrepareResponse = context => context.Context.Response.Headers.CacheControl = cacheControl,
        });

        logger.LogInformation("Team logos served from {Directory} at {RequestPath}", directory, RequestPath);
        return app;
    }
}
