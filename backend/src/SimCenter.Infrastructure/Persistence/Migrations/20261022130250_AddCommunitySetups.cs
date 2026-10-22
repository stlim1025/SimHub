using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCommunitySetups : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "community_setups",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    condition = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    rank = table.Column<int>(type: "integer", nullable: false),
                    source = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    source_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    source_url = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    author = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    team_name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    session_type = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    lap_time_ms = table.Column<int>(type: "integer", nullable: false),
                    steering = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    set_on = table.Column<DateOnly>(type: "date", nullable: true),
                    sections = table.Column<string>(type: "jsonb", nullable: false),
                    fetched_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_community_setups", x => x.id);
                    table.ForeignKey(
                        name: "fk_community_setups_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_community_setups_game_code_track_id_condition_source_id",
                table: "community_setups",
                columns: new[] { "game_code", "track_id", "condition", "source_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_community_setups_track_id",
                table: "community_setups",
                column: "track_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "community_setups");
        }
    }
}
