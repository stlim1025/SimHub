using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTrackSampleChunks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "track_sample_chunks",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    agent_device_id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    game_code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    session_ref = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    session_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    chunk_index = table.Column<int>(type: "integer", nullable: false),
                    is_last = table.Column<bool>(type: "boolean", nullable: false),
                    format = table.Column<int>(type: "integer", nullable: false),
                    sample_rate_hz = table.Column<int>(type: "integer", nullable: false),
                    frame_count = table.Column<int>(type: "integer", nullable: false),
                    sample_count = table.Column<int>(type: "integer", nullable: false),
                    track_length_m = table.Column<int>(type: "integer", nullable: true),
                    payload = table.Column<byte[]>(type: "bytea", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_track_sample_chunks", x => x.id);
                    table.ForeignKey(
                        name: "fk_track_sample_chunks_agent_devices_agent_device_id",
                        column: x => x.agent_device_id,
                        principalTable: "agent_devices",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_track_sample_chunks_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_track_sample_chunks_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_track_sample_chunks_agent_device_id_session_ref_chunk_index",
                table: "track_sample_chunks",
                columns: new[] { "agent_device_id", "session_ref", "chunk_index" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_track_sample_chunks_track_id_game_code",
                table: "track_sample_chunks",
                columns: new[] { "track_id", "game_code" });

            migrationBuilder.CreateIndex(
                name: "ix_track_sample_chunks_user_id",
                table: "track_sample_chunks",
                column: "user_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "track_sample_chunks");
        }
    }
}
