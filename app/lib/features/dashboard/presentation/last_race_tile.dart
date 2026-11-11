import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../../core/widgets/track_flag.dart';
import '../../lap_detail/application/lap_detail_providers.dart';
import '../../lap_detail/domain/lap_corners.dart';
import '../../lap_detail/domain/lap_detail_models.dart';
import '../../lap_detail/domain/track_map.dart' as track;
import '../../lap_detail/presentation/corner_labels.dart';
import '../../laps/domain/lap_models.dart' show LapSector;
import '../../sessions/application/sessions_providers.dart';
import '../../sessions/domain/session_detail_display.dart';
import '../../sessions/domain/session_display.dart';
import '../../sessions/domain/session_models.dart';
import '../../sessions/presentation/race_review_track_map.dart';
import '../../sessions/presentation/session_highlights_page.dart' show sessionHighlightsLocation;
import '../../sessions/presentation/session_widgets.dart' show kTabularStyle;
import '../../tracks/application/track_corners_provider.dart';
import '../../tracks/application/track_outlines_provider.dart';
import '../../tracks/domain/track_outline.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard_home.dart';

/// 타일 높이(서킷 그림과 결과를 나란히 놓을 때). 넓은 홈 보드에서는 오른쪽 열(연결 상태 + Personal Bests)도 이 높이에 맞춘다.
const double kLastRaceTileHeight = 400;

const String _eyebrowLabel = 'LAST RACE';
const String _gridSuffix = ' 출발';
const String _winnerGapPrefix = '우승과 ';
const String _separator = ' · ';
const String _bestLapLabel = '베스트 랩';
const String _pitStopsLabel = '피트';
const String _pitStopsSuffix = '회';
const String _pointsLabel = '포인트';
const String _highlightsLabel = '하이라이트';
const String _openSessionLabel = '세션 열기';
const String _emptyText = '아직 기록된 레이스가 없어요. 레이스를 마치면 여기에 결과와 서킷이 표시돼요.';
const String _sectorMapSemanticLabel = '섹터와 코너 번호가 적힌 트랙 지도';
const String _loadFailedText = '최근 레이스를 불러오지 못했어요.';

// -- 크기 ---------------------------------------------------------------------

const double _tilePadding = 20;

/// 타일 폭이 이보다 좁으면 서킷 그림을 위, 결과를 아래로 쌓는다.
const double _stackedMaxWidth = 640;
const double _stackedMapHeight = 220;
const double _mapInfoGap = 24;
const int _mapFlex = 6;
const int _infoFlex = 5;

const double _eyebrowLetterSpacing = 1.8;
const double _seasonLetterSpacing = 0.6;
const double _eyebrowGap = 12;
const double _titleFontSize = 30;
const double _flagSize = 22;
const double _flagGap = 10;
const double _positionFontSize = 84;
const double _tightLineHeight = 1;
const double _smallGap = 6;
const double _sectionGap = 14;
const double _resultRowHeight = 32;
const double _buttonGap = 8;
const double _buttonIconSize = 18;

/// 서킷 그림: 아래에 굵은 노면 띠, 위에 얇은 강조색 선.
const double _trackBandWidth = 16;
const double _trackLineWidth = 3.2;

/// 홈 맨 위 "Last Race" 타일(B안 미션 컨트롤): 가장 최근 레이스의 서킷(내 랩으로 그린 섹터 색 지도, 없으면 윤곽)을 크게 그리고, 옆에 결과
/// (순위 · 출발 대비 · 우승과 차이 · 베스트 랩 · 피트 · 포인트)와 하이라이트 · 세션 열기 버튼을 둔다.
/// 레이스가 없으면 안내 문구, 불러오지 못하면 다시 시도 버튼. [height]를 주면 어느 상태든 그 높이로 그린다(넓은 보드).
class LastRaceTile extends ConsumerWidget {
  const LastRaceTile({super.key, this.height});

  /// 고정 높이. null이면 결과는 [kLastRaceTileHeight](좁으면 내용 높이), 안내·로딩·오류는 내용 높이.
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final race = ref.watch(lastRaceProvider);
    final fixedHeight = height;
    Widget sized(Widget child) => fixedHeight == null ? child : SizedBox(height: fixedHeight, child: child);

    return race.when(
      // 불러오는 동안에는 결과 타일 자리만 잡아 둔다(다 받으면 같은 높이로 바뀐다).
      loading: () => SizedBox(height: fixedHeight ?? kLastRaceTileHeight, child: const Card(child: PageLoadingBar())),
      error: (e, _) => sized(Card(
        child: ErrorRetry(
          error: e,
          fallbackMessage: _loadFailedText,
          onRetry: () => ref.invalidate(lastRaceProvider),
        ),
      )),
      data: (summary) => summary == null
          ? sized(const _EmptyTile())
          : _RaceTile(key: const ValueKey('last-race-tile'), race: summary, height: fixedHeight),
    );
  }
}

/// 레이스가 아직 없을 때: 머리글 + 안내 문구.
class _EmptyTile extends StatelessWidget {
  const _EmptyTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('last-race-empty'),
      child: Padding(
        padding: const EdgeInsets.all(_tilePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Eyebrow(),
            const SizedBox(height: _sectionGap),
            Text(_emptyText, style: TextStyle(color: context.palette.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _RaceTile extends ConsumerWidget {
  const _RaceTile({super.key, required this.race, required this.height});

  final SessionSummary race;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 라운드 · 피트 · 우승과 차이 · 하이라이트 여부는 세션 상세에만 있다. 받기 전이나 못 받으면 목록 값만 보여 준다.
    final detail = ref.watch(sessionDetailProvider(race.sessionId));
    final extras = lastRaceExtrasOf(detail.valueOrNull);
    final map = _map(ref, detail);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _stackedMaxWidth) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(_tilePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (map != null) ...[
                    SizedBox(height: _stackedMapHeight, child: map),
                    const SizedBox(height: _sectionGap),
                  ],
                  _RaceInfo(race: race, extras: extras, fill: false),
                ],
              ),
            ),
          );
        }
        // 타일 바깥 높이를 고정해 넓은 보드에서 오른쪽 열과 바닥이 맞는다.
        return SizedBox(
          height: height ?? kLastRaceTileHeight,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(_tilePadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (map != null) ...[
                    Expanded(flex: _mapFlex, child: map),
                    const SizedBox(width: _mapInfoGap),
                  ],
                  Expanded(flex: _infoFlex, child: _RaceInfo(race: race, extras: extras, fill: true)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 서킷 그림: 이 레이스의 내 랩(최고 랩, 없으면 저장된 첫 랩)에 위치가 있으면 그 랩으로 그린 섹터 색 지도
  /// (레이스 리뷰 지도와 같은 그림), 없으면 서킷 윤곽, 둘 다 없으면 null.
  /// 세션 상세·랩 트레이스·공식 코너를 받는 동안은 빈 칸(윤곽 → 섹터 지도로 바뀌어 보이지 않게).
  Widget? _map(WidgetRef ref, AsyncValue<SessionDetail> detail) {
    final outline = ref.watch(trackOutlinesProvider).valueOrNull?[race.trackName];
    final corners = ref.watch(trackCornersProvider);
    final mapLap = switch (detail.valueOrNull) {
      final SessionDetail value => sessionMapLap(value),
      null => null,
    };
    final lapId = mapLap?.lapId;
    final trace = lapId == null ? null : ref.watch(lapTraceProvider(lapId));
    if (detail.isLoading || corners.isLoading || (trace?.isLoading ?? false)) {
      return const SizedBox.shrink();
    }
    final lapTrace = trace?.valueOrNull;
    if (mapLap != null && lapTrace != null && lapTrace.hasPositions) {
      return _SectorBoardMap(
        trace: lapTrace,
        sectors: sessionLapSectors(mapLap),
        officialCorners: corners.valueOrNull?[race.trackName],
      );
    }
    return outline == null ? null : _TrackBoardMap(outline: outline);
  }
}

/// 섹터 색 서킷 그림(어두운 테두리 + 섹터 색 선 + 코너 번호 배지)을 칸 가득 그리고, 섹터를 알면 아래에 섹터 범례.
class _SectorBoardMap extends StatelessWidget {
  const _SectorBoardMap({required this.trace, required this.sectors, required this.officialCorners});

  final LapTrace trace;
  final List<LapSector> sectors;
  final List<OfficialCorner>? officialCorners;

  @override
  Widget build(BuildContext context) {
    final sectorIndexes = track.sectorIndexesOf(trace.timeMs, sectors);
    return Column(
      key: const ValueKey('last-race-sector-map'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Semantics(
            label: _sectorMapSemanticLabel,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: RaceTrackMapPainter(
                  trace: trace,
                  sectorIndexes: sectorIndexes,
                  corners: resolveLapCorners(trace, officialCorners),
                  labelStyle: cornerLabelStyleOf(context),
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        if (sectorIndexes != null) ...[
          const SizedBox(height: kTrackSectorLegendGap),
          const TrackSectorLegend(),
        ],
      ],
    );
  }
}

/// `LAST RACE` 머리글 + 오른쪽 굵은 시즌 줄(`Driver Career Season 1 · R9`).
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final value = this.value;
    return Row(
      children: [
        Text(
          _eyebrowLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: _eyebrowLetterSpacing,
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: _eyebrowGap),
          Expanded(
            child: Text(
              value,
              key: const ValueKey('last-race-season'),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: _seasonLetterSpacing),
            ),
          ),
        ],
      ],
    );
  }
}

/// 결과 열: 머리글 · 트랙 · 큰 순위 · 출발 대비 줄 · 결과 표 · 버튼. [fill]이면 버튼을 맨 아래에 붙인다(고정 높이 타일).
class _RaceInfo extends StatelessWidget {
  const _RaceInfo({required this.race, required this.extras, required this.fill});

  final SessionSummary race;
  final LastRaceExtras extras;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final round = extras.round;
    final seasonLine = [gameModeLine(race.gameMode, race.seasonNumber), if (round != null) 'R$round'].join(_separator);
    final status = race.myResultStatus;
    final retired = status != null && !isRunningOrFinished(status);
    final position = race.myPosition;
    final positionText = retired ? resultStatusLabel(status) : (position == null ? kNoValueText : 'P$position');
    final bestLap = race.myBestLapTimeMs;
    final pitStops = extras.pitStops;
    final points = race.myPoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _Eyebrow(value: seasonLine),
        const SizedBox(height: _smallGap),
        Row(
          children: [
            TrackFlag(countryCode: race.countryCode, size: _flagSize),
            const SizedBox(width: _flagGap),
            Flexible(
              child: Text(
                race.trackName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: _titleFontSize, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '$_separator${sessionKindName(race.sessionKind, sprintWeekend: race.isSprintWeekend)}',
              style: theme.textTheme.titleMedium?.copyWith(color: palette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: _smallGap),
        Text(
          positionText,
          key: const ValueKey('last-race-position'),
          style: theme.textTheme.displayMedium?.merge(kTabularStyle).copyWith(
                fontSize: _positionFontSize,
                fontWeight: FontWeight.w800,
                height: _tightLineHeight,
                // 강조색 계열이되 밝은 표면에서도 읽히는 링크 색(어두운 테마는 앰버 그대로).
                color: retired ? palette.danger : palette.link,
              ),
        ),
        const SizedBox(height: _smallGap),
        _StartLine(race: race, winnerGap: extras.winnerGap),
        const SizedBox(height: _sectionGap),
        _ResultRow(
          key: const ValueKey('last-race-best-lap'),
          label: _bestLapLabel,
          value: bestLap == null ? kNoValueText : formatLapTime(bestLap),
          color: extras.fastestLap ? AppColors.fastestLap : null,
        ),
        if (pitStops != null)
          _ResultRow(
            key: const ValueKey('last-race-pits'),
            label: _pitStopsLabel,
            value: '$pitStops$_pitStopsSuffix',
          ),
        _ResultRow(
          key: const ValueKey('last-race-points'),
          label: _pointsLabel,
          value: points == null ? kNoValueText : '$points',
        ),
        if (fill) const Spacer() else const SizedBox(height: _sectionGap),
        Wrap(
          spacing: _buttonGap,
          runSpacing: _buttonGap,
          children: [
            if (extras.hasHighlights)
              FilledButton.icon(
                key: const ValueKey('last-race-highlights'),
                onPressed: () => context.go(sessionHighlightsLocation(race.sessionId)),
                icon: const Icon(Icons.play_arrow, size: _buttonIconSize),
                label: const Text(_highlightsLabel),
              ),
            // 하이라이트가 없으면 세션 열기가 유일한 동작이라 채운 버튼으로 그린다.
            if (extras.hasHighlights)
              OutlinedButton(
                key: const ValueKey('last-race-open'),
                onPressed: () => context.go(sessionLocation(race.sessionId)),
                child: const Text(_openSessionLabel),
              )
            else
              FilledButton(
                key: const ValueKey('last-race-open'),
                onPressed: () => context.go(sessionLocation(race.sessionId)),
                child: const Text(_openSessionLabel),
              ),
          ],
        ),
      ],
    );
  }
}

/// `P7 출발 · +4 · 우승과 +0:04.218`. 순위 변화는 올라가면 초록, 내려가면 빨강. 보여 줄 값이 없으면 빈 칸.
class _StartLine extends StatelessWidget {
  const _StartLine({required this.race, required this.winnerGap});

  final SessionSummary race;
  final String? winnerGap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final grid = race.myGridPosition;
    final gained = positionsGained(grid: grid, finish: race.myPosition);
    final gap = winnerGap;
    final parts = <InlineSpan>[
      if (grid != null) TextSpan(text: 'P$grid$_gridSuffix'),
      if (gained != null)
        TextSpan(
          text: positionsGainedText(gained),
          style: TextStyle(
            color: gained > 0 ? palette.success : (gained < 0 ? palette.danger : palette.textMuted),
            fontWeight: FontWeight.w700,
          ),
        ),
      if (gap != null) TextSpan(text: '$_winnerGapPrefix$gap'),
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const TextSpan(text: _separator),
          parts[i],
        ],
      ]),
      key: const ValueKey('last-race-start'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge?.merge(kTabularStyle).copyWith(color: palette.textMuted),
    );
  }
}

/// 결과 표 한 줄: 흐린 라벨 + 오른쪽 굵은 값, 아래 구분선.
class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Container(
      height: _resultRowHeight,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.border))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted))),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.merge(kTabularStyle).copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// 서킷 윤곽을 칸 가득(비율 유지) 그린다.
class _TrackBoardMap extends StatelessWidget {
  const _TrackBoardMap({required this.outline});

  final TrackOutline outline;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('last-race-track'),
      painter: _TrackBoardPainter(outline: outline, bandColor: context.palette.border),
      size: Size.infinite,
    );
  }
}

/// 정규화 윤곽 → 굵은 노면 띠 + 얇은 강조색 선(닫힌 선).
class _TrackBoardPainter extends CustomPainter {
  const _TrackBoardPainter({required this.outline, required this.bandColor});

  final TrackOutline outline;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.points.length < 2 || size.isEmpty) {
      return;
    }
    const inset = _trackBandWidth;
    final scaleX = (size.width - inset * 2) / outline.width;
    final scaleY = (size.height - inset * 2) / outline.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    if (scale <= 0) {
      return;
    }
    final offset = Offset(
      (size.width - outline.width * scale) / 2,
      (size.height - outline.height * scale) / 2,
    );
    final first = outline.points.first;
    final path = Path()..moveTo(offset.dx + first.dx * scale, offset.dy + first.dy * scale);
    for (final p in outline.points.skip(1)) {
      path.lineTo(offset.dx + p.dx * scale, offset.dy + p.dy * scale);
    }
    path.close();
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = bandColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _trackBandWidth
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(
        path,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = _trackLineWidth
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_TrackBoardPainter oldDelegate) =>
      oldDelegate.outline != outline || oldDelegate.bandColor != bandColor;
}
