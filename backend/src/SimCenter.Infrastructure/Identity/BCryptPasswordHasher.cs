using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Identity;

/// <summary>IPasswordHasher 구현(BCrypt.Net-Next). salt는 해시 문자열에 내장된다.</summary>
public sealed class BCryptPasswordHasher : IPasswordHasher
{
    public string Hash(string password) => BCrypt.Net.BCrypt.HashPassword(password);

    public bool Verify(string password, string passwordHash) => BCrypt.Net.BCrypt.Verify(password, passwordHash);
}
