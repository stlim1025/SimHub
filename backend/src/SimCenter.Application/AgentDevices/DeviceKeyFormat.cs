using System.Buffers.Text;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Application.AgentDevices;

/// <summary>
/// Agent 장치 키 형식(11 §4.2). 32바이트 난수를 base64url(패딩 없음, 43자)로 인코딩한다.
/// 원문은 연결 응답에서 한 번만 내려가고 서버에는 해시만 남는다.
/// </summary>
public static class DeviceKeyFormat
{
    /// <summary>키 난수 바이트 수(256비트).</summary>
    public const int KeyBytes = 32;

    public static string Create(IRandomSource random)
    {
        ArgumentNullException.ThrowIfNull(random);
        return Base64Url.EncodeToString(random.GetBytes(KeyBytes));
    }
}
