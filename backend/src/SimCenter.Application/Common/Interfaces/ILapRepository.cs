using SimCenter.Domain.Entities;

namespace SimCenter.Application.Common.Interfaces;

/// <summary>Lap 영속성 포트. 섹터는 Lap.Sectors로 함께 저장된다(cascade).</summary>
public interface ILapRepository
{
    Task AddAsync(Lap lap, CancellationToken cancellationToken = default);
}
