using System.Security.Cryptography;
using System.Text;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Common;

/// <summary>
/// IApiKeyHasher 구현. 고엔트로피 키를 SHA-256으로 결정적 해시(소문자 hex)한다.
/// 결정적이라 DB 인덱스로 조회 가능(D-21). 원문 키는 어디에도 저장하지 않는다.
/// </summary>
public sealed class Sha256ApiKeyHasher : IApiKeyHasher
{
    public string Hash(string rawKey)
    {
        ArgumentException.ThrowIfNullOrEmpty(rawKey);
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(rawKey));
        return Convert.ToHexStringLower(bytes);
    }
}
