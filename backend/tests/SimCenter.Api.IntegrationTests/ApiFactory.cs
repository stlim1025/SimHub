using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// Development 환경으로 부팅해 user-secrets 로드 + 마이그레이션/시드가 실행되게 한다.
/// 연결 문자열은 Database만 테스트 DB(<see cref="TestDatabase.Name"/>)로 바꿔, 개발 DB에 테스트 데이터가 쌓이지 않게 한다.
/// TestServer는 원격 IP를 제공하지 않으므로, 테스트가 <see cref="RemoteIpHeader"/> 헤더로 요청별 원격 IP를 지정할 수 있게 한다
/// (IP 기반 요청 제한을 테스트 간에 격리하기 위함). 헤더가 없으면 원격 IP는 null이다.
/// 운영 설정을 시험할 때는 환경 이름과 추가 설정을 지정하는 생성자를 쓴다(추가 설정은 appsettings·user-secrets보다 우선한다).
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    /// <summary>요청의 <c>Connection.RemoteIpAddress</c>를 지정하는 테스트 전용 헤더.</summary>
    public const string RemoteIpHeader = "X-Test-Remote-IP";

    /// <summary>커뮤니티 셋업 주기 갱신 스위치 설정 키.</summary>
    private const string CommunitySetupsEnabledKey = "CommunitySetups:Enabled";

    private readonly string _environmentName;
    private readonly IReadOnlyDictionary<string, string?> _settings;

    public ApiFactory()
        : this(Environments.Development, new Dictionary<string, string?>())
    {
    }

    /// <param name="environmentName">호스트 환경 이름(예: <see cref="Environments.Production"/>).</param>
    /// <param name="settings">테스트 DB 연결 문자열에 더해 넣을 설정.</param>
    /// <remarks>xUnit 클래스 픽스처는 public 생성자가 하나여야 하므로 internal로 둔다.</remarks>
    internal ApiFactory(string environmentName, IReadOnlyDictionary<string, string?> settings)
    {
        _environmentName = environmentName;
        _settings = settings;
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        builder.UseEnvironment(_environmentName);
        // 호스트 설정은 Program에 명령줄 인수로 전달되어 서비스 등록 시점(AddInfrastructure가 연결 문자열을 읽을 때)에 보인다.
        // ConfigureAppConfiguration은 Program의 등록 코드가 끝난 뒤 적용되어 개발 DB 연결 문자열이 그대로 쓰인다.
        // 커뮤니티 셋업 갱신(외부 사이트 요청)은 테스트에서 항상 끈다 — 운영 환경으로 부팅하는 테스트도 마찬가지.
        var hostSettings = new Dictionary<string, string?>(_settings)
        {
            [TestDatabase.ConnectionStringKey] = TestDatabase.BuildConnectionString(),
            [CommunitySetupsEnabledKey] = bool.FalseString,
        };
        builder.ConfigureHostConfiguration(config => config.AddInMemoryCollection(hostSettings));
        builder.ConfigureServices(services => services.AddSingleton<IStartupFilter, TestRemoteIpStartupFilter>());
        return base.CreateHost(builder);
    }

    /// <summary>파이프라인 맨 앞에서 테스트 헤더 값을 원격 IP로 반영한다.</summary>
    private sealed class TestRemoteIpStartupFilter : IStartupFilter
    {
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
        {
            app.Use(async (context, nextMiddleware) =>
            {
                if (context.Request.Headers.TryGetValue(RemoteIpHeader, out var value)
                    && IPAddress.TryParse(value.ToString(), out var address))
                {
                    context.Connection.RemoteIpAddress = address;
                }

                await nextMiddleware();
            });

            next(app);
        };
    }
}
