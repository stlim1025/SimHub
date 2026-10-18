using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>랩 텔레메트리 트레이스(D-45, 테이블 <c>lap_telemetry_traces</c>). <c>Payload</c>는 bytea(gzip JSON, D-18).</summary>
public sealed class LapTelemetryTraceConfiguration : IEntityTypeConfiguration<LapTelemetryTrace>
{
    public void Configure(EntityTypeBuilder<LapTelemetryTrace> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.ResolutionM).IsRequired();
        builder.Property(x => x.SampleCount).IsRequired();
        builder.Property(x => x.Payload).IsRequired();

        // Lap과 1:0..1. 내비게이션 없이 FK만 건다 — 큰 값이라 랩 조회가 실수로 불러오지 않게 한다.
        builder.HasOne<Lap>()
            .WithOne()
            .HasForeignKey<LapTelemetryTrace>(x => x.LapId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => x.LapId).IsUnique();
    }
}
