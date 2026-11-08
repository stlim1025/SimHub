import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../auth/application/auth_controller.dart';
import '../../devices/presentation/connection_status_card.dart';
import '../../lap_detail/domain/lap_detail_display.dart';
import '../../laps/application/fresh_laps.dart';
import '../../laps/application/laps_providers.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import '../../laps/presentation/lap_cells.dart';
import '../../sessions/domain/session_display.dart' show formatGapMs;
import '../../sessions/presentation/session_widgets.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard_home.dart';
import 'dashboard_season_section.dart';
import 'last_race_tile.dart';
import 'personal_bests_card.dart';

/// 본문 폭이 이 값 이상이면 홈을 B안 보드로 놓는다: 첫 줄 [Last Race 7 | 연결 상태 + Personal Bests 5],
/// 둘째 줄 [시즌 7 | 최근 랩 5].
const double kDashboardBoardMinWidth = 1200;

/// 본문 폭이 이 값 이상(보드보다 좁음)이면 최근 랩과 Personal Bests를 나란히 놓는다. 더 좁으면 모두 위에서 아래로.
const double kDashboardPairMinWidth = 760;

const int _mainFlex = 7;
const int _sideFlex = 5;
const double _gap = 24;

const String _recentLapsTitle = '최근 랩';
const String _viewAllLapsLabel = 'View all lap times';
const String _recentLapsFailedText = '최근 랩을 불러오지 못했어요.';
const String _noLapsText = '아직 기록된 랩이 없어요. 게임을 플레이하면 여기에 최근 랩이 표시돼요.';
const String _invalidText = '무효';
const String _personalBestText = 'PB';

/// 최근 랩 표 열 폭.
const double _dateColumnWidth = 124;
const double _lapTimeColumnWidth = 84;
const double _pbGapColumnWidth = 72;
const int _trackColumnFlex = 3;
const int _modeColumnFlex = 2;

/// 로그인 직후 홈(B안 미션 컨트롤). 환영 문구 + 최근 레이스 타일 + 연결 상태 + 트랙별 최고 랩 + 시즌 요약 + 내 최근 랩(docs/11 §7.3).
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(authControllerProvider).valueOrNull?.displayName ?? '';
    final theme = Theme.of(context);

    return ListView(
      padding: pagePadding(context),
      children: [
        Text(
          'Welcome $displayName!',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: _gap),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= kDashboardBoardMinWidth
              ? const _Board()
              : _Stacked(pairLists: box.maxWidth >= kDashboardPairMinWidth),
        ),
      ],
    );
  }
}

/// 넓은 화면: 12칸 보드처럼 두 줄. 첫 줄 오른쪽 열은 Last Race 타일 높이까지 Personal Bests를 늘려 바닥을 맞춘다.
class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: _mainFlex, child: LastRaceTile(height: kLastRaceTileHeight)),
            const SizedBox(width: _gap),
            Expanded(
              flex: _sideFlex,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kLastRaceTileHeight),
                child: const FillColumn(gap: _gap, children: [ConnectionStatusCard(), PersonalBestsCard()]),
              ),
            ),
          ],
        ),
        const SizedBox(height: _gap),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: _mainFlex, child: DashboardSeasonSection()),
            SizedBox(width: _gap),
            Expanded(flex: _sideFlex, child: _RecentLapsCard()),
          ],
        ),
      ],
    );
  }
}

/// 보드보다 좁은 화면: Last Race 타일부터 위에서 아래로. [pairLists]면 최근 랩과 Personal Bests를 나란히.
class _Stacked extends StatelessWidget {
  const _Stacked({required this.pairLists});

  final bool pairLists;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LastRaceTile(),
        const SizedBox(height: _gap),
        const ConnectionStatusCard(),
        const SizedBox(height: _gap),
        const DashboardSeasonSection(),
        const SizedBox(height: _gap),
        if (pairLists)
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _RecentLapsCard()),
              SizedBox(width: _gap),
              Expanded(child: PersonalBestsCard()),
            ],
          )
        else ...const [
          _RecentLapsCard(),
          SizedBox(height: _gap),
          PersonalBestsCard(),
        ],
      ],
    );
  }
}

/// 최근 랩 카드: 트랙 · 모드 · 날짜 · 랩타임 · 그 트랙 최고 랩과의 차. 실시간으로 막 들어온 랩 행은 잠깐 강조된다(D-50, docs/15 §9).
class _RecentLapsCard extends ConsumerWidget {
  const _RecentLapsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentLapsProvider);
    final laps = recent.valueOrNull?.laps;
    return SessionCard(
      title: _recentLapsTitle,
      padded: laps == null || laps.isEmpty,
      // 좁은 카드에서도 제목 칸이 남도록 링크는 남는 폭만 쓴다.
      trailing: Flexible(
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.go('/laps'),
            child: const Text(_viewAllLapsLabel),
          ),
        ),
      ),
      child: recent.when(
        loading: () => const PageLoadingBar(),
        error: (e, _) => ErrorRetry(
          error: e,
          fallbackMessage: _recentLapsFailedText,
          onRetry: () => ref.invalidate(recentLapsProvider),
        ),
        data: (data) => data.laps.isEmpty ? const SessionEmptyText(_noLapsText) : _RecentLapsTable(laps: data.laps),
      ),
    );
  }
}

class _RecentLapsTable extends ConsumerWidget {
  const _RecentLapsTable({required this.laps});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  final List<Lap> laps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshIds = ref.watch(freshLapIdsProvider);
    // 트랙별 최고 랩을 아직 못 받았거나 못 읽었으면 차 칸만 비운다.
    final bests = personalBestByTrackName(ref.watch(myTracksProvider).valueOrNull ?? const []);
    final palette = context.palette;
    final muted = TextStyle(color: palette.textMuted);
    return CompactTable<Lap>(
      framed: false,
      rows: laps,
      rowKey: (lap) => ValueKey('recent-lap-${lap.lapId}'),
      isFresh: (lap) => freshIds.contains(lap.lapId),
      // 행을 누르면 그 랩의 상세(D-46).
      onRowTap: (lap) => context.go(lapDetailLocation(lap.lapId)),
      columns: [
        CompactColumn(
          label: 'Track',
          flex: _trackColumnFlex,
          cell: (lap) => Text(
            lap.trackName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        CompactColumn(
          label: 'Mode',
          flex: _modeColumnFlex,
          compactHidden: true,
          cell: (lap) => Text(
            lapModeLabel(gameMode: lap.gameMode, sessionType: lap.sessionType),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
        CompactColumn(
          label: 'Date',
          width: _dateColumnWidth,
          compactHidden: true,
          cell: (lap) => Text(
            _dateFormat.format(lap.setAt.toLocal()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted.merge(kTabularStyle),
          ),
        ),
        CompactColumn(
          label: 'Lap Time',
          width: _lapTimeColumnWidth,
          alignment: Alignment.centerRight,
          cell: (lap) => Text(formatLapTime(lap.lapTimeMs), style: lapTimeLinkStyle(context)),
        ),
        CompactColumn(
          label: 'vs PB',
          width: _pbGapColumnWidth,
          alignment: Alignment.centerRight,
          cell: (lap) => _PersonalBestGap(lap: lap, bests: bests),
        ),
      ],
    );
  }
}

/// 최근 랩의 최고 랩 대비 칸: 무효 랩은 `무효`, 그 랩이 최고 랩이면 `PB`(초록), 아니면 `+0.482`(빨강), 모르면 빈 칸.
class _PersonalBestGap extends StatelessWidget {
  const _PersonalBestGap({required this.lap, required this.bests});

  final Lap lap;
  final Map<String, int> bests;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (!lap.isValid) {
      return Text(_invalidText, style: TextStyle(color: palette.danger));
    }
    final gap = gapToPersonalBest(lap, bests);
    if (gap == null) {
      return const SizedBox.shrink();
    }
    return gap <= 0
        ? Text(_personalBestText, style: TextStyle(color: palette.success, fontWeight: FontWeight.w700))
        : Text(formatGapMs(gap), style: kTabularStyle.copyWith(color: palette.danger));
  }
}
