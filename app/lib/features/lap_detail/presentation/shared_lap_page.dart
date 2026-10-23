import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/layout/layout_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/auth_redirect.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/track_flag.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/user_preferences.dart';
import '../../laps/presentation/empty_laps_card.dart';
import '../../tracks/application/track_widths_provider.dart';
import '../../tracks/application/tracks_providers.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../application/lap_detail_providers.dart';
import '../domain/lap_compare.dart';
import '../domain/lap_detail_display.dart';
import '../domain/lap_detail_models.dart';
import '../domain/shared_lap.dart';
import 'lap_details_tab.dart';
import 'telemetry_tab.dart';

const String _dashboardPath = '/';
const String _loginLabel = '로그인';
const String _myRecordsLabel = '내 기록으로';
const String _notFoundMessage = '찾을 수 없는 랩입니다.';
const String _fallbackTitle = 'Lap';
const String _noTraceText = '이 랩은 텔레메트리가 저장되지 않았어요';

/// 주소에 비교 랩이 없거나 서버가 받아들이지 않았을 때 — Comparison 카드·비교 선을 숨긴다.
const LapCompareSelection _noCompare = LapCompareSelection(kind: LapCompareKind.none);

const int _httpNotFound = 404;
const double _topBarHeight = 56;
const double _topBarPaddingX = 16;
const double _brandGap = 10;
const double _titleFlagSize = 28;
const double _titleGap = 10;
const double _titleFontSize = 22;
const double _driverIconSize = 16;
const double _driverGap = 6;
const double _sectionGap = 16;
const EdgeInsets _tabLabelPadding = EdgeInsets.symmetric(horizontal: 8);

/// 탭 값 → 탭 글자(`kSharedLapTabs`와 같은 순서로 그린다).
const Map<String, String> _tabLabels = {
  kLapTabDetails: 'Lap Details',
  kLapTabTelemetry: 'Telemetry',
};

/// 공유 링크로 여는 랩(`/share/laps/:lapId`, 로그인 없음). 셸 밖 화면이다: 머리줄(SimHub 로고 · [로그인] 또는 [내 기록으로])
/// + 국기 · `{트랙} Lap {랩타임}` · 드라이버 이름 + 탭 2개(Lap Details · Telemetry). 비교 선택·내 최고 랩·세션 이동처럼
/// 로그인이 필요한 것은 없다. 탭은 `?tab=details|telemetry`(모르는 값은 details). 주소에 `?compareLapId=`가 있으면
/// 공유한 사람이 보던 비교(Comparison 카드·Delta·비교 선·고스트 차)를 그대로 보인다. 없는 랩이면 404 상태.
class SharedLapPage extends ConsumerStatefulWidget {
  const SharedLapPage({super.key, required this.lapId, this.tab, this.compareLapId});

  final String lapId;

  /// 주소의 `tab` 쿼리. null이거나 모르는 값이면 `details`.
  final String? tab;

  /// 주소의 `compareLapId` 쿼리(비교 중이던 랩). null이면 비교 없음.
  final String? compareLapId;

  @override
  ConsumerState<SharedLapPage> createState() => _SharedLapPageState();
}

class _SharedLapPageState extends ConsumerState<SharedLapPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String get _tab => normalizeSharedLapTab(widget.tab);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: kSharedLapTabs.length,
      vsync: this,
      initialIndex: kSharedLapTabs.indexOf(_tab),
    );
  }

  @override
  void didUpdateWidget(SharedLapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = kSharedLapTabs.indexOf(_tab);
    if (_tabController.index != index) {
      _tabController.index = index;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 탭을 바꿀 때 브라우저 기록이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다.
  void _selectTab(int index) {
    final tab = kSharedLapTabs[index];
    if (tab != _tab) {
      Router.neglect(
        context,
        () => context.go(sharedLapLocation(widget.lapId, tab: tab, compareLapId: widget.compareLapId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = SharedLapKey(widget.lapId, widget.compareLapId);
    final shared = ref.watch(sharedLapProvider(key));
    final loaded = shared.valueOrNull;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TopBar(),
          const Divider(height: 1),
          Expanded(
            child: PageLoadingHost(
              child: ListView(
                padding: kPagePadding,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                      child: loaded != null
                          ? _SharedBody(
                              shared: loaded,
                              tab: _tab,
                              tabController: _tabController,
                              onTab: _selectTab,
                            )
                          : shared.when(
                              loading: () => const PageLoadingBar(),
                              error: (e, _) => _isNotFound(e)
                                  ? const NotFoundState(
                                      message: _notFoundMessage,
                                      backLabel: AppConfig.brandName,
                                      backPath: _dashboardPath,
                                    )
                                  : ErrorRetry(
                                      error: e,
                                      fallbackMessage: '랩을 불러오지 못했어요.',
                                      onRetry: () => ref.invalidate(sharedLapProvider(key)),
                                    ),
                              data: (_) => const SizedBox.shrink(),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// SimHub 로고 + 이름 · 오른쪽에 [로그인](로그아웃 상태) 또는 [내 기록으로](로그인 상태).
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(authControllerProvider).valueOrNull != null;
    return SizedBox(
      height: _topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _topBarPaddingX),
        child: Row(
          children: [
            const BrandMark(),
            const SizedBox(width: _brandGap),
            Flexible(
              child: Text(
                AppConfig.brandName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            loggedIn
                ? FilledButton(onPressed: () => context.go(_dashboardPath), child: const Text(_myRecordsLabel))
                : FilledButton(onPressed: () => context.go(kLoginPath), child: const Text(_loginLabel)),
          ],
        ),
      ),
    );
  }
}

/// 머리줄 + 탭 막대 + 탭 내용.
class _SharedBody extends StatelessWidget {
  const _SharedBody({required this.shared, required this.tab, required this.tabController, required this.onTab});

  final SharedLap shared;
  final String tab;
  final TabController tabController;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(shared: shared),
        const SizedBox(height: _sectionGap),
        TabBar(
          controller: tabController,
          onTap: onTab,
          labelPadding: _tabLabelPadding,
          tabs: [for (final tab in kSharedLapTabs) Tab(text: _tabLabels[tab])],
        ),
        const SizedBox(height: _sectionGap),
        tab == kLapTabTelemetry
            ? _SharedTelemetry(shared: shared)
            : LapDetailsTab(detail: shared.detail, compare: _compareOf(shared.detail)),
      ],
    );
  }
}

/// 서버가 비교 랩을 실어 보냈으면 그 랩 하나와의 비교, 아니면 비교 없음.
LapCompareSelection _compareOf(LapDetail detail) {
  final comparison = detail.comparison;
  return comparison == null || comparison.lapId == detail.lap.lapId
      ? _noCompare
      : LapCompareSelection(kind: LapCompareKind.lap, compareLapId: comparison.lapId);
}

/// 국기 + `Jeddah Lap 1:38.448` + 드라이버 이름.
class _Header extends StatelessWidget {
  const _Header({required this.shared});

  final SharedLap shared;

  @override
  Widget build(BuildContext context) {
    final detail = shared.detail;
    final title = detail.lap.trackName.isEmpty
        ? _fallbackTitle
        : '${detail.lap.trackName} Lap ${formatLapTime(detail.lap.lapTimeMs)}';
    final muted = context.palette.textMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TrackFlag(countryCode: detail.countryCode, size: _titleFlagSize),
            const SizedBox(width: _titleGap),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        if (shared.displayName.isNotEmpty) ...[
          const SizedBox(height: _driverGap),
          Row(
            children: [
              Icon(Icons.person_outline, size: _driverIconSize, color: muted),
              const SizedBox(width: _driverGap),
              Flexible(child: Text(shared.displayName, style: TextStyle(color: muted, fontWeight: FontWeight.w600))),
            ],
          ),
        ],
      ],
    );
  }
}

/// 공유 랩의 Telemetry. 비교 랩이 있고 트레이스가 있으면 공개 트레이스로 비교 선·Delta·고스트 차를 그린다.
/// 속도 단위는 로그인했으면 사용자 설정, 아니면 미터법.
class _SharedTelemetry extends ConsumerWidget {
  const _SharedTelemetry({required this.shared});

  final SharedLap shared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lap = shared.detail.lap;
    if (!lap.hasTrace) {
      return const EmptyLapsCard(message: _noTraceText);
    }
    final comparison = _compareOf(shared.detail).kind == LapCompareKind.none ? null : shared.detail.comparison;
    final comparisonId = comparison != null && comparison.hasTrace ? comparison.lapId : null;
    final trace = ref.watch(sharedLapTraceProvider(lap.lapId));
    final reference = comparisonId == null ? null : ref.watch(sharedLapTraceProvider(comparisonId));
    final units = ref.watch(authControllerProvider).valueOrNull?.preferences.units ?? UnitSystem.metric;
    // 비교 랩 트레이스가 아직 오는 중이면 기다린다. 실패하면 이 랩만 그린다.
    if (trace.isLoading || (reference?.isLoading ?? false)) {
      return const PageLoadingBar();
    }
    return trace.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: '텔레메트리를 불러오지 못했어요.',
        onRetry: () => ref.invalidate(sharedLapTraceProvider(lap.lapId)),
      ),
      data: (data) => data == null || data.isEmpty
          ? const EmptyLapsCard(message: _noTraceText)
          : TelemetryCharts(
              trace: data,
              reference: reference?.valueOrNull,
              lapTimeMs: lap.lapTimeMs,
              referenceLapTimeMs: comparison?.lapTimeMs,
              referenceLabel: comparison == null ? kDefaultReferenceLabel : referenceLegendLabel(comparison),
              units: units,
              sectors: lap.sectors,
              referenceSectors: comparison?.sectors ?? const [],
              playerTeam: lap.team,
              referenceTeam: comparison?.team,
              playerTyreCompound: visualCompoundName(shared.detail.car?.visualTyreCompound),
              realTrack: ref.watch(trackWidthsProvider).valueOrNull?[lap.trackName],
              trackSamples: ref
                  .watch(trackGeometryProvider((trackId: shared.detail.trackId, gameCode: lap.gameCode)))
                  .valueOrNull,
              estimatedTrackWidthM: kEstimatedTrackWidthsM[lap.trackName],
              streetCircuit: kStreetCircuits.contains(lap.trackName),
            ),
    );
  }
}
