using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class SeasonConfiguration : IEntityTypeConfiguration<Season>
{
    public void Configure(EntityTypeBuilder<Season> builder)
    {
        builder.HasKey(x => x.Id);

        // 병합 경로에서 Id를 채운 새 행을 이미 추적 중인 부모에 붙일 때 INSERT가 되도록 DB 생성 키를 쓰지 않는다(12 §4.5).
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.SeasonLinkId).IsRequired();
        builder.Property(x => x.GameMode).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.FirstSessionAt).IsRequired();
        builder.Property(x => x.LastSessionAt).IsRequired();

        // 가져온 시즌(docs/15 §12, D-55). 게임에서 기록된 시즌은 모두 null.
        builder.Property(x => x.ImportedFrom).HasMaxLength(20);
        builder.Property(x => x.ImportedStandings).HasColumnType(JsonColumns.Jsonb);

        // 시즌 주인. 내비게이션 없이 FK만 건다.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasIndex(x => new { x.UserId, x.GameCode, x.SeasonLinkId })
            .IsUnique()
            .HasFilter(SoftDeleteFilters.ActiveRows);

        // 목록 정렬(LastSessionAt 내림차순).
        builder.HasIndex(x => new { x.UserId, x.LastSessionAt });
    }
}
