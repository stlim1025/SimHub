using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 텔레메트리 전부 수집(D-49, 15 §8): 랩 스냅샷의 그 밖의 값 묶음(<c>lap_snapshots.details</c>)과
    /// 세션의 랩별 기록·순위 묶음(<c>game_sessions.details</c>)을 jsonb 열로 더한다. 가산적 변경만 한다.
    /// </summary>
    public partial class AddTelemetryDetails : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "details",
                table: "lap_snapshots",
                type: "jsonb",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "details",
                table: "game_sessions",
                type: "jsonb",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "details",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "details",
                table: "game_sessions");
        }
    }
}
