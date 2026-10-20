using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Extensions.FileProviders;
using Microsoft.Net.Http.Headers;

namespace SimCenter.Api.Startup;

/// <summary>
/// 내려받기 파일(Agent 설치 묶음). 빌드 산출물은 공개 저장소에 넣지 않고, 서버 PC의 폴더(<c>Downloads:Directory</c>)에서
/// <c>/downloads/{파일}</c>로 내보낸다. 허용 확장자는 .zip·.exe(첨부로 내려받기)와 .json(빌드 정보)뿐, 익명 접근.
/// 새 빌드를 올리면 바로 받도록 <c>Cache-Control: no-cache</c>(매번 재검증)를 붙인다.
/// 설정이 없거나 폴더가 없으면 아무것도 내보내지 않는다(404). 팀 로고(<see cref="TeamLogosSetup"/>)와 같은 방식이며,
/// 웹 앱이 빌드 정보 JSON을 XHR로 읽으므로 파이프라인에서 <c>UseCors()</c> 뒤에 둔다.
/// </summary>
public static class DownloadsSetup
{
    /// <summary>내려받기 폴더 설정 키(절대 경로).</summary>
    public const string DirectoryKey = "Downloads:Directory";

    /// <summary>내려받기 URL 경로 접두사.</summary>
    public const string RequestPath = "/downloads";

    private const string ZipExtension = ".zip";
    private const string ZipContentType = "application/zip";
    private const string ExeExtension = ".exe";
    private const string ExeContentType = "application/vnd.microsoft.portable-executable";
    private const string JsonExtension = ".json";
    private const string JsonContentType = "application/json";

    /// <summary>항상 서버에 재검증(ETag/Last-Modified)해 새 빌드를 바로 받게 한다.</summary>
    private const string CacheControlValue = "no-cache";

    /// <summary>브라우저가 열지 않고 파일로 저장하게 할 확장자(.json은 앱이 읽는 메타데이터라 제외).</summary>
    private static readonly HashSet<string> AttachmentExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ZipExtension, ExeExtension };

    /// <summary>설정된 내려받기 폴더가 있으면 정적 파일 미들웨어를 붙인다. 없으면 로그만 남기고 그대로 둔다.</summary>
    public static WebApplication UseDownloads(this WebApplication app)
    {
        ArgumentNullException.ThrowIfNull(app);

        var logger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger(typeof(DownloadsSetup));
        var directory = app.Configuration[DirectoryKey];
        if (string.IsNullOrWhiteSpace(directory))
        {
            logger.LogInformation("Downloads disabled: {Key} is not set", DirectoryKey);
            return app;
        }

        if (!Path.IsPathRooted(directory) || !Directory.Exists(directory))
        {
            logger.LogWarning("Downloads disabled: directory {Directory} ({Key}) does not exist or is not absolute", directory, DirectoryKey);
            return app;
        }

        // 허용 확장자만 알려진 형식으로 두고 그 밖의 파일은 내보내지 않는다(ServeUnknownFileTypes = false).
        var contentTypes = new FileExtensionContentTypeProvider(
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                [ZipExtension] = ZipContentType,
                [ExeExtension] = ExeContentType,
                [JsonExtension] = JsonContentType,
            });

        app.UseStaticFiles(new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(directory),
            RequestPath = RequestPath,
            ContentTypeProvider = contentTypes,
            ServeUnknownFileTypes = false,
            OnPrepareResponse = PrepareResponse,
        });

        logger.LogInformation("Downloads served from {Directory} at {RequestPath}", directory, RequestPath);
        return app;
    }

    private static void PrepareResponse(StaticFileResponseContext context)
    {
        var headers = context.Context.Response.Headers;
        headers.CacheControl = CacheControlValue;

        var fileName = context.File.Name;
        if (AttachmentExtensions.Contains(Path.GetExtension(fileName)))
        {
            var disposition = new ContentDispositionHeaderValue("attachment");
            disposition.SetHttpFileName(fileName);
            headers.ContentDisposition = disposition.ToString();
        }
    }
}
