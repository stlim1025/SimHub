import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/pagination_bar.dart';
import '../../../core/widgets/stat.dart';
import '../../sessions/domain/session_display.dart';
import '../application/seasons_providers.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';
import 'season_import_dialog.dart';

const String _seasonsPath = '/seasons';
const String _telemetryAppPath = '/telemetry-app';
const String _telemetryAppLabel = 'Telemetry App';

const String _guideText = '커리어나 그랑프리 모드에서 세션을 결과 화면까지 마치면 시즌이 기록됩니다.';

const double _cardGap = 12;
const double _statSpacing = 32;

/// 내 시즌 목록(docs/12 §8.3): 카드 20개씩 + 페이지 바. 페이지 번호는 화면 상태다.
class SeasonsPage extends ConsumerStatefulWidget {
  const SeasonsPage({super.key});

  @override
  ConsumerState<SeasonsPage> createState() => _SeasonsPageState();
}

class _SeasonsPageState extends ConsumerState<SeasonsPage> {
  int _page = 1;

  void _changePage(int page) => setState(() => _page = page);

  /// 시즌 가져오기(docs/15 §12, D-55). 가져오면 목록을 새로 읽고 만든 시즌으로 간다.
  Future<void> _openImport() async {
    final seasonId = await showDialog<String>(context: context, builder: (_) => const SeasonImportDialog());
    if (seasonId == null || !mounted) return;
    ref.invalidate(seasonsProvider);
    context.go('$_seasonsPath/$seasonId');
  }

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(seasonsProvider(_page));

    return ListView(
      padding: pagePadding(context),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Seasons',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            OutlinedButton.icon(
              onPressed: _openImport,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text(kSeasonImportTitle),
            ),
          ],
        ),
        const SizedBox(height: 24),
        seasons.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '시즌 목록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(seasonsProvider(_page)),
          ),
          data: (data) => data.total == 0
              ? const EmptyStateCard(
                  message: _guideText,
                  actionLabel: _telemetryAppLabel,
                  actionPath: _telemetryAppPath,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final season in data.items) ...[
                      _SeasonCard(season: season),
                      const SizedBox(height: _cardGap),
                    ],
                    PaginationBar(
                      page: data.page,
                      pageSize: data.pageSize,
                      total: data.total,
                      onPageChanged: _changePage,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 시즌 한 장: 모드 배지 + 제목 + 기간 + 라운드 수 · 내 순위 · 선두. 누르면 시즌 상세.
class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.season});

  final SeasonSummary season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => context.go('$_seasonsPath/${season.seasonId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ModeBadge(label: gameModeLabel(season.gameMode)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      seasonTitle(season),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.palette.textMuted),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                seasonPeriodLabel(season),
                style: theme.textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: _statSpacing,
                runSpacing: 8,
                children: [
                  Stat(label: '라운드', value: roundsLabel(season.roundCount)),
                  Stat(label: '내 순위', value: myStandingLabel(season.myPosition, season.myPoints)),
                  Stat(label: '선두', value: leaderLabel(season.leaderName, season.leaderPoints)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 게임 모드 배지(`Driver Career` …).
class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.accent),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
      ),
    );
  }
}
