using Microsoft.Extensions.Options;
using SimCenter.Application.Common.Interfaces;

namespace SimCenter.Infrastructure.Configuration;

/// <summary>IRankingTimeZoneProvider의 설정 기반 구현. <see cref="RankingOptions.TimeZoneId"/>를 그대로 노출한다.</summary>
public sealed class ConfiguredRankingTimeZoneProvider : IRankingTimeZoneProvider
{
    public ConfiguredRankingTimeZoneProvider(IOptions<RankingOptions> options)
        => TimeZoneId = options.Value.TimeZoneId;

    public string TimeZoneId { get; }
}
