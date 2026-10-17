using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;

namespace SimCenter.Agent.Infrastructure.Credentials;

/// <summary>
/// Windows DPAPI(<see cref="DataProtectionScope.CurrentUser"/>)로 암호화해 파일에 보관하는 장치 키 저장소.
/// 같은 Windows 사용자 계정에서만 복호화할 수 있다. 키 내용은 로그에 남기지 않는다.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class DpapiDeviceCredentialStore : IDeviceCredentialStore
{
    private const string TempFileExtension = ".tmp";

    // 앱 고유 엔트로피 — 같은 사용자 세션의 다른 앱이 이 파일을 그대로 복호화하지 못하게 하는 보조 값(비밀이 아님).
    private static readonly byte[] AppEntropy = Encoding.UTF8.GetBytes("SimCenter.Agent.DeviceKey.v1");

    private readonly string _filePath;
    private readonly ILogger<DpapiDeviceCredentialStore> _logger;
    private readonly object _gate = new();

    public DpapiDeviceCredentialStore(string filePath, ILogger<DpapiDeviceCredentialStore> logger)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filePath);
        ArgumentNullException.ThrowIfNull(logger);
        _filePath = filePath;
        _logger = logger;
    }

    /// <summary>기본 저장 위치: <c>%LOCALAPPDATA%\SimCenter\Agent\device.key</c>.</summary>
    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SimCenter",
        "Agent",
        "device.key");

    public event EventHandler? Changed;

    public string? Load()
    {
        lock (_gate)
        {
            if (!File.Exists(_filePath))
            {
                return null;
            }

            byte[]? plain = null;
            try
            {
                var protectedBytes = File.ReadAllBytes(_filePath);
                plain = ProtectedData.Unprotect(protectedBytes, AppEntropy, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(plain);
            }
            catch (Exception ex) when (ex is CryptographicException or ArgumentException or IOException or UnauthorizedAccessException)
            {
                // 예외 메시지에는 키 내용이 없다. 손상·다른 사용자 계정 등은 미연결로 취급한다.
                _logger.LogError(ex, "장치 키 복호화/읽기 실패 — 미연결로 처리합니다. path={Path}", _filePath);
                return null;
            }
            finally
            {
                if (plain is not null)
                {
                    CryptographicOperations.ZeroMemory(plain);
                }
            }
        }
    }

    public void Save(string deviceKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceKey);

        lock (_gate)
        {
            WriteAtomically(deviceKey);
        }

        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Clear()
    {
        lock (_gate)
        {
            // 멱등 — 폴더째 없는 경우 File.Delete가 DirectoryNotFoundException을 던지므로 존재 여부를 먼저 본다.
            if (File.Exists(_filePath))
            {
                File.Delete(_filePath);
            }
        }

        Changed?.Invoke(this, EventArgs.Empty);
    }

    // 같은 폴더의 임시 파일에 먼저 쓰고 교체 — 쓰기 도중 크래시해도 기존 키 파일이 반쯤 쓰인 상태로 남지 않는다.
    private void WriteAtomically(string deviceKey)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(_filePath))!;
        Directory.CreateDirectory(directory);

        var tempPath = Path.Combine(directory, $"{Path.GetFileName(_filePath)}.{Guid.NewGuid():N}{TempFileExtension}");
        var plain = Encoding.UTF8.GetBytes(deviceKey);
        try
        {
            var protectedBytes = ProtectedData.Protect(plain, AppEntropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(tempPath, protectedBytes);
            File.Move(tempPath, _filePath, overwrite: true);
        }
        catch
        {
            TryDelete(tempPath);
            throw;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plain);
        }
    }

    private void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger.LogWarning(ex, "임시 파일 삭제 실패 path={Path}", path);
        }
    }
}
