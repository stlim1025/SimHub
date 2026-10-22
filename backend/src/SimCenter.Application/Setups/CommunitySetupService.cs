using System.Globalization;
using SimCenter.Application.Common;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Constants;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Setups;

/// <summary>커뮤니티 셋업 조회 유스케이스.</summary>
public interface ICommunitySetupService
{
    /// <summary>게임의 트랙(캘린더 순) + 조건별 셋업 수.</summary>
    Task<IReadOnlyList<SetupTrackDto>> GetTracksAsync(string gameCode, CancellationToken cancellationToken = default);

    /// <summary>트랙·조건의 셋업 목록(순위 순). 트랙이 없으면 <see cref="NotFoundException"/>.</summary>
    Task<SetupListResponse> GetListAsync(Guid trackId, string condition, CancellationToken cancellationToken = default);

    /// <summary>셋업 상세. 없으면 <see cref="NotFoundException"/>.</summary>
    Task<SetupDetailDto> GetDetailAsync(Guid id, CancellationToken cancellationToken = default);
}

/// <summary><see cref="ICommunitySetupService"/> 구현. 서킷 이름은 정적 카탈로그(<see cref="TrackCatalog"/>)에서 붙인다.</summary>
public sealed class CommunitySetupService : ICommunitySetupService
{
    private const string SetOnFormat = "yyyy-MM-dd";

    private readonly ICommunitySetupRepository _setups;
    private readonly ITrackRepository _tracks;

    public CommunitySetupService(ICommunitySetupRepository setups, ITrackRepository tracks)
    {
        _setups = setups;
        _tracks = tracks;
    }

    public async Task<IReadOnlyList<SetupTrackDto>> GetTracksAsync(string gameCode, CancellationToken cancellationToken = default)
    {
        var tracks = await _tracks.GetAllAsync(cancellationToken);
        var counts = await _setups.GetCountsAsync(gameCode, cancellationToken);
        var countByKey = counts.ToDictionary(c => (c.TrackId, c.Condition), c => c.Count);

        // 순서(표시 순서 → 이름)는 리포지토리가 보장한다.
        return tracks
            .Where(t => t.GameCode == gameCode)
            .Select(t => new SetupTrackDto(
                t.Id,
                t.Name,
                t.CountryCode,
                t.DisplayOrder,
                TrackCatalog.Find(t.GameCode, t.GameTrackId)?.CircuitName,
                countByKey.GetValueOrDefault((t.Id, SetupConditions.Dry)),
                countByKey.GetValueOrDefault((t.Id, SetupConditions.Wet))))
            .ToList();
    }

    public async Task<SetupListResponse> GetListAsync(Guid trackId, string condition, CancellationToken cancellationToken = default)
    {
        var track = await _tracks.GetByIdAsync(trackId, cancellationToken)
            ?? throw new NotFoundException("트랙을 찾을 수 없습니다.");

        var setups = await _setups.GetActiveAsync(trackId, condition, cancellationToken);
        var items = setups
            .Select(s => new SetupListItemDto(s.Id, s.Rank, s.TeamName, s.SessionType, s.LapTimeMs, s.SourceUrl))
            .ToList();
        DateTime? fetchedAt = setups.Count == 0 ? null : setups.Max(s => s.FetchedAt);

        return new SetupListResponse(ToTrackRef(track), condition, fetchedAt, items);
    }

    public async Task<SetupDetailDto> GetDetailAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var setup = await _setups.GetByIdAsync(id, cancellationToken)
            ?? throw new NotFoundException("셋업을 찾을 수 없습니다.");
        var track = setup.Track ?? await _tracks.GetByIdAsync(setup.TrackId, cancellationToken)
            ?? throw new NotFoundException("트랙을 찾을 수 없습니다.");

        return new SetupDetailDto(
            setup.Id,
            setup.Rank,
            setup.GameCode,
            ToTrackRef(track),
            setup.Condition,
            setup.TeamName,
            setup.SessionType,
            setup.LapTimeMs,
            setup.Steering,
            setup.SetOn?.ToString(SetOnFormat, CultureInfo.InvariantCulture),
            setup.SourceUrl,
            setup.FetchedAt,
            SetupSections.Deserialize(setup.Sections));
    }

    private static SetupTrackRefDto ToTrackRef(Track track)
        => new(track.Id, track.Name, track.CountryCode, TrackCatalog.Find(track.GameCode, track.GameTrackId)?.CircuitName);
}
