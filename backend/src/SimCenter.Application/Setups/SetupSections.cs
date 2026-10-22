using System.Text.Json;

namespace SimCenter.Application.Setups;

/// <summary>셋업 값 한 줄(출처 표기 그대로, 예: "Front Camber" / "-3.50˚").</summary>
public sealed record SetupItemDto(string Label, string Value);

/// <summary>셋업 값 묶음 한 칸(예: "Aerodynamics").</summary>
public sealed record SetupSectionDto(string Title, IReadOnlyList<SetupItemDto> Items);

/// <summary><c>community_setups.sections</c>(jsonb) ↔ 묶음 목록. JSON 이름은 camelCase(<c>title</c>·<c>items</c>·<c>label</c>·<c>value</c>).</summary>
public static class SetupSections
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);

    public static string Serialize(IReadOnlyList<SetupSectionDto> sections)
    {
        ArgumentNullException.ThrowIfNull(sections);
        return JsonSerializer.Serialize(sections, Options);
    }

    /// <summary>저장된 JSON을 읽는다. 비었거나 깨졌으면 빈 목록(조회는 실패시키지 않는다).</summary>
    public static IReadOnlyList<SetupSectionDto> Deserialize(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return [];
        }

        try
        {
            return JsonSerializer.Deserialize<List<SetupSectionDto>>(json, Options) ?? [];
        }
        catch (JsonException)
        {
            return [];
        }
    }
}
