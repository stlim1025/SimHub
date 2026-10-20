using System.Net;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.Startup;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 팀 로고 정적 파일(D-48): <c>TeamLogos:Directory</c>의 PNG를 <c>/team-logos/{코드}.png</c>로 익명 제공하고,
/// 허용 오리진(GitHub Pages)에는 CORS 헤더를 붙인다. 없는 파일·PNG가 아닌 파일은 404, 폴더가 없으면 아무것도 내보내지 않는다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class TeamLogosE2ETests : IDisposable
{
    private const string PagesOrigin = "https://stlim1025.github.io";

    /// <summary>Production은 user-secrets를 읽지 않으므로 테스트 전용 서명 키를 넣는다(시크릿 아님).</summary>
    private const string TestJwtKey = "integration-test-jwt-key-not-a-secret-0123456789";

    /// <summary>PNG 시그니처(8바이트) — 내용 확인용 가짜 로고.</summary>
    private static readonly byte[] PngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"simcenter-team-logos-{Guid.NewGuid():N}");

    public TeamLogosE2ETests()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllBytes(Path.Combine(_directory, "FER.png"), PngBytes);
        File.WriteAllText(Path.Combine(_directory, "notes.txt"), "not a logo");
    }

    public void Dispose() => Directory.Delete(_directory, recursive: true);

    [Fact]
    public async Task ExistingLogo_IsServedAnonymouslyAsPngWithCacheAndCors()
    {
        await using var factory = CreateFactory(_directory);
        var request = new HttpRequestMessage(HttpMethod.Get, $"{TeamLogosSetup.RequestPath}/FER.png");
        request.Headers.Add("Origin", PagesOrigin);

        var response = await factory.CreateClient().SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("image/png", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(PngBytes, await response.Content.ReadAsByteArrayAsync());
        Assert.True(response.Headers.CacheControl?.Public);
        Assert.Equal(TimeSpan.FromDays(1), response.Headers.CacheControl?.MaxAge);
        Assert.Equal(PagesOrigin, response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task MissingLogoOrNonPng_IsNotFound()
    {
        await using var factory = CreateFactory(_directory);
        var client = factory.CreateClient();

        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"{TeamLogosSetup.RequestPath}/MER.png")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"{TeamLogosSetup.RequestPath}/notes.txt")).StatusCode);
    }

    [Fact]
    public async Task MissingDirectory_ServesNothingAndStillStarts()
    {
        await using var factory = CreateFactory(Path.Combine(_directory, "missing"));

        var response = await factory.CreateClient().GetAsync($"{TeamLogosSetup.RequestPath}/FER.png");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static ApiFactory CreateFactory(string directory) => new(Environments.Production, new Dictionary<string, string?>
    {
        ["Jwt:Key"] = TestJwtKey,
        [DatabaseStartup.MigrateOnStartupKey] = "false", // 컬렉션 fixture가 이미 마이그레이션·시드했다
        ["Cors:AllowedOrigins:0"] = PagesOrigin,
        [TeamLogosSetup.DirectoryKey] = directory,
    });
}
