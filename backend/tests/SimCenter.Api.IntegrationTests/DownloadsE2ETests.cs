using System.Net;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.Startup;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Agent 내려받기 정적 파일: <c>Downloads:Directory</c>의 .zip·.exe·.json을 <c>/downloads/{파일}</c>로 익명 제공한다.
/// zip·exe는 첨부(Content-Disposition: attachment), 모두 <c>Cache-Control: no-cache</c>, 허용 오리진에는 CORS 헤더.
/// 없는 파일·허용하지 않는 확장자는 404, 폴더가 없으면 아무것도 내보내지 않는다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class DownloadsE2ETests : IDisposable
{
    private const string PagesOrigin = "https://stlim1025.github.io";

    /// <summary>Production은 user-secrets를 읽지 않으므로 테스트 전용 서명 키를 넣는다(시크릿 아님).</summary>
    private const string TestJwtKey = "integration-test-jwt-key-not-a-secret-0123456789";

    private const string ZipName = "SimHubAgent.zip";
    private const string ExeName = "SimHubAgent.exe";
    private const string MetadataName = "SimHubAgent.json";
    private const string MetadataJson = """{"version":"abc1234-20261020"}""";

    /// <summary>ZIP 로컬 헤더 시그니처(4바이트) — 내용 확인용 가짜 묶음.</summary>
    private static readonly byte[] ZipBytes = [0x50, 0x4B, 0x03, 0x04];

    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"simcenter-downloads-{Guid.NewGuid():N}");

    public DownloadsE2ETests()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllBytes(Path.Combine(_directory, ZipName), ZipBytes);
        File.WriteAllBytes(Path.Combine(_directory, ExeName), [0x4D, 0x5A]);
        File.WriteAllText(Path.Combine(_directory, MetadataName), MetadataJson);
        File.WriteAllText(Path.Combine(_directory, "appsettings.txt"), "not downloadable");
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task Zip_IsServedAnonymouslyAsAttachmentWithNoCacheAndCors()
    {
        await using var factory = CreateFactory(_directory);
        var request = new HttpRequestMessage(HttpMethod.Get, $"{DownloadsSetup.RequestPath}/{ZipName}");
        request.Headers.Add("Origin", PagesOrigin);

        var response = await factory.CreateClient().SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/zip", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(ZipBytes, await response.Content.ReadAsByteArrayAsync());
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition?.DispositionType);
        Assert.Equal(ZipName, response.Content.Headers.ContentDisposition?.FileName?.Trim('"'));
        Assert.True(response.Headers.CacheControl?.NoCache);
        Assert.Equal(PagesOrigin, response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task Exe_IsServedAsPortableExecutableAttachment()
    {
        await using var factory = CreateFactory(_directory);

        var response = await factory.CreateClient().GetAsync($"{DownloadsSetup.RequestPath}/{ExeName}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/vnd.microsoft.portable-executable", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal("attachment", response.Content.Headers.ContentDisposition?.DispositionType);
    }

    [Fact]
    public async Task Metadata_IsServedAsJsonInlineWithNoCacheAndCors()
    {
        await using var factory = CreateFactory(_directory);
        var request = new HttpRequestMessage(HttpMethod.Get, $"{DownloadsSetup.RequestPath}/{MetadataName}");
        request.Headers.Add("Origin", PagesOrigin);

        var response = await factory.CreateClient().SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(MetadataJson, await response.Content.ReadAsStringAsync());
        Assert.Null(response.Content.Headers.ContentDisposition);
        Assert.True(response.Headers.CacheControl?.NoCache);
        Assert.Equal(PagesOrigin, response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task MissingFileOrDisallowedExtension_IsNotFound()
    {
        await using var factory = CreateFactory(_directory);
        var client = factory.CreateClient();

        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"{DownloadsSetup.RequestPath}/Other.zip")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"{DownloadsSetup.RequestPath}/appsettings.txt")).StatusCode);
    }

    [Fact]
    public async Task MissingDirectory_ServesNothingAndStillStarts()
    {
        await using var factory = CreateFactory(Path.Combine(_directory, "missing"));

        var response = await factory.CreateClient().GetAsync($"{DownloadsSetup.RequestPath}/{ZipName}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static ApiFactory CreateFactory(string directory) => new(Environments.Production, new Dictionary<string, string?>
    {
        ["Jwt:Key"] = TestJwtKey,
        [DatabaseStartup.MigrateOnStartupKey] = "false", // 컬렉션 fixture가 이미 마이그레이션·시드했다
        ["Cors:AllowedOrigins:0"] = PagesOrigin,
        [DownloadsSetup.DirectoryKey] = directory,
    });
}
