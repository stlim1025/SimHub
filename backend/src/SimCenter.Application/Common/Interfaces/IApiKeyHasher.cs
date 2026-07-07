namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// Agent API Key 해시 포트(D-21). 고엔트로피 키를 결정적으로 해시해 조회 가능하게 한다(SHA-256).
/// 비밀번호(BCrypt, salted)와 달리 조회를 위해 결정적이어야 하므로 IPasswordHasher와 분리한다.
/// </summary>
public interface IApiKeyHasher
{
    string Hash(string rawKey);
}
