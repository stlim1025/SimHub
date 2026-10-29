import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/layout/equal_height.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../domain/race_review.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

const String _title = 'Race Review';
const String _collapseLabel = '레이스 리뷰 접기';
const String _expandLabel = '레이스 리뷰 펼치기';
const String _fieldMedianLabel = 'AI 중앙값';
const String _paceRankLabel = '페이스 순위';
const String _myMedianLabel = '내 중앙값';
const String _toFieldLabel = 'AI 중앙값 대비';
const String _gridLabel = '출발';
const String _finishLabel = '완주';
const String _winnerLabel = '우승 차';
const String _trendLabel = '랩타임 추세';
const String _wearLabel = '마모';
const String _stintMedianLabel = '중앙값';
const String _endLifeLabel = '끝 수명';
const String _firstStoreLabel = '1랩 끝';
const String _lastStoreLabel = '끝';
const String _deployLabel = '배포';
const String _harvestLabel = '회수';
const String _lowLapsLabel = '바닥 랩';
const String _fullLapsLabel = '가득 찬 랩';
const String _perLapCaption = '랩당';
const String _storeChartCaption = '랩 끝 잔량';
const String _flowChartCaption = '랩별 배포 · 회수';

const Map<ReviewGrade, String> _gradeText = {
  ReviewGrade.good: '좋음',
  ReviewGrade.fair: '보통',
  ReviewGrade.poor: '아쉬움',
};

/// 넓으면 항목 블록을 두 열로.
const double _twoColumnWidth = 760;
const double _blockGap = 16;
const double _blockPadding = 16;
const double _blockRadius = 10;
const double _innerGap = 12;
const double _noteGap = 6;
const double _noteIconSize = 16;
const double _noteIconGap = 6;
const double _noteFontSize = 13;
const double _noteLineHeight = 1.45;
const double _blockTitleSize = 15;
const double _pillRadius = 999;
const EdgeInsets _pillPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 3);
const double _pillFontSize = 12;
const double _pillAlpha = 0.16;

/// 큰 숫자·작은 설명.
const double _bigValueSize = 22;
const double _captionSize = 11;
const double _statGap = 20;

/// 페이스 막대: 이름 칸·값 칸 폭, 막대 높이, 가장 빠른 차(길이 0)도 보이게 하는 최소 비율, 다른 차·AI 중앙값 막대 투명도.
const double _ladderNameWidth = 92;
const double _ladderValueWidth = 84;
const double _ladderBarHeight = 10;
const double _ladderRowGap = 6;
const double _ladderGap = 8;
const double _ladderMinFactor = 0.02;
const double _ladderOtherAlpha = 0.7;
const double _ladderFieldAlpha = 0.4;

/// 스틴트 타임라인 높이·랩 눈금 줄 높이, 컴파운드 이름을 다 쓸 최소 랩 수.
const double _timelineHeight = 24;
const double _timelineRadius = 6;
const double _segmentGap = 1;
const double _lapTickHeight = 16;
const double _lapTickWidth = 28;
const double _segmentLabelSize = 11;
const int _segmentNameMinLaps = 6;

/// 피트 칩.
const double _chipCircleSize = 16;
const double _chipGap = 6;
const EdgeInsets _chipPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const double _chipRadius = 8;
const double _arrowIconSize = 14;

/// 수치 칸.
const EdgeInsets _metricPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const double _metricRadius = 6;
const double _metricValueSize = 13;
const double _metricMinWidth = 96;

/// 타이어 수명 막대.
const double _lifeBarHeight = 8;
const double _lifeLabelWidth = 52;
const double _lifeValueWidth = 44;
const double _stintCircleSize = 20;
const double _stintGap = 14;

/// 배터리 게이지: 몸통·꼭지 크기, 테두리, 잔량 색 경계(비율).
const double _batteryWidth = 34;
const double _batteryHeight = 56;
const double _batteryCapWidth = 14;
const double _batteryCapHeight = 4;
const double _batteryBorder = 2;
const double _batteryRadius = 5;
const double _batteryInset = 3;
const double _batteryLowFraction = 0.15;
const double _batteryFullFraction = 0.95;
const double _batteryGaugeWidth = 64;
const double _batteryGaugeGap = 4;
const double _flowLabelWidth = 36;
const double _flowValueWidth = 64;
const double _flowBarHeight = 10;
const double _batteryWideWidth = 380;

/// 랩별 그래프: 그릴 최소 랩 수, 높이, 막대가 칸에서 차지하는 비율·최소·최대 폭(랩이 적어도 막대가 뭉툭해지지 않게)·모서리, 눈금 간격.
const int _lapChartMinLaps = 2;
const double _lapChartHeight = 64;
const double _lapBarFill = 0.7;
const double _lapBarMinWidth = 1;
const double _lapBarMaxWidth = 10;
const double _lapBarRadius = 1.5;
const double _lapChartTickGap = 2;

const double _msPerSecond = 1000;
const double _percent = 100;
const double _joulesPerKj = 1000;
const int _chipSecondDigits = 1;
const int _lapSecondDigits = 3;
const int _wearDigits = 1;

String _signedSeconds(int ms, {int digits = _lapSecondDigits}) =>
    '${ms >= 0 ? '+' : '−'}${(ms.abs() / _msPerSecond).toStringAsFixed(digits)}초';

String _seconds(int ms, {int digits = _lapSecondDigits}) => '${(ms.abs() / _msPerSecond).toStringAsFixed(digits)}초';

Color _gradeColor(ReviewGrade grade, AppPalette palette) => switch (grade) {
      ReviewGrade.good => palette.success,
      ReviewGrade.fair => palette.textMuted,
      ReviewGrade.poor => palette.danger,
    };

/// 레이스 총평 카드: 한 줄 총평, 항목(페이스·전략·타이어·배터리)마다 평가 + 그림 + 짚을 것. 넓으면 두 열.
/// 제목 줄을 누르면 접고 편다(처음엔 펼침).
class RaceReviewCard extends StatefulWidget {
  const RaceReviewCard({super.key, required this.review});

  final RaceReview review;

  @override
  State<RaceReviewCard> createState() => _RaceReviewCardState();
}

class _RaceReviewCardState extends State<RaceReviewCard> {
  var _expanded = true;

  RaceReview get review => widget.review;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = raceReviewSections(review);
    final summary = raceReviewSummary(sections);
    final blocks = [
      for (final s in sections) _SectionBlock(title: s.title, section: s.section, visual: _visualFor(s.title)),
    ];
    return SessionCard(
      key: const ValueKey('race-review'),
      title: _title,
      collapsed: !_expanded,
      onTitleTap: _toggle,
      trailing: Icon(
        _expanded ? Icons.expand_less : Icons.expand_more,
        key: const ValueKey('race-review-toggle'),
        semanticLabel: _expanded ? _collapseLabel : _expandLabel,
        color: context.palette.textMuted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary != null) ...[
            Text(summary, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: _blockGap),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= _twoColumnWidth ? 2 : 1;
              final rows = <Widget>[
                for (var i = 0; i < blocks.length; i += columns)
                  // 나란한 블록은 같은 높이로(내용이 짧은 쪽도 바닥을 맞춘다).
                  EqualHeightRow(
                    gap: _blockGap,
                    children: [
                      for (var j = 0; j < columns; j++)
                        i + j < blocks.length ? blocks[i + j] : const SizedBox.shrink(),
                    ],
                  ),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const SizedBox(height: _blockGap),
                    rows[i],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _visualFor(String title) {
    final pace = review.pace;
    final battery = review.battery;
    return switch (title) {
      kPaceSectionTitle when pace != null => _PaceChart(pace: pace),
      kStrategySectionTitle => _StrategyView(strategy: review.strategy, stints: review.stints),
      kTyreSectionTitle => _StintList(stints: review.stints),
      kBatterySectionTitle when battery != null => _BatteryView(battery: battery),
      _ => null,
    };
  }
}

/// 항목 블록: 제목·평가 알약, 그림, 짚을 것(관찰 → 할 것).
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.section, this.visual});

  final String title;
  final ReviewSection section;
  final Widget? visual;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _gradeColor(section.grade, palette);
    final visual = this.visual;
    return Container(
      padding: const EdgeInsets.all(_blockPadding),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(_blockRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: _blockTitleSize)),
              ),
              Container(
                padding: _pillPadding,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: _pillAlpha),
                  borderRadius: BorderRadius.circular(_pillRadius),
                ),
                child: Text(
                  _gradeText[section.grade]!,
                  key: ValueKey('race-review-grade-$title'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: _pillFontSize),
                ),
              ),
            ],
          ),
          if (visual != null) ...[
            const SizedBox(height: _innerGap),
            visual,
          ],
          if (section.lines.isNotEmpty) const SizedBox(height: _innerGap),
          for (final (i, line) in section.lines.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : _noteGap),
              child: _Note(line: line),
            ),
        ],
      ),
    );
  }
}

/// 짚을 것 한 줄: `관찰 → 할 것`이면 전구 아이콘과 함께 할 것을 굵게.
class _Note extends StatelessWidget {
  const _Note({required this.line});

  static const String _adviceArrow = ' → ';

  final String line;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final split = line.indexOf(_adviceArrow);
    final observation = split < 0 ? line : line.substring(0, split);
    final advice = split < 0 ? null : line.substring(split + _adviceArrow.length);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          advice == null ? Icons.chevron_right : Icons.lightbulb_outline,
          size: _noteIconSize,
          color: advice == null ? palette.textMuted : AppColors.accent,
        ),
        const SizedBox(width: _noteIconGap),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: observation),
                if (advice != null) ...[
                  const TextSpan(text: _adviceArrow),
                  TextSpan(text: advice, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
            style: TextStyle(fontSize: _noteFontSize, height: _noteLineHeight, color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// 큰 숫자 + 작은 설명.
class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.caption, this.unit, this.color});

  final String value;
  final String caption;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unit = this.unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: kTabularStyle.copyWith(fontSize: _bigValueSize, fontWeight: FontWeight.w800, color: color),
              ),
              if (unit != null) TextSpan(text: ' $unit', style: TextStyle(color: palette.textMuted)),
            ],
          ),
        ),
        Text(caption, style: TextStyle(fontSize: _captionSize, color: palette.textMuted)),
      ],
    );
  }
}

/// 작은 수치 칸 하나의 내용: 이름·값(색)·보조 값.
typedef _MetricData = ({String label, String value, String? sub, Color? color});

/// 작은 수치 칸 묶음: 칸 높이·최소 폭을 맞춘다(한 칸이라도 보조 값이 있으면 모든 칸이 그 줄을 비워 둔다).
class _MetricGroup extends StatelessWidget {
  const _MetricGroup(this.metrics);

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reserveSub = metrics.any((m) => m.sub != null);
    final captionStyle = TextStyle(fontSize: _captionSize, color: palette.textMuted);
    return Wrap(
      spacing: _chipGap,
      runSpacing: _chipGap,
      children: [
        for (final m in metrics)
          Container(
            constraints: const BoxConstraints(minWidth: _metricMinWidth),
            padding: _metricPadding,
            decoration: BoxDecoration(color: palette.tableHeader, borderRadius: BorderRadius.circular(_metricRadius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.label, style: captionStyle),
                Text(
                  m.value,
                  style: kTabularStyle.copyWith(fontSize: _metricValueSize, fontWeight: FontWeight.w700, color: m.color),
                ),
                if (reserveSub) Text(m.sub ?? '', style: kTabularStyle.merge(captionStyle)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 가로 막대 하나(바탕 + 채움).
class _Bar extends StatelessWidget {
  const _Bar({required this.factor, required this.color, required this.height});

  final double factor;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Container(height: height, decoration: BoxDecoration(color: context.palette.tableHeader, borderRadius: radius)),
        FractionallySizedBox(
          widthFactor: factor.clamp(0, 1).toDouble(),
          child: Container(height: height, decoration: BoxDecoration(color: color, borderRadius: radius)),
        ),
      ],
    );
  }
}

/// 페이스: 순위·내 중앙값·AI 중앙값 대비, 그리고 깨끗한 랩 중앙값 막대(길수록 느리다, 오른쪽 = 나와의 차이).
class _PaceChart extends StatelessWidget {
  const _PaceChart({required this.pace});

  final RacePaceReview pace;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final toField = pace.myMedianMs - pace.fieldMedianMs;
    final ahead = pace.aheadMedianMs;
    final aheadName = pace.aheadName;
    final behind = pace.behindMedianMs;
    final behindName = pace.behindName;
    final rows = <({String name, int ms, bool me, bool field})>[
      (name: pace.fastestName, ms: pace.fastestMedianMs, me: false, field: false),
      if (ahead != null && aheadName != null && aheadName != pace.fastestName)
        (name: aheadName, ms: ahead, me: false, field: false),
      (name: kPlayerName, ms: pace.myMedianMs, me: true, field: false),
      if (behind != null && behindName != null && behindName != pace.fastestName)
        (name: behindName, ms: behind, me: false, field: false),
      (name: _fieldMedianLabel, ms: pace.fieldMedianMs, me: false, field: true),
    ]..sort((a, b) => a.ms.compareTo(b.ms));
    final fastest = rows.first.ms;
    final span = math.max(1, rows.last.ms - fastest);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: _statGap,
          runSpacing: _innerGap,
          children: [
            _BigStat(value: '${pace.rank}위', unit: '/ ${pace.rankedCars}대', caption: _paceRankLabel),
            _BigStat(value: formatLapTime(pace.myMedianMs), caption: _myMedianLabel),
            _BigStat(
              value: _signedSeconds(toField),
              caption: _toFieldLabel,
              color: _gradeColor(paceGrade(pace), palette),
            ),
          ],
        ),
        const SizedBox(height: _innerGap),
        for (final (i, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _ladderRowGap),
            child: Row(
              children: [
                SizedBox(
                  width: _ladderNameWidth,
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: row.me ? FontWeight.w700 : null,
                      color: row.field ? palette.textMuted : null,
                    ),
                  ),
                ),
                const SizedBox(width: _ladderGap),
                Expanded(
                  child: _Bar(
                    factor: math.max(_ladderMinFactor, (row.ms - fastest) / span),
                    color: row.me
                        ? AppColors.accent
                        : palette.textMuted.withValues(alpha: row.field ? _ladderFieldAlpha : _ladderOtherAlpha),
                    height: _ladderBarHeight,
                  ),
                ),
                SizedBox(
                  width: _ladderValueWidth,
                  child: Text(
                    row.me ? formatLapTime(row.ms) : _signedSeconds(row.ms - pace.myMedianMs),
                    textAlign: TextAlign.right,
                    style: kTabularStyle.copyWith(
                      fontWeight: row.me ? FontWeight.w700 : null,
                      color: row.me ? null : palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 전략: 출발 → 완주, 스틴트 타임라인(컴파운드 색, 피트 랩 눈금), 피트 칩, 우승 차 전략.
class _StrategyView extends StatelessWidget {
  const _StrategyView({required this.strategy, required this.stints});

  final RaceStrategyReview strategy;
  final List<RaceStintReview> stints;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final grid = strategy.gridPosition;
    final finish = strategy.finishPosition;
    final winnerStops = strategy.winnerStops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (grid != null && finish != null)
          // 화살표·순위 변화를 큰 숫자 줄(기준선)에 맞춘다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _BigStat(value: 'P$grid', caption: _gridLabel),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _innerGap),
                child: Icon(Icons.arrow_forward, color: palette.textMuted),
              ),
              _BigStat(value: 'P$finish', caption: _finishLabel, color: palette.podiumFor(finish)),
              const SizedBox(width: _innerGap),
              PositionChangeText(change: grid - finish),
            ],
          ),
        if (stints.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          _StintTimeline(stints: stints, pitLaps: [for (final s in strategy.pitStops) s.lap]),
        ],
        if (strategy.pitStops.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          Wrap(
            spacing: _chipGap,
            runSpacing: _chipGap,
            children: [
              for (final stop in strategy.pitStops) _PitChip(stop: stop, fieldLossMs: strategy.fieldPitLossMs),
            ],
          ),
        ],
        if (winnerStops != null && strategy.winnerCompounds.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          Wrap(
            spacing: _chipGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_winnerLabel, style: TextStyle(color: palette.textMuted)),
              ..._compoundFlow(strategy.winnerCompounds, palette),
              Text('$winnerStops스톱', style: TextStyle(color: palette.textMuted)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 컴파운드 원을 화살표로 잇는다.
List<Widget> _compoundFlow(List<String> compounds, AppPalette palette) => [
      for (final (i, compound) in compounds.indexed) ...[
        if (i > 0) Icon(Icons.arrow_right_alt, size: _arrowIconSize, color: palette.textMuted),
        TyreCompoundCircle(compound: compound, tooltip: compound, size: _chipCircleSize),
      ],
    ];

/// 스틴트 타임라인: 1랩 ~ 마지막 랩을 스틴트 컴파운드 색으로 채우고(빈 랩은 회색), 아래에 시작·피트·마지막 랩 눈금.
class _StintTimeline extends StatelessWidget {
  const _StintTimeline({required this.stints, required this.pitLaps});

  final List<RaceStintReview> stints;
  final List<int> pitLaps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sorted = [...stints]..sort((a, b) => a.startLap.compareTo(b.startLap));
    final total = math.max(sorted.map((s) => s.endLap).reduce(math.max), pitLaps.fold(0, math.max));
    final segments = <({String? compound, int laps})>[];
    var cursor = 1;
    for (final stint in sorted) {
      if (stint.startLap > cursor) {
        segments.add((compound: null, laps: stint.startLap - cursor));
      }
      final from = math.max(cursor, stint.startLap);
      if (stint.endLap >= from) {
        segments.add((compound: stint.compound, laps: stint.endLap - from + 1));
        cursor = stint.endLap + 1;
      }
    }
    if (cursor <= total) {
      segments.add((compound: null, laps: total - cursor + 1));
    }
    final ticks = {1, ...pitLaps, total}.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(_timelineRadius),
          child: SizedBox(
            height: _timelineHeight,
            child: Row(
              children: [
                for (final (i, segment) in segments.indexed)
                  Expanded(
                    flex: segment.laps,
                    child: Container(
                      margin: EdgeInsets.only(left: i == 0 ? 0 : _segmentGap),
                      color: segment.compound == null ? palette.border : tyreColorOf(segment.compound!),
                      alignment: Alignment.center,
                      child: segment.compound == null
                          ? null
                          : Text(
                              segment.laps >= _segmentNameMinLaps ? segment.compound! : segment.compound![0],
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                fontSize: _segmentLabelSize,
                                fontWeight: FontWeight.w700,
                                color: AppColors.background,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: _lapTickHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final lap in ticks)
                    Positioned(
                      // 1랩은 왼쪽 끝, 피트 랩·마지막 랩은 그 랩이 끝나는 자리.
                      left: (lap == 1 ? 0 : width * lap / total - _lapTickWidth / 2)
                          .clamp(0, math.max(0, width - _lapTickWidth))
                          .toDouble(),
                      width: _lapTickWidth,
                      child: Text(
                        'L$lap',
                        textAlign: lap == 1
                            ? TextAlign.left
                            : lap == total
                                ? TextAlign.right
                                : TextAlign.center,
                        style: kTabularStyle.copyWith(fontSize: _captionSize, color: palette.textMuted),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 피트 칩: 랩, 바꾼 컴파운드, 순위 변화, 손실(AI 손실) — 평가 색 테두리.
class _PitChip extends StatelessWidget {
  const _PitChip({required this.stop, required this.fieldLossMs});

  final RacePitStopReview stop;
  final int? fieldLossMs;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final grade = pitStopGrade(stop, fieldLossMs);
    final before = stop.positionBefore;
    final after = stop.positionAfter;
    final loss = stop.lossMs;
    final fieldLoss = fieldLossMs;
    return Container(
      padding: _chipPadding,
      decoration: BoxDecoration(
        border: Border.all(color: grade == ReviewGrade.fair ? palette.border : _gradeColor(grade, palette)),
        borderRadius: BorderRadius.circular(_chipRadius),
      ),
      child: Wrap(
        spacing: _chipGap,
        runSpacing: _chipGap / 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('L${stop.lap}', style: kTabularStyle.copyWith(fontWeight: FontWeight.w700)),
          Row(mainAxisSize: MainAxisSize.min, children: _compoundFlow([stop.fromCompound, stop.toCompound], palette)),
          if (before != null && after != null) Text('P$before→P$after', style: kTabularStyle),
          if (loss != null) Text(_seconds(loss, digits: _chipSecondDigits), style: kTabularStyle),
          if (loss != null && fieldLoss != null)
            Text(
              'AI ${_seconds(fieldLoss, digits: _chipSecondDigits)}',
              style: kTabularStyle.copyWith(color: palette.textMuted, fontSize: _captionSize),
            ),
        ],
      ),
    );
  }
}

/// 타이어: 스틴트마다 컴파운드·랩 범위, 끝 수명 막대, 추세·마모·중앙값(같은 컴파운드 AI와).
class _StintList extends StatelessWidget {
  const _StintList({required this.stints});

  final List<RaceStintReview> stints;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, stint) in stints.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _stintGap),
            child: _stintOf(stint, palette),
          ),
      ],
    );
  }

  Widget _stintOf(RaceStintReview stint, AppPalette palette) {
    final life = stint.endLifePct;
    final trend = stint.trendMsPerLap;
    final fieldTrend = stint.fieldTrendMsPerLap;
    final extra = stint.extraTrendMs;
    final wear = stint.wearPerLapPct;
    final median = stint.medianMs;
    final fieldMedian = stint.fieldMedianMs;
    final lifeColor = life == null
        ? palette.textMuted
        : life < kLowTyreLifePct
            ? AppColors.wearCritical
            : life < kHealthyTyreLifePct
                ? AppColors.wearMedium
                : AppColors.wearLow;
    Color? versusField(int mine, int field, int margin) => mine - field >= margin
        ? palette.danger
        : mine - field <= -margin
            ? palette.success
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TyreCompoundCircle(compound: stint.compound, tooltip: stint.compound, size: _stintCircleSize),
            const SizedBox(width: _chipGap),
            Text(
              '${stint.compound} · L${stint.startLap}–L${stint.endLap}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (life != null) ...[
          const SizedBox(height: _noteGap),
          Row(
            children: [
              SizedBox(
                width: _lifeLabelWidth,
                child: Text(_endLifeLabel, style: TextStyle(fontSize: _captionSize, color: palette.textMuted)),
              ),
              Expanded(child: _Bar(factor: life / _percent, color: lifeColor, height: _lifeBarHeight)),
              SizedBox(
                width: _lifeValueWidth,
                child: Text(
                  '${life.round()}%',
                  textAlign: TextAlign.right,
                  style: kTabularStyle.copyWith(fontWeight: FontWeight.w700, color: lifeColor),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: _noteGap),
        _MetricGroup([
          if (trend != null)
            (
              label: _trendLabel,
              value: '${_signedSeconds(trend)}/랩',
              sub: fieldTrend == null ? null : 'AI ${_signedSeconds(fieldTrend)}',
              color: extra == null || fieldTrend == null ? null : versusField(trend, fieldTrend, kTrendMarginMs),
            ),
          if (wear != null)
            (
              label: _wearLabel,
              value: '${wear.toStringAsFixed(_wearDigits)}%/랩',
              sub: null,
              color: wear >= kFastWearPct ? palette.danger : null,
            ),
          if (median != null)
            (
              label: _stintMedianLabel,
              value: formatLapTime(median),
              sub: fieldMedian == null ? null : 'AI ${formatLapTime(fieldMedian)}',
              color: fieldMedian == null ? null : versusField(median, fieldMedian, kPaceMarginMs),
            ),
        ]),
      ],
    );
  }
}

/// 배터리: 1랩 끝·최저·끝 잔량 게이지, 랩당 배포·회수 막대, 바닥·가득 찬 랩 수.
class _BatteryView extends StatelessWidget {
  const _BatteryView({required this.battery});

  final RaceBatteryReview battery;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final deploy = battery.averageDeployJ;
    final harvest = battery.averageHarvestJ;
    final flowMax = math.max(deploy ?? 0, harvest ?? 0);
    final gauges = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BatteryGauge(label: _firstStoreLabel, fraction: battery.firstStoreJ / kErsCapacityJ),
        const SizedBox(width: _batteryGaugeGap),
        _BatteryGauge(label: '최저 · L${battery.minStoreLap}', fraction: battery.minStoreJ / kErsCapacityJ),
        const SizedBox(width: _batteryGaugeGap),
        _BatteryGauge(label: _lastStoreLabel, fraction: battery.lastStoreJ / kErsCapacityJ),
      ],
    );
    final flows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (flowMax > 0) ...[
          Text(_perLapCaption, style: TextStyle(fontSize: _captionSize, color: palette.textMuted)),
          if (deploy != null) _flowRow(_deployLabel, deploy, flowMax, AppColors.accent),
          if (harvest != null) _flowRow(_harvestLabel, harvest, flowMax, palette.success),
          const SizedBox(height: _innerGap),
        ],
        _MetricGroup([
          (
            label: _lowLapsLabel,
            value: '${battery.lowLaps}',
            sub: null,
            color: battery.lowLaps >= kErsFlagLaps ? palette.danger : null,
          ),
          (
            label: _fullLapsLabel,
            value: '${battery.fullLaps}',
            sub: null,
            color: battery.fullLaps >= kErsFlagLaps ? palette.danger : null,
          ),
        ]),
      ],
    );
    final perLap = battery.perLap;
    final flowLaps = [for (final l in perLap) if (l.deployedJ != null || l.harvestedJ != null) l];
    final summary = LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= _batteryWideWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [gauges, const SizedBox(width: _statGap), Expanded(child: flows)],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Align(alignment: Alignment.centerLeft, child: gauges), const SizedBox(height: _innerGap), flows],
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        if (perLap.length >= _lapChartMinLaps) ...[
          const SizedBox(height: _blockGap),
          _LapChart(
            caption: _storeChartCaption,
            laps: [for (final l in perLap) l.lap],
            series: [
              (
                values: [for (final l in perLap) l.storeJ / kErsCapacityJ],
                colorOf: (double v) => _storeColor(v, palette),
              ),
            ],
            maxValue: 1,
          ),
        ],
        if (flowLaps.length >= _lapChartMinLaps) ...[
          const SizedBox(height: _innerGap),
          _LapChart(
            caption: _flowChartCaption,
            laps: [for (final l in flowLaps) l.lap],
            series: [
              (values: [for (final l in flowLaps) l.deployedJ ?? 0], colorOf: (double _) => AppColors.accent),
              (values: [for (final l in flowLaps) l.harvestedJ ?? 0], colorOf: (double _) => palette.success),
            ],
            maxValue: flowLaps.map((l) => math.max(l.deployedJ ?? 0, l.harvestedJ ?? 0)).fold(0, math.max),
          ),
        ],
      ],
    );
  }

  Widget _flowRow(String label, double joules, double max, Color color) => Padding(
        padding: const EdgeInsets.only(top: _noteGap),
        child: Row(
          children: [
            SizedBox(width: _flowLabelWidth, child: Text(label)),
            Expanded(child: _Bar(factor: joules / max, color: color, height: _flowBarHeight)),
            SizedBox(
              width: _flowValueWidth,
              child: Text('${(joules / _joulesPerKj).round()}kJ', textAlign: TextAlign.right, style: kTabularStyle),
            ),
          ],
        ),
      );
}

/// 잔량 비율 → 색(거의 바닥 빨강, 가득 노랑, 그 외 초록).
Color _storeColor(double fraction, AppPalette palette) => fraction < _batteryLowFraction
    ? palette.danger
    : fraction >= _batteryFullFraction
        ? AppColors.wearMedium
        : palette.success;

/// 랩별 막대 계열 하나: 랩마다 값, 값 → 색.
typedef _LapSeries = ({List<double> values, Color Function(double value) colorOf});

/// 랩별 막대 그래프: 설명, 막대(계열이 여럿이면 한 랩에 나란히), 아래 첫·가운데·마지막 랩 눈금.
class _LapChart extends StatelessWidget {
  const _LapChart({required this.caption, required this.laps, required this.series, required this.maxValue});

  final String caption;
  final List<int> laps;
  final List<_LapSeries> series;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tickStyle = kTabularStyle.copyWith(fontSize: _captionSize, color: palette.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(caption, style: TextStyle(fontSize: _captionSize, color: palette.textMuted)),
        const SizedBox(height: _noteGap),
        SizedBox(
          height: _lapChartHeight,
          child: CustomPaint(
            painter: _LapBarsPainter(series: series, maxValue: maxValue, baseline: palette.border),
          ),
        ),
        const SizedBox(height: _lapChartTickGap),
        Row(
          children: [
            Text('L${laps.first}', style: tickStyle),
            const Spacer(),
            Text('L${laps[laps.length ~/ 2]}', style: tickStyle),
            const Spacer(),
            Text('L${laps.last}', style: tickStyle),
          ],
        ),
      ],
    );
  }
}

/// 랩마다 한 칸, 칸 안에 계열 수만큼 막대를 나란히, 아래 기준선.
class _LapBarsPainter extends CustomPainter {
  _LapBarsPainter({required this.series, required this.maxValue, required this.baseline});

  final List<_LapSeries> series;
  final double maxValue;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    final count = series.first.values.length;
    if (count == 0 || maxValue <= 0) {
      return;
    }
    final slot = size.width / count;
    final barWidth = (slot * _lapBarFill / series.length).clamp(_lapBarMinWidth, _lapBarMaxWidth).toDouble();
    final groupWidth = barWidth * series.length;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final left = slot * i + (slot - groupWidth) / 2;
      for (final (k, s) in series.indexed) {
        final value = s.values[i];
        final height = (value / maxValue).clamp(0, 1) * size.height;
        paint.color = s.colorOf(value);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left + barWidth * k, size.height - height, barWidth, height),
            topLeft: const Radius.circular(_lapBarRadius),
            topRight: const Radius.circular(_lapBarRadius),
          ),
          paint,
        );
      }
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = baseline);
  }

  @override
  bool shouldRepaint(_LapBarsPainter old) => old.series != series || old.maxValue != maxValue || old.baseline != baseline;
}

/// 배터리 모양 게이지: 잔량 비율만큼 아래부터 채운다(거의 바닥 빨강, 가득 노랑, 그 외 초록).
class _BatteryGauge extends StatelessWidget {
  const _BatteryGauge({required this.label, required this.fraction});

  final String label;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = fraction.clamp(0, 1).toDouble();
    final color = _storeColor(value, palette);
    return SizedBox(
      width: _batteryGaugeWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _batteryCapWidth,
            height: _batteryCapHeight,
            decoration: BoxDecoration(
              color: palette.textMuted,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_batteryBorder)),
            ),
          ),
          Container(
            width: _batteryWidth,
            height: _batteryHeight,
            padding: const EdgeInsets.all(_batteryInset),
            decoration: BoxDecoration(
              border: Border.all(color: palette.textMuted, width: _batteryBorder),
              borderRadius: BorderRadius.circular(_batteryRadius),
            ),
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value,
              widthFactor: 1,
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_batteryBorder)),
              ),
            ),
          ),
          const SizedBox(height: _noteGap),
          Text('${(value * _percent).round()}%', style: kTabularStyle.copyWith(fontWeight: FontWeight.w700)),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: _captionSize, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
