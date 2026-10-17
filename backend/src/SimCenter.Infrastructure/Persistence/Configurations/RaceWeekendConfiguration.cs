using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class RaceWeekendConfiguration : IEntityTypeConfiguration<RaceWeekend>
{
    public void Configure(EntityTypeBuilder<RaceWeekend> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.WeekendLinkId).IsRequired();
        builder.Property(x => x.FirstSessionAt).IsRequired();

        builder.HasOne(x => x.Season)
            .WithMany(x => x.Weekends)
            .HasForeignKey(x => x.SeasonId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(x => x.Track)
            .WithMany()
            .HasForeignKey(x => x.TrackId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(x => new { x.SeasonId, x.WeekendLinkId })
            .IsUnique()
            .HasFilter(SoftDeleteFilters.ActiveRows);
    }
}
