using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class AgentPairingCodeConfiguration : IEntityTypeConfiguration<AgentPairingCode>
{
    public void Configure(EntityTypeBuilder<AgentPairingCode> builder)
    {
        builder.HasKey(x => x.Id);

        // SHA-256 hex = 64자. 무효화(soft delete)된 코드와도 겹치지 않도록 Unique(필터 없는 일반 인덱스).
        builder.Property(x => x.CodeHash).IsRequired().HasMaxLength(64);

        builder.HasIndex(x => x.CodeHash).IsUnique();
        builder.HasIndex(x => x.UserId);

        // 코드에서 User로 가는 내비게이션만 둔다(User 쪽 컬렉션 없음).
        builder.HasOne(x => x.User)
            .WithMany()
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
