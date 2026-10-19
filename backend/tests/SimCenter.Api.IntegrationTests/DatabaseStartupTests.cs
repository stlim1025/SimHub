using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.Startup;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 기동 시 마이그레이션·시드 실행 여부 판단(16 §4.2). DB 없이 설정·환경만으로 확인한다.
/// </summary>
public sealed class DatabaseStartupTests
{
    [Theory]
    [InlineData("Development", null, true)]   // 설정이 없으면 Development는 기존처럼 실행
    [InlineData("Production", null, false)]   // 설정이 없으면 운영은 실행하지 않음
    [InlineData("Production", "true", true)]  // 운영도 설정으로 켠다
    [InlineData("Development", "false", false)] // 개발도 설정으로 끌 수 있다
    public void ShouldMigrate_UsesSetting_ElseDevelopmentDefault(string environmentName, string? setting, bool expected)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { [DatabaseStartup.MigrateOnStartupKey] = setting })
            .Build();

        var actual = DatabaseStartup.ShouldMigrate(new FakeHostEnvironment(environmentName), configuration);

        Assert.Equal(expected, actual);
    }

    private sealed class FakeHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;

        public string ApplicationName { get; set; } = nameof(DatabaseStartupTests);

        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;

        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
