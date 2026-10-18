using System.Text.Json;

namespace SimCenter.Application.Seasons.Queries.Detail;

/// <summary>
/// 저장된 jsonb(D-49) 읽기 도우미. 모양을 검사하지 않고 저장했으므로 키가 없거나 종류가 달라도 예외 없이 null로 읽는다(docs/15 §11.4: 없으면 null).
/// </summary>
internal static class JsonReads
{
    /// <summary>JSON 객체 원문을 연다. 비었거나 객체가 아니거나 깨졌으면 null.</summary>
    public static JsonDocument? ParseObject(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return null;
        }

        try
        {
            var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                return document;
            }

            document.Dispose();
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static JsonElement? Child(JsonElement parent, string name, JsonValueKind kind)
        => parent.ValueKind == JsonValueKind.Object && parent.TryGetProperty(name, out var value) && value.ValueKind == kind
            ? value
            : null;

    public static JsonElement? Object(JsonElement parent, string name) => Child(parent, name, JsonValueKind.Object);

    public static JsonElement? Array(JsonElement parent, string name) => Child(parent, name, JsonValueKind.Array);

    /// <summary>숫자 값을 정수로(소수는 반올림). 없거나 숫자가 아니거나 int 범위 밖이면 null.</summary>
    public static int? Int(JsonElement parent, string name)
        => Child(parent, name, JsonValueKind.Number) is { } value ? ToInt(value) : null;

    public static int? ToInt(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        if (value.TryGetInt32(out var whole))
        {
            return whole;
        }

        var number = Math.Round(value.GetDouble(), MidpointRounding.AwayFromZero);
        return double.IsFinite(number) && number is >= int.MinValue and <= int.MaxValue ? (int)number : null;
    }

    /// <summary>불리언 값. 없거나 불리언이 아니면 null.</summary>
    public static bool? Bool(JsonElement parent, string name)
    {
        if (parent.ValueKind != JsonValueKind.Object || !parent.TryGetProperty(name, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null,
        };
    }

    public static string? String(JsonElement parent, string name)
        => Child(parent, name, JsonValueKind.String) is { } value ? value.GetString() : null;
}
