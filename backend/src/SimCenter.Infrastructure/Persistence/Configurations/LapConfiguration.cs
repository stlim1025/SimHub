using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class LapConfiguration : IEntityTypeConfiguration<Lap>
{
    public void Configure(EntityTypeBuilder<Lap> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.SessionType).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.LapNumber).IsRequired();
        builder.Property(x => x.LapTimeMs).IsRequired();
        builder.Property(x => x.SetAt).IsRequired();

        builder.HasOne(x => x.DrivingSession)
            .WithMany(x => x.Laps)
            .HasForeignKey(x => x.DrivingSessionId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(x => x.Track)
            .WithMany()
            .HasForeignKey(x => x.TrackId)
            .OnDelete(DeleteBehavior.Restrict);

        // 랭킹 쿼리 최적화(03-entity-design §3.6).
        builder.HasIndex(x => new { x.TrackId, x.GameCode, x.SessionType, x.IsRankingEligible, x.SetAt });
        builder.HasIndex(x => new { x.UserId, x.TrackId, x.LapTimeMs });
        builder.HasIndex(x => new { x.TrackId, x.LapTimeMs })
            .HasFilter("is_ranking_eligible = true");
    }
}
