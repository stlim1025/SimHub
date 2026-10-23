using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>트랙 형상 표본 조각(테이블 <c>track_sample_chunks</c>). <c>Payload</c>는 bytea(gzip).</summary>
public sealed class TrackSampleChunkConfiguration : IEntityTypeConfiguration<TrackSampleChunk>
{
    public void Configure(EntityTypeBuilder<TrackSampleChunk> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.SessionRef).IsRequired().HasMaxLength(TrackSampleChunk.SessionRefMaxLength);
        builder.Property(x => x.SessionType).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.Payload).IsRequired();

        // 장치·주인·트랙은 FK만 건다. 실제 삭제로 표본이 연쇄 삭제되지 않게 Restrict.
        builder.HasOne<AgentDevice>()
            .WithMany()
            .HasForeignKey(x => x.AgentDeviceId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne<Track>()
            .WithMany()
            .HasForeignKey(x => x.TrackId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(x => new { x.AgentDeviceId, x.SessionRef, x.ChunkIndex }).IsUnique();

        // 트랙 형상 계산은 트랙·게임별로 모은다.
        builder.HasIndex(x => new { x.TrackId, x.GameCode });
    }
}
