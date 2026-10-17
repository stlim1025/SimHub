using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

/// <summary>스틴트와 결과의 관계(FK·Cascade)는 부모 쪽 <see cref="SessionResultConfiguration"/>에서 정의한다.</summary>
public sealed class SessionResultTyreStintConfiguration : IEntityTypeConfiguration<SessionResultTyreStint>
{
    public void Configure(EntityTypeBuilder<SessionResultTyreStint> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();

        builder.Property(x => x.StintNumber).IsRequired();
        builder.Property(x => x.EndLap).IsRequired();
        builder.Property(x => x.VisualCompound).IsRequired().HasConversion<string>().HasMaxLength(20);
        builder.Property(x => x.ActualCompound).HasMaxLength(10);
    }
}
