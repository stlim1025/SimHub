namespace SimCenter.Application.Common.Exceptions;

/// <summary>권한 없음(→ HTTP 403). 인증은 됐으나 해당 리소스에 대한 권한이 없을 때. 예: 타인 세션 종료.</summary>
public sealed class ForbiddenException : AppException
{
    public ForbiddenException(string message) : base(message)
    {
    }
}
