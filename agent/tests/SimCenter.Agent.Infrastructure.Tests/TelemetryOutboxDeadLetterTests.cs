using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using SimCenter.Agent.Infrastructure.Configuration;
using SimCenter.Agent.Infrastructure.Outbox;

namespace SimCenter.Agent.Infrastructure.Tests;

public class TelemetryOutboxDeadLetterTests
{
    private const string Reason = "payload JSON 파싱 실패";

    private static readonly DateTime OccurredAt = new(2026, 10, 17, 9, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime MovedAt = new(2026, 10, 17, 9, 5, 30, DateTimeKind.Utc);

    // 연결이 하나로 유지되므로 :memory: DB가 테스트 수명 동안 보존된다(TelemetryOutboxTests와 같은 방식).
    private static TelemetryOutbox NewOutbox(string path = ":memory:")
        => new(Options.Create(new AgentOptions { OutboxPath = path }));

    [Fact]
    public async Task Move_TakesItemOutOfOutbox_AndKeepsPayloadReasonAndTime()
    {
        await using var outbox = NewOutbox();
        var poison = Guid.NewGuid();
        var next = Guid.NewGuid();
        await outbox.EnqueueAsync(poison, OccurredAt, "{not json");
        await outbox.EnqueueAsync(next, OccurredAt.AddSeconds(1), "{}");

        var moved = await outbox.MoveToDeadLetterAsync(poison, Reason, MovedAt);

        Assert.True(moved);
        Assert.Equal(next, Assert.Single(await outbox.GetPendingAsync(10)).EventId); // 뒤 항목은 그대로 남는다.
        Assert.Equal(1, await outbox.CountDeadLettersAsync());

        var deadLetter = Assert.Single(await outbox.GetDeadLettersAsync(10));
        Assert.Equal(poison, deadLetter.EventId);
        Assert.Equal("{not json", deadLetter.PayloadJson);
        Assert.Equal(Reason, deadLetter.Reason);
        Assert.Equal(MovedAt, deadLetter.DeadLetteredAt);
        Assert.Equal(DateTimeKind.Utc, deadLetter.DeadLetteredAt.Kind);
    }

    [Fact]
    public async Task Move_UnknownItem_ReturnsFalse_AndAddsNothing()
    {
        await using var outbox = NewOutbox();
        await outbox.EnqueueAsync(Guid.NewGuid(), OccurredAt, "{}");

        var moved = await outbox.MoveToDeadLetterAsync(Guid.NewGuid(), Reason, MovedAt);

        Assert.False(moved);
        Assert.Equal(1, await outbox.CountAsync());
        Assert.Equal(0, await outbox.CountDeadLettersAsync());
    }

    [Fact]
    public async Task EmptyOutbox_HasNoDeadLetters()
    {
        await using var outbox = NewOutbox();

        Assert.Equal(0, await outbox.CountDeadLettersAsync());
        Assert.Empty(await outbox.GetDeadLettersAsync(10));
    }

    [Fact]
    public async Task OutboxFileFromBeforeDeadLetters_GetsTheNewTable()
    {
        var path = Path.Combine(Path.GetTempPath(), $"simcenter-outbox-legacy-{Guid.NewGuid():N}.db");
        var eventId = Guid.NewGuid();
        try
        {
            // dead-letter 테이블이 생기기 전의 스키마(outbox만) 파일을 만든다.
            await using (var legacy = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path }.ToString()))
            {
                await legacy.OpenAsync();
                await using var command = legacy.CreateCommand();
                command.CommandText =
                    """
                    CREATE TABLE outbox(
                        seq INTEGER PRIMARY KEY AUTOINCREMENT,
                        event_id TEXT NOT NULL UNIQUE,
                        occurred_at TEXT NOT NULL,
                        payload TEXT NOT NULL
                    );
                    INSERT INTO outbox(event_id, occurred_at, payload) VALUES($id, '2026-10-17T09:00:00.0000000Z', '{}');
                    """;
                command.Parameters.AddWithValue("$id", eventId.ToString());
                await command.ExecuteNonQueryAsync();
            }

            await using (var outbox = NewOutbox(path))
            {
                Assert.True(await outbox.MoveToDeadLetterAsync(eventId, Reason, MovedAt));
                Assert.Equal(0, await outbox.CountAsync());
                Assert.Equal(1, await outbox.CountDeadLettersAsync());
            }
        }
        finally
        {
            SqliteConnection.ClearAllPools();
            File.Delete(path);
        }
    }
}
