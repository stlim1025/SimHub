namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// 암호학적 난수 바이트 공급 포트. 연결 코드·장치 키 생성에서 static 난수 직접 호출을 금지하고(헌장)
/// 이 추상을 주입해 결정론적 테스트를 가능하게 한다. 구현은 Infrastructure(RandomNumberGenerator).
/// </summary>
public interface IRandomSource
{
    /// <summary>난수 바이트 <paramref name="count"/>개를 반환한다.</summary>
    byte[] GetBytes(int count);
}
