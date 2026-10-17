namespace SimCenter.Application.AgentDevices;

/// <summary>Agent 연결 유스케이스(11 §4): 연결 코드 발급과 코드 → 장치 키 교환.</summary>
public interface IAgentPairingService
{
    /// <summary>사용자의 연결 코드를 발급한다. 같은 사용자의 미사용 코드는 모두 무효화된다.</summary>
    Task<PairingCodeResponse> IssueCodeAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>연결 코드를 소비하고 코드 주인의 장치를 만들어 장치 키를 한 번만 돌려준다.</summary>
    Task<PairResponse> PairAsync(PairRequest request, CancellationToken cancellationToken = default);
}
