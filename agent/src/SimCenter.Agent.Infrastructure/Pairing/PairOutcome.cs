namespace SimCenter.Agent.Infrastructure.Pairing;

/// <summary>
/// 계정 연결 시도의 결과. <see cref="Message"/>는 사용자에게 그대로 보여 줘도 되는 한국어 문구이며
/// 연결 코드·장치 키 원문을 담지 않는다.
/// </summary>
/// <param name="Succeeded">연결되어 장치 키가 저장되었는지 여부.</param>
/// <param name="Message">사용자에게 보여 줄 결과 설명.</param>
public sealed record PairOutcome(bool Succeeded, string Message);
