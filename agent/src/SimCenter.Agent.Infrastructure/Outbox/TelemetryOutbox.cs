using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;

namespace SimCenter.Agent.Infrastructure.Outbox;

/// <summary>Outbox의 대기 항목(멱등키 + 전송할 wire JSON).</summary>
public sealed record OutboxItem(Guid EventId, string PayloadJson);

/// <summary>
/// SQLite 기반 Outbox(docs/06 §5). 이벤트는 전송 전 이곳에 먼저 기록되어 전원/네트워크 장애에도 유실되지 않는다.
/// 파이프라인 스레드(쓰기)와 업로더 스레드(읽기/삭제)가 공유하므로 단일 연결 + 세마포어로 직렬화한다.
/// EventId UNIQUE + INSERT OR IGNORE로 재적재도 멱등하다.
/// </summary>
public sealed class TelemetryOutbox : IAsyncDisposable
{
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
            command.Parameters.AddWithValue("$at", occurredAt.ToUniversalTime().ToString("O"));
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

    private async Task<SqliteConnection> GetConnectionAsync(CancellationToken cancellationToken)
    {
        if (_connection is not null)
        {
            return _connection;
        }

        var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var command = connection.CreateCommand())
        {
            command.CommandText =
                """
                CREATE TABLE IF NOT EXISTS outbox(
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT NOT NULL UNIQUE,
                    occurred_at TEXT NOT NULL,
                    payload TEXT NOT NULL
                );
                """;
            await command.ExecuteNonQueryAsync(cancellationToken);
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
