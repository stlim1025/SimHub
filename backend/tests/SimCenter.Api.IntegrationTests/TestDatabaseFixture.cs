using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using SimCenter.Domain.Entities;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// <see cref="DatabaseCollection"/> 시작 시 한 번: 테스트 DB를 생성·마이그레이션·시드하고 이전 실행이 남긴 데이터를 비운다.
/// 실행 전에 비우므로 실행을 반복해도 데이터가 쌓이지 않고, 마지막 실행의 데이터는 디버깅용으로 남는다.
/// 시드 테이블(<see cref="SeedEntityTypes"/>)과 마이그레이션 이력은 남긴다.
/// 다른 프로세스의 테스트 실행이 같은 테스트 DB를 쓰는 도중에 비우지 않도록, 실행 내내 advisory lock을 잡는다.
/// </summary>
public sealed class TestDatabaseFixture : IAsyncLifetime
{
    /// <summary>테스트 실행 간 상호 배제용 advisory lock 키(임의 고정값).</summary>
    private const long RunLockKey = 7_351_120_026;

    /// <summary>다른 실행이 끝나기를 기다리는 최대 시간.</summary>
    private const int RunLockWaitSeconds = 600;

    /// <summary>실행마다 비우지 않는 시드 엔터티(호스트 시작 시 DbSeeder가 채운다).</summary>
    private static readonly Type[] SeedEntityTypes = [typeof(Track)];

    private NpgsqlConnection? _runLockConnection;

    public async Task InitializeAsync()
    {
        // 호스트를 한 번 부팅하면 Program(Development)이 테스트 DB를 생성·마이그레이션·시드한다.
        await using var factory = new ApiFactory();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        EnsureTestDatabase(db);

        // 풀링을 꺼야 Dispose 때 물리 연결(세션)이 닫히며 lock이 풀린다. 풀에 반환된 연결은 세션을 유지해 lock을 계속 쥔다.
        var runLockConnectionString = new NpgsqlConnectionStringBuilder(db.Database.GetConnectionString()) { Pooling = false };
        _runLockConnection = new NpgsqlConnection(runLockConnectionString.ConnectionString);
        await _runLockConnection.OpenAsync();
        await AcquireRunLockAsync(_runLockConnection);

        await db.Database.ExecuteSqlRawAsync(BuildTruncateSql(db));
    }

    public async Task DisposeAsync()
    {
        // 풀링하지 않는 연결이므로 닫으면 세션이 끝나 advisory lock도 풀린다. 프로세스가 비정상 종료돼도 서버가 세션을 정리하며 풀린다.
        if (_runLockConnection is not null)
        {
            await _runLockConnection.DisposeAsync();
        }
    }

    /// <summary>연결 문자열 교체가 적용되지 않아 개발 DB를 가리키면 데이터를 비우기 전에 중단한다.</summary>
    private static void EnsureTestDatabase(AppDbContext db)
    {
        var database = db.Database.GetDbConnection().Database;
        if (!string.Equals(database, TestDatabase.Name, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"테스트 DB '{TestDatabase.Name}'가 아닌 '{database}'에 연결되어 데이터 정리를 중단합니다.");
        }
    }

    private static async Task AcquireRunLockAsync(NpgsqlConnection connection)
    {
        await using var command = new NpgsqlCommand("SELECT pg_advisory_lock(@key)", connection)
        {
            CommandTimeout = RunLockWaitSeconds,
        };
        command.Parameters.AddWithValue("key", RunLockKey);
        await command.ExecuteNonQueryAsync();
    }

    /// <summary>
    /// 모델의 테이블 중 시드 테이블을 뺀 전부를 한 문장으로 비운다. 새 엔터티가 추가돼도 자동으로 포함된다.
    /// CASCADE를 쓰지 않으므로, 비우는 테이블을 참조하는 테이블이 목록에 없으면(예: 시드 테이블) 조용히 지우지 않고 실패한다.
    /// </summary>
    private static string BuildTruncateSql(AppDbContext db)
    {
        var sql = db.GetService<ISqlGenerationHelper>();
        var tables = db.Model.GetEntityTypes()
            .Where(entityType => !SeedEntityTypes.Contains(entityType.ClrType))
            .Select(entityType => (Table: entityType.GetTableName(), Schema: entityType.GetSchema()))
            .Where(mapping => mapping.Table is not null)
            .Distinct()
            .Select(mapping => sql.DelimitIdentifier(mapping.Table!, mapping.Schema));

        return $"TRUNCATE TABLE {string.Join(", ", tables)}";
    }
}
