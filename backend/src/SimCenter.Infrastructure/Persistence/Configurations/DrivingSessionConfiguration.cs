using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class DrivingSessionConfiguration : IEntityTypeConfiguration<DrivingSession>
{
    public void Configure(EntityTypeBuilder<DrivingSession> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.SessionType).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.Status).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.StartedAt).IsRequired();

        builder.HasOne(x => x.User)
            .WithMany(x => x.Sessions)
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(x => x.SimRig)
            .WithMany()
            .HasForeignKey(x => x.SimRigId)
            .OnDelete(DeleteBehavior.Restrict);

        // Rig당 Active 세션 1개 보장(부분 유니크 인덱스, D-2). 컬럼명은 snake_case 매핑을 따른다.
        builder.HasIndex(x => x.SimRigId)
            .IsUnique()
            .HasFilter("status = 'Active'");

        // Agent 이벤트의 세션 매칭 조회용.
        builder.HasIndex(x => new { x.SimRigId, x.Status, x.StartedAt });
    }
}
