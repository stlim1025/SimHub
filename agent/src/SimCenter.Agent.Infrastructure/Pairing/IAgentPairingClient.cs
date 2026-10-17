namespace SimCenter.Agent.Infrastructure.Pairing;

/// <summary>
/// 웹에서 발급한 1회용 연결 코드로 이 PC를 계정에 연결한다(docs/11 §4·§6.3).
/// Cli(<c>pair</c> 명령)와 Tray가 함께 쓴다.
/// </summary>
public interface IAgentPairingClient
{
    /// <summary>
    /// 서버에 <c>{ code, deviceName }</c>을 보내 장치 키를 받고, 성공하면 <see cref="Credentials.IDeviceCredentialStore"/>에 저장한다.
    /// 서버 거절·네트워크 오류·저장 실패는 예외가 아니라 실패 <see cref="PairOutcome"/>으로 돌려준다.
    /// </summary>
    /// <param name="code">사용자가 입력한 연결 코드(<c>XXXX-XXXX</c>). 정규화는 서버가 한다.</param>
    /// <param name="deviceName">서버에 표시할 PC 이름.</param>
    /// <param name="ct">호출자 취소 토큰. 취소되면 <see cref="OperationCanceledException"/>을 던진다.</param>
    Task<PairOutcome> PairAsync(string code, string deviceName, CancellationToken ct);
}
