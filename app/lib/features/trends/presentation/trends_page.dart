import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/layout/page_padding.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/empty_state_card.dart';
import '../../../core/widgets/error_retry.dart';
import '../../../core/widgets/menu_items.dart';
import '../../../core/widgets/page_loading_bar.dart';
import '../../sessions/presentation/session_widgets.dart';
import '../data/trends_repository.dart';
import '../domain/trends_models.dart';
import 'trend_chart.dart';

const String _title = 'Trends';
const String _errorMessage = '추세를 불러오지 못했어요.';
const String _emptyMessage = '아직 기록된 레이스·랩이 없어요.';
const String _noData = '아직 데이터가 없어요.';

const String _raceResultsTitle = 'Race Results';
const String _aiTitle = 'AI Difficulty';
const String _racePaceTitle = 'Race Pace vs Teammate';
const String _qualiTitle = 'Qualifying vs Teammate';
const String _fieldTitle = 'Pace vs Field';
const String _consistencyTitle = 'Consistency';
const String _weeklyTitle = 'Laps per Week';
const String _progressionTitle = 'Lap Time Progression';

const String _raceResultsCaption = '선 = 결과, 흐린 점 = 출발 그리드';
const String _teammateCaption = '아래(초록) = 같은 차 AI 팀메이트보다 빠름';
const String _fieldCaption = '내 최고 랩 대 AI 최고 랩 중앙값 · 아래(초록) = 빠름';
const String _consistencyCaption = '깨끗한 랩(첫 랩·피트 제외) 표준편차 · 낮을수록 꾸준함';
const String _progressionCaption = '선 = 그때까지 최고 랩, 흐린 점 = 그 세션 최고 랩';

/// 넓은 화면에서 카드 둘을 나란히 두는 최소 폭·간격.
const double _pairRowWidth = 1100;
const double _cardGap = 20;
const double _titleGap = 16;
const double _captionGap = 8;
const int _msPerSecond = 1000;
const int _secondsDigits = 3;
const int _percentDigits = 1;

/// 세로 눈금의 초·랩타임 소수 자리(왼쪽 칸에 들어가게 짧게).
const int _tickSecondsDigits = 1;
const int _tickLapTimeTrim = 2;

final DateFormat _tickFormat = DateFormat('MM.dd');

/// 내 성과 추세(Trends 메뉴): 레이스 결과·AI 난이도·팀메이트 대비 레이스/예선 페이스·필드 대비 페이스·꾸준함·주행량·트랙별 최고 랩 변화.
/// 모두 시간 순 그래프이고, 점에 마우스를 올리거나 누르면 그 레이스(세션)와 값이 보인다. 넓으면 두 장씩 나란히 둔다.
class TrendsPage extends ConsumerWidget {
  const TrendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trends = ref.watch(trendsProvider);
    return ListView(
      padding: pagePadding(context),
      children: [
        Text(_title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: _titleGap),
        trends.when(
          loading: () => const PageLoadingBar(),
          error: (e, _) => ErrorRetry(error: e, fallbackMessage: _errorMessage, onRetry: () => ref.invalidate(trendsProvider)),
          data: (data) => data.races.isEmpty && data.tracks.isEmpty
              ? const EmptyStateCard(message: _emptyMessage)
              : _TrendsBoard(trends: data),
        ),
      ],
    );
  }
}

class _TrendsBoard extends StatelessWidget {
  const _TrendsBoard({required this.trends});

  final Trends trends;

  @override
  Widget build(BuildContext context) {
    final races = trends.races;
    final cards = [
      _ChartCard(
        key: const ValueKey('trend-race-results'),
        title: _raceResultsTitle,
        caption: _raceResultsCaption,
        chart: TrendChart(
          points: [
            for (final r in races)
              TrendPoint(
                label: _raceLabel(r),
                tick: _tickFormat.format(r.classifiedAt.toLocal()),
                value: r.position?.toDouble(),
                secondary: r.grid?.toDouble(),
                detail: [if (r.grid != null) 'Grid P${r.grid}', if (r.aiDifficulty != null) 'AI ${r.aiDifficulty}'].join(' · '),
              ),
          ],
          kind: TrendChartKind.line,
          invertY: true,
          formatValue: (v) => 'P${v.round()}',
          semanticLabel: _raceResultsTitle,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-ai-difficulty'),
        title: _aiTitle,
        chart: TrendChart(
          points: [
            for (final r in races)
              TrendPoint(
                label: _raceLabel(r),
                tick: _tickFormat.format(r.classifiedAt.toLocal()),
                value: r.aiDifficulty?.toDouble(),
              ),
          ],
          kind: TrendChartKind.line,
          formatValue: (v) => '${v.round()}',
          semanticLabel: _aiTitle,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-race-pace'),
        title: _racePaceTitle,
        caption: _teammateCaption,
        chart: _gapBars(
          [
            for (final r in races)
              TrendPoint(
                label: _raceLabel(r),
                tick: _tickFormat.format(r.classifiedAt.toLocal()),
                value: _seconds(r.teammatePaceGapPerLapMs),
                detail: _positionDetail(r),
              ),
          ],
          _racePaceTitle,
          perLap: true,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-qualifying'),
        title: _qualiTitle,
        caption: _teammateCaption,
        chart: _gapBars(
          [
            for (final q in trends.qualifying)
              TrendPoint(
                label: '${_tickFormat.format(q.at.toLocal())} ${q.trackName}',
                tick: _tickFormat.format(q.at.toLocal()),
                value: _seconds(q.teammateGapMs),
                detail: [if (q.position != null) 'P${q.position}', if (q.aiDifficulty != null) 'AI ${q.aiDifficulty}'].join(' · '),
              ),
          ],
          _qualiTitle,
          perLap: false,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-field-pace'),
        title: _fieldTitle,
        caption: _fieldCaption,
        chart: TrendChart(
          points: [
            for (final r in races)
              TrendPoint(
                label: _raceLabel(r),
                tick: _tickFormat.format(r.classifiedAt.toLocal()),
                value: r.fieldPaceGapPercent,
                detail: _positionDetail(r),
              ),
          ],
          kind: TrendChartKind.bars,
          formatValue: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(_percentDigits)}%',
          semanticLabel: _fieldTitle,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-consistency'),
        title: _consistencyTitle,
        caption: _consistencyCaption,
        chart: TrendChart(
          points: [
            for (final r in races)
              TrendPoint(
                label: _raceLabel(r),
                tick: _tickFormat.format(r.classifiedAt.toLocal()),
                value: _seconds(r.consistencyMs),
                detail: r.cleanLaps == null ? null : '${r.cleanLaps} clean laps',
              ),
          ],
          kind: TrendChartKind.line,
          formatValue: (v) => '${v.toStringAsFixed(_secondsDigits)}s',
          semanticLabel: _consistencyTitle,
        ),
      ),
      _ChartCard(
        key: const ValueKey('trend-weekly-laps'),
        title: _weeklyTitle,
        chart: TrendChart(
          points: [
            for (final w in trends.weeklyLaps)
              TrendPoint(
                label: '${_tickFormat.format(w.weekStart)} ~',
                tick: _tickFormat.format(w.weekStart),
                value: w.laps.toDouble(),
              ),
          ],
          kind: TrendChartKind.bars,
          neutralBars: true,
          formatValue: (v) => '${v.round()}',
          semanticLabel: _weeklyTitle,
        ),
      ),
      _ProgressionCard(tracks: trends.tracks),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _pairRowWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: _cardGap),
                cards[i],
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i += 2) ...[
              if (i > 0) const SizedBox(height: _cardGap),
              EqualHeightRow(gap: _cardGap, children: [cards[i], if (i + 1 < cards.length) cards[i + 1]]),
            ],
          ],
        );
      },
    );
  }

  /// 팀메이트 대비 차이 막대(초, 음수 = 내가 빠름 = 초록).
  static TrendChart _gapBars(List<TrendPoint> points, String title, {required bool perLap}) => TrendChart(
        points: points,
        kind: TrendChartKind.bars,
        formatValue: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(_secondsDigits)}s${perLap ? ' / lap' : ''}',
        formatTick: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(_tickSecondsDigits)}s',
        semanticLabel: title,
      );

  static String _raceLabel(RaceTrend r) =>
      '${_tickFormat.format(r.classifiedAt.toLocal())} ${r.trackName}${r.isSprint ? ' · Sprint' : ''}';

  static String? _positionDetail(RaceTrend r) => r.position == null ? null : 'P${r.position}';

  static double? _seconds(int? ms) => ms == null ? null : ms / _msPerSecond;
}

/// 그래프 카드: 제목 + (있으면) 한 줄 읽는 법 + 그래프. 점이 하나도 없으면 안내 문구.
class _ChartCard extends StatelessWidget {
  const _ChartCard({super.key, required this.title, required this.chart, this.caption, this.trailing});

  final String title;
  final TrendChart chart;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textMuted);
    final hasData = chart.points.any((p) => p.value != null);
    return SessionCard(
      title: title,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (caption case final text?) ...[Text(text, style: muted), const SizedBox(height: _captionGap)],
          if (hasData) chart else Text(_noData, style: muted),
        ],
      ),
    );
  }
}

/// 트랙별 최고 랩 변화: 오른쪽 위 메뉴로 트랙을 고른다(기본 = 랩이 가장 많은 트랙).
class _ProgressionCard extends StatefulWidget {
  const _ProgressionCard({required this.tracks});

  final List<TrackProgression> tracks;

  @override
  State<_ProgressionCard> createState() => _ProgressionCardState();
}

class _ProgressionCardState extends State<_ProgressionCard> {
  String? _trackId;

  @override
  Widget build(BuildContext context) {
    final tracks = widget.tracks;
    final selected = tracks.where((t) => t.trackId == _trackId).firstOrNull ?? tracks.firstOrNull;
    return _ChartCard(
      key: const ValueKey('trend-progression'),
      title: _progressionTitle,
      caption: _progressionCaption,
      trailing: selected == null
          ? null
          : PopupMenuButton<String>(
              key: const ValueKey('trend-progression-track'),
              tooltip: _progressionTitle,
              onSelected: (id) => setState(() => _trackId = id),
              itemBuilder: (_) => [
                for (final t in tracks)
                  CheckMenuItem<String>(value: t.trackId, checked: t.trackId == selected.trackId, label: t.trackName),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(selected.trackName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
      chart: TrendChart(
        points: [
          for (final p in selected?.points ?? const <TrackProgressionPoint>[])
            TrendPoint(
              label: '${_tickFormat.format(p.at.toLocal())} · ${p.sessionType}',
              tick: _tickFormat.format(p.at.toLocal()),
              value: p.bestSoFarMs.toDouble(),
              secondary: p.sessionBestMs.toDouble(),
              detail: 'Session best ${formatLapTime(p.sessionBestMs)}',
            ),
        ],
        kind: TrendChartKind.line,
        formatValue: (v) => formatLapTime(v.round()),
        formatTick: _lapTimeTick,
        semanticLabel: _progressionTitle,
      ),
    );
  }
}

/// 세로 눈금용 짧은 랩타임(`1:24.0`, 소수 첫째 자리). 순수 함수.
String _lapTimeTick(double ms) {
  final text = formatLapTime(ms.round());
  return text.substring(0, text.length - _tickLapTimeTrim);
}
