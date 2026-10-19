using System.Net;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.Startup;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// CORS(16 §4.4, D-56): 운영은 <c>Cors:AllowedOrigins</c>에 적힌 오리진(GitHub Pages)만 허용하고, 설정이 없으면 CORS를 열지 않는다.
/// Development는 기존처럼 루프백 오리진(Flutter 웹 dev)만 허용한다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class CorsE2ETests
{
    private const string PagesOrigin = "https://stlim1025.github.io";
    private const string OtherOrigin = "https://evil.example";
    private const string LoopbackOrigin = "http://localhost:5960";

    /// <summary>운영 환경이지만 appsettings 파일이 없는 환경 이름(설정 없음 = CORS 닫힘 확인용).</summary>
    private const string EnvironmentWithoutSettingsFile = "Staging";

    /// <summary>Production은 user-secrets를 읽지 않으므로 테스트 전용 서명 키를 넣는다(시크릿 아님).</summary>
    private const string TestJwtKey = "integration-test-jwt-key-not-a-secret-0123456789";

    [Fact]
    public async Task Production_PreflightFromAllowedOrigin_IsAllowedWithCredentials()
    {
        await using var factory = CreateFactory(Environments.Production, new Dictionary<string, string?>
        {
            ["Cors:AllowedOrigins:0"] = PagesOrigin,
        });

        var response = await factory.CreateClient().SendAsync(BuildPreflight(PagesOrigin));

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(PagesOrigin, SingleHeader(response, "Access-Control-Allow-Origin"));
        Assert.Equal("true", SingleHeader(response, "Access-Control-Allow-Credentials"));
    }

    [Fact]
    public async Task Production_PreflightFromOtherOrigin_IsNotAllowed()
    {
        await using var factory = CreateFactory(Environments.Production, new Dictionary<string, string?>
        {
            ["Cors:AllowedOrigins:0"] = PagesOrigin,
        });

        var response = await factory.CreateClient().SendAsync(BuildPreflight(OtherOrigin));

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    [Fact]
    public async Task NonDevelopment_WithoutAllowedOrigins_SendsNoCorsHeaders()
    {
        await using var factory = CreateFactory(EnvironmentWithoutSettingsFile, new Dictionary<string, string?>());

        var response = await factory.CreateClient().SendAsync(BuildPreflight(PagesOrigin));

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    [Fact]
    public async Task Development_PreflightFromLoopbackOrigin_IsStillAllowed()
    {
        await using var factory = new ApiFactory();

        var response = await factory.CreateClient().SendAsync(BuildPreflight(LoopbackOrigin));

        Assert.Equal(LoopbackOrigin, SingleHeader(response, "Access-Control-Allow-Origin"));
    }

    private static ApiFactory CreateFactory(string environmentName, Dictionary<string, string?> settings)
    {
        settings["Jwt:Key"] = TestJwtKey;
        settings[DatabaseStartup.MigrateOnStartupKey] = "false"; // 컬렉션 fixture가 이미 마이그레이션·시드했다
        return new ApiFactory(environmentName, settings);
    }

    /// <summary>브라우저가 인증 헤더를 실은 GET 전에 보내는 preflight 요청.</summary>
    private static HttpRequestMessage BuildPreflight(string origin)
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/v1/me");
        request.Headers.Add("Origin", origin);
        request.Headers.Add("Access-Control-Request-Method", "GET");
        request.Headers.Add("Access-Control-Request-Headers", "authorization");
        return request;
    }

    private static string? SingleHeader(HttpResponseMessage response, string name)
        => response.Headers.TryGetValues(name, out var values) ? values.Single() : null;
}
