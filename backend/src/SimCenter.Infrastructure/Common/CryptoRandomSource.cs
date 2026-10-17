using System.Security.Cryptography;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Common;

/// <summary>
/// IRandomSource 구현. 연결 코드·장치 키처럼 추측 불가여야 하는 값을 위해
/// 암호학적으로 안전한 난수(<see cref="RandomNumberGenerator"/>)를 쓴다.
/// </summary>
public sealed class CryptoRandomSource : IRandomSource
{
    public byte[] GetBytes(int count) => RandomNumberGenerator.GetBytes(count);
}
