namespace SimCenter.Application.Common.Exceptions;

/// <summary>검증 실패(→ HTTP 400). 필드별 오류를 함께 전달한다.</summary>
public sealed class ValidationException : AppException
{
    public IReadOnlyDictionary<string, string[]> Errors { get; }

    public ValidationException(string message, IReadOnlyDictionary<string, string[]>? errors = null)
        : base(message)
    {
        Errors = errors ?? new Dictionary<string, string[]>();
    }

    public ValidationException(string field, string error)
        : this("Validation failed.", new Dictionary<string, string[]> { [field] = new[] { error } })
    {
    }
}
