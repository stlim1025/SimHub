using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddUserProfileSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 가산적 변경(14 §4). defaultValue는 기존 사용자 백필 값이다 — 이 마이그레이션 시점의 UserProfileDefaults와 같다
            // (공개 · 사진 없음 · F1_25 · Wheel · Pc · Metric · Asia/Seoul · System). 새 행은 엔티티 초기값이 채운다.
            migrationBuilder.AddColumn<string>(
                name: "avatar_team",
                table: "users",
                type: "character varying(8)",
                maxLength: 8,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "console",
                table: "users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Pc");

            migrationBuilder.AddColumn<string>(
                name: "controller",
                table: "users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Wheel");

            migrationBuilder.AddColumn<string>(
                name: "preferred_game",
                table: "users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "F1_25");

            migrationBuilder.AddColumn<bool>(
                name: "show_on_leaderboard",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<string>(
                name: "theme",
                table: "users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "System");

            migrationBuilder.AddColumn<string>(
                name: "time_zone_id",
                table: "users",
                type: "character varying(64)",
                maxLength: 64,
                nullable: false,
                defaultValue: "Asia/Seoul");

            migrationBuilder.AddColumn<string>(
                name: "units",
                table: "users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "Metric");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "avatar_team",
                table: "users");

            migrationBuilder.DropColumn(
                name: "console",
                table: "users");

            migrationBuilder.DropColumn(
                name: "controller",
                table: "users");

            migrationBuilder.DropColumn(
                name: "preferred_game",
                table: "users");

            migrationBuilder.DropColumn(
                name: "show_on_leaderboard",
                table: "users");

            migrationBuilder.DropColumn(
                name: "theme",
                table: "users");

            migrationBuilder.DropColumn(
                name: "time_zone_id",
                table: "users");

            migrationBuilder.DropColumn(
                name: "units",
                table: "users");
        }
    }
}
