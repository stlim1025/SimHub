namespace SimCenter.Application.Common.Exceptions;

/// <summary>
/// 애플리케이션 계층 예외의 베이스. ExceptionHandlingMiddleware가 이 계층 예외를
/// RFC 7807 ProblemDetails로 매핑한다(04-api-design §표준 에러).
/// </summary>
public abstract class AppException : Exception
{
    protected AppException(string message) : base(message)
    {
    }
}
