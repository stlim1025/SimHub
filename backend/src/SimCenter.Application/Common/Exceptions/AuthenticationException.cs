namespace SimCenter.Application.Common.Exceptions;

/// <summary>인증 실패(→ HTTP 401). 예: 잘못된 자격 증명.</summary>
public sealed class AuthenticationException : AppException
{
    public AuthenticationException(string message) : base(message)
    {
    }
}
