import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/stat.dart';
import '../../seasons/domain/season_display.dart';
import '../application/sessions_providers.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'session_results_table.dart';

const String _sessionsPath = '/sessions';
const String _backToSessionsTooltip = '세션 목록';
const String _backToSeasonTooltip = '시즌으로';
const String _notFoundMessage = '찾을 수 없는 세션입니다.';
const String _notFoundBackLabel = 'Sessions';

/// 세션 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Session';

const int _httpNotFound = 404;
const double _statSpacing = 32;

/// 세션 결과 화면(docs/12 §8.3): 헤더 + 결과 표. 남의 것이거나 없는 세션이면 404 상태를 보여 준다.
///
/// [from]은 주소의 `?from=` 값이다. `season`(시즌 화면의 세션 칩)이고 불러온 세션이 시즌에 속하면
/// 뒤로 가기가 그 시즌으로 돌아가고, 그 밖(없음·모르는 값·시즌 없는 세션·아직 로딩)은 세션 목록으로 간다.
class SessionDetailPage extends ConsumerWidget {
  const SessionDetailPage({super.key, required this.sessionId, this.from});

  final String sessionId;
  final String? from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final backSeasonId = from == kSessionFromSeason ? detail.valueOrNull?.header.seasonId : null;

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(
          title: detail.valueOrNull?.header.trackName ?? _fallbackTitle,
          backTooltip: backSeasonId == null ? _backToSessionsTooltip : _backToSeasonTooltip,
          onBack: () => context.go(backSeasonId == null ? _sessionsPath : seasonLocation(backSeasonId)),
        ),
        const SizedBox(height: 16),
        detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _isNotFound(e)
              ? const NotFoundState(
                  message: _notFoundMessage,
                  backLabel: _notFoundBackLabel,
                  backPath: _sessionsPath,
                )
              : ErrorRetry(
                  error: e,
                  fallbackMessage: '세션 결과를 불러오지 못했어요.',
                  onRetry: () => ref.invalidate(sessionDetailProvider(sessionId)),
                ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderStats(header: data.header),
              const SizedBox(height: 16),
              SessionResultsTable(results: data.results, isRace: data.header.sessionType == 'Race'),
            ],
          ),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.backTooltip, required this.onBack});

  final String title;
  final String backTooltip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: backTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// 세션 라벨 · 모드 · 날짜 · AI 난이도 · (시즌이면) 라운드. 라운드(`R7`)는 그 시즌의 Season 탭으로 가는 링크다.
class _HeaderStats extends StatelessWidget {
  const _HeaderStats({required this.header});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final SessionDetailHeader header;

  @override
  Widget build(BuildContext context) {
    final seasonId = header.seasonId;
    final round = header.round;
    return Wrap(
      spacing: _statSpacing,
      runSpacing: 8,
      children: [
        Stat(label: '세션', value: sessionKindLabel(header.sessionKind)),
        Stat(label: '모드', value: gameModeLabel(header.gameMode)),
        Stat(label: '날짜', value: _dateFormat.format(header.classifiedAt.toLocal())),
        if (header.aiDifficulty > 0) Stat(label: 'AI 난이도', value: '${header.aiDifficulty}'),
        if (seasonId != null && round != null)
          Stat(
            label: '시즌',
            value: 'R$round',
            onTap: () => context.go(seasonLocation(seasonId)),
          ),
      ],
    );
  }
}
