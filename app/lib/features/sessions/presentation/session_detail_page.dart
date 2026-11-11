import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/layout_constants.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/layout/viewport_pinned.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/compact_table.dart' show kCompactRowHeight;
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/track_flag.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/lap_compare.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../seasons/domain/season_display.dart';
import '../../tracks/application/track_corners_provider.dart';
import '../application/sessions_providers.dart';
import '../domain/race_review.dart';
import '../domain/session_board.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'engine_wear_card.dart';
import 'final_classification_card.dart';
import 'penalties_card.dart';
import 'race_review_card.dart';
import 'race_review_track_map.dart';
import 'session_board_cards.dart';
import 'session_board_layout.dart';
import 'session_details_card.dart';
import 'session_highlights_page.dart';
import 'session_kpi_strip.dart';
import 'session_laps_card.dart';
import 'tyre_stint_cards.dart';

const String _sessionsPath = '/sessions';
const String _backToSessionsTooltip = '세션 목록';
const String _backToSeasonTooltip = '시즌으로';
const String _notFoundMessage = '찾을 수 없는 세션입니다.';
const String _notFoundBackLabel = 'Sessions';
const String _highlightsLabel = '하이라이트';
const String _analysisErrorMessage = '레이스 분석을 불러오지 못했어요.';

/// KPI 띠 경로 글자(세션 목록에서 왔을 때 · 시즌에서 왔을 때).
const String _sessionsCrumb = 'Sessions';
const String _seasonCrumb = 'Season';

/// 세션 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Session';

const int _httpNotFound = 404;
const double _headerFlagSize = 24;
const double _headerGap = 8;
const double _headerFontSize = 22;
const double _cardGap = 20;
const double _sectionGap = 16;

/// B안 보드 첫 줄 폭 비율(12칸 격자의 5칸 : 7칸 — Final Classification : 순위 그래프·스틴트·핵심 장면).
const int _boardLeftFlex = 5;
const int _boardRightFlex = 7;

/// 보드의 Final Classification 행 높이(22대가 한 화면에 들어가게 기본 44보다 낮게).
const double _boardClassificationRowHeight = 34;

/// 보드 순위 그래프의 기본 높이(낮게 두고, 왼쪽 순위표가 더 높으면 그만큼 늘어난다).
const double _boardChartHeight = 200;

/// 레이스 리뷰 옆 트랙 지도 칸 폭, 지도를 옆 칸에 둘 최소 콘텐츠 폭(리뷰의 그림·짚을 것 두 칸이 눌리지 않게).
const double _reviewMapWidth = 300;
const double _reviewMapSideWidth = 1080;

/// 탭 값 → 탭 글자(`kSessionTabs`와 같은 순서로 그린다).
const Map<String, String> _tabLabels = {
  kSessionTabResults: 'Results',
  kSessionTabReview: 'Race Review',
};

/// 세션 상세(docs/15 §11.3, D-53, B안 미션 컨트롤): 맨 위 KPI 띠(경로 + 국기 · 트랙 · 세션 종류 + 결과 숫자 + 하이라이트) +
/// 카드 7장 — Details · Final Classification · Laps · Engine Wear · Tyre Stints 2종 · Penalties. 레이스는 순위 그래프·
/// 모든 차 스틴트·핵심 장면 카드가 더 있다. 콘텐츠 폭 1500px 이상은 12칸 보드, 900px 이상은 2열, 미만은 1열.
/// 레이스 리뷰가 있는 레이스는 KPI 띠 아래 탭 두 개(Results · Race Review)로 나누고, 탭은 주소의 `?tab=`과 동기화된다.
/// 불러오는 동안·실패하면 KPI 띠 대신 간단한 헤더(← + 국기 + 트랙 + 세션 종류)를 둔다.
/// 남의 것이거나 없는 세션이면 404 상태를 보여 준다.
///
/// [from]은 주소의 `?from=` 값이다. `season`(시즌 화면의 세션 칩)이고 불러온 세션이 시즌에 속하면
/// 뒤로 가기가 그 시즌으로 돌아가고, 그 밖(없음·모르는 값·시즌 없는 세션·아직 로딩)은 세션 목록으로 간다.
class SessionDetailPage extends ConsumerStatefulWidget {
  const SessionDetailPage({super.key, required this.sessionId, this.from, this.tab});

  final String sessionId;
  final String? from;

  /// 주소의 `tab` 쿼리. null이거나 모르는 값이면 결과 탭(레이스 리뷰가 없는 세션은 탭 없이 결과만).
  final String? tab;

  @override
  ConsumerState<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends ConsumerState<SessionDetailPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String get _tab => normalizeSessionTab(widget.tab);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kSessionTabs.length, vsync: this, initialIndex: kSessionTabs.indexOf(_tab));
  }

  @override
  void didUpdateWidget(SessionDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 주소가 바뀌면(뒤로 가기·다른 화면에서의 이동 포함) 탭 막대의 선택도 따라간다.
    final index = kSessionTabs.indexOf(_tab);
    if (_tabController.index != index) {
      _tabController.index = index;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 탭을 누를 때마다 브라우저 기록에 항목이 쌓이지 않도록 neglect로 감싸 쿼리만 바꾼다(`from`은 그대로 둔다).
  void _selectTab(int index) {
    final tab = kSessionTabs[index];
    if (tab == _tab) {
      return;
    }
    final location = sessionLocation(widget.sessionId, fromSeason: widget.from == kSessionFromSeason, tab: tab);
    Router.neglect(context, () => context.go(location));
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final loaded = detail.valueOrNull;
    final header = loaded?.header;
    final backSeasonId = widget.from == kSessionFromSeason ? header?.seasonId : null;
    final backTooltip = backSeasonId == null ? _backToSessionsTooltip : _backToSeasonTooltip;
    void onBack() => context.go(backSeasonId == null ? _sessionsPath : seasonLocation(backSeasonId));
    final onHighlights = header != null && header.sessionType == kRaceSessionType && header.hasFieldSamples
        ? () => context.go(sessionHighlightsLocation(sessionId))
        : null;

    return ListView(
      // Race Review 탭은 오른쪽 트랙 지도 칸만큼 더 넓게 써서 리뷰 폭은 그대로 둔다(헤더·탭 막대는 본문 폭 그대로).
      padding: pagePadding(
        context,
        maxWidth: _tab == kSessionTabReview ? kContentMaxWidth + _reviewMapWidth + _sectionGap : kContentMaxWidth,
      ),
      children: [
        _ContentWidth(
          child: loaded == null
              ? _Header(header: header, backTooltip: backTooltip, onBack: onBack, onHighlights: onHighlights)
              : SessionKpiStrip(
                  detail: loaded,
                  crumb: backSeasonId == null
                      ? _sessionsCrumb
                      : [_seasonCrumb, ?header?.seasonNumber?.toString()].join(' '),
                  backTooltip: backTooltip,
                  onBack: onBack,
                  onHighlights: onHighlights,
                ),
        ),
        const SizedBox(height: _sectionGap),
        detail.when(
          loading: () => const PageLoadingBar(),
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
          data: (data) => _SessionCards(detail: data, tab: _tab, tabController: _tabController, onTab: _selectTab),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// 자식을 왼쪽에 붙여 본문 최대 폭([kContentMaxWidth])까지만 쓰게 한다 — Race Review 탭이 지도 칸만큼 넓어져도
/// 헤더·탭 막대·지도 없는 리뷰는 Results 탭과 같은 폭으로 둔다.
class _ContentWidth extends StatelessWidget {
  const _ContentWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kContentMaxWidth), child: child),
      );
}

/// ← + 국기 + 트랙 이름 + 세션 종류(`Qualifying 3`). 아직 모르면 `Session`(불러오는 중·실패 — 불러오면 KPI 띠로 바뀐다).
class _Header extends StatelessWidget {
  const _Header({required this.header, required this.backTooltip, required this.onBack, this.onHighlights});

  final SessionDetailHeader? header;
  final String backTooltip;
  final VoidCallback onBack;

  /// 레이스 하이라이트 열기(모든 차 표본이 있는 레이스만). null이면 버튼 없음.
  final VoidCallback? onHighlights;

  @override
  Widget build(BuildContext context) {
    final value = header;
    // F1Laps처럼 "Saudi Arabia Race"를 한 줄 제목(22px)으로 — 페이지 큰 제목(28px)은 이 화면에서 지나치게 크다.
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: _headerFontSize, fontWeight: FontWeight.bold);
    return Row(
      children: [
        IconButton(tooltip: backTooltip, icon: const Icon(Icons.arrow_back), onPressed: onBack),
        const SizedBox(width: 4),
        if (value != null) ...[
          TrackFlag(countryCode: value.countryCode, size: _headerFlagSize),
          const SizedBox(width: _headerGap),
        ],
        Expanded(
          child: Wrap(
            spacing: _headerGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(value?.trackName ?? _fallbackTitle, style: style),
              if (value != null)
                Text(
                  sessionKindName(value.sessionKind, sprintWeekend: value.isSprintWeekend),
                  style: style?.copyWith(fontWeight: FontWeight.w500, color: context.palette.textMuted),
                ),
            ],
          ),
        ),
        if (onHighlights != null)
          FilledButton.tonalIcon(
            key: const ValueKey('session-highlights'),
            onPressed: onHighlights,
            icon: const Icon(Icons.movie_outlined),
            label: const Text(_highlightsLabel),
          ),
      ],
    );
  }
}

/// 결과 카드들. 레이스 리뷰가 있으면 위에 탭 막대(Results · Race Review)를 두고 [tab]에 고른 쪽만 그린다.
class _SessionCards extends StatelessWidget {
  const _SessionCards({required this.detail, required this.tab, required this.tabController, required this.onTab});

  final SessionDetail detail;
  final String tab;
  final TabController tabController;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final review = detail.raceReview;
    if (review == null || raceReviewSections(review).isEmpty) {
      return _ResultCards(detail: detail);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContentWidth(
          child: TabBar(
            controller: tabController,
            onTap: onTab,
            tabs: [for (final tab in kSessionTabs) Tab(text: _tabLabels[tab])],
          ),
        ),
        const SizedBox(height: _sectionGap),
        if (tab == kSessionTabReview) _RaceReviewTab(detail: detail, review: review) else _ResultCards(detail: detail),
      ],
    );
  }
}

/// Race Review 탭: 심층 분석과 공식 코너를 다 받은 뒤 한 번에 그린다(받는 동안은 불러오는 중 막대, 분석을 못 받으면 다시 시도).
class _RaceReviewTab extends ConsumerWidget {
  const _RaceReviewTab({required this.detail, required this.review});

  final SessionDetail detail;
  final RaceReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = detail.header.sessionId;
    final analysis = ref.watch(raceAnalysisProvider(sessionId));
    final corners = ref.watch(trackCornersProvider);
    final mapLap = sessionMapLap(detail);
    final mapLapId = mapLap?.lapId;
    final trace = mapLapId == null ? null : ref.watch(lapTraceProvider(mapLapId));
    if (analysis.isLoading || corners.isLoading || (trace?.isLoading ?? false)) {
      return const PageLoadingBar();
    }
    final official = corners.valueOrNull?[detail.header.trackName];
    return analysis.when(
      loading: () => const PageLoadingBar(),
      error: (e, _) => ErrorRetry(
        error: e,
        fallbackMessage: _analysisErrorMessage,
        onRetry: () => ref.invalidate(raceAnalysisProvider(sessionId)),
      ),
      data: (data) {
        final card = RaceReviewCard(review: review, analysis: data, officialCorners: official, setup: detail.setup);
        final lapTrace = trace?.valueOrNull;
        if (mapLap == null || lapTrace == null || !lapTrace.hasPositions) {
          return _ContentWidth(child: card);
        }
        final map = RaceReviewTrackMap(trace: lapTrace, sectors: sessionLapSectors(mapLap), officialCorners: official);
        // 넓으면 오른쪽 칸에 지도를 두고 스크롤해도 화면 위에 붙어 따라오게, 좁으면 리뷰 위에 둔다.
        return LayoutBuilder(
          builder: (context, box) => box.maxWidth >= _reviewMapSideWidth
              ? ViewportPinned(asideWidth: _reviewMapWidth, gap: _sectionGap, main: card, pinned: map)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [map, const SizedBox(height: _sectionGap), card],
                ),
        );
      },
    );
  }
}

/// 결과 카드(Results 탭, 레이스 리뷰가 없으면 화면 전체): 카드 7장 + 레이스면 순위 그래프 · 모든 차 스틴트 · 핵심 장면.
/// - 1500px 이상(B안 보드): 레이스는 [Final Classification(5칸) | 순위 그래프 / (스틴트 | 핵심 장면)(7칸)] ·
///   [Details | Engine Wear | Penalties] · [Tyre Life | Lap Times] · [Laps]. 보드 오른쪽 카드가 없으면(예선·연습)
///   [Details | Engine Wear | Penalties] · [Final Classification | Laps] · [Tyre Life | Lap Times].
/// - 900px 이상(2열): [Details | Final Classification] · 순위 그래프 · [스틴트 | 핵심 장면] · Laps · [Engine Wear | Tyre Life] ·
///   [Lap Times | Penalties].
/// - 그 미만은 1열.
/// 핵심 장면은 장면이 하나도 없으면 빠진다(모든 차 표본이 있으면 하이라이트의 내 장면도 담는다).
class _ResultCards extends ConsumerWidget {
  const _ResultCards({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = detail.header;
    final isRace = header.sessionType == kRaceSessionType;
    final details = SessionDetailsCard(detail: detail);
    // 모든 차 표본이 있고 내 최고 랩이 있으면, 순위표의 다른 차(최고 랩 기록이 있는)와 내 최고 랩을 비교할 수 있다.
    final myBestLapId = detail.myBestLap?.lapId;
    FinalClassificationCard classification({double rowHeight = kCompactRowHeight}) => FinalClassificationCard(
          results: detail.results,
          isRace: isRace,
          rowHeight: rowHeight,
          onCompare: !header.hasFieldSamples || myBestLapId == null
              ? null
              : (row) => context.go(lapDetailLocation(
                    myBestLapId,
                    tab: kLapTabTelemetry,
                    compare: LapCompareSelection.car(
                      sessionId: header.sessionId,
                      carIndex: row.carIndex,
                      name: row.name,
                      lapTimeMs: row.bestLapTimeMs,
                      teamColor: row.teamColor,
                    ),
                  )),
          canCompare: (row) => !row.isPlayer && row.bestLapTimeMs != null,
        );
    final laps = SessionLapsCard(laps: detail.laps);
    final engine = EngineWearCard(wear: detail.engineWear);
    final tyreLife = TyreLifeCard(stints: detail.tyreStints);
    final lapTimes = StintLapTimesCard(stints: detail.tyreStints);
    final penalties = PenaltiesCard(penalties: detail.penalties);

    // 레이스 보드 카드: 내 순위 그래프 · 모든 차 스틴트 · 핵심 장면(하이라이트는 모든 차 표본이 있을 때만 받는다).
    final highlights = isRace && header.hasFieldSamples
        ? ref.watch(raceHighlightsProvider(header.sessionId)).valueOrNull
        : null;
    final trace = isRace ? positionTraceOf(detail) : null;
    final moments = isRace ? keyMomentsOf(detail, highlights: highlights) : const <KeyMoment>[];
    PositionChartCard? chart({double height = kPositionChartHeight}) =>
        trace == null ? null : PositionChartCard(trace: trace, height: height);
    final fieldStints = isRace && detail.results.any((r) => r.tyreStints.isNotEmpty)
        ? FieldTyreStintsCard(results: detail.results, totalLaps: header.totalLaps)
        : null;
    final keyMoments = moments.isEmpty ? null : KeyMomentsCard(moments: moments);
    final sideCards = <Widget>[?fieldStints, ?keyMoments];
    final Widget? sideRow = switch (sideCards.length) {
      0 => null,
      1 => sideCards.single,
      _ => EqualHeightRow(gap: _cardGap, children: sideCards),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final List<Widget> rows;
        if (constraints.maxWidth >= kSessionDetailThreeColumnWidth) {
          final boardRight = <Widget>[?chart(height: _boardChartHeight), ?sideRow];
          rows = boardRight.isEmpty
              ? [
                  EqualHeightRow(gap: _cardGap, children: [details, engine, penalties]),
                  _Pair(classification(), laps),
                  _Pair(tyreLife, lapTimes),
                ]
              : [
                  BoardRow(
                    key: const ValueKey('session-board'),
                    gap: _cardGap,
                    flex: const [_boardLeftFlex, _boardRightFlex],
                    children: [
                      classification(rowHeight: _boardClassificationRowHeight),
                      // 왼쪽 순위표가 더 높으면 위 그래프 카드가 남는 높이를 받는다(그래프가 없으면 아래 줄).
                      BoardColumn(gap: _cardGap, stretchIndex: 0, children: boardRight),
                    ],
                  ),
                  EqualHeightRow(gap: _cardGap, children: [details, engine, penalties]),
                  _Pair(tyreLife, lapTimes),
                  laps,
                ];
        } else if (constraints.maxWidth >= kSessionDetailTwoColumnWidth) {
          rows = [
            _Pair(details, classification()),
            ?chart(),
            ?sideRow,
            laps,
            _Pair(engine, tyreLife),
            _Pair(lapTimes, penalties),
          ];
        } else {
          rows = [details, classification(), ?chart(), ...sideCards, laps, engine, tyreLife, lapTimes, penalties];
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: _cardGap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// 2열의 한 줄: 두 카드는 같은 폭·같은 높이, 가로 간격 = 세로 간격(docs/15 §11.3).
class _Pair extends StatelessWidget {
  const _Pair(this.left, this.right);

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => EqualHeightRow(gap: _cardGap, children: [left, right]);
}
