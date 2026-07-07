namespace SimCenter.Application.Common.Interfaces;

/// <summary>비밀번호 해시/검증 포트. 구현은 Infrastructure(BCrypt).</summary>
public interface IPasswordHasher
{
    string Hash(string password);

    bool Verify(string password, string passwordHash);
}
