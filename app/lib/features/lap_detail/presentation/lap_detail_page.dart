import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/layout_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/track_flag.dart';
import '../../laps/domain/lap_display.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'best_laps_tab.dart';
import 'lap_details_tab.dart';
import 'lap_time_cards.dart';

const String _lapsPath = '/laps';
const String _notFoundMessage = '찾을 수 없는 랩입니다.';
const String _notFoundBackLabel = 'Laps';
const String _backTooltip = '트랙 표로';

/// 랩을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Lap';

const int _httpNotFound = 404;
const double _titleFlagSize = 28;
const double _titleGap = 10;
const double _sectionGap = 16;
const double _compareGap = 8;
const double _compareRadius = 6;
const EdgeInsets _comparePadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const EdgeInsets _tabLabelPadding = EdgeInsets.symmetric(horizontal: 8);

/// 탭 값 → 탭 글자(`kLapTabs`와 같은 순서로 그린다).
const Map<String, String> _tabLabels = {
  kLapTabDetails: 'Lap Details',
  kLapTabTelemetry: 'Telemetry',
  kLapTabBest: 'Your Best Laps',
};

/// 랩 상세(D-46, docs/15 §2.3): 머리줄(← 트랙 표 · 국기 + 트랙 이름 · 랩타임) + 탭 3개(Lap Details · Telemetry · Your Best Laps)
/// + "Compare with: 내 최고 유효 랩". 탭은 주소의 `?tab=`과 동기화된다(모르는 값은 details). 남의 것이거나 없는 랩이면 404 상태.
class LapDetailPage extends ConsumerStatefulWidget {
  const LapDetailPage({super.key, required this.lapId, this.tab});

  final String lapId;

  /// 주소의 `tab` 쿼리. null이거나 모르는 값이면 `details`.
  final String? tab;

  @override
  ConsumerState<LapDetailPage> createState() => _LapDetailPageState();
}

class _LapDetailPageState extends ConsumerState<LapDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String get _tab => normalizeLapTab(widget.tab);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kLapTabs.length, vsync: this, initialIndex: kLapTabs.indexOf(_tab));
  }

  @override
  void didUpdateWidget(LapDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 주소가 바뀌면(뒤로 가기·다른 화면에서의 이동 포함) 탭 막대의 선택도 따라간다.
    final index = kLapTabs.indexOf(_tab);
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
    final tab = kLapTabs[index];
    if (tab == _tab) {
      return;
    }
    Router.neglect(context, () => context.go(lapDetailLocation(widget.lapId, tab: tab)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(lapDetailProvider(widget.lapId));
    final loaded = detail.valueOrNull;

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(
          detail: loaded,
          onBack: () => context.go(loaded == null ? _lapsPath : trackLapsLocation(loaded.trackId)),
        ),
        const SizedBox(height: _sectionGap),
        detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _isNotFound(e)
              ? const NotFoundState(message: _notFoundMessage, backLabel: _notFoundBackLabel, backPath: _lapsPath)
              : ErrorRetry(
                  error: e,
                  fallbackMessage: '랩 상세를 불러오지 못했어요.',
                  onRetry: () => ref.invalidate(lapDetailProvider(widget.lapId)),
                ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                controller: _tabController,
                onTap: _selectTab,
                labelPadding: _tabLabelPadding,
                tabs: [for (final tab in kLapTabs) Tab(text: _tabLabels[tab])],
              ),
              const SizedBox(height: _sectionGap),
              _CompareWith(detail: data),
              const SizedBox(height: _sectionGap),
              _TabContent(tab: _tab, detail: data),
            ],
          ),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// ← 트랙 표 + 국기 + `Jeddah · 1:38.448`.
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.onBack});

  final LapDetail? detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final loaded = detail;
    final title = loaded == null ? _fallbackTitle : '${loaded.lap.trackName} · ${formatLapTime(loaded.lap.lapTimeMs)}';
    return Row(
      children: [
        IconButton(tooltip: _backTooltip, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        const SizedBox(width: 4),
        if (loaded != null) ...[
          TrackFlag(countryCode: loaded.countryCode, size: _titleFlagSize),
          const SizedBox(width: _titleGap),
        ],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

/// "Compare with" + 비교 대상(표시만 — 선택지는 내 최고 유효 랩 하나, D-46).
class _CompareWith extends StatelessWidget {
  const _CompareWith({required this.detail});

  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final comparison = detail.comparison;
    final text = switch (comparison) {
      null => kNoComparisonText,
      _ when detail.isPersonalBest => '내 최고 유효 랩 · 이 랩',
      final ComparisonLap best => '내 최고 유효 랩 · ${formatLapTime(best.lapTimeMs)}',
    };
    return Wrap(
      spacing: _compareGap,
      runSpacing: _compareGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Compare with', style: TextStyle(color: palette.textMuted)),
        Container(
          padding: _comparePadding,
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(_compareRadius),
          ),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// 선택된 탭의 내용. 세 탭이 같은 [detail]을 쓴다.
class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.detail});

  final String tab;
  final LapDetail detail;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      kLapTabTelemetry => const SizedBox.shrink(),
      kLapTabBest => BestLapsTab(detail: detail),
      _ => LapDetailsTab(detail: detail),
    };
  }
}
