using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class AgentDeviceConfiguration : IEntityTypeConfiguration<AgentDevice>
{
    public void Configure(EntityTypeBuilder<AgentDevice> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Name).IsRequired().HasMaxLength(50);

        // SHA-256 hex = 64자. 장치 키로 인입을 인증하므로 Unique(soft delete 행 포함).
        builder.Property(x => x.ApiKeyHash).IsRequired().HasMaxLength(64);

        builder.HasIndex(x => x.ApiKeyHash).IsUnique();
        builder.HasIndex(x => x.UserId);

        // 사용자 삭제로 장치가 연쇄 삭제되지 않도록 Restrict(11 §3.1).
        builder.HasOne(x => x.User)
            .WithMany(u => u.AgentDevices)
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
