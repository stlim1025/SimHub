using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Domain.Entities;

namespace SimCenter.Application.Seasons.Commands;

/// <summary>
/// 내 시즌 이름·완료·삭제(<see cref="ISeasonCommandService"/>). Domain·포트에만 의존한다.
/// 삭제 = soft delete — 전역 필터로 이후 시즌 조회에서 자동 제외된다.
/// </summary>
public sealed class SeasonCommandService : ISeasonCommandService
{
    private const string NameField = "name";
    private const string CompletedField = "completed";
    private const string NotFoundMessage = "시즌을 찾을 수 없습니다.";
    private const string CompletedRequiredMessage = "completed 값이 필요합니다.";

    private static readonly string NameTooLongMessage = $"시즌 이름은 {Season.NameMaxLength}자 이하여야 합니다.";

    private readonly ISeasonRepository _seasons;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IClock _clock;

    public SeasonCommandService(ISeasonRepository seasons, IUnitOfWork unitOfWork, IClock clock)
    {
        _seasons = seasons;
        _unitOfWork = unitOfWork;
        _clock = clock;
    }

    public async Task RenameAsync(Guid userId, Guid seasonId, RenameSeasonRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var name = NormalizeName(request.Name);
        var season = await GetMineAsync(userId, seasonId, cancellationToken);

        season.Rename(name, _clock.UtcNow);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }

    public async Task SetCompletedAsync(
        Guid userId, Guid seasonId, SetSeasonCompletionRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var completed = request.Completed ?? throw new ValidationException(CompletedField, CompletedRequiredMessage);
        var season = await GetMineAsync(userId, seasonId, cancellationToken);

        var now = _clock.UtcNow;
        if (completed)
        {
            season.MarkCompleted(now);
        }
        else
        {
            season.Reopen(now);
        }

        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }

    public async Task DeleteAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default)
    {
        var season = await GetMineAsync(userId, seasonId, cancellationToken);

        season.SoftDelete(_clock.UtcNow);
        await _unitOfWork.SaveChangesAsync(cancellationToken);
    }

    private async Task<Season> GetMineAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken)
        => await _seasons.GetMineAsync(userId, seasonId, cancellationToken)
            ?? throw new NotFoundException(NotFoundMessage);

    /// <summary>앞뒤 공백 제거, 빈 값은 null(기본 이름). 너무 길면 400.</summary>
    private static string? NormalizeName(string? name)
    {
        var trimmed = name?.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        return trimmed.Length > Season.NameMaxLength
            ? throw new ValidationException(NameField, NameTooLongMessage)
            : trimmed;
    }
}
