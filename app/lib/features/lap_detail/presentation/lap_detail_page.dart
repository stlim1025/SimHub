import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_notice.dart';
import '../../../core/layout/layout_constants.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/track_flag.dart';
import '../../laps/domain/lap_display.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import 'best_laps_tab.dart';
import 'compare_controls.dart';
import 'lap_details_tab.dart';
import 'telemetry_tab.dart';

const String _lapsPath = '/laps';
const String _notFoundMessage = '찾을 수 없는 랩입니다.';
const String _notFoundBackLabel = 'Laps';
const String _backTooltip = '트랙 표로';
const String _shareLabel = 'Share';
const String _sharedText = '주소를 복사했어요';
const String _shareFailedText = '복사하지 못했어요. 주소창에서 직접 복사해 주세요.';

/// 랩을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Lap';

const int _httpNotFound = 404;
const double _titleFlagSize = 28;
const double _titleGap = 10;
const double _titleFontSize = 22;
const double _sectionGap = 16;
const double _reloadBarHeight = 2;
const double _shareIconSize = 18;
const EdgeInsets _tabLabelPadding = EdgeInsets.symmetric(horizontal: 8);

/// 탭 값 → 탭 글자(`kLapTabs`와 같은 순서로 그린다).
const Map<String, String> _tabLabels = {
  kLapTabDetails: 'Lap Details',
  kLapTabTelemetry: 'Telemetry',
  kLapTabBest: 'Your Best Laps',
};

/// 랩 상세(D-46, docs/15 §2.3·§10): 머리줄(← 트랙 표 · 국기 + `{트랙} Lap {랩타임}` · [Share]) + 탭 3개
/// + "Compare with ▾"·"Filter by ▾"(D-51). 탭·비교 선택은 주소 쿼리와 동기화된다(모르는 값은 기본).
/// 남의 것이거나 없는 랩이면 404 상태.
class LapDetailPage extends ConsumerStatefulWidget {
  const LapDetailPage({super.key, required this.lapId, this.tab, this.compare = LapCompareSelection.defaults});

  final String lapId;

  /// 주소의 `tab` 쿼리. null이거나 모르는 값이면 `details`.
  final String? tab;

  /// 주소의 비교 선택(`compare`·`compareLapId`·필터).
  final LapCompareSelection compare;

  @override
  ConsumerState<LapDetailPage> createState() => _LapDetailPageState();
}

class _LapDetailPageState extends ConsumerState<LapDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 비교 선택을 바꿔 다시 불러오는 동안 보일 직전 상세(같은 랩일 때만).
  LapDetail? _lastLoaded;

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

  /// 탭·비교 선택을 바꿀 때마다 브라우저 기록에 항목이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다.
  void _navigate({String? tab, LapCompareSelection? compare}) {
    final location = lapDetailLocation(
      widget.lapId,
      tab: tab ?? (widget.tab == null ? null : _tab),
      compare: compare ?? widget.compare,
    );
    Router.neglect(context, () => context.go(location));
  }

  void _selectTab(int index) {
    final tab = kLapTabs[index];
    if (tab != _tab) {
      _navigate(tab: tab);
    }
  }

  void _selectCompare(LapCompareSelection next) {
    if (next != widget.compare) {
      _navigate(compare: next);
    }
  }

  /// 로그인 없이 볼 수 있는 공유 주소(`/share/laps/{id}`, Telemetry 탭이면 그 탭)를 클립보드에 복사한다.
  /// 다른 랩과 비교 중이면 지금 비교 중인 랩 ID(`compareLapId`)를 함께 실어 같은 비교를 보게 한다.
  Future<void> _share() async {
    final messenger = AppToaster.of(context);
    final location = sharedLapLocation(widget.lapId, tab: _tab, compareLapId: _comparedLapId());
    final url = shareUrlFor(ref.read(shareBaseUriProvider), location);
    try {
      await Clipboard.setData(ClipboardData(text: url));
      messenger.show(_sharedText, tone: NoticeTone.success);
    } on PlatformException {
      messenger.show(_shareFailedText, tone: NoticeTone.error);
    }
  }

  /// 지금 비교 중인 다른 랩의 ID. 비교 안 함·비교 대상 없음·이 랩 자신과의 비교면 null.
  String? _comparedLapId() {
    if (widget.compare.kind == LapCompareKind.none) {
      return null;
    }
    final detail = ref.read(lapDetailProvider(LapDetailKey(widget.lapId, widget.compare))).valueOrNull;
    final comparison = detail?.comparison;
    return comparison == null || comparison.lapId == widget.lapId ? null : comparison.lapId;
  }

  @override
  Widget build(BuildContext context) {
    final key = LapDetailKey(widget.lapId, widget.compare);
    final detail = ref.watch(lapDetailProvider(key));
    final fresh = detail.valueOrNull;
    if (fresh != null) {
      _lastLoaded = fresh;
    }
    final stale = _lastLoaded?.lap.lapId == widget.lapId ? _lastLoaded : null;
    final shown = fresh ?? (detail.isLoading ? stale : null);

    return ListView(
      padding: pagePadding(context, maxWidth: kWideContentMaxWidth),
      children: [
        _Header(
          detail: shown,
          onBack: () => context.go(shown == null ? _lapsPath : trackLapsLocation(shown.trackId)),
          onShare: _share,
        ),
        const SizedBox(height: _sectionGap),
        if (shown != null)
          _DetailBody(
            detail: shown,
            reloading: fresh == null,
            tab: _tab,
            compare: widget.compare,
            tabController: _tabController,
            onTab: _selectTab,
            onCompare: _selectCompare,
          )
        else
          detail.when(
            loading: () => const PageLoadingBar(),
            error: (e, _) => _isNotFound(e)
                ? const NotFoundState(message: _notFoundMessage, backLabel: _notFoundBackLabel, backPath: _lapsPath)
                : ErrorRetry(
                    error: e,
                    fallbackMessage: '랩 상세를 불러오지 못했어요.',
                    onRetry: () => ref.invalidate(lapDetailProvider(key)),
                  ),
            data: (_) => const SizedBox.shrink(),
          ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// 탭 막대 + 비교 선택 + 탭 내용. [reloading]이면 비교를 바꿔 다시 불러오는 중(직전 내용 위에 얇은 진행 막대).
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.reloading,
    required this.tab,
    required this.compare,
    required this.tabController,
    required this.onTab,
    required this.onCompare,
  });

  final LapDetail detail;
  final bool reloading;
  final String tab;
  final LapCompareSelection compare;
  final TabController tabController;
  final ValueChanged<int> onTab;
  final ValueChanged<LapCompareSelection> onCompare;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: tabController,
          onTap: onTab,
          labelPadding: _tabLabelPadding,
          tabs: [for (final tab in kLapTabs) Tab(text: _tabLabels[tab])],
        ),
        const SizedBox(height: _sectionGap),
        CompareControls(selection: compare, onChanged: onCompare),
        SizedBox(
          height: _sectionGap,
          child: reloading
              ? const Center(child: LinearProgressIndicator(minHeight: _reloadBarHeight))
              : null,
        ),
        _TabContent(tab: tab, detail: detail, compare: compare),
      ],
    );
  }
}

/// ← 트랙 표 + 국기 + `Jeddah Lap 1:38.448` + [Share].
class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.onBack, required this.onShare});

  final LapDetail? detail;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final loaded = detail;
    final title = loaded == null ? _fallbackTitle : '${loaded.lap.trackName} Lap ${formatLapTime(loaded.lap.lapTimeMs)}';
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
            // 세션 상세 제목과 같은 한 줄 제목 크기(22px).
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.bold),
          ),
        ),
        if (loaded != null)
          OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share, size: _shareIconSize),
            label: const Text(_shareLabel),
          ),
      ],
    );
  }
}

/// 선택된 탭의 내용. 세 탭이 같은 [detail]을 쓴다.
class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.detail, required this.compare});

  final String tab;
  final LapDetail detail;
  final LapCompareSelection compare;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      kLapTabTelemetry => TelemetryTab(detail: detail, compare: compare),
      kLapTabBest => BestLapsTab(detail: detail),
      _ => LapDetailsTab(detail: detail, compare: compare),
    };
  }
}
