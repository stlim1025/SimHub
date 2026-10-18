using System.Text.Json;
using F1Enums = F1Game.UDP.Enums;

namespace SimCenter.Agent.Infrastructure.Tests;

/// <summary>
/// Agent가 보내는 트랙 ID(<c>(int)SessionDataPacket.Track</c>)가 공유 계약 <c>shared/telemetry/f1_25_track_ids.json</c>과 같은지 확인한다.
/// 백엔드는 같은 계약으로 트랙 시드를 검사하므로(TrackSeedE2ETests), F1Game.UDP를 올려 새 트랙이 생기면
/// 이 테스트가 먼저 실패해 계약·시드 갱신을 알린다(시드에 없는 트랙의 기록은 Reject되어 영구 손실).
/// </summary>
public class TrackIdContractTests
{
    private const string ContractRelativePath = "shared/telemetry/f1_25_track_ids.json";

    [Fact]
    public void LibraryTrackEnum_MatchesSharedContract()
    {
        var library = Enum.GetValues<F1Enums.Track>()
            .Where(track => track != F1Enums.Track.Unknown)
            .Select(track => (int)track)
            .Order()
            .ToList();

        var contract = ReadContractTrackIds().Order().ToList();

        Assert.Equal(library, contract);
    }

    private static IReadOnlyList<int> ReadContractTrackIds()
    {
        using var document = JsonDocument.Parse(File.ReadAllText(FindContractPath()));
        return document.RootElement.GetProperty("trackIds").EnumerateArray().Select(id => id.GetInt32()).ToList();
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
