using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class TrackConfiguration : IEntityTypeConfiguration<Track>
{
    public void Configure(EntityTypeBuilder<Track> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(80);

        builder.HasIndex(x => new { x.GameCode, x.GameTrackId }).IsUnique();
    }
}
