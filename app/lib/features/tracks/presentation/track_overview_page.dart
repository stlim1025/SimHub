import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/not_found_state.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat.dart';
import '../../../core/widgets/team_name_cell.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/lap_compare.dart';
import '../../lap_detail/presentation/detail_list.dart';
import '../../lap_detail/presentation/track_map.dart';
import '../../laps/domain/lap_display.dart';
import '../../laps/domain/lap_models.dart';
import '../../profile/application/selected_game_provider.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../../setups/domain/setups_display.dart';
import '../../setups/presentation/page_heading.dart';
import '../application/tracks_providers.dart';
import '../domain/track_overview_models.dart';

const String _tracksLabel = 'Tracks';
const String _errorMessage = '트랙 정보를 불러오지 못했다.';
const String _notFoundMessage = '찾을 수 없는 트랙이다.';

const String _setupsLinkTitle = 'Top Setups';
const String _leaderboardLinkTitle = 'Leaderboard';
const String _statsSuffix = 'stats';

const String _statBestLap = 'My best lap';
const String _statBestTimeTrial = 'My Time Trial best';
const String _statAverageLap = 'Average lap time';
const String _statAverageAi = 'Average AI difficulty';
const String _statLaps = 'Laps';
const String _statSessions = 'Sessions';

const String _topTimeTrialTitle = 'Fastest Time Trial laps';
const String _topTimeTrialEmpty = '아직 이 트랙의 Time Trial 기록이 없다.';
const String _fullLeaderboardLabel = 'Full leaderboard';
const String _bestLapsTitle = 'Best Lap Times';
const String _bestLapsEmpty = '이 트랙에서 달린 랩이 아직 없다.';
const String _invalidLabel = 'Invalid';
const String _trackDetailsTitle = 'Track Details';
const String _detailGrandPrix = 'Grand Prix Name';
const String _detailCircuit = 'Circuit Name';
const String _detailLength = 'Length';
const String _detailLapRecord = 'F1 Lap Record';
const String _kmUnit = 'km';
const int _lengthFractionDigits = 3;

const int _httpNotFound = 404;
const double _sectionGap = 24;
const double _blockGap = 20;
const double _headingGap = 12;
const double _linkPadding = 20;
const double _linkIconGap = 12;
const double _statsPadding = 24;
const double _statsSpacing = 40;
const double _statsRunSpacing = 20;
const double _topRowGap = 12;
const double _topRankWidth = 24;
const double _topTimeWidth = 84;
const double _rankWidth = 40;
const double _lapTimeWidth = 100;
const double _dateWidth = 140;
const int _sessionFlex = 2;
const int _teamFlex = 3;

/// 콘텐츠 폭이 이 값 이상이면 바로가기 카드를 나란히.
const double kTrackLinksRowWidth = 560;

/// 콘텐츠 폭이 이 값 이상이면 기록 요약과 Time Trial 상위 카드를 나란히.
const double kTrackStatsRowWidth = 900;

/// 트랙 개요(`/tracks/:trackId`, F1Laps `F1 26 Australia` 모양): 이동 경로 + 국기·제목·서킷 이름,
/// 바로가기(Top Setups · Leaderboard), `{트랙} stats`(내 기록 요약 + Fastest Time Trial laps), Best Lap Times(내 빠른 랩 10개),
/// Track Details(+ [TrackOverview.mapLapId] 랩의 트랙 지도).
class TrackOverviewPage extends ConsumerWidget {
  const TrackOverviewPage({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trackOverviewProvider(trackId));
    final track = overview.valueOrNull?.track;
    final String selectedGame = ref.watch(selectedGameProvider);
    final gameCode = track?.gameCode ?? selectedGame;
    return ListView(
      padding: pagePadding(context),
      children: [
        PageHeading(
          crumbs: [
            (label: gameYearLabelOf(gameCode), path: null),
            (label: _tracksLabel, path: kTracksPath),
            if (track != null) (label: track.name, path: null),
          ],
          title: track == null ? '${gameTitleOf(gameCode)} $_tracksLabel' : '${gameTitleOf(gameCode)} ${track.name}',
          subtitle: track?.circuitName,
          countryCode: track?.countryCode,
          showFlag: track != null,
        ),
        const SizedBox(height: _blockGap),
        overview.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => e is ApiException && e.statusCode == _httpNotFound
              ? const NotFoundState(message: _notFoundMessage, backLabel: _tracksLabel, backPath: kTracksPath)
              : ErrorRetry(
                  error: e,
                  fallbackMessage: _errorMessage,
                  onRetry: () => ref.invalidate(trackOverviewProvider(trackId)),
                ),
          data: (data) => _OverviewBody(overview: data),
        ),
      ],
    );
  }
}

class _OverviewBody extends StatelessWidget {
  const _OverviewBody({required this.overview});

  final TrackOverview overview;

  @override
  Widget build(BuildContext context) {
    final track = overview.track;
    final links = [
      _QuickLinkCard(
        key: const ValueKey('track-link-setups'),
        icon: Icons.tune,
        title: _setupsLinkTitle,
        path: setupTrackLocation(track.trackId),
      ),
      _QuickLinkCard(
        key: const ValueKey('track-link-leaderboard'),
        icon: Icons.emoji_events_outlined,
        title: _leaderboardLinkTitle,
        path: leaderboardLocation(track.trackId),
      ),
    ];
    final stats = _MyStatsCard(stats: overview.myStats);
    final top = _TopTimeTrialCard(laps: overview.topTimeTrial, trackId: track.trackId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Responsive(minRowWidth: kTrackLinksRowWidth, children: links),
        const SizedBox(height: _sectionGap),
        Text('${track.name} $_statsSuffix', style: cardTitleStyle(context)),
        const SizedBox(height: _headingGap),
        _Responsive(minRowWidth: kTrackStatsRowWidth, children: [stats, top]),
        const SizedBox(height: _sectionGap),
        _BestLapsCard(laps: overview.myBestLaps),
        const SizedBox(height: _sectionGap),
        _TrackDetailsCard(track: track, mapLapId: overview.mapLapId),
      ],
    );
  }
}

/// 폭이 [minRowWidth] 이상이면 같은 높이로 나란히, 아니면 위아래로 쌓는다.
class _Responsive extends StatelessWidget {
  const _Responsive({required this.minRowWidth, required this.children});

  final double minRowWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= minRowWidth
          ? EqualHeightRow(gap: _blockGap, children: children)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: _blockGap),
                  children[i],
                ],
              ],
            ),
    );
  }
}

/// 바로가기 카드: 아이콘 + 굵은 제목. 누르면 [path]로 간다.
class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({super.key, required this.icon, required this.title, required this.path});

  final IconData icon;
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(path),
        child: Padding(
          padding: const EdgeInsets.all(_linkPadding),
          child: Row(
            children: [
              Icon(icon, color: palette.textMuted),
              const SizedBox(width: _linkIconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

String _msText(int? ms) => ms == null ? kLapNoValueText : formatLapTime(ms);

/// 내 기록 요약 카드: 최고 랩 · Time Trial 최고 · 평균 랩 · 평균 AI 난이도 · 랩 수 · 세션 수.
class _MyStatsCard extends StatelessWidget {
  const _MyStatsCard({required this.stats});

  final TrackMyStats stats;

  @override
  Widget build(BuildContext context) {
    final ai = stats.averageAiDifficulty;
    final items = <(String, String)>[
      (_statBestLap, _msText(stats.bestLapMs)),
      (_statBestTimeTrial, _msText(stats.bestTimeTrialLapMs)),
      (_statAverageLap, _msText(stats.averageLapMs)),
      (_statAverageAi, ai == null ? kLapNoValueText : '${ai.round()}'),
      (_statLaps, '${stats.lapCount}'),
      (_statSessions, '${stats.sessionCount}'),
    ];
    return Card(
      key: const ValueKey('track-my-stats'),
      child: Padding(
        padding: const EdgeInsets.all(_statsPadding),
        child: Wrap(
          spacing: _statsSpacing,
          runSpacing: _statsRunSpacing,
          children: [
            for (final (label, value) in items) Stat(key: ValueKey('track-stat-$label'), label: label, value: value),
          ],
        ),
      ),
    );
  }
}

/// Fastest Time Trial laps(상위 3): 순위 · 시간 · 이름 · 팀. 아래에 리더보드 링크.
class _TopTimeTrialCard extends StatelessWidget {
  const _TopTimeTrialCard({required this.laps, required this.trackId});

  final List<TrackTopLap> laps;
  final String trackId;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted;
    return SectionCard(
      key: const ValueKey('track-top-time-trial'),
      title: _topTimeTrialTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (laps.isEmpty)
            Text(_topTimeTrialEmpty, style: TextStyle(color: muted))
          else
            for (var i = 0; i < laps.length; i++) ...[
              if (i > 0) const SizedBox(height: _topRowGap),
              Row(
                key: ValueKey('track-top-${laps[i].rank}'),
                children: [
                  SizedBox(width: _topRankWidth, child: Text('${laps[i].rank}', style: TextStyle(color: muted))),
                  SizedBox(
                    width: _topTimeWidth,
                    child: Text(
                      formatLapTime(laps[i].lapTimeMs),
                      style: kTabularStyle.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Text(laps[i].displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Flexible(child: TeamNameCell(teamName: laps[i].teamName)),
                ],
              ),
            ],
          const SizedBox(height: _topRowGap),
          TextButton(onPressed: () => context.go(leaderboardLocation(trackId)), child: const Text(_fullLeaderboardLabel)),
        ],
      ),
    );
  }
}

/// Best Lap Times: 내 빠른 랩 표(# · LAP TIME · SESSION · TEAM · DATE). 줄을 누르면 랩 상세로 간다.
class _BestLapsCard extends StatelessWidget {
  const _BestLapsCard({required this.laps});

  final List<TrackBestLap> laps;

  @override
  Widget build(BuildContext context) {
    final muted = context.palette.textMuted;
    return SectionCard(
      key: const ValueKey('track-best-laps'),
      title: _bestLapsTitle,
      child: laps.isEmpty
          ? Text(_bestLapsEmpty, style: TextStyle(color: muted))
          : CompactTable<(int, TrackBestLap)>(
              framed: false,
              rows: [for (var i = 0; i < laps.length; i++) (i + 1, laps[i])],
              rowKey: (row) => ValueKey('track-best-lap-${row.$2.lapId}'),
              onRowTap: (row) => context.go('/laps/${Uri.encodeComponent(row.$2.lapId)}'),
              columns: [
                CompactColumn(label: '#', width: _rankWidth, cell: (row) => Text('${row.$1}', style: kTabularStyle)),
                CompactColumn(
                  label: 'Lap Time',
                  width: _lapTimeWidth,
                  cell: (row) => Text(
                    formatLapTime(row.$2.lapTimeMs),
                    style: row.$2.isValid
                        ? kTabularStyle.copyWith(fontWeight: FontWeight.w600)
                        : kTabularStyle.copyWith(color: muted, decoration: TextDecoration.lineThrough),
                  ),
                ),
                CompactColumn(
                  label: 'Session',
                  flex: _sessionFlex,
                  cell: (row) => Text(
                    row.$2.isValid
                        ? sessionTypeLabel(row.$2.sessionType)
                        : '${sessionTypeLabel(row.$2.sessionType)} · $_invalidLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CompactColumn(
                  label: 'Team',
                  flex: _teamFlex,
                  compactHidden: true,
                  cell: (row) => TeamNameCell(teamName: row.$2.teamName),
                ),
                CompactColumn(
                  label: 'Date',
                  width: _dateWidth,
                  compactHidden: true,
                  cell: (row) => Text(formatLapDate(row.$2.setAt), style: TextStyle(color: muted)),
                ),
              ],
            ),
    );
  }
}

/// Track Details: Grand Prix 이름 · 서킷 이름 · 길이 · F1 랩 레코드, [mapLapId]가 있으면 그 아래 트랙 지도.
class _TrackDetailsCard extends StatelessWidget {
  const _TrackDetailsCard({required this.track, required this.mapLapId});

  final TrackInfo track;
  final String? mapLapId;

  @override
  Widget build(BuildContext context) {
    final length = track.lengthKm;
    final lapId = mapLapId;
    return SectionCard(
      key: const ValueKey('track-details'),
      title: _trackDetailsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailList(
            items: [
              DetailItem(_detailGrandPrix, text: track.grandPrixName ?? kLapNoValueText),
              DetailItem(_detailCircuit, text: track.circuitName ?? kLapNoValueText),
              DetailItem(
                _detailLength,
                text: length == null ? kLapNoValueText : '${length.toStringAsFixed(_lengthFractionDigits)} $_kmUnit',
              ),
              DetailItem(_detailLapRecord, text: track.f1LapRecord ?? kLapNoValueText),
            ],
          ),
          if (lapId != null) _TrackOverviewMap(lapId: lapId),
        ],
      ),
    );
  }
}

/// [lapId] 랩의 트레이스로 그린 트랙 지도(커서 없음, 랩 상세의 섹터 시간으로 섹터 색·범례). 위치가 없거나 불러오지 못하면 아무것도 그리지 않는다.
/// 남의 Time Trial 랩도 볼 수 있게 비교 랩 트레이스([comparisonTraceProvider])를 쓴다.
class _TrackOverviewMap extends ConsumerStatefulWidget {
  const _TrackOverviewMap({required this.lapId});

  final String lapId;

  @override
  ConsumerState<_TrackOverviewMap> createState() => _TrackOverviewMapState();
}

class _TrackOverviewMapState extends ConsumerState<_TrackOverviewMap> {
  /// 커서는 쓰지 않는다(늘 null).
  final ValueNotifier<double?> _noCursor = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _noCursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trace = ref.watch(comparisonTraceProvider(widget.lapId)).valueOrNull;
    if (trace == null || !trace.hasPositions) {
      return const SizedBox.shrink();
    }
    // 지도 랩은 내 랩이라 랩 상세의 섹터 시간으로 랩 상세 지도처럼 섹터별 색을 칠한다(못 불러오면 한 색).
    final sectors = ref.watch(lapDetailProvider(LapDetailKey(widget.lapId))).valueOrNull?.lap.sectors ?? const <LapSector>[];
    return Padding(
      padding: const EdgeInsets.only(top: _blockGap),
      child: TrackMap(
        trace: trace,
        sectors: sectors,
        cursor: _noCursor,
        showLegend: sectors.isNotEmpty,
        paintKey: const ValueKey('track-overview-map'),
      ),
    );
  }
}
