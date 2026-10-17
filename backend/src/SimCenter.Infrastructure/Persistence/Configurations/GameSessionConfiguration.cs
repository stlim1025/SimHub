using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class GameSessionConfiguration : IEntityTypeConfiguration<GameSession>
{
    public void Configure(EntityTypeBuilder<GameSession> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.GameCode).IsRequired().HasMaxLength(20);
        builder.Property(x => x.SessionKey).IsRequired().HasMaxLength(80);
        builder.Property(x => x.SessionRef).IsRequired().HasMaxLength(32);
        builder.Property(x => x.SessionType).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.SessionKind).IsRequired().HasConversion<string>().HasMaxLength(30);
        builder.Property(x => x.GameMode).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.ClassifiedAt).IsRequired();

        // 세션 주인. 내비게이션 없이 FK만 건다.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        // 마지막으로 결과를 보낸 장치. FK만 건다 — AgentDevice는 soft-delete 필터 대상이라 내비게이션을 거치면
        // inner join이 되어 연결 해제된 장치의 세션이 사라진다(Lap.AgentDevice와 같은 함정, Ruling R10).
        builder.HasOne<AgentDevice>()
            .WithMany()
            .HasForeignKey(x => x.AgentDeviceId)
            .OnDelete(DeleteBehavior.Restrict);

        // 시즌 대상이 아니면 null. 부모를 실제로 지우지 않으므로 Restrict.
        builder.HasOne<Season>()
            .WithMany()
            .HasForeignKey(x => x.SeasonId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne<RaceWeekend>()
            .WithMany()
            .HasForeignKey(x => x.RaceWeekendId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(x => x.Track)
            .WithMany()
            .HasForeignKey(x => x.TrackId)
            .OnDelete(DeleteBehavior.Restrict);

        // 결과는 세션에 종속된다. 컬렉션에서 Remove·Clear하지 않으므로(지우기는 IsDeleted) Cascade가 실제로 일어나는 일은 없다.
        builder.HasMany(x => x.Results)
            .WithOne()
            .HasForeignKey(x => x.GameSessionId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(x => new { x.UserId, x.GameCode, x.SessionKey })
            .IsUnique()
            .HasFilter(SoftDeleteFilters.ActiveRows);

        // 목록(ClassifiedAt 내림차순)과 시즌·주말별 세션 조회.
        builder.HasIndex(x => new { x.UserId, x.ClassifiedAt });
        builder.HasIndex(x => x.RaceWeekendId);
        builder.HasIndex(x => x.SeasonId);
    }
}
