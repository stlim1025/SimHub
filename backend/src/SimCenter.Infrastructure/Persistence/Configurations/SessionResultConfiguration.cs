using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class SessionResultConfiguration : IEntityTypeConfiguration<SessionResult>
{
    public void Configure(EntityTypeBuilder<SessionResult> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.CarIndex).IsRequired();
        builder.Property(x => x.ResultStatus).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.DriverKey).IsRequired().HasMaxLength(80);
        builder.Property(x => x.DriverName).HasMaxLength(64);
        builder.Property(x => x.TeamName).HasMaxLength(SessionResult.TeamNameMaxLength);

        // 스틴트는 결과에 종속된다. 지우기는 항상 IsDeleted라 Cascade가 실제로 일어나는 일은 없다.
        builder.HasMany(x => x.TyreStints)
            .WithOne()
            .HasForeignKey(x => x.SessionResultId)
            .OnDelete(DeleteBehavior.Cascade);

        // 한 세션의 차 번호는 활성 행 사이에서 유일하다(지워진 행은 제외).
        builder.HasIndex(x => new { x.GameSessionId, x.CarIndex })
            .IsUnique()
            .HasFilter(SoftDeleteFilters.ActiveRows);

        builder.HasIndex(x => new { x.GameSessionId, x.DriverKey });
    }
}
