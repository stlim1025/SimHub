using System.Net;

namespace SimCenter.Agent.Infrastructure.Upload;

/// <summary>
/// 허브 연결 실패가 장치 키 거부(HTTP 401)인지 판별한다(docs/11 §6.4). 401이면 재시도해도 소용없으므로 업로드를 멈춘다.
/// SignalR 클라이언트는 negotiate 실패를 <see cref="HttpRequestException"/>으로, 전송 방식 전체 실패를
/// <see cref="AggregateException"/>으로 감싸 던지므로 내부 예외까지 살펴본다.
/// </summary>
public static class UnauthorizedDetector
{
    public static bool IsUnauthorized(Exception ex)
    {
        ArgumentNullException.ThrowIfNull(ex);

        for (Exception? current = ex; current is not null; current = current.InnerException)
        {
            if (current is HttpRequestException { StatusCode: HttpStatusCode.Unauthorized })
            {
                return true;
            }

            if (current is AggregateException aggregate)
            {
                return aggregate.InnerExceptions.Any(IsUnauthorized);
            }
        }

        return false;
    }
}
