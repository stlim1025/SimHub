import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/fresh_highlight.dart';
import '../../auth/application/auth_controller.dart';
import '../../devices/presentation/connection_status_card.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../laps/application/fresh_laps.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import '../../laps/presentation/lap_cells.dart';
import '../application/dashboard_providers.dart';

/// 로그인 직후 홈. 환영 문구 + 내 최근 랩(docs/11 §7.3).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authControllerProvider).valueOrNull?.displayName ?? '';
    final recent = ref.watch(recentLapsProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: pagePadding(context),
      children: [
        Text(
          'Welcome $displayName!',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        const ConnectionStatusCard(),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('최근 랩', style: theme.textTheme.titleMedium)),
            TextButton(
              onPressed: () => context.go('/laps'),
              child: const Text('View all lap times'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        recent.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '최근 랩을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(recentLapsProvider),
          ),
          data: (data) => data.laps.isEmpty ? const _EmptyLaps() : _RecentLaps(laps: data.laps),
        ),
      ],
    );
  }
}

class _EmptyLaps extends StatelessWidget {
  const _EmptyLaps();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '아직 기록된 랩이 없어요. 게임을 플레이하면 여기에 최근 랩이 표시돼요.',
          style: TextStyle(color: context.palette.textMuted),
        ),
      ),
    );
  }
}

/// 최근 랩 목록. 실시간으로 막 들어온 랩 행은 잠깐 강조된다(D-50, docs/15 §9).
class _RecentLaps extends ConsumerWidget {
  const _RecentLaps({required this.laps});

  final List<Lap> laps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshIds = ref.watch(freshLapIdsProvider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < laps.length; i++) ...[
            if (i > 0) const Divider(),
            KeyedSubtree(
              key: ValueKey('recent-lap-${laps[i].lapId}'),
              child: freshIds.contains(laps[i].lapId)
                  ? FreshHighlight(child: _RecentLapRow(lap: laps[i]))
                  : _RecentLapRow(lap: laps[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentLapRow extends StatelessWidget {
  const _RecentLapRow({required this.lap});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final Lap lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = lapModeLabel(gameMode: lap.gameMode, sessionType: lap.sessionType);
    // 행을 누르면 그 랩의 상세(D-46).
    return InkWell(
      onTap: () => context.go(lapDetailLocation(lap.lapId)),
      hoverColor: AppColors.rowHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lap.trackName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '$mode · ${_dateFormat.format(lap.setAt.toLocal())}',
                    style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
                  ),
                ],
              ),
            ),
            if (!lap.isValid) ...[
              Text('무효', style: theme.textTheme.bodySmall?.copyWith(color: context.palette.danger)),
              const SizedBox(width: 12),
            ],
            Text(formatLapTime(lap.lapTimeMs), style: lapTimeLinkStyle(context)),
          ],
        ),
      ),
    );
  }
}
