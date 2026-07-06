using System;

namespace SimCenter.Application.Common.Interfaces;

public interface IClock
{
    DateTime UtcNow { get; }
}
