import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/page_padding.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../application/seasons_providers.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';
import 'season_import_dialog.dart';

const String _telemetryAppPath = '/telemetry-app';
const String _telemetryAppLabel = 'Telemetry App';

const String _guideText = '커리어나 그랑프리 모드에서 세션을 결과 화면까지 마치면 시즌이 기록됩니다.';

/// Seasons 메뉴 진입점(F1Laps 시즌 화면처럼 바로 시즌을 연다): 내 시즌을 읽어
/// 가장 최근의 진행 중인 시즌(없으면 가장 최근 시즌) 상세로 바꿔 간다. 시즌이 없으면 안내 + 가져오기 버튼.
/// 이동은 브라우저 기록을 바꿔치기해(neglect) 뒤로 가기가 다시 이 화면으로 돌아와 되튕기지 않는다.
class SeasonsPage extends ConsumerStatefulWidget {
  const SeasonsPage({super.key});

  @override
  ConsumerState<SeasonsPage> createState() => _SeasonsPageState();
}

class _SeasonsPageState extends ConsumerState<SeasonsPage> {
  /// 이동을 한 번만 예약한다(다시 그려져도 중복 이동하지 않게).
  bool _redirecting = false;

  void _redirectTo(SeasonSummary season) {
    if (_redirecting) return;
    _redirecting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Router.neglect(context, () => context.go(seasonLocation(season.seasonId)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(allSeasonsProvider);
    const loading = PageLoadingBar();

    return ListView(
      padding: pagePadding(context),
      children: [
        seasons.when(
          loading: () => loading,
          error: (e, _) => ErrorRetry(
            error: e,
            fallbackMessage: '시즌 목록을 불러오지 못했어요.',
            onRetry: () => ref.invalidate(allSeasonsProvider),
          ),
          data: (data) {
            final target = landingSeason(data);
            if (target == null) {
              return const _NoSeasons();
            }
            _redirectTo(target);
            return loading;
          },
        ),
      ],
    );
  }
}

/// 시즌이 하나도 없을 때: 제목 + 가져오기 버튼 + 기록 안내.
class _NoSeasons extends ConsumerWidget {
  const _NoSeasons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              onPressed: () => openSeasonImport(context, ref),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text(kSeasonImportTitle),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const EmptyStateCard(
          message: _guideText,
          actionLabel: _telemetryAppLabel,
          actionPath: _telemetryAppPath,
        ),
      ],
    );
  }
}
