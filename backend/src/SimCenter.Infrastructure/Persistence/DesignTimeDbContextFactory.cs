using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace SimCenter.Infrastructure.Persistence;

/// <summary>
/// 설계 시(dotnet ef) DbContext 생성 팩토리. 마이그레이션 '생성'은 DB에 연결하지 않으므로
/// 실제 연결 문자열이 필요 없다. 이 팩토리는 웹 호스트/시크릿과 무관하게 마이그레이션을 만들 수 있게 한다.
/// 연결 문자열은 SIMCENTER_POSTGRES 환경변수로 재정의할 수 있다(database update 시 사용).
/// </summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var connectionString = Environment.GetEnvironmentVariable("SIMCENTER_POSTGRES")
            ?? "Host=localhost;Database=simcenter;Username=postgres;Password=postgres";

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(connectionString)
            .UseSnakeCaseNamingConvention()
            .Options;

        return new AppDbContext(options);
    }
}
