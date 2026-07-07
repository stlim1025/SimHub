using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using SimCenter.Application.Common.Exceptions;

namespace SimCenter.Api.Middleware;

/// <summary>
/// 애플리케이션 예외를 RFC 7807 ProblemDetails로 매핑한다(04-api-design §표준 에러).
/// 예상치 못한 예외는 500으로 상세 미노출, traceId만 반환한다.
/// </summary>
public sealed class ExceptionHandlingMiddleware
{
    private const string ProblemJson = "application/problem+json";
    private const string ErrorBaseUri = "https://simcenter/errors/";

    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await WriteProblemAsync(context, ex);
        }
    }

    private async Task WriteProblemAsync(HttpContext context, Exception exception)
    {
        var traceId = context.TraceIdentifier;

        var problem = exception switch
        {
            ValidationException ve => CreateProblem(StatusCodes.Status400BadRequest, "validation", "Validation failed", ve.Message, traceId, ve.Errors),
            AuthenticationException ae => CreateProblem(StatusCodes.Status401Unauthorized, "authentication", "Authentication failed", ae.Message, traceId),
            ForbiddenException fe => CreateProblem(StatusCodes.Status403Forbidden, "forbidden", "Forbidden", fe.Message, traceId),
            NotFoundException ne => CreateProblem(StatusCodes.Status404NotFound, "not-found", "Resource not found", ne.Message, traceId),
            ConflictException ce => CreateProblem(StatusCodes.Status409Conflict, "conflict", "Conflict", ce.Message, traceId),
            _ => CreateProblem(StatusCodes.Status500InternalServerError, "internal", "An unexpected error occurred", "서버 오류가 발생했습니다.", traceId),
        };

        if (problem.Status == StatusCodes.Status500InternalServerError)
        {
            _logger.LogError(exception, "Unhandled exception. TraceId={TraceId}", traceId);
        }
        else
        {
            _logger.LogWarning("Handled {ExceptionType}: {Message}. TraceId={TraceId}",
                exception.GetType().Name, exception.Message, traceId);
        }

        context.Response.StatusCode = problem.Status!.Value;
        context.Response.ContentType = ProblemJson;
        await context.Response.WriteAsync(JsonSerializer.Serialize(problem));
    }

    private static ProblemDetails CreateProblem(
        int status,
        string errorType,
        string title,
        string detail,
        string traceId,
        IReadOnlyDictionary<string, string[]>? errors = null)
    {
        var problem = new ProblemDetails
        {
            Type = ErrorBaseUri + errorType,
            Title = title,
            Status = status,
            Detail = detail,
        };
        problem.Extensions["traceId"] = traceId;
        if (errors is { Count: > 0 })
        {
            problem.Extensions["errors"] = errors;
        }

        return problem;
    }
}
