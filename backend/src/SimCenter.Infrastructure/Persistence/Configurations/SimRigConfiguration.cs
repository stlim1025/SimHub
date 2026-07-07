using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class SimRigConfiguration : IEntityTypeConfiguration<SimRig>
{
    public void Configure(EntityTypeBuilder<SimRig> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.RigCode).IsRequired().HasMaxLength(30);
        builder.Property(x => x.DisplayName).IsRequired().HasMaxLength(50);

        // SHA-256 hex = 64자. 선택적(키 미발급 좌석 허용), 발급 시 Unique.
        builder.Property(x => x.ApiKeyHash).HasMaxLength(64);

        builder.HasIndex(x => x.RigCode).IsUnique();
        builder.HasIndex(x => x.ApiKeyHash).IsUnique();
    }
}
