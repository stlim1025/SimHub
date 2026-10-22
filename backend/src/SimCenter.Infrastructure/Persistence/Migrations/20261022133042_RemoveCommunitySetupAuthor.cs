using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 커뮤니티 셋업의 작성자(F1Laps 사용자 닉네임) 칸을 지운다 — 개인정보라 모으지도 보여 주지도 않는다.
    /// 되돌리면 칸만 null 허용으로 다시 만든다(지운 값은 돌아오지 않는다).
    /// </summary>
    public partial class RemoveCommunitySetupAuthor : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "author",
                table: "community_setups");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "author",
                table: "community_setups",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);
        }
    }
}
