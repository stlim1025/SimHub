using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Infrastructure.Persistence.Configurations;

public sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    /// <summary>enum 이름 문자열 열 길이(가장 긴 값 "PlayStation"보다 여유 있게).</summary>
    private const int EnumNameMaxLength = 20;

    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Email).IsRequired().HasMaxLength(256);
        builder.Property(x => x.PasswordHash).IsRequired();
        builder.Property(x => x.DisplayName).IsRequired().HasMaxLength(50);

        // 프로필 설정(14 §4). DB 기본값은 모델에 두지 않는다 — bool의 CLR 기본값(false)이 DB 기본값(true)으로
        // 바뀌어 들어가는 일을 막기 위해서다. 기존 행 백필 값은 마이그레이션(AddUserProfileSettings)에만 있다.
        builder.Property(x => x.ShowOnLeaderboard).IsRequired();
        builder.Property(x => x.AvatarTeam).HasMaxLength(AvatarTeamCodes.MaxLength);
        builder.Property(x => x.PreferredGame).IsRequired().HasMaxLength(GameCodes.MaxLength);
        builder.Property(x => x.Controller).IsRequired().HasConversion<string>().HasMaxLength(EnumNameMaxLength);
        builder.Property(x => x.Console).IsRequired().HasConversion<string>().HasMaxLength(EnumNameMaxLength);
        builder.Property(x => x.Units).IsRequired().HasConversion<string>().HasMaxLength(EnumNameMaxLength);
        builder.Property(x => x.TimeZoneId).IsRequired().HasMaxLength(UserProfileDefaults.TimeZoneIdMaxLength);
        builder.Property(x => x.Theme).IsRequired().HasConversion<string>().HasMaxLength(EnumNameMaxLength);

        builder.HasIndex(x => x.Email).IsUnique();
    }
}
