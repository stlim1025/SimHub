using System.Net;
using System.Net.Sockets;
using SimCenter.Agent.Infrastructure.Upload;

namespace SimCenter.Agent.Infrastructure.Tests;

public class UnauthorizedDetectorTests
{
    private static HttpRequestException Http(HttpStatusCode status)
        => new("Response status code does not indicate success.", inner: null, statusCode: status);

    [Fact]
    public void UnauthorizedDetector_True_ForHttp401_IncludingInner()
    {
        var direct = Http(HttpStatusCode.Unauthorized);
        var wrapped = new InvalidOperationException("연결 실패", direct);
        var aggregated = new AggregateException(new SocketException(), new Exception("transport", direct));

        Assert.True(UnauthorizedDetector.IsUnauthorized(direct));
        Assert.True(UnauthorizedDetector.IsUnauthorized(wrapped));
        Assert.True(UnauthorizedDetector.IsUnauthorized(aggregated));
    }

    [Fact]
    public void UnauthorizedDetector_False_ForOtherErrors()
    {
        Assert.False(UnauthorizedDetector.IsUnauthorized(Http(HttpStatusCode.InternalServerError)));
        Assert.False(UnauthorizedDetector.IsUnauthorized(Http(HttpStatusCode.Forbidden)));
        Assert.False(UnauthorizedDetector.IsUnauthorized(new SocketException()));
        Assert.False(UnauthorizedDetector.IsUnauthorized(new HttpRequestException("no status")));
        Assert.False(UnauthorizedDetector.IsUnauthorized(new AggregateException(new SocketException())));
    }
}
