using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>랩 스냅샷(D-44, 테이블 <c>lap_snapshots</c>). 값 열은 모두 nullable, 날씨는 문자열.</summary>
public sealed class LapSnapshotConfiguration : IEntityTypeConfiguration<LapSnapshot>
{
    private const int WeatherMaxLength = 20;

    public void Configure(EntityTypeBuilder<LapSnapshot> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.Weather).HasConversion<string>().HasMaxLength(WeatherMaxLength);

        // 그 밖의 값 묶음(D-49): JSON 객체 원문 그대로.
        builder.Property(x => x.Details).HasColumnType(JsonColumns.Jsonb);

        // Lap과 1:0..1. 랩은 실제로 지우지 않지만, 지운다면 스냅샷도 함께 지운다.
        builder.HasOne<Lap>()
            .WithOne(x => x.Snapshot)
            .HasForeignKey<LapSnapshot>(x => x.LapId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => x.LapId).IsUnique();
    }
}
