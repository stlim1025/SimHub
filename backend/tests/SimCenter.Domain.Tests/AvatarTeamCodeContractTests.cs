using SimCenter.Domain.Constants;

namespace SimCenter.Domain.Tests;

/// <summary>
/// 프로필 사진 팀 코드 계약(14 §4): 백엔드 <see cref="AvatarTeamCodes.All"/>가 OpenAPI <c>AvatarTeamCode</c> enum과,
/// 프로필의 nullable <c>avatarTeam</c> 인라인 enum(null 포함)과 같은 순서·값인지 확인한다.
/// 앱 목록(<c>kAvatarTeams</c>)은 앱 테스트(<c>app/test/avatar_team_contract_test.dart</c>)가 같은 OpenAPI enum과 비교한다.
/// 트랙 ID 계약 테스트(TrackIdContractTests·TrackSeedE2ETests)와 같은 방식으로 저장소의 계약 파일을 읽는다.
/// </summary>
public class AvatarTeamCodeContractTests
{
    private const string ContractRelativePath = "shared/openapi/openapi.yaml";
    private const string SchemaHeader = "    AvatarTeamCode:";
    private const string EnumPrefix = "enum: [";
    private const string NullItem = "null";

    /// <summary>스키마 1개 + nullable 인라인 2개(UserProfile·UpdateProfileRequest의 avatarTeam).</summary>
    private const int ExpectedInlineEnumCount = 2;

    [Fact]
    public void OpenApiAvatarTeamCodeEnum_MatchesBackendCodes()
    {
        var lines = File.ReadAllLines(FindContractPath());

        Assert.Equal(AvatarTeamCodes.All, ReadSchemaEnum(lines));
    }

    [Fact]
    public void OpenApiNullableAvatarTeamEnums_MatchBackendCodesPlusNull()
    {
        var lines = File.ReadAllLines(FindContractPath());
        var inline = lines
            .Select(ParseEnumLine)
            .Where(items => items is not null && items.Contains(NullItem) && items.Contains(AvatarTeamCodes.Mercedes))
            .ToList();

        Assert.Equal(ExpectedInlineEnumCount, inline.Count);
        Assert.All(inline, items => Assert.Equal(AvatarTeamCodes.All.Append(NullItem), items!));
    }

    private static IReadOnlyList<string> ReadSchemaEnum(string[] lines)
    {
        var start = Array.IndexOf(lines, SchemaHeader);
        Assert.True(start >= 0, $"{ContractRelativePath}에 AvatarTeamCode 스키마가 없습니다.");

        // 스키마 블록(들여쓰기가 더 깊은 줄들) 안의 enum 줄.
        var block = lines.Skip(start + 1).TakeWhile(line => line.Length == 0 || line.StartsWith("      ", StringComparison.Ordinal));
        var items = block.Select(ParseEnumLine).FirstOrDefault(parsed => parsed is not null);
        Assert.NotNull(items);
        return items;
    }

    /// <summary><c>enum: [A, B, null]</c> 한 줄 → 항목 목록. enum 줄이 아니면 null.</summary>
    private static List<string>? ParseEnumLine(string line)
    {
        var trimmed = line.Trim();
        if (!trimmed.StartsWith(EnumPrefix, StringComparison.Ordinal) || !trimmed.EndsWith(']'))
        {
            return null;
        }

        return trimmed[EnumPrefix.Length..^1]
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .ToList();
    }

    /// <summary>테스트 실행 폴더(bin/…)에서 위로 올라가며 저장소의 계약 파일을 찾는다.</summary>
    private static string FindContractPath()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, ContractRelativePath);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException($"저장소에서 {ContractRelativePath}를 찾지 못했습니다.");
    }
}
