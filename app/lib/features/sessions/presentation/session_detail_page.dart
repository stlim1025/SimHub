import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/layout_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/track_flag.dart';
import '../../seasons/domain/season_display.dart';
import '../application/sessions_providers.dart';
import '../domain/session_detail_display.dart';
import '../domain/session_display.dart';
import '../domain/session_models.dart';
import 'engine_wear_card.dart';
import 'final_classification_card.dart';
import 'penalties_card.dart';
import 'session_details_card.dart';
import 'session_laps_card.dart';
import 'tyre_stint_cards.dart';

const String _sessionsPath = '/sessions';
const String _backToSessionsTooltip = '세션 목록';
const String _backToSeasonTooltip = '시즌으로';
const String _notFoundMessage = '찾을 수 없는 세션입니다.';
const String _notFoundBackLabel = 'Sessions';

/// 세션 이름을 알 수 없을 때(로딩 중·조회 실패)의 제목.
const String _fallbackTitle = 'Session';

const int _httpNotFound = 404;
const double _headerFlagSize = 28;
const double _headerGap = 10;
const double _cardGap = 16;

/// 세션 상세(docs/15 §11.3, D-53): 헤더(국기 + 트랙 + 세션 종류) + 카드 7장 — Details · Final Classification · Laps ·
/// Engine Wear · Tyre Stints 2종 · Penalties. 콘텐츠 폭 900px 이상이면 2열(Laps는 열이 많아 한 줄 전체), 미만이면 1열.
/// 남의 것이거나 없는 세션이면 404 상태를 보여 준다.
///
/// [from]은 주소의 `?from=` 값이다. `season`(시즌 화면의 세션 칩)이고 불러온 세션이 시즌에 속하면
/// 뒤로 가기가 그 시즌으로 돌아가고, 그 밖(없음·모르는 값·시즌 없는 세션·아직 로딩)은 세션 목록으로 간다.
class SessionDetailPage extends ConsumerWidget {
  const SessionDetailPage({super.key, required this.sessionId, this.from});

  final String sessionId;
  final String? from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final header = detail.valueOrNull?.header;
    final backSeasonId = from == kSessionFromSeason ? header?.seasonId : null;

    return ListView(
      padding: kPagePadding,
      children: [
        _Header(
          header: header,
          backTooltip: backSeasonId == null ? _backToSessionsTooltip : _backToSeasonTooltip,
          onBack: () => context.go(backSeasonId == null ? _sessionsPath : seasonLocation(backSeasonId)),
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
          data: (data) => _SessionCards(detail: data),
        ),
      ],
    );
  }

  static bool _isNotFound(Object error) => error is ApiException && error.statusCode == _httpNotFound;
}

/// ← + 국기 + 트랙 이름 + 세션 종류(`Qualifying 3`). 아직 모르면 `Session`.
class _Header extends StatelessWidget {
  const _Header({required this.header, required this.backTooltip, required this.onBack});

  final SessionDetailHeader? header;
  final String backTooltip;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final value = header;
    final style = Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);
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
      ],
    );
  }
}

/// 카드 7장. 2열이면 [Details | Final Classification] · [Laps] · [Engine Wear | Tyre Life] · [Lap Times | Penalties].
class _SessionCards extends StatelessWidget {
  const _SessionCards({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final details = SessionDetailsCard(detail: detail);
    final classification = FinalClassificationCard(
      results: detail.results,
      isRace: detail.header.sessionType == 'Race',
    );
    final laps = SessionLapsCard(laps: detail.laps);
    final engine = EngineWearCard(wear: detail.engineWear);
    final tyreLife = TyreLifeCard(stints: detail.tyreStints);
    final lapTimes = StintLapTimesCard(stints: detail.tyreStints);
    final penalties = PenaltiesCard(penalties: detail.penalties);

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = constraints.maxWidth >= kSessionDetailTwoColumnWidth
            ? <Widget>[
                _Pair(details, classification),
                laps,
                _Pair(engine, tyreLife),
                _Pair(lapTimes, penalties),
              ]
            : <Widget>[details, classification, laps, engine, tyreLife, lapTimes, penalties];
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
