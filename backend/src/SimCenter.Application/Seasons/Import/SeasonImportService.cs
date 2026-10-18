using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using SimCenter.Application.Common.Exceptions;
using SimCenter.Application.Common.Interfaces;
using SimCenter.Application.Seasons.Import.Building;
using SimCenter.Domain.Entities;
using SimCenter.Domain.Enums;
using SimCenter.Domain.Seasons;

namespace SimCenter.Application.Seasons.Import;

/// <summary>
/// 시즌 가져오기(docs/15 §12, D-55). 파싱(<see cref="ImportDocumentReader"/>) → 연결할 게임 시즌 찾기 → 그래프 만들기(<see cref="SeasonImportBuilder"/>)
/// → 미리보기 또는 저장. 저장은 한 트랜잭션: 시즌·주말·가져온 세션 추가, 연결할 기록 세션의 모드·키·시즌 변경, 그 세션 랩의 키 변경.
/// <para>
/// 연결 후보 = 시즌에 없는 내 기록 세션 중 같은 게임·커리어 계열(가져온 모드 또는 예전 <c>Other</c>)이고 시즌·주말 링크가 있는 가장 최근 값.
/// 옮긴 세션의 키는 <c>SessionKeys.For</c>(D-29)로 다시 계산해 앞으로 오는 같은 링크의 세션이 이 시즌에 붙는다.
/// 후보가 없으면 시즌 링크 = 게임·모드·이름의 해시(음수 — 게임 링크와 겹치지 않음)라 같은 시즌을 두 번 가져오면 409다.
/// </para>
/// </summary>
public sealed class SeasonImportService : ISeasonImportService
{
    private const string MarkdownField = "markdown";

    private readonly ISeasonImportRepository _imports;
    private readonly ISeasonRepository _seasons;
    private readonly IGameSessionRepository _sessions;
    private readonly ITrackRepository _tracks;
    private readonly IUnitOfWork _unitOfWork;
    private readonly ITransactionRunner _transactions;
    private readonly IIdGenerator _ids;
    private readonly IClock _clock;
    private readonly ILogger<SeasonImportService> _logger;

    public SeasonImportService(
        ISeasonImportRepository imports,
        ISeasonRepository seasons,
        IGameSessionRepository sessions,
        ITrackRepository tracks,
        IUnitOfWork unitOfWork,
        ITransactionRunner transactions,
        IIdGenerator ids,
        IClock clock,
        ILogger<SeasonImportService> logger)
    {
        _imports = imports;
        _seasons = seasons;
        _sessions = sessions;
        _tracks = tracks;
        _unitOfWork = unitOfWork;
        _transactions = transactions;
        _ids = ids;
        _clock = clock;
        _logger = logger;
    }

    public async Task<SeasonImportPreviewDto> PreviewAsync(
        Guid userId, SeasonImportRequest request, CancellationToken cancellationToken = default)
    {
        var bundle = Read(request);
        var prepared = await PrepareAsync(userId, bundle, cancellationToken);
        var graph = BuildGraph(userId, bundle, prepared);
        return SeasonImportPreviewMapper.Map(bundle, graph, prepared.TrackNames, prepared.LinkId, prepared.AlreadyImported);
    }

    public async Task<SeasonImportResultDto> ImportAsync(
        Guid userId, SeasonImportRequest request, CancellationToken cancellationToken = default)
    {
        var bundle = Read(request);
        return await _transactions.RunAsync(async ct =>
        {
            var prepared = await PrepareAsync(userId, bundle, ct);
            if (prepared.AlreadyImported)
            {
                throw new ConflictException("이미 가져온 시즌입니다(같은 게임 시즌 링크 또는 같은 이름의 가져온 시즌이 있습니다).");
            }

            var graph = BuildGraph(userId, bundle, prepared);
            await PersistAsync(userId, bundle, graph, ct);
            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation(
                "시즌 가져오기 user={User} season={Season} link={Link} sessions={Sessions} attached={Attached}",
                userId, graph.Season.Id, graph.Season.SeasonLinkId, graph.Sessions.Count, graph.Attachments.Count);
            return new SeasonImportResultDto(graph.Season.Id, graph.Sessions.Count, graph.Attachments.Count);
        }, cancellationToken);
    }

    // ---- 파싱 ----

    private static ImportBundle Read(SeasonImportRequest request)
    {
        var markdown = request?.Markdown;
        if (string.IsNullOrWhiteSpace(markdown))
        {
            throw MarkdownError("붙여 넣은 내용이 없습니다.");
        }

        if (markdown.Length > ISeasonImportService.MaxMarkdownLength)
        {
            throw MarkdownError($"내용이 너무 깁니다(최대 {ISeasonImportService.MaxMarkdownLength}자).");
        }

        try
        {
            return ImportDocumentReader.Read(markdown);
        }
        catch (F1LapsFormatException ex)
        {
            throw FormatError(ex);
        }
    }

    private static ValidationException FormatError(F1LapsFormatException ex)
        => MarkdownError(ex.LineNumber > 0 ? $"{ex.LineNumber}번째 줄: {ex.Message}" : ex.Message);

    /// <summary>400 본문의 detail과 <c>errors.markdown</c>에 같은 문구를 싣는다(앱이 그대로 보여 준다).</summary>
    private static ValidationException MarkdownError(string message)
        => new(message, new Dictionary<string, string[]> { [MarkdownField] = [message] });

    private SeasonImportGraph BuildGraph(Guid userId, ImportBundle bundle, Prepared prepared)
    {
        try
        {
            return SeasonImportBuilder.Build(new SeasonImportInput(
                userId, bundle, prepared.TracksByRound, prepared.Linked, prepared.SeasonLinkId, _clock.UtcNow, _ids.NewId));
        }
        catch (F1LapsFormatException ex)
        {
            throw FormatError(ex);
        }
    }

    // ---- 준비 ----

    private sealed record Prepared(
        IReadOnlyDictionary<int, Track> TracksByRound,
        IReadOnlyDictionary<Guid, string> TrackNames,
        IReadOnlyList<GameSession> Linked,
        long? LinkId,
        long SeasonLinkId,
        bool AlreadyImported);

    private async Task<Prepared> PrepareAsync(Guid userId, ImportBundle bundle, CancellationToken cancellationToken)
    {
        var tracks = (await _tracks.GetAllAsync(cancellationToken)).Where(t => t.GameCode == bundle.GameCode).ToList();
        var tracksByRound = tracks
            .Where(t => t.DisplayOrder is >= 1 and <= ImportCalendar.RoundCount)
            .GroupBy(t => t.DisplayOrder)
            .ToDictionary(g => g.Key, g => g.First());

        var modes = new[] { bundle.GameMode, GameMode.Other };
        var unseasoned = await _imports.GetUnseasonedLinkedSessionsAsync(userId, bundle.GameCode, modes, cancellationToken);
        long? linkId = unseasoned.OrderByDescending(s => s.ClassifiedAt).Select(s => (long?)s.SeasonLinkId).FirstOrDefault();
        var linked = linkId is { } id ? unseasoned.Where(s => s.SeasonLinkId == id).ToList() : [];
        var seasonLinkId = linkId ?? SyntheticLinkId(bundle);

        var trackNames = tracks.ToDictionary(t => t.Id, t => t.Name);
        foreach (var session in linked.Where(s => s.Track is not null))
        {
            trackNames.TryAdd(session.TrackId, session.Track!.Name);
        }

        return new Prepared(tracksByRound, trackNames, linked, linkId, seasonLinkId,
            await IsAlreadyImportedAsync(userId, bundle, seasonLinkId, cancellationToken));
    }

    private async Task<bool> IsAlreadyImportedAsync(Guid userId, ImportBundle bundle, long seasonLinkId, CancellationToken cancellationToken)
    {
        if (await _seasons.GetByLinkAsync(userId, bundle.GameCode, seasonLinkId, cancellationToken) is not null)
        {
            return true;
        }

        var imported = await _imports.GetImportedSeasonsAsync(userId, bundle.GameCode, cancellationToken);
        return imported.Any(s => s.GameMode == bundle.GameMode
            && string.Equals(ImportedSeasonSnapshot.TryRead(s.ImportedStandings)?.Title, bundle.Title, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>게임·모드·이름 → 음수 링크(결정적). 게임 링크(양수)와 겹치지 않는다.</summary>
    private static long SyntheticLinkId(ImportBundle bundle)
    {
        var key = $"{bundle.GameCode}|{bundle.GameMode}|{DriverNameMatcher.Normalize(bundle.Title)}";
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(key));
        return -(1 + (BitConverter.ToInt64(hash, 0) & 0x3FFF_FFFF_FFFF_FFFF));
    }

    // ---- 저장 ----

    private async Task PersistAsync(Guid userId, ImportBundle bundle, SeasonImportGraph graph, CancellationToken cancellationToken)
    {
        var now = _clock.UtcNow;
        await _seasons.AddAsync(graph.Season, cancellationToken);
        foreach (var weekend in graph.Weekends)
        {
            await _seasons.AddWeekendAsync(weekend, cancellationToken);
        }

        foreach (var session in graph.Sessions)
        {
            await _sessions.AddAsync(session, cancellationToken);
        }

        foreach (var attachment in graph.Attachments)
        {
            await AttachAsync(userId, bundle.GameMode, graph.Season, attachment, now, cancellationToken);
        }
    }

    /// <summary>기록 세션을 이 시즌으로 옮긴다: 모드 → 가져온 모드, 키 → <c>SessionKeys.For</c>(D-29), 그 키의 내 랩도 같이.</summary>
    private async Task AttachAsync(
        Guid userId, GameMode mode, Season season, SessionAttachment attachment, DateTime now, CancellationToken cancellationToken)
    {
        var session = attachment.Session;
        var oldKey = session.SessionKey;
        var newKey = SessionKeys.For(mode, session.SeasonLinkId, session.WeekendLinkId, session.SessionLinkId, session.SessionRef);

        session.GameMode = mode;
        session.SeasonId = season.Id;
        session.RaceWeekendId = attachment.Weekend.Id;
        session.UpdatedAt = now;

        if (newKey == oldKey)
        {
            return;
        }

        if (await _imports.SessionKeyInUseAsync(userId, session.GameCode, newKey, cancellationToken))
        {
            _logger.LogWarning("세션 키 충돌로 옛 키 유지 session={Session} oldKey={OldKey} newKey={NewKey}", session.Id, oldKey, newKey);
            return;
        }

        foreach (var lap in await _imports.GetLapsBySessionKeyAsync(userId, session.GameCode, oldKey, cancellationToken))
        {
            lap.SessionKey = newKey;
            lap.UpdatedAt = now;
        }

        session.SessionKey = newKey;
    }
}
