using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>JWT 발급 포트. 구현은 Infrastructure(HS256).</summary>
public interface IJwtTokenGenerator
{
    /// <summary>사용자에 대한 access token과 만료 시각(UTC)을 발급한다.</summary>
    (string Token, DateTime ExpiresAt) Generate(User user);
}
