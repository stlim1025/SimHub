using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Common;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence;

/// <summary>
/// EF Core DbContext(Code First, PostgreSQL). 공통 규약(03-entity-design §1)을 일괄 적용한다:
/// Soft Delete 전역 쿼리 필터, 모든 시각 UTC 저장/조회. snake_case 매핑은 DI에서 설정한다.
/// </summary>
public sealed class AppDbContext : DbContext, IUnitOfWork
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Store> Stores => Set<Store>();
    public DbSet<SimRig> SimRigs => Set<SimRig>();
    public DbSet<Track> Tracks => Set<Track>();
    public DbSet<DrivingSession> DrivingSessions => Set<DrivingSession>();
    public DbSet<Lap> Laps => Set<Lap>();
    public DbSet<LapSector> LapSectors => Set<LapSector>();
    public DbSet<ProcessedEvent> ProcessedEvents => Set<ProcessedEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        ApplySoftDeleteFilter(modelBuilder);
        ApplyUtcDateTimeConverter(modelBuilder);
    }

    /// <summary>BaseEntity 파생 타입에 IsDeleted == false 전역 필터를 적용한다.</summary>
    private static void ApplySoftDeleteFilter(ModelBuilder modelBuilder)
    {
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            if (!typeof(BaseEntity).IsAssignableFrom(entityType.ClrType))
            {
                continue;
            }

            var parameter = Expression.Parameter(entityType.ClrType, "e");
            var property = Expression.Property(parameter, nameof(BaseEntity.IsDeleted));
            var filter = Expression.Lambda(Expression.Not(property), parameter);
            entityType.SetQueryFilter(filter);
        }
    }

    /// <summary>모든 DateTime/DateTime? 값을 UTC로 저장/조회한다(03 §1 시간대 규약).</summary>
    private static void ApplyUtcDateTimeConverter(ModelBuilder modelBuilder)
    {
        var utcConverter = new ValueConverter<DateTime, DateTime>(
            v => v.ToUniversalTime(),
            v => DateTime.SpecifyKind(v, DateTimeKind.Utc));

        var nullableUtcConverter = new ValueConverter<DateTime?, DateTime?>(
            v => v.HasValue ? v.Value.ToUniversalTime() : v,
            v => v.HasValue ? DateTime.SpecifyKind(v.Value, DateTimeKind.Utc) : v);

        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            foreach (var property in entityType.GetProperties())
            {
                if (property.ClrType == typeof(DateTime))
                {
                    property.SetValueConverter(utcConverter);
                }
                else if (property.ClrType == typeof(DateTime?))
                {
                    property.SetValueConverter(nullableUtcConverter);
                }
            }
        }
    }

    // IUnitOfWork.SaveChangesAsync는 DbContext.SaveChangesAsync(CancellationToken)가 그대로 만족한다.
}
