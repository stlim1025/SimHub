using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Email).IsRequired().HasMaxLength(256);
        builder.Property(x => x.PasswordHash).IsRequired();
        builder.Property(x => x.DisplayName).IsRequired().HasMaxLength(50);

        builder.HasIndex(x => x.Email).IsUnique();
    }
}
