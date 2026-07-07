namespace SimCenter.Application.Common.Exceptions;

/// <summary>리소스 없음(→ HTTP 404).</summary>
public sealed class NotFoundException : AppException
{
    public NotFoundException(string message) : base(message)
    {
    }
}
