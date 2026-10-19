namespace SimCenter.Application.Seasons.Commands;

/// <summary>시즌 이름 바꾸기 요청(<c>PUT /me/seasons/{id}/name</c>). null·빈 값 = 기본 이름으로 되돌리기.</summary>
public sealed record RenameSeasonRequest(string? Name);

/// <summary>
/// 시즌 완료 표시 요청(<c>PUT /me/seasons/{id}/completion</c>). 빠진 값이 false로 조용히 바뀌지 않도록 nullable로 받아 서비스가 검증한다.
/// </summary>
public sealed record SetSeasonCompletionRequest(bool? Completed);
