using Microsoft.Extensions.Configuration;
using Npgsql;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// 통합 테스트 전용 DB. 개발 DB(<c>simcenter</c>)와 분리해 테스트 계정·장치·랩이 개발 화면(Leaderboard 등)에 섞이지 않게 한다.
/// 호스트·계정·비밀번호는 개발 호스트와 같은 출처(user-secrets → 환경 변수)의 <c>ConnectionStrings:Postgres</c>를 재사용하고 Database만 바꾼다.
/// </summary>
internal static class TestDatabase
{
    /// <summary>테스트 DB 이름. 데이터 정리는 이 이름의 DB에서만 허용된다.</summary>
    public const string Name = "simcenter_test";

    /// <summary>호스트가 읽는 연결 문자열 설정 키.</summary>
    public const string ConnectionStringKey = "ConnectionStrings:Postgres";

    /// <summary>개발 연결 문자열에서 Database만 <see cref="Name"/>으로 바꾼 연결 문자열.</summary>
    public static string BuildConnectionString()
    {
        // 개발 호스트(Development)와 같은 우선순위: user-secrets 뒤에 환경 변수가 덮어쓴다.
        var configuration = new ConfigurationBuilder()
            .AddUserSecrets<Program>(optional: true)
            .AddEnvironmentVariables()
            .Build();

        var developmentConnectionString = configuration[ConnectionStringKey]
            ?? throw new InvalidOperationException(
                $"연결 문자열 '{ConnectionStringKey}'가 설정되지 않았습니다. user-secrets를 먼저 주입하세요(docs/TESTING-local-e2e.md §0).");

        return new NpgsqlConnectionStringBuilder(developmentConnectionString) { Database = Name }.ConnectionString;
    }
}
