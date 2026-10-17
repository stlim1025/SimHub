import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../auth/application/auth_controller.dart';
import '../../devices/presentation/connection_status_card.dart';
import '../../laps/domain/lap_models.dart';
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
      padding: kPagePadding,
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
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
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
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '아직 기록된 랩이 없어요. 게임을 플레이하면 여기에 최근 랩이 표시돼요.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _RecentLaps extends StatelessWidget {
  const _RecentLaps({required this.laps});

  final List<Lap> laps;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < laps.length; i++) ...[
            if (i > 0) const Divider(),
            _RecentLapRow(lap: laps[i]),
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
    return Padding(
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
                  '${lap.sessionType} · ${_dateFormat.format(lap.setAt.toLocal())}',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (!lap.isValid) ...[
            Text('무효', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
            const SizedBox(width: 12),
          ],
          Text(
            formatLapTime(lap.lapTimeMs),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
