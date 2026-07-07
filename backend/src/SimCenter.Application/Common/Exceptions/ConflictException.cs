namespace SimCenter.Application.Common.Exceptions;

/// <summary>상태 충돌(→ HTTP 409). 예: 이미 존재하는 이메일, 이미 활성 세션.</summary>
public sealed class ConflictException : AppException
{
    public ConflictException(string message) : base(message)
    {
    }
}
