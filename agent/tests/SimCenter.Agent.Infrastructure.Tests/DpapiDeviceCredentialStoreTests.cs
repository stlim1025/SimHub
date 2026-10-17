using System.Runtime.Versioning;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using SimCenter.Agent.Infrastructure.Credentials;

namespace SimCenter.Agent.Infrastructure.Tests;

[SupportedOSPlatform("windows")]
public sealed class DpapiDeviceCredentialStoreTests : IDisposable
{
    private const string Key = "key-123";

    // 테스트마다 고유한 임시 폴더를 쓰고, 끝나면 통째로 삭제한다.
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), "simcenter-dpapi-tests-" + Guid.NewGuid().ToString("N"));

    private string FilePath => Path.Combine(_directory, "device.key");

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private DpapiDeviceCredentialStore NewStore()
        => new(FilePath, NullLogger<DpapiDeviceCredentialStore>.Instance);

    [Fact]
    public void SaveThenLoad_RoundTrips()
    {
        var store = NewStore();

        store.Save(Key);

        Assert.Equal(Key, store.Load());
    }

    [Fact]
    public void Load_MissingFile_ReturnsNull()
    {
        var store = NewStore();

        Assert.Null(store.Load());
    }

    [Fact]
    public void Load_CorruptFile_ReturnsNull()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllBytes(FilePath, [0x01, 0x02, 0x03, 0xFF, 0xFE, 0x00, 0x7A]);
        var store = NewStore();

        Assert.Null(store.Load());
    }

    [Fact]
    public void Load_EmptyFile_ReturnsNull()
    {
        Directory.CreateDirectory(_directory);
        File.WriteAllBytes(FilePath, []);
        var store = NewStore();

        Assert.Null(store.Load());
    }

    [Fact]
    public void Clear_MissingFile_DoesNotThrow()
    {
        var store = NewStore();

        store.Clear();

        Assert.Null(store.Load());
    }

    [Fact]
    public void Save_LeavesNoTempFilesBehind()
    {
        var store = NewStore();

        store.Save(Key);

        Assert.Equal([FilePath], Directory.GetFiles(_directory));
    }

    [Fact]
    public void Save_OverwritesExistingKey()
    {
        var store = NewStore();

        store.Save("a");
        store.Save("b");

        Assert.Equal("b", store.Load());
    }

    [Fact]
    public void Save_FileDoesNotContainPlaintext()
    {
        var store = NewStore();

        store.Save(Key);

        var raw = Encoding.UTF8.GetString(File.ReadAllBytes(FilePath));
        Assert.DoesNotContain(Key, raw);
    }

    [Fact]
    public void SaveAndClear_RaiseChanged()
    {
        var store = NewStore();
        var changedCount = 0;
        store.Changed += (_, _) => changedCount++;

        store.Save(Key);
        Assert.Equal(1, changedCount);

        store.Clear();
        Assert.Equal(2, changedCount);
        Assert.Null(store.Load());
    }
}
