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

        // 표시 정보(D-43). 시드가 매번 맞춘다 — 기존 행은 마이그레이션에서 null·0으로 시작한다.
        builder.Property(x => x.CountryCode).HasMaxLength(Track.CountryCodeLength);
        builder.Property(x => x.DisplayOrder).IsRequired();

        builder.HasIndex(x => new { x.GameCode, x.GameTrackId }).IsUnique();
    }
}
