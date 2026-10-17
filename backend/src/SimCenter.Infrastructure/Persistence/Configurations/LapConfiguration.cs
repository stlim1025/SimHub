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

        // 랩을 보낸 장치(D-25). 장치 해제는 soft delete라 랩이 남고, 실제 삭제로 랩이 연쇄 삭제되지 않도록 Restrict.
        // 주의(Ruling R10): AgentDevice는 soft-delete 필터 대상이고 이 관계는 필수라, Lap.AgentDevice를 거치는
        // Include·프로젝션은 inner join이 되어 연결 해제된 장치의 랩을 숨긴다. 장치 정보가 필요하면
        // IgnoreQueryFilters()나 AgentDeviceId 기준 left join을 쓴다. 모델 변경(추가 마이그레이션)을 피하려고 내비게이션은 유지한다.
        builder.HasOne(x => x.AgentDevice)
            .WithMany()
            .HasForeignKey(x => x.AgentDeviceId)
            .OnDelete(DeleteBehavior.Restrict);

        // 랩 주인(11 §3.2). 내비게이션 없이 FK만 건다.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(x => x.UserId)
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
