import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/stat.dart';
import '../application/seasons_providers.dart';
import '../domain/season_display.dart';
import '../domain/season_models.dart';
import 'season_results_tab.dart';
import 'season_rounds_tab.dart';
import 'season_standings_tab.dart';

const String _seasonsPath = '/seasons';
const String _notFoundMessage = '찾을 수 없는 시즌입니다.';
const String _notFoundBackLabel = 'Seasons';

/// 시즌 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Season';

const int _httpNotFound = 404;
const double _statSpacing = 32;

/// 탭 값 → 탭 글자(`kSeasonTabs`와 같은 순서로 그린다).
const Map<String, String> _tabLabels = {
  kSeasonTabSeason: 'Season',
  kSeasonTabResults: 'Results',
  kSeasonTabStandings: 'Standings',
};

/// 시즌 상세(docs/12 §8.3): 헤더 + 탭 3개(Season · Results · Standings).
/// 탭은 주소의 `?tab=`과 동기화된다(모르는 값은 season). 남의 것이거나 없는 시즌이면 404 상태를 보여 준다.
class SeasonDetailPage extends ConsumerStatefulWidget {
  const SeasonDetailPage({super.key, required this.seasonId, this.tab});

  final String seasonId;

  /// 주소의 `tab` 쿼리. null이거나 모르는 값이면 `season`.
  final String? tab;

  @override
  ConsumerState<SeasonDetailPage> createState() => _SeasonDetailPageState();
}

class _SeasonDetailPageState extends ConsumerState<SeasonDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String get _tab => normalizeSeasonTab(widget.tab);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: kSeasonTabs.length,
      vsync: this,
      initialIndex: kSeasonTabs.indexOf(_tab),
    );
  }

  @override
  void didUpdateWidget(SeasonDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 주소가 바뀌면(뒤로 가기·다른 화면에서의 이동 포함) 탭 막대의 선택도 따라간다.
    final index = kSeasonTabs.indexOf(_tab);
    if (_tabController.index != index) {
      _tabController.index = index;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 탭을 누를 때마다 브라우저 기록에 항목이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다.
  void _selectTab(int index) {
    final tab = kSeasonTabs[index];
    if (tab == _tab) {
      return;
    }
    Router.neglect(context, () => context.go(seasonLocation(widget.seasonId, tab: tab)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(seasonDetailProvider(widget.seasonId));
    final season = detail.valueOrNull?.season;

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(
          title: season == null ? _fallbackTitle : seasonTitle(season),
          onBack: () => context.go(_seasonsPath),
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
                  backPath: _seasonsPath,
                )
              : ErrorRetry(
                  error: e,
                  fallbackMessage: '시즌을 불러오지 못했어요.',
                  onRetry: () => ref.invalidate(seasonDetailProvider(widget.seasonId)),
                ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderStats(season: data.season),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                onTap: _selectTab,
                tabs: [for (final tab in kSeasonTabs) Tab(text: _tabLabels[tab])],
              ),
              const SizedBox(height: 16),
              _TabContent(tab: _tab, detail: data),
            ],
          ),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
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
          tooltip: '시즌 목록',
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

/// 모드 · 기간 · 라운드 수 · 내 순위와 점수.
class _HeaderStats extends StatelessWidget {
  const _HeaderStats({required this.season});

  final SeasonSummary season;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: _statSpacing,
      runSpacing: 8,
      children: [
        Stat(label: '모드', value: seasonModeLabel(season)),
        Stat(label: '기간', value: seasonPeriodLabel(season)),
        if (season.importedFrom case final source?) Stat(label: '가져옴', value: source),
        Stat(label: '라운드', value: roundsLabel(season.roundCount)),
        Stat(label: '내 순위', value: myStandingLabel(season.myPosition, season.myPoints)),
      ],
    );
  }
}

/// 선택된 탭의 내용. 세 탭이 같은 [detail] 스냅샷을 쓴다.
class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.detail});

  final String tab;
  final SeasonDetail detail;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      kSeasonTabResults => SeasonResultsTab(rounds: detail.rounds, drivers: detail.standings.drivers),
      kSeasonTabStandings => SeasonStandingsTab(standings: detail.standings),
      _ => SeasonRoundsTab(rounds: detail.rounds),
    };
  }
}
