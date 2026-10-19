namespace SimCenter.Api.Startup;

/// <summary>
/// 기동 시 DB 마이그레이션·시드 실행 여부(16 §4.2, D-56).
/// </summary>
public static class DatabaseStartup
{
    /// <summary>마이그레이션·시드 실행 여부 설정 키(bool).</summary>
    public const string MigrateOnStartupKey = "Database:MigrateOnStartup";

    /// <summary>
    /// 기동 시 마이그레이션·시드를 실행해야 하는지 판단한다. 설정이 있으면 그 값을, 없으면 Development 여부를 따른다(기존 동작).
    /// 트랙 시드는 운영에도 필요하므로(D-41) 운영은 설정으로 켠다. bool로 읽을 수 없는 값이면 기동을 멈춘다.
    /// </summary>
    public static bool ShouldMigrate(IHostEnvironment environment, IConfiguration configuration)
        => configuration.GetValue<bool?>(MigrateOnStartupKey) ?? environment.IsDevelopment();
}
