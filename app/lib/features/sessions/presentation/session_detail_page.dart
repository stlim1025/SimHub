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
const String _notFoundMessage = '찾을 수 없는 세션입니다.';
const String _notFoundBackLabel = 'Sessions';

/// 세션 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Session';

const int _httpNotFound = 404;
const double _statSpacing = 32;

/// 세션 결과 화면(docs/12 §8.3): 헤더 + 결과 표. 남의 것이거나 없는 세션이면 404 상태를 보여 준다.
class SessionDetailPage extends ConsumerWidget {
  const SessionDetailPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(
          title: detail.valueOrNull?.header.trackName ?? _fallbackTitle,
          onBack: () => _goBack(context),
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

  /// 화면 안의 뒤로 가기. 시즌 화면의 세션 칩처럼 위에 쌓여 열렸으면 연 화면으로 돌아가고,
  /// 직접 열렸거나(딥링크·새로고침) 쌓인 화면이 없으면 세션 목록으로 간다.
  static void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_sessionsPath);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '세션 목록',
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
