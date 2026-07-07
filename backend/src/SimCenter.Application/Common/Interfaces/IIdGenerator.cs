namespace SimCenter.Application.Common.Interfaces;

/// <summary>
/// PK(UUID v7) 생성 포트. v7은 시간을 내장하므로 static 직접 호출을 금지하고(헌장)
/// 이 추상을 통해 주입해 결정론적 테스트를 가능하게 한다(D-6).
/// </summary>
public interface IIdGenerator
{
    Guid NewId();
}
