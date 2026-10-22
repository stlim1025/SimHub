using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>커뮤니티 셋업(테이블 <c>community_setups</c>). 셋업 값 묶음은 jsonb, 기록 날짜는 date.</summary>
public sealed class CommunitySetupConfiguration : IEntityTypeConfiguration<CommunitySetup>
{
    public void Configure(EntityTypeBuilder<CommunitySetup> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(GameCodes.MaxLength);
        builder.Property(x => x.Condition).IsRequired().HasMaxLength(SetupConditions.MaxLength);
        builder.Property(x => x.Source).IsRequired().HasMaxLength(CommunitySetup.SourceMaxLength);
        builder.Property(x => x.SourceId).IsRequired().HasMaxLength(CommunitySetup.SourceIdMaxLength);
        builder.Property(x => x.SourceUrl).IsRequired().HasMaxLength(CommunitySetup.SourceUrlMaxLength);
        builder.Property(x => x.TeamName).HasMaxLength(CommunitySetup.TeamNameMaxLength);
        builder.Property(x => x.SessionType).HasMaxLength(CommunitySetup.SessionTypeMaxLength);
        builder.Property(x => x.Steering).HasMaxLength(CommunitySetup.SteeringMaxLength);
        builder.Property(x => x.Sections).IsRequired().HasColumnType(JsonColumns.Jsonb);

        builder.HasOne(x => x.Track)
            .WithMany()
            .HasForeignKey(x => x.TrackId)
            .OnDelete(DeleteBehavior.Restrict);

        // 같은 묶음 안의 같은 출처 셋업은 한 행(지워진 행도 되살려 재사용하므로 필터 없이 unique).
        builder.HasIndex(x => new { x.GameCode, x.TrackId, x.Condition, x.SourceId }).IsUnique();
    }
}
