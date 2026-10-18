using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 랩 상세·텔레메트리(15 §5, D-43~D-45). 가산적 변경만 한다: 트랙 국가·표시 순서 열, 랩 게임 모드 열,
    /// 랩 스냅샷(<c>lap_snapshots</c>)·트레이스(<c>lap_telemetry_traces</c>) 테이블. 기존 트랙의 국가·순서는 시작 시 시드가 채운다.
    /// </summary>
    public partial class AddLapDetailAndTrace : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "country_code",
                table: "tracks",
                type: "character varying(2)",
                maxLength: 2,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "display_order",
                table: "tracks",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "game_mode",
                table: "laps",
                type: "character varying(30)",
                maxLength: 30,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "lap_snapshots",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    lap_id = table.Column<Guid>(type: "uuid", nullable: false),
                    team_id = table.Column<int>(type: "integer", nullable: true),
                    visual_tyre_compound = table.Column<int>(type: "integer", nullable: true),
                    actual_tyre_compound = table.Column<int>(type: "integer", nullable: true),
                    tyre_age_laps = table.Column<int>(type: "integer", nullable: true),
                    tyre_wear_start_front_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_start_front_right = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_start_rear_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_start_rear_right = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_end_front_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_end_front_right = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_end_rear_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_wear_end_rear_right = table.Column<double>(type: "double precision", nullable: true),
                    tyre_damage_front_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_damage_front_right = table.Column<double>(type: "double precision", nullable: true),
                    tyre_damage_rear_left = table.Column<double>(type: "double precision", nullable: true),
                    tyre_damage_rear_right = table.Column<double>(type: "double precision", nullable: true),
                    brake_damage_front_left = table.Column<double>(type: "double precision", nullable: true),
                    brake_damage_front_right = table.Column<double>(type: "double precision", nullable: true),
                    brake_damage_rear_left = table.Column<double>(type: "double precision", nullable: true),
                    brake_damage_rear_right = table.Column<double>(type: "double precision", nullable: true),
                    front_left_wing_damage = table.Column<int>(type: "integer", nullable: true),
                    front_right_wing_damage = table.Column<int>(type: "integer", nullable: true),
                    rear_wing_damage = table.Column<int>(type: "integer", nullable: true),
                    floor_damage = table.Column<int>(type: "integer", nullable: true),
                    diffuser_damage = table.Column<int>(type: "integer", nullable: true),
                    sidepod_damage = table.Column<int>(type: "integer", nullable: true),
                    gearbox_damage = table.Column<int>(type: "integer", nullable: true),
                    engine_damage = table.Column<int>(type: "integer", nullable: true),
                    fuel_start_kg = table.Column<double>(type: "double precision", nullable: true),
                    fuel_end_kg = table.Column<double>(type: "double precision", nullable: true),
                    fuel_remaining_laps = table.Column<double>(type: "double precision", nullable: true),
                    ers_store_start_j = table.Column<double>(type: "double precision", nullable: true),
                    ers_store_end_j = table.Column<double>(type: "double precision", nullable: true),
                    ers_deployed_j = table.Column<double>(type: "double precision", nullable: true),
                    ers_harvested_j = table.Column<double>(type: "double precision", nullable: true),
                    weather = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    air_temp_c = table.Column<int>(type: "integer", nullable: true),
                    track_temp_c = table.Column<int>(type: "integer", nullable: true),
                    rain_forecast_percent = table.Column<int>(type: "integer", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_lap_snapshots", x => x.id);
                    table.ForeignKey(
                        name: "fk_lap_snapshots_laps_lap_id",
                        column: x => x.lap_id,
                        principalTable: "laps",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "lap_telemetry_traces",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    lap_id = table.Column<Guid>(type: "uuid", nullable: false),
                    resolution_m = table.Column<int>(type: "integer", nullable: false),
                    sample_count = table.Column<int>(type: "integer", nullable: false),
                    payload = table.Column<byte[]>(type: "bytea", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_lap_telemetry_traces", x => x.id);
                    table.ForeignKey(
                        name: "fk_lap_telemetry_traces_laps_lap_id",
                        column: x => x.lap_id,
                        principalTable: "laps",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_lap_snapshots_lap_id",
                table: "lap_snapshots",
                column: "lap_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_lap_telemetry_traces_lap_id",
                table: "lap_telemetry_traces",
                column: "lap_id",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "lap_snapshots");

            migrationBuilder.DropTable(
                name: "lap_telemetry_traces");

            migrationBuilder.DropColumn(
                name: "country_code",
                table: "tracks");

            migrationBuilder.DropColumn(
                name: "display_order",
                table: "tracks");

            migrationBuilder.DropColumn(
                name: "game_mode",
                table: "laps");
        }
    }
}
