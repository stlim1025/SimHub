using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Net.Http.Headers;

namespace SimCenter.Api.Common;

/// <summary>
/// 성공(200) 응답을 브라우저에만 잠시 캐시하게 한다: <c>Cache-Control: private, max-age</c> + <c>Vary: Authorization</c>
/// (같은 브라우저에서 다른 사용자로 로그인하면 캐시를 나눠 쓰지 않는다). 404 등 실패 응답은 캐시하지 않는다 —
/// 트레이스가 나중에 올라오면 바로 보여야 한다. 랩 트레이스처럼 한번 저장되면 바뀌지 않는 큰 응답에만 붙인다.
/// </summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class PrivateCacheAttribute(int seconds) : ResultFilterAttribute
{
    /// <summary>랩 트레이스 캐시 시간(초): 탭을 오가거나 비교를 다시 열 때 다시 받지 않을 만큼.</summary>
    public const int LapTraceSeconds = 3600;

    public override void OnResultExecuting(ResultExecutingContext context)
    {
        if (context.Result is ObjectResult { StatusCode: null or StatusCodes.Status200OK })
        {
            var headers = context.HttpContext.Response.Headers;
            headers.CacheControl = $"private, max-age={seconds}";
            headers.Append(HeaderNames.Vary, HeaderNames.Authorization);
        }

        base.OnResultExecuting(context);
    }
}
