using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SimCenter.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// 드라이버 어시스트 열(docs/15 §10, D-51): 비교 필터(같은 어시스트)를 SQL로 거르기 위해 <c>lap_snapshots.details</c>의
    /// status·session 값 6개를 정수 열로 더하고, 기존 행은 details에서 채운다. 가산적 변경만 한다.
    /// </summary>
    public partial class AddLapSnapshotAssists : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "anti_lock_brakes",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "braking_assist",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "dynamic_racing_line",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "gearbox_assist",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "steering_assist",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "traction_control",
                table: "lap_snapshots",
                type: "integer",
                nullable: true);

            migrationBuilder.Sql(BackfillSql);
        }

        /// <summary>
        /// 이미 저장된 details에서 채운다(LapAssistReader와 같은 규칙: 0~255 정수만, 그 밖은 null). 통합 테스트가 같은 문장을 검증한다.
        /// </summary>
        public static string BackfillSql => $"""
            UPDATE lap_snapshots SET
                traction_control = {Assist("status", "tractionControl")},
                anti_lock_brakes = {Assist("status", "antiLockBrakes")},
                steering_assist = {Assist("session", "steeringAssist")},
                braking_assist = {Assist("session", "brakingAssist")},
                gearbox_assist = {Assist("session", "gearboxAssist")},
                dynamic_racing_line = {Assist("session", "dynamicRacingLine")}
            WHERE details IS NOT NULL;
            """;

        /// <summary>
        /// details의 한 값 → 정수 열(숫자·정수·0~255가 아니면 NULL). 바깥 CASE가 숫자일 때만 안쪽 형 변환을 평가하게 한다
        /// (AND는 평가 순서를 보장하지 않는다). 키는 고정 문자열이라 SQL 주입 여지가 없다.
        /// </summary>
        private static string Assist(string section, string key)
        {
            var number = $"(details -> '{section}' ->> '{key}')::numeric";
            return $"CASE WHEN jsonb_typeof(details -> '{section}' -> '{key}') = 'number' THEN "
                + $"CASE WHEN {number} = trunc({number}) AND {number} BETWEEN 0 AND 255 THEN {number}::integer END END";
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "anti_lock_brakes",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "braking_assist",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "dynamic_racing_line",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "gearbox_assist",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "steering_assist",
                table: "lap_snapshots");

            migrationBuilder.DropColumn(
                name: "traction_control",
                table: "lap_snapshots");
        }
    }
}
