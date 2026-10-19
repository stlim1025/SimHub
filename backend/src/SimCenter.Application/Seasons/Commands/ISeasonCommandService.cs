namespace SimCenter.Application.Seasons.Commands;

/// <summary>
/// 내 시즌 관리 유스케이스: 이름 바꾸기 · 완료 표시 · 삭제. 남의 시즌·없는 시즌·지운 시즌은 모두 404(D-34)다.
/// </summary>
public interface ISeasonCommandService
{
    /// <summary>
    /// 표시 이름을 바꾼다. 앞뒤 공백을 지우고, 비었거나 null이면 기본 이름(null)으로 되돌린다.
    /// 지운 뒤 길이가 <see cref="Domain.Entities.Season.NameMaxLength"/>를 넘으면 400(<c>name</c>).
    /// </summary>
    Task RenameAsync(Guid userId, Guid seasonId, RenameSeasonRequest request, CancellationToken cancellationToken = default);

    /// <summary>
    /// 완료 표시를 켜거나 끈다. 켤 때 이미 완료면 처음 시각을 유지한다. 값이 없으면 400(<c>completed</c>).
    /// </summary>
    Task SetCompletedAsync(Guid userId, Guid seasonId, SetSeasonCompletionRequest request, CancellationToken cancellationToken = default);

    /// <summary>시즌을 지운다(soft delete). 세션은 남고 시즌 목록·상세에서만 빠진다.</summary>
    Task DeleteAsync(Guid userId, Guid seasonId, CancellationToken cancellationToken = default);
}
