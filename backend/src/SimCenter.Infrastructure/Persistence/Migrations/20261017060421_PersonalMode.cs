using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 개인 모드 전환(D-25, 11 §3.4): 랩 귀속을 체크인 세션에서 연결된 Agent 장치로 바꾸고 매장·좌석·체크인 테이블을 없앤다.
    /// </summary>
    public partial class PersonalMode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 1. 기존 랩·섹터·멱등 기록 삭제(사용자 승인 2026-10-17). 모두 로컬 개발·테스트 데이터이고 귀속할 장치가 없다.
            //    행이 남아 있으면 아래 NOT NULL FK(agent_device_id) 추가가 실패한다. 회원(users)·트랙(tracks)은 유지한다.
            migrationBuilder.Sql("DELETE FROM lap_sectors; DELETE FROM laps; DELETE FROM processed_events;");

            // 2. laps.driving_session_id 컬럼·FK·인덱스 삭제.
            migrationBuilder.DropForeignKey(
                name: "fk_laps_driving_sessions_driving_session_id",
                table: "laps");

            migrationBuilder.DropIndex(
                name: "ix_laps_driving_session_id",
                table: "laps");

            migrationBuilder.DropColumn(
                name: "driving_session_id",
                table: "laps");

            // 3. laps.agent_device_id 추가(필수) + 인덱스 + FK → agent_devices(Restrict). 표가 비어 있어 기본값이 필요 없다.
            migrationBuilder.AddColumn<Guid>(
                name: "agent_device_id",
                table: "laps",
                type: "uuid",
                nullable: false);

            migrationBuilder.CreateIndex(
                name: "ix_laps_agent_device_id",
                table: "laps",
                column: "agent_device_id");

            migrationBuilder.AddForeignKey(
                name: "fk_laps_agent_devices_agent_device_id",
                table: "laps",
                column: "agent_device_id",
                principalTable: "agent_devices",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            // 4. laps.user_id FK → users(Restrict). 기존 (user_id, track_id, lap_time_ms) 인덱스가 FK 조회를 덮는다.
            migrationBuilder.AddForeignKey(
                name: "fk_laps_users_user_id",
                table: "laps",
                column: "user_id",
                principalTable: "users",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);

            // 5. 카페 모델 테이블 삭제(참조 순서: driving_sessions → sim_rigs → stores).
            migrationBuilder.DropTable(
                name: "driving_sessions");

            migrationBuilder.DropTable(
                name: "sim_rigs");

            migrationBuilder.DropTable(
                name: "stores");
        }

        /// <inheritdoc />
        /// <remarks>
        /// 스키마만 되돌린다(EF 생성본). 삭제한 랩·매장·좌석·세션 데이터는 복원하지 않는다.
        /// 되돌릴 때 laps에 행이 남아 있으면 driving_sessions FK 추가가 실패하므로 먼저 비워야 한다.
        /// </remarks>
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_laps_agent_devices_agent_device_id",
                table: "laps");

            migrationBuilder.DropForeignKey(
                name: "fk_laps_users_user_id",
                table: "laps");

            migrationBuilder.RenameColumn(
                name: "agent_device_id",
                table: "laps",
                newName: "driving_session_id");

            migrationBuilder.RenameIndex(
                name: "ix_laps_agent_device_id",
                table: "laps",
                newName: "ix_laps_driving_session_id");

            migrationBuilder.CreateTable(
                name: "stores",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    time_zone_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stores", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "sim_rigs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    store_id = table.Column<Guid>(type: "uuid", nullable: false),
                    api_key_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    display_name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    rig_code = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
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
                    sim_rig_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ended_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false),
                    session_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    started_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    store_id = table.Column<Guid>(type: "uuid", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
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
                name: "ix_sim_rigs_api_key_hash",
                table: "sim_rigs",
                column: "api_key_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sim_rigs_rig_code",
                table: "sim_rigs",
                column: "rig_code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sim_rigs_store_id",
                table: "sim_rigs",
                column: "store_id");

            migrationBuilder.AddForeignKey(
                name: "fk_laps_driving_sessions_driving_session_id",
                table: "laps",
                column: "driving_session_id",
                principalTable: "driving_sessions",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
