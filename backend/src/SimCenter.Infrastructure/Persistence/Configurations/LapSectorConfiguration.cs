using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class LapSectorConfiguration : IEntityTypeConfiguration<LapSector>
{
    public void Configure(EntityTypeBuilder<LapSector> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.SectorNumber).IsRequired();
        builder.Property(x => x.SectorTimeMs).IsRequired();

        builder.HasOne(x => x.Lap)
            .WithMany(x => x.Sectors)
            .HasForeignKey(x => x.LapId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => new { x.LapId, x.SectorNumber }).IsUnique();
    }
}
