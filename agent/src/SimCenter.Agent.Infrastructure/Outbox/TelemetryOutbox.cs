using System.Globalization;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;

namespace SimCenter.Agent.Infrastructure.Outbox;

/// <summary>Outbox의 대기 항목(멱등키 + 전송할 wire JSON).</summary>
public sealed record OutboxItem(Guid EventId, string PayloadJson);

/// <summary>dead-letter로 옮긴 항목(진단·테스트용 읽기 모델, docs/13 §3.4).</summary>
internal sealed record DeadLetterItem(Guid EventId, string PayloadJson, string Reason, DateTime DeadLetteredAt);

/// <summary>
/// SQLite 기반 Outbox(docs/06 §5). 이벤트는 전송 전 이곳에 먼저 기록되어 전원/네트워크 장애에도 유실되지 않는다.
/// 파이프라인 스레드(쓰기)와 업로더 스레드(읽기/삭제)가 공유하므로 단일 연결 + 세마포어로 직렬화한다.
/// EventId UNIQUE + INSERT OR IGNORE로 재적재도 멱등하다.
/// 다시 읽어도 바뀌지 않는 항목(손상된 payload)은 같은 파일의 <c>outbox_dead_letter</c>로 옮겨 보관한다(docs/13 §3.4, D-37).
/// </summary>
public sealed class TelemetryOutbox : IAsyncDisposable
{
    // 시각 저장 형식(왕복 가능한 ISO-8601, UTC).
    private const string TimestampFormat = "O";

    private readonly string _connectionString;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private SqliteConnection? _connection;

    public TelemetryOutbox(IOptions<AgentOptions> options)
    {
        var path = string.IsNullOrWhiteSpace(options.Value.OutboxPath) ? "outbox.db" : options.Value.OutboxPath;
        _connectionString = new SqliteConnectionStringBuilder { DataSource = path }.ToString();
    }

    public async Task EnqueueAsync(Guid eventId, DateTime occurredAt, string payloadJson, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "INSERT OR IGNORE INTO outbox(event_id, occurred_at, payload) VALUES($id, $at, $payload);";
            command.Parameters.AddWithValue("$id", eventId.ToString());
            command.Parameters.AddWithValue("$at", occurredAt.ToUniversalTime().ToString(TimestampFormat));
            command.Parameters.AddWithValue("$payload", payloadJson);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>occurredAt(동률 시 삽입 순서) 순으로 대기 항목을 최대 <paramref name="max"/>개 반환한다.</summary>
    public async Task<IReadOnlyList<OutboxItem>> GetPendingAsync(int max, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT event_id, payload FROM outbox ORDER BY occurred_at, seq LIMIT $max;";
            command.Parameters.AddWithValue("$max", max);

            var items = new List<OutboxItem>();
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                items.Add(new OutboxItem(Guid.Parse(reader.GetString(0)), reader.GetString(1)));
            }

            return items;
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Ack/Reject(서버 응답)를 받은 항목을 제거한다.</summary>
    public async Task DeleteAsync(Guid eventId, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "DELETE FROM outbox WHERE event_id = $id;";
            command.Parameters.AddWithValue("$id", eventId.ToString());
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<int> CountAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM outbox;";
            return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>
    /// 대기 항목을 dead-letter로 옮긴다(복사 + 삭제를 한 트랜잭션으로). Outbox에 없는 id면 아무것도 하지 않고 false.
    /// </summary>
    /// <param name="eventId">옮길 항목.</param>
    /// <param name="reason">옮긴 사유(로그·진단용).</param>
    /// <param name="deadLetteredAt">옮긴 시각(UTC, 호출자가 IClock으로 정한다).</param>
    public async Task<bool> MoveToDeadLetterAsync(
        Guid eventId, string reason, DateTime deadLetteredAt, CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reason);

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var transaction = (SqliteTransaction)await connection.BeginTransactionAsync(cancellationToken);

            await using var copy = connection.CreateCommand();
            copy.Transaction = transaction;
            copy.CommandText =
                """
                INSERT OR REPLACE INTO outbox_dead_letter(event_id, occurred_at, payload, reason, dead_lettered_at)
                SELECT event_id, occurred_at, payload, $reason, $at FROM outbox WHERE event_id = $id;
                """;
            copy.Parameters.AddWithValue("$id", eventId.ToString());
            copy.Parameters.AddWithValue("$reason", reason);
            copy.Parameters.AddWithValue("$at", deadLetteredAt.ToUniversalTime().ToString(TimestampFormat));
            var copied = await copy.ExecuteNonQueryAsync(cancellationToken);

            if (copied == 0)
            {
                await transaction.RollbackAsync(cancellationToken);
                return false;
            }

            await using var delete = connection.CreateCommand();
            delete.Transaction = transaction;
            delete.CommandText = "DELETE FROM outbox WHERE event_id = $id;";
            delete.Parameters.AddWithValue("$id", eventId.ToString());
            await delete.ExecuteNonQueryAsync(cancellationToken);

            await transaction.CommitAsync(cancellationToken);
            return true;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<int> CountDeadLettersAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT COUNT(*) FROM outbox_dead_letter;";
            return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>옮긴 시각 순으로 dead-letter 항목을 최대 <paramref name="max"/>개 반환한다(진단·테스트용).</summary>
    internal async Task<IReadOnlyList<DeadLetterItem>> GetDeadLettersAsync(int max, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var connection = await GetConnectionAsync(cancellationToken);
            await using var command = connection.CreateCommand();
            command.CommandText =
                "SELECT event_id, payload, reason, dead_lettered_at FROM outbox_dead_letter ORDER BY dead_lettered_at LIMIT $max;";
            command.Parameters.AddWithValue("$max", max);

            var items = new List<DeadLetterItem>();
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                items.Add(new DeadLetterItem(
                    Guid.Parse(reader.GetString(0)),
                    reader.GetString(1),
                    reader.GetString(2),
                    DateTime.Parse(reader.GetString(3), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind)));
            }

            return items;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<SqliteConnection> GetConnectionAsync(CancellationToken cancellationToken)
    {
        if (_connection is not null)
        {
            return _connection;
        }

        var connection = new SqliteConnection(_connectionString);
        try
        {
            await connection.OpenAsync(cancellationToken);

            // 기존 파일에도 없는 테이블만 만든다(dead-letter 테이블은 마이그레이션 없이 추가된다).
            await using var command = connection.CreateCommand();
            command.CommandText =
                """
                CREATE TABLE IF NOT EXISTS outbox(
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT NOT NULL UNIQUE,
                    occurred_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS outbox_dead_letter(
                    event_id TEXT PRIMARY KEY,
                    occurred_at TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    dead_lettered_at TEXT NOT NULL
                );
                """;
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch
        {
            // 초기화 도중 실패·취소(종료)되면 열린 연결이 남아 파일 핸들이 새지 않도록 닫는다.
            await connection.DisposeAsync();
            throw;
        }

        _connection = connection;
        return connection;
    }

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }

        _gate.Dispose();
    }
}
