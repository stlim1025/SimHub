using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddSeasonsAndSessions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "session_key",
                table: "laps",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "seasons",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    season_link_id = table.Column<long>(type: "bigint", nullable: false),
                    game_mode = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    first_session_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    last_session_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_seasons", x => x.id);
                    table.ForeignKey(
                        name: "fk_seasons_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "race_weekends",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    season_id = table.Column<Guid>(type: "uuid", nullable: false),
                    weekend_link_id = table.Column<long>(type: "bigint", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    first_session_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_race_weekends", x => x.id);
                    table.ForeignKey(
                        name: "fk_race_weekends_seasons_season_id",
                        column: x => x.season_id,
                        principalTable: "seasons",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_race_weekends_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "game_sessions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    agent_device_id = table.Column<Guid>(type: "uuid", nullable: false),
                    season_id = table.Column<Guid>(type: "uuid", nullable: true),
                    race_weekend_id = table.Column<Guid>(type: "uuid", nullable: true),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    session_key = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    season_link_id = table.Column<long>(type: "bigint", nullable: false),
                    weekend_link_id = table.Column<long>(type: "bigint", nullable: false),
                    session_link_id = table.Column<long>(type: "bigint", nullable: false),
                    session_ref = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    session_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    session_kind = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    game_mode = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    total_laps = table.Column<int>(type: "integer", nullable: false),
                    ai_difficulty = table.Column<int>(type: "integer", nullable: false),
                    is_network_game = table.Column<bool>(type: "boolean", nullable: false),
                    classified_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_game_sessions", x => x.id);
                    table.ForeignKey(
                        name: "fk_game_sessions_agent_devices_agent_device_id",
                        column: x => x.agent_device_id,
                        principalTable: "agent_devices",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_game_sessions_race_weekends_race_weekend_id",
                        column: x => x.race_weekend_id,
                        principalTable: "race_weekends",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_game_sessions_seasons_season_id",
                        column: x => x.season_id,
                        principalTable: "seasons",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_game_sessions_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_game_sessions_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "session_results",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    car_index = table.Column<int>(type: "integer", nullable: false),
                    position = table.Column<int>(type: "integer", nullable: false),
                    grid_position = table.Column<int>(type: "integer", nullable: false),
                    num_laps = table.Column<int>(type: "integer", nullable: false),
                    points = table.Column<int>(type: "integer", nullable: false),
                    num_pit_stops = table.Column<int>(type: "integer", nullable: false),
                    num_penalties = table.Column<int>(type: "integer", nullable: false),
                    result_status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    best_lap_time_ms = table.Column<int>(type: "integer", nullable: false),
                    total_race_time_ms = table.Column<int>(type: "integer", nullable: false),
                    penalties_time_ms = table.Column<int>(type: "integer", nullable: false),
                    driver_key = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    driver_name = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    game_driver_id = table.Column<int>(type: "integer", nullable: true),
                    team_id = table.Column<int>(type: "integer", nullable: true),
                    race_number = table.Column<int>(type: "integer", nullable: true),
                    is_ai_controlled = table.Column<bool>(type: "boolean", nullable: false),
                    is_player = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_session_results", x => x.id);
                    table.ForeignKey(
                        name: "fk_session_results_game_sessions_game_session_id",
                        column: x => x.game_session_id,
                        principalTable: "game_sessions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "session_result_tyre_stints",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    session_result_id = table.Column<Guid>(type: "uuid", nullable: false),
                    stint_number = table.Column<int>(type: "integer", nullable: false),
                    end_lap = table.Column<int>(type: "integer", nullable: false),
                    visual_compound = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    actual_compound = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_session_result_tyre_stints", x => x.id);
                    table.ForeignKey(
                        name: "fk_session_result_tyre_stints_session_results_session_result_id",
                        column: x => x.session_result_id,
                        principalTable: "session_results",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_agent_device_id",
                table: "game_sessions",
                column: "agent_device_id");

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_race_weekend_id",
                table: "game_sessions",
                column: "race_weekend_id");

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_season_id",
                table: "game_sessions",
                column: "season_id");

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_track_id",
                table: "game_sessions",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_user_id_classified_at",
                table: "game_sessions",
                columns: new[] { "user_id", "classified_at" });

            migrationBuilder.CreateIndex(
                name: "ix_game_sessions_user_id_game_code_session_key",
                table: "game_sessions",
                columns: new[] { "user_id", "game_code", "session_key" },
                unique: true,
                filter: "is_deleted = false");

            migrationBuilder.CreateIndex(
                name: "ix_race_weekends_season_id_weekend_link_id",
                table: "race_weekends",
                columns: new[] { "season_id", "weekend_link_id" },
                unique: true,
                filter: "is_deleted = false");

            migrationBuilder.CreateIndex(
                name: "ix_race_weekends_track_id",
                table: "race_weekends",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_seasons_user_id_game_code_season_link_id",
                table: "seasons",
                columns: new[] { "user_id", "game_code", "season_link_id" },
                unique: true,
                filter: "is_deleted = false");

            migrationBuilder.CreateIndex(
                name: "ix_seasons_user_id_last_session_at",
                table: "seasons",
                columns: new[] { "user_id", "last_session_at" });

            migrationBuilder.CreateIndex(
                name: "ix_session_result_tyre_stints_session_result_id",
                table: "session_result_tyre_stints",
                column: "session_result_id");

            migrationBuilder.CreateIndex(
                name: "ix_session_results_game_session_id_car_index",
                table: "session_results",
                columns: new[] { "game_session_id", "car_index" },
                unique: true,
                filter: "is_deleted = false");

            migrationBuilder.CreateIndex(
                name: "ix_session_results_game_session_id_driver_key",
                table: "session_results",
                columns: new[] { "game_session_id", "driver_key" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "session_result_tyre_stints");

            migrationBuilder.DropTable(
                name: "session_results");

            migrationBuilder.DropTable(
                name: "game_sessions");

            migrationBuilder.DropTable(
                name: "race_weekends");

            migrationBuilder.DropTable(
                name: "seasons");

            migrationBuilder.DropColumn(
                name: "session_key",
                table: "laps");
        }
    }
}
