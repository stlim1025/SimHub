using System.Text;
using System.Text.Json;

namespace SimCenter.Application.Common;

/// <summary>
/// 받은 JSON 값을 PostgreSQL jsonb 열에 그대로 저장할 원문으로 만든다(D-49). 구조는 보지 않고 저장할 수 있는지만 본다:
/// 객체인지, 크기 한도 안인지, jsonb가 거부하는 문자열(NUL <c>\u0000</c>·짝 없는 서로게이트)이 없는지.
/// 저장할 수 없는 값을 그대로 넣으면 커밋이 예외가 되어 같은 이벤트가 끝없이 재시도되므로, 그런 값은 미리 버린다.
/// </summary>
public static class JsonbText
{
    private const char Nul = '\0';

    /// <summary>저장할 원문. 저장할 수 없으면 null과 사유.</summary>
    public static string? TryCaptureObject(JsonElement value, int maxBytes, out string? rejectReason)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            rejectReason = $"객체가 아닙니다({value.ValueKind})";
            return null;
        }

        var raw = value.GetRawText();
        var bytes = Encoding.UTF8.GetByteCount(raw);
        if (bytes > maxBytes)
        {
            rejectReason = $"크기 {bytes}B > 한도 {maxBytes}B";
            return null;
        }

        if (!AllStringsStorable(value))
        {
            rejectReason = "jsonb에 저장할 수 없는 문자열(NUL·짝 없는 서로게이트)이 있습니다";
            return null;
        }

        rejectReason = null;
        return raw;
    }

    /// <summary>모든 문자열 값과 속성 이름이 디코딩되고 NUL을 품지 않는지(깊이는 파서 한도 64로 이미 제한된다).</summary>
    private static bool AllStringsStorable(JsonElement element)
    {
        try
        {
            return element.ValueKind switch
            {
                JsonValueKind.String => !element.GetString()!.Contains(Nul),
                JsonValueKind.Object => element.EnumerateObject()
                    .All(p => !p.Name.Contains(Nul) && AllStringsStorable(p.Value)),
                JsonValueKind.Array => element.EnumerateArray().All(AllStringsStorable),
                _ => true,
            };
        }
        catch (InvalidOperationException)
        {
            // 짝 없는 서로게이트 등 UTF-16으로 읽을 수 없는 escape.
            return false;
        }
    }
}
