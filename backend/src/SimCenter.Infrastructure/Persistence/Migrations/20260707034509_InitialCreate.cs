using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "stores",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stores", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "tracks",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    game_track_id = table.Column<int>(type: "integer", nullable: false),
                    name = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tracks", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    password_hash = table.Column<string>(type: "text", nullable: false),
                    display_name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "sim_rigs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    store_id = table.Column<Guid>(type: "uuid", nullable: false),
                    rig_code = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    display_name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sim_rigs", x => x.id);
                    table.ForeignKey(
                        name: "fk_sim_rigs_stores_store_id",
                        column: x => x.store_id,
                        principalTable: "stores",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "driving_sessions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    sim_rig_id = table.Column<Guid>(type: "uuid", nullable: false),
                    store_id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    session_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    started_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ended_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_driving_sessions", x => x.id);
                    table.ForeignKey(
                        name: "fk_driving_sessions_sim_rigs_sim_rig_id",
                        column: x => x.sim_rig_id,
                        principalTable: "sim_rigs",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_driving_sessions_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "laps",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    driving_session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    session_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    lap_number = table.Column<int>(type: "integer", nullable: false),
                    lap_time_ms = table.Column<int>(type: "integer", nullable: false),
                    is_valid = table.Column<bool>(type: "boolean", nullable: false),
                    is_invalidated_manually = table.Column<bool>(type: "boolean", nullable: false),
                    is_ranking_eligible = table.Column<bool>(type: "boolean", nullable: false),
                    set_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_laps", x => x.id);
                    table.ForeignKey(
                        name: "fk_laps_driving_sessions_driving_session_id",
                        column: x => x.driving_session_id,
                        principalTable: "driving_sessions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_laps_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "lap_sectors",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    lap_id = table.Column<Guid>(type: "uuid", nullable: false),
                    sector_number = table.Column<int>(type: "integer", nullable: false),
                    sector_time_ms = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_lap_sectors", x => x.id);
                    table.ForeignKey(
                        name: "fk_lap_sectors_laps_lap_id",
                        column: x => x.lap_id,
                        principalTable: "laps",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_driving_sessions_sim_rig_id",
                table: "driving_sessions",
                column: "sim_rig_id",
                unique: true,
                filter: "status = 'Active'");

            migrationBuilder.CreateIndex(
                name: "ix_driving_sessions_sim_rig_id_status_started_at",
                table: "driving_sessions",
                columns: new[] { "sim_rig_id", "status", "started_at" });

            migrationBuilder.CreateIndex(
                name: "ix_driving_sessions_user_id",
                table: "driving_sessions",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_lap_sectors_lap_id_sector_number",
                table: "lap_sectors",
                columns: new[] { "lap_id", "sector_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_laps_driving_session_id",
                table: "laps",
                column: "driving_session_id");

            migrationBuilder.CreateIndex(
                name: "ix_laps_track_id_game_code_session_type_is_ranking_eligible_se",
                table: "laps",
                columns: new[] { "track_id", "game_code", "session_type", "is_ranking_eligible", "set_at" });

            migrationBuilder.CreateIndex(
                name: "ix_laps_track_id_lap_time_ms",
                table: "laps",
                columns: new[] { "track_id", "lap_time_ms" },
                filter: "is_ranking_eligible = true");

            migrationBuilder.CreateIndex(
                name: "ix_laps_user_id_track_id_lap_time_ms",
                table: "laps",
                columns: new[] { "user_id", "track_id", "lap_time_ms" });

            migrationBuilder.CreateIndex(
                name: "ix_sim_rigs_rig_code",
                table: "sim_rigs",
                column: "rig_code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sim_rigs_store_id",
                table: "sim_rigs",
                column: "store_id");

            migrationBuilder.CreateIndex(
                name: "ix_tracks_game_code_game_track_id",
                table: "tracks",
                columns: new[] { "game_code", "game_track_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_users_email",
                table: "users",
                column: "email",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "lap_sectors");

            migrationBuilder.DropTable(
                name: "laps");

            migrationBuilder.DropTable(
                name: "driving_sessions");

            migrationBuilder.DropTable(
                name: "tracks");

            migrationBuilder.DropTable(
                name: "sim_rigs");

            migrationBuilder.DropTable(
                name: "users");

            migrationBuilder.DropTable(
                name: "stores");
        }
    }
}
