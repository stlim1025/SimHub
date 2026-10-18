using System.Security.Claims;
using Microsoft.AspNetCore.SignalR;

namespace SimCenter.Api.Hubs;

/// <summary>
/// SignalR 사용자 식별 = JWT <c>sub</c>(사용자 ID, docs/15 §9, D-50). <c>Clients.User(userId)</c>가 이 값으로 연결을 찾는다.
/// JwtBearer는 기본으로 <c>sub</c>를 <see cref="ClaimTypes.NameIdentifier"/>로 바꿔 싣지만, 그 매핑에 기대지 않도록 둘 다 본다.
/// </summary>
public sealed class JwtSubjectUserIdProvider : IUserIdProvider
{
    private const string SubjectClaim = "sub";

    public string? GetUserId(HubConnectionContext connection)
    {
        ArgumentNullException.ThrowIfNull(connection);
        return FindUserId(connection.User)?.ToString();
    }

    /// <summary>연결 주체의 사용자 ID. 없거나 GUID가 아니면 null.</summary>
    public static Guid? FindUserId(ClaimsPrincipal? user)
    {
        var value = user?.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? user?.FindFirst(SubjectClaim)?.Value;
        return Guid.TryParse(value, out var userId) ? userId : null;
    }
}
