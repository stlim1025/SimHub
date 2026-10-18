import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../sessions/domain/session_display.dart';
import '../data/seasons_repository.dart';
import '../domain/season_import_models.dart';

const String kSeasonImportTitle = 'F1Laps에서 가져오기';
const String kSeasonImportPreviewLabel = '미리보기';
const String kSeasonImportSubmitLabel = '가져오기';
const String kSeasonImportAlreadyText = '이미 가져온 시즌이에요. 같은 시즌은 다시 가져올 수 없어요.';

const String _hintText = 'F1Laps 시즌·세션 내보내기와 인게임 순위표 마크다운을 그대로 붙여 넣으세요.\n'
    '여러 문서를 이어 붙여도 돼요(# 제목으로 구분).';
const String _cancelLabel = '취소';
const String _fallbackError = '가져오기를 처리하지 못했어요.';
const String _recordedMark = '기록';
const int _driverPreviewCount = 10;
const int _constructorPreviewCount = 5;
const int _editorLines = 8;
const double _dialogMaxWidth = 760;
const double _gap = 12;

const Map<String, String> _documentKinds = {
  'InGameStandings': '인게임 순위표',
  'F1LapsSeason': 'F1Laps 시즌 요약',
  'F1LapsSession': 'F1Laps 세션',
};

/// 시즌 가져오기 대화상자(docs/15 §12, D-55): 붙여넣기 → [미리보기] → [가져오기]. 가져오면 만든 시즌 Id로 닫힌다.
/// 오류(형식·409)는 대화상자 안에 보여 주고 닫지 않는다.
class SeasonImportDialog extends ConsumerStatefulWidget {
  const SeasonImportDialog({super.key});

  @override
  ConsumerState<SeasonImportDialog> createState() => _SeasonImportDialogState();
}

class _SeasonImportDialogState extends ConsumerState<SeasonImportDialog> {
  final _controller = TextEditingController();
  SeasonImportPreview? _preview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 내용이 바뀌면 이전 미리보기는 맞지 않으니 지운다(버튼 상태도 다시 그린다).
  void _onChanged(String _) => setState(() {
        _preview = null;
        _error = null;
      });

  Future<void> _run(Future<void> Function(SeasonsRepository repo) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(seasonsRepositoryProvider));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = _fallbackError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewImport() => _run((repo) async {
        final preview = await repo.previewImport(_controller.text);
        if (mounted) setState(() => _preview = preview);
      });

  Future<void> _import() => _run((repo) async {
        final seasonId = await repo.importSeason(_controller.text);
        if (mounted) Navigator.of(context).pop(seasonId);
      });

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final hasText = _controller.text.trim().isNotEmpty;
    final canImport = !_busy && preview != null && !preview.alreadyImported;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(kSeasonImportTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: _gap),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('season-import-markdown'),
                        controller: _controller,
                        onChanged: _onChanged,
                        minLines: _editorLines,
                        maxLines: _editorLines,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: const InputDecoration(hintText: _hintText, border: OutlineInputBorder()),
                      ),
                      if (_error case final error?) ...[
                        const SizedBox(height: _gap),
                        Text(error, key: const Key('season-import-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      if (preview != null) ...[
                        const SizedBox(height: _gap),
                        _PreviewView(preview: preview),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: _gap),
              // 휴대폰 폭에서 넘치지 않게 줄바꿈되는 버튼 줄.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_busy) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text(_cancelLabel)),
                  OutlinedButton(
                    onPressed: !_busy && hasText ? _previewImport : null,
                    child: const Text(kSeasonImportPreviewLabel),
                  ),
                  FilledButton(onPressed: canImport ? _import : null, child: const Text(kSeasonImportSubmitLabel)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 미리보기 본문: 찾은 문서 · 시즌 · 연결할 게임 시즌 · 라운드 · 스탠딩.
class _PreviewView extends StatelessWidget {
  const _PreviewView({required this.preview});

  final SeasonImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    final heading = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final link = preview.linkCandidate;

    return Column(
      key: const Key('season-import-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(seasonImportHeader(preview), style: heading),
        const SizedBox(height: 4),
        for (final document in preview.documents) Text(documentLine(document), style: muted),
        const SizedBox(height: 8),
        Text(link == null ? '연결할 게임 시즌 없음 — 새 시즌으로 만들어요.' : linkLine(link)),
        if (preview.alreadyImported)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(kSeasonImportAlreadyText, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: _gap),
        Text('라운드 ${preview.rounds.length}개', style: heading),
        const SizedBox(height: 4),
        for (final round in preview.rounds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(roundLine(round)),
          ),
        const SizedBox(height: _gap),
        Text('드라이버 스탠딩', style: heading),
        const SizedBox(height: 4),
        for (final driver in preview.drivers.take(_driverPreviewCount))
          Text(
            '${driver.position}. ${driver.name} · ${driver.teamName} · ${driver.points}점',
            style: driver.isPlayer ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        if (preview.constructors.isNotEmpty) ...[
          const SizedBox(height: _gap),
          Text('컨스트럭터', style: heading),
          const SizedBox(height: 4),
          for (final team in preview.constructors.take(_constructorPreviewCount))
            Text('${team.position}. ${team.teamName} · ${team.points}점'),
        ],
      ],
    );
  }
}

/// `Season 1 · Driver Career · Ferrari · GOMDOL SUPER`.
String seasonImportHeader(SeasonImportPreview preview) => [
      preview.title,
      gameModeLabel(preview.gameMode),
      ?preview.teamName,
      preview.playerName,
    ].join(' · ');

/// `인게임 순위표 · Season 1 — 라운드 5 · 세션 5 · 드라이버 22`.
String documentLine(SeasonImportDocument document) =>
    '${_documentKinds[document.kind] ?? document.kind} · ${document.title} — '
    '라운드 ${document.rounds} · 세션 ${document.sessions} · 드라이버 ${document.drivers}';

/// `연결할 게임 시즌: 2160041047, 옮길 세션 3개 (Miami Q1·Q2·Q3)`.
String linkLine(SeasonLinkCandidate link) {
  final tracks = link.sessions.map((s) => s.trackName).toSet().join(', ');
  final kinds = link.sessions.map((s) => sessionKindLabel(s.kind)).join('·');
  return '연결할 게임 시즌: ${link.seasonLinkId}, 옮길 세션 ${link.sessions.length}개'
      '${link.sessions.isEmpty ? '' : ' ($tracks $kinds)'}';
}

/// `R1 Melbourne — R(22대, 6랩) · 내 점수 25`. 옮길 기록 세션은 `Q1(기록)`.
String roundLine(SeasonImportRound round) {
  // 스프린트 주말(Race2가 있음)이면 Race = 스프린트(S), Race2 = 레이스(R).
  final sprintWeekend = round.sessions.any((s) => s.sessionKind == 'Race2');
  final sessions = round.sessions.map((s) {
    final details = [
      if (s.isRecorded) _recordedMark,
      if (s.carCount > 1) '${s.carCount}대',
      if (s.lapCount > 0) '${s.lapCount}랩',
    ];
    final label = sessionKindLabel(s.sessionKind, sprintWeekend: sprintWeekend);
    return details.isEmpty ? label : '$label(${details.join(', ')})';
  }).join(' · ');
  final points = round.myPoints == null ? '' : ' · 내 점수 ${round.myPoints}';
  return 'R${round.round} ${round.trackName} — $sessions$points';
}
