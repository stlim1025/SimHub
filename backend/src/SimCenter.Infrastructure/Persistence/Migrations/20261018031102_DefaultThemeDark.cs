using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 기본 테마를 System → Dark로 바꾼다(D-40, 14 §7). 모델은 바뀌지 않는다(엔티티 초기값만 Dark) — 데이터와 열 기본값만 맞춘다.
    /// AddUserProfileSettings는 이미 개발 DB에 적용됐으므로 고치지 않고 이 마이그레이션을 더한다.
    /// </summary>
    public partial class DefaultThemeDark : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 백필로 System이 된 기존 사용자도 지금까지의 어두운 화면을 유지한다. (기능 공개 직후라 직접 System을 고른 사용자는 없다고 본다.)
            migrationBuilder.Sql("UPDATE users SET theme = 'Dark' WHERE theme = 'System';");
            migrationBuilder.Sql("ALTER TABLE users ALTER COLUMN theme SET DEFAULT 'Dark';");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // 열 기본값만 되돌린다. Up 뒤에 Dark를 직접 고른 사용자와 구분할 수 없으므로 데이터는 되돌리지 않는다.
            migrationBuilder.Sql("ALTER TABLE users ALTER COLUMN theme SET DEFAULT 'System';");
        }
    }
}
