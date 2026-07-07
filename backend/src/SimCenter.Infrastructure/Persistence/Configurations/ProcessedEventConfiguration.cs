using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class ProcessedEventConfiguration : IEntityTypeConfiguration<ProcessedEvent>
{
    public void Configure(EntityTypeBuilder<ProcessedEvent> builder)
    {
        // PK = Agent 멱등키(EventId 자체). BaseEntity가 아니므로 별도 규약 없음.
        builder.HasKey(x => x.EventId);
        builder.Property(x => x.EventId).ValueGeneratedNever();

        builder.Property(x => x.EventType).IsRequired().HasMaxLength(40);
        builder.Property(x => x.ProcessedAt).IsRequired();
    }
}
