using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SimCenter.Api.Startup;
using SimCenter.Domain.Constants;
using SimCenter.Infrastructure.Persistence;

namespace SimCenter.Api.IntegrationTests;

/// <summary>
/// <c>Database:MigrateOnStartup</c>이 실제 기동에서 마이그레이션·시드 실행을 정하는지 확인한다(16 §4.2, D-56).
/// 시드는 기존 트랙의 국가를 시드 값으로 맞추므로, 국가를 틀린 값으로 바꿔 두고 기동 후 고쳐졌는지로 시드 실행 여부를 본다.
/// </summary>
[Collection(DatabaseCollection.Name)]
public sealed class MigrateOnStartupE2ETests
{
    private const int JeddahId = 29;
    private const string JeddahCountry = "SA";
    private const string WrongCountry = "XX";

    /// <summary>Production은 user-secrets를 읽지 않으므로 테스트 전용 서명 키를 넣는다(시크릿 아님).</summary>
    private const string TestJwtKey = "integration-test-jwt-key-not-a-secret-0123456789";

    [Fact]
    public async Task Production_WithMigrateOnStartupTrue_RunsSeedOnStartup()
    {
        await SetJeddahCountryAsync(WrongCountry);
        try
        {
            await using var factory = new ApiFactory(Environments.Production, new Dictionary<string, string?>
            {
                [DatabaseStartup.MigrateOnStartupKey] = "true",
                ["Jwt:Key"] = TestJwtKey,
            });

            Assert.Equal(JeddahCountry, await ReadJeddahCountryAsync(factory));
        }
        finally
        {
            await RestoreSeedAsync();
        }
    }

    [Fact]
    public async Task Development_WithMigrateOnStartupFalse_SkipsSeedOnStartup()
    {
        await SetJeddahCountryAsync(WrongCountry);
        try
        {
            await using var factory = new ApiFactory(Environments.Development, new Dictionary<string, string?>
            {
                [DatabaseStartup.MigrateOnStartupKey] = "false",
            });

            Assert.Equal(WrongCountry, await ReadJeddahCountryAsync(factory));
        }
        finally
        {
            await RestoreSeedAsync();
        }
    }

    /// <summary>기본 호스트(Development, 시드 실행)를 띄운 뒤 국가를 바꾼다. 기동 시 시드가 먼저 끝나므로 바꾼 값이 남는다.</summary>
    private static async Task SetJeddahCountryAsync(string countryCode)
    {
        await using var factory = new ApiFactory();
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Tracks.Where(t => t.GameCode == GameCodes.F1_25 && t.GameTrackId == JeddahId)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.CountryCode, countryCode));
    }

    /// <summary>호스트를 띄우고(= 설정에 따라 기동 시 시드) Jeddah의 국가를 읽는다.</summary>
    private static async Task<string?> ReadJeddahCountryAsync(ApiFactory factory)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return await db.Tracks
            .Where(t => t.GameCode == GameCodes.F1_25 && t.GameTrackId == JeddahId)
            .Select(t => t.CountryCode)
            .SingleAsync();
    }

    /// <summary>기본 호스트를 띄워 시드로 원래 값을 되돌린다.</summary>
    private static async Task RestoreSeedAsync()
    {
        await using var factory = new ApiFactory();
        _ = factory.Services;
    }
}
