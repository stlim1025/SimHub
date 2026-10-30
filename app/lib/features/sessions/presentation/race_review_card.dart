import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/util/lap_time.dart';
import '../../../core/widgets/compact_table.dart';
import '../../lap_detail/domain/lap_corners.dart' show OfficialCorner;
import '../domain/race_analysis.dart';
import '../domain/race_review.dart';
import 'race_analysis_views.dart';
import 'race_chart_hover.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

const String _title = 'Race Review';
const String _collapseLabel = '레이스 리뷰 접기';
const String _expandLabel = '레이스 리뷰 펼치기';
const String _fieldMedianLabel = 'AI 보통 랩타임';
const String _paceRankLabel = '페이스 순위';
const String _myMedianLabel = '내 보통 랩타임';
const String _toFieldLabel = 'AI 보통 랩타임과 차이';
const String _gridLabel = '출발';
const String _finishLabel = '완주';
const String _winnerLabel = '우승 차';
const String _trendLabel = '랩마다 느려진 시간';
const String _wearLabel = '랩마다 닳은 양';
const String _stintMedianLabel = '보통 랩타임';
const String _endLifeLabel = '남은 수명';
const String _firstStoreLabel = '1랩 끝';
const String _lastStoreLabel = '마지막 랩';
const String _deployLabel = '쓴 양';
const String _harvestLabel = '채운 양';
const String _lowLapsLabel = '배터리가 바닥난 랩';
const String _fullLapsLabel = '배터리가 꽉 찬 랩';
const String _perLapCaption = '한 랩 평균';
const String _versusAiLabel = 'AI와 차이';
const String _positionChartCaption = '랩마다 순위';
const String _gridTooltip = '출발';
const String _pitTooltip = '피트 스톱';
const String _storeLabel = '배터리';
const String _storeChartCaption = '랩이 끝날 때 배터리';
const String _flowChartCaption = '랩마다 쓴 양과 채운 양';

const Map<ReviewGrade, String> _gradeText = {
  ReviewGrade.good: '좋음',
  ReviewGrade.fair: '보통',
  ReviewGrade.poor: '아쉬움',
};

/// 넓으면 고른 항목의 그림과 짚을 것을 나란히(그림 쪽을 더 넓게 — 표·그래프 칸이 눌리지 않게).
const double _twoColumnWidth = 760;
const double _sideBySideGap = 24;
const int _visualFlex = 3;
const int _notesFlex = 2;
const double _blockGap = 16;
const double _blockRadius = 10;

/// 항목 탭 칸: 안쪽 여백, 제목과 평가 사이, 아래 강조선 두께, 칸 구분선 두께.
const EdgeInsets _tabPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 10);
const double _tabGap = 6;
const double _tabIndicatorWidth = 2;
const double _tabDividerWidth = 1;
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
const double _ladderNameWidth = 108;
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

/// 컴파운드 원·화살표, 줄 안 간격.
const double _chipCircleSize = 16;
const double _chipGap = 6;
const double _arrowIconSize = 14;

/// 피트 스톱 표: 머리글, 랩·타이어 칸 폭, 나머지 열 비율, 타이어 사정 열을 숨기는 표 폭, 초 자릿수.
const String _pitLapHeader = '랩';
const String _pitTyreHeader = '타이어';
const String _pitPositionHeader = '순위';
const String _pitLossHeader = '피트 손실';
const String _pitWearHeader = '닳은 정도';
const String _pitLifeHeader = '남은 수명';
const String _pitGainHeader = '새 타이어 이득';
const double _pitLapWidth = 40;
const double _pitTyreWidth = 56;
const int _pitWideFlex = 3;
const int _pitNarrowFlex = 2;
const double _pitTableCompactWidth = 480;
const int _pitSecondDigits = 1;
const int _pitGainDigits = 2;

/// 수치 칸.
const EdgeInsets _metricPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const double _metricRadius = 6;
const double _metricValueSize = 13;
const double _metricMinWidth = 96;

/// 타이어 수명 막대.
const double _lifeBarHeight = 8;
const double _lifeLabelWidth = 60;
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
const double _batteryGaugeWidth = 64;
const double _batteryGaugeGap = 4;
const double _flowLabelWidth = 52;
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

/// 랩별 순위 그래프: 높이, 세로축 칸 폭·글자 높이·그래프와의 간격, 기준선 두께, 선 두께·점 크기, 피트 점선 길이·간격.
const double _positionChartHeight = 120;
const double _positionAxisWidth = 32;
const double _axisLabelHeight = 14;
const double _axisLabelGap = 6;
const double _gridLineWidth = 1;
const double _positionLineWidth = 2;
const double _positionDotRadius = 2.5;
const double _pitDash = 3;
const double _pitDashGap = 3;

/// 랩별 막대 그래프 툴팁 자리: 막대 칸 가운데 비율.
const double _half = 0.5;

const double _msPerSecond = 1000;
const double _percent = 100;
const int _lapSecondDigits = 3;
const int _wearDigits = 1;

String _signedSeconds(int ms, {int digits = _lapSecondDigits}) =>
    '${ms >= 0 ? '+' : '−'}${(ms.abs() / _msPerSecond).toStringAsFixed(digits)}초';

/// 배터리 양(J)을 배터리 게이지 %로(한 통 = 100%).
String _batteryPct(double joules) => '${(joules / kErsCapacityJ * _percent).round()}%';

String _seconds(int ms, {int digits = _lapSecondDigits}) => '${(ms.abs() / _msPerSecond).toStringAsFixed(digits)}초';

Color _gradeColor(ReviewGrade grade, AppPalette palette) => switch (grade) {
      ReviewGrade.good => palette.success,
      ReviewGrade.fair => palette.textMuted,
      ReviewGrade.poor => palette.danger,
    };

/// 레이스 총평 카드: 한 줄 총평, 항목 탭(페이스·전략·타이어·배터리 — 탭마다 평가), 고른 항목의 그림 + 짚을 것.
/// 항목마다 심층 분석([analysis])의 줄과 그림(코너별 타이어 부담·구간별 배터리·대안 전략·랩별 페이스 기준)을 함께 그린다.
/// 제목 줄을 누르면 접고 편다(처음엔 펼침).
class RaceReviewCard extends StatefulWidget {
  const RaceReviewCard({super.key, required this.review, required this.analysis, this.officialCorners, this.setup});

  final RaceReview review;

  /// 심층 분석, 구간 이름에 쓸 공식 코너, 세팅 제안에 쓸 레이스 셋업.
  final RaceAnalysis analysis;
  final List<OfficialCorner>? officialCorners;
  final Map<String, Object?>? setup;

  @override
  State<RaceReviewCard> createState() => _RaceReviewCardState();
}

class _RaceReviewCardState extends State<RaceReviewCard> {
  var _expanded = true;

  /// 고른 항목 제목(없거나 사라졌으면 첫 항목).
  String? _selected;

  RaceReview get review => widget.review;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = widget.analysis;
    final labels = segmentLabels(analysis, widget.officialCorners);
    final sections = raceReviewSectionsWithAnalysis(review, analysis, widget.officialCorners, widget.setup);
    final summary = raceReviewSummary(sections);
    final current = sections.where((s) => s.title == _selected).firstOrNull ?? sections.firstOrNull;
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
          if (current != null) ...[
            _SectionTabs(
              sections: sections,
              selected: current.title,
              onSelected: (title) => setState(() => _selected = title),
            ),
            const SizedBox(height: _blockGap),
            _SectionBody(
              key: ValueKey('race-review-section-${current.title}'),
              section: current.section,
              visual: _visualFor(current.title, analysis, labels),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _visualFor(String title, RaceAnalysis analysis, List<String> labels) {
    final pace = review.pace;
    final battery = review.battery;
    final base = switch (title) {
      kPaceSectionTitle when pace != null => _PaceChart(pace: pace),
      kStrategySectionTitle => _StrategyView(
          strategy: review.strategy,
          stints: review.stints,
          stopContexts: analysis.strategy?.stops ?? const [],
        ),
      kTyreSectionTitle => _StintList(stints: review.stints),
      kBatterySectionTitle when battery != null => _BatteryView(battery: battery),
      _ => null,
    };
    final strategy = analysis.strategy;
    final deep = switch (title) {
      kPaceSectionTitle when analysis.lapPace.isNotEmpty => LapPaceView(analysis: analysis),
      kStrategySectionTitle when strategy != null && strategy.options.length > 1 => StrategyAnalysisView(strategy: strategy),
      kTyreSectionTitle when analysis.drivenStints.isNotEmpty => TyreLoadView(analysis: analysis, labels: labels),
      kBatterySectionTitle when analysis.stints.any((s) => s.segments.any((d) => d.deployKj != null)) =>
        BatterySegmentsView(analysis: analysis, labels: labels),
      _ => null,
    };
    if (deep == null || base == null) {
      return deep ?? base;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [base, const SizedBox(height: _blockGap), deep],
    );
  }
}

/// 항목 탭: 항목마다 같은 폭 칸(제목 + 평가 알약)을 한 줄로. 고른 칸은 바탕색과 아래 강조선.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.sections, required this.selected, required this.onSelected});

  final List<({String title, ReviewSection section})> sections;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(_blockRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_blockRadius),
        // 제목이 두 줄로 접히는 칸이 있어도 칸 높이·구분선을 맞춘다.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, s) in sections.indexed) ...[
                if (i > 0) Container(width: _tabDividerWidth, color: palette.border),
                Expanded(
                  child: _SectionTab(
                    title: s.title,
                    grade: s.section.grade,
                    selected: s.title == selected,
                    onTap: () => onSelected(s.title),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 항목 탭 칸 하나.
class _SectionTab extends StatelessWidget {
  const _SectionTab({required this.title, required this.grade, required this.selected, required this.onTap});

  final String title;
  final ReviewGrade grade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = _gradeColor(grade, palette);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.tableHeader : Colors.transparent,
        child: InkWell(
          key: ValueKey('race-review-tab-$title'),
          onTap: onTap,
          child: Container(
            padding: _tabPadding,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: _tabIndicatorWidth),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: _blockTitleSize,
                    color: selected ? palette.textPrimary : palette.textMuted,
                  ),
                ),
                const SizedBox(height: _tabGap),
                Container(
                  padding: _pillPadding,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: _pillAlpha),
                    borderRadius: BorderRadius.circular(_pillRadius),
                  ),
                  child: Text(
                    _gradeText[grade]!,
                    key: ValueKey('race-review-grade-$title'),
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: _pillFontSize),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 고른 항목: 그림과 짚을 것(관찰 → 할 것). 넓으면 그림(왼쪽)과 짚을 것(오른쪽)을 나란히, 좁으면 위아래로.
class _SectionBody extends StatelessWidget {
  const _SectionBody({super.key, required this.section, this.visual});

  final ReviewSection section;
  final Widget? visual;

  @override
  Widget build(BuildContext context) {
    final visual = this.visual;
    final notes = section.lines.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, line) in section.lines.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : _noteGap),
                  child: _Note(line: line),
                ),
            ],
          );
    if (visual == null || notes == null) {
      return visual ?? notes ?? const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= _twoColumnWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: _visualFlex, child: visual),
                const SizedBox(width: _sideBySideGap),
                Expanded(flex: _notesFlex, child: notes),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [visual, const SizedBox(height: _blockGap), notes],
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
    final mySectors = pace.mySectorMs;
    final sectors = sectorGaps(mySectors, pace.fieldSectorMs);

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
        if (sectors != null && mySectors != null) ...[
          const SizedBox(height: _innerGap),
          _MetricGroup([
            for (var i = 0; i < kSectorCount; i++)
              (
                label: '${i + 1}섹터 $_versusAiLabel',
                value: _signedSeconds(sectors[i]),
                sub: _seconds(mySectors[i]),
                color: sectors[i] >= kSectorMarginMs
                    ? palette.danger
                    : sectors[i] <= -kSectorMarginMs
                        ? palette.success
                        : null,
              ),
          ]),
        ],
      ],
    );
  }
}

/// 전략: 출발 → 완주, 스틴트 타임라인(컴파운드 색, 피트 랩 눈금), 피트 스톱 표, 우승 차 전략.
class _StrategyView extends StatelessWidget {
  const _StrategyView({required this.strategy, required this.stints, this.stopContexts = const []});

  final RaceStrategyReview strategy;
  final List<RaceStintReview> stints;

  /// 심층 분석의 스톱마다 타이어 사정(닳은 정도·남은 수명·새 타이어 이득) — 피트 스톱 표에 같은 랩끼리 붙인다.
  final List<RaceStopContext> stopContexts;

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
              _BigStat(value: '$grid위', caption: _gridLabel),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _innerGap),
                child: Icon(Icons.arrow_forward, color: palette.textMuted),
              ),
              _BigStat(value: '$finish위', caption: _finishLabel, color: palette.podiumFor(finish)),
              const SizedBox(width: _innerGap),
              PositionChangeText(change: grid - finish),
            ],
          ),
        if (stints.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          Padding(
            // 아래 순위 그래프의 세로축 칸만큼 비워 랩 자리를 맞춘다.
            padding: EdgeInsets.only(left: strategy.lapPositions.length >= _lapChartMinLaps ? _positionAxisWidth : 0),
            child: _StintTimeline(stints: stints, pitLaps: [for (final s in strategy.pitStops) s.lap]),
          ),
        ],
        if (strategy.lapPositions.length >= _lapChartMinLaps) ...[
          const SizedBox(height: _innerGap),
          _PositionChart(
            positions: strategy.lapPositions,
            grid: strategy.gridPosition,
            pitLaps: [for (final s in strategy.pitStops) s.lap],
            totalLaps: math.max(
              strategy.lapPositions.last.lap,
              stints.isEmpty ? 0 : stints.map((s) => s.endLap).reduce(math.max),
            ),
          ),
        ],
        if (strategy.pitStops.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          _PitStopTable(stops: strategy.pitStops, fieldLossMs: strategy.fieldPitLossMs, contexts: stopContexts),
        ],
        if (winnerStops != null && strategy.winnerCompounds.isNotEmpty) ...[
          const SizedBox(height: _innerGap),
          Wrap(
            spacing: _chipGap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_winnerLabel, style: TextStyle(color: palette.textMuted)),
              ..._compoundFlow(strategy.winnerCompounds, palette),
              Text('피트 $winnerStops번', style: TextStyle(color: palette.textMuted)),
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
                              segment.laps >= _segmentNameMinLaps
                                  ? compoundName(segment.compound!)
                                  : compoundName(segment.compound!).characters.first,
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
                        '$lap랩',
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

/// 피트 스톱 표 한 줄: 결과 쪽 스톱과 (있으면) 같은 랩의 심층 분석 타이어 사정.
typedef _PitStopRow = ({RacePitStopReview stop, RaceStopContext? context});

/// 피트 스톱 표: 스톱마다 한 줄, 열마다 같은 자리(랩·타이어·순위·피트 손실과 AI·닳은 정도·남은 수명·새 타이어 이득).
/// 피트 손실은 평가 색, 새 타이어 이득은 초록. 좁으면 타이어 사정 세 열은 숨긴다(짚을 것 문장에 같은 값이 있다).
class _PitStopTable extends StatelessWidget {
  const _PitStopTable({required this.stops, required this.fieldLossMs, required this.contexts});

  final List<RacePitStopReview> stops;
  final int? fieldLossMs;
  final List<RaceStopContext> contexts;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final muted = kTabularStyle.copyWith(color: palette.textMuted, fontSize: _captionSize);
    final hasContext = contexts.isNotEmpty;
    final rows = <_PitStopRow>[
      for (final stop in stops) (stop: stop, context: contexts.where((c) => c.lap == stop.lap).firstOrNull),
    ];
    Widget value(String? text, {Color? color, FontWeight? weight}) => Text(
          text ?? '–',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: kTabularStyle.copyWith(color: text == null ? palette.textMuted : color, fontWeight: weight),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(_blockRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_blockRadius),
        child: CompactTable<_PitStopRow>(
          framed: false,
          compactWidth: _pitTableCompactWidth,
          rowKey: (r) => ValueKey('race-review-pit-${r.stop.lap}'),
          rows: rows,
          columns: [
            CompactColumn(
              label: _pitLapHeader,
              width: _pitLapWidth,
              cell: (r) => value('${r.stop.lap}랩', weight: FontWeight.w700),
            ),
            CompactColumn(
              label: _pitTyreHeader,
              width: _pitTyreWidth,
              cell: (r) => Row(
                mainAxisSize: MainAxisSize.min,
                children: _compoundFlow([r.stop.fromCompound, r.stop.toCompound], palette),
              ),
            ),
            CompactColumn(
              label: _pitPositionHeader,
              flex: _pitWideFlex,
              // 좁은 칸에서도 말줄임 없이 한 줄에 다 보이게 필요하면 글자를 줄인다.
              cell: (r) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: value(
                  r.stop.positionBefore == null || r.stop.positionAfter == null
                      ? null
                      : '${r.stop.positionBefore}위→${r.stop.positionAfter}위',
                ),
              ),
            ),
            CompactColumn(
              label: _pitLossHeader,
              flex: _pitWideFlex,
              cell: (r) {
                final loss = r.stop.lossMs;
                final field = fieldLossMs;
                final grade = pitStopGrade(r.stop, field);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    value(
                      loss == null ? null : _seconds(loss, digits: _pitSecondDigits),
                      color: grade == ReviewGrade.fair ? null : _gradeColor(grade, palette),
                      weight: FontWeight.w700,
                    ),
                    if (loss != null && field != null)
                      Text(
                        'AI는 ${_seconds(field, digits: _pitSecondDigits)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                  ],
                );
              },
            ),
            if (hasContext) ...[
              CompactColumn(
                label: _pitWearHeader,
                flex: _pitNarrowFlex,
                compactHidden: true,
                cell: (r) => value(r.context?.wearPct == null ? null : '${r.context!.wearPct!.round()}%'),
              ),
              CompactColumn(
                label: _pitLifeHeader,
                flex: _pitNarrowFlex,
                compactHidden: true,
                cell: (r) => value(r.context?.lifeLapsLeft == null ? null : '${r.context!.lifeLapsLeft}랩'),
              ),
              CompactColumn(
                label: _pitGainHeader,
                flex: _pitWideFlex,
                compactHidden: true,
                cell: (r) {
                  final gain = r.context?.newSetGainMs;
                  return value(
                    gain == null || gain <= 0 ? null : '랩당 ${_seconds(gain, digits: _pitGainDigits)}',
                    color: palette.success,
                  );
                },
              ),
            ],
          ],
        ),
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
    final axle = axleWear(stint);
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
              stintName(stint.compound, stint.startLap, stint.endLap),
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
              value: _signedSeconds(trend),
              sub: fieldTrend == null ? null : 'AI는 ${_signedSeconds(fieldTrend)}',
              color: extra == null || fieldTrend == null ? null : versusField(trend, fieldTrend, kTrendMarginMs),
            ),
          if (wear != null)
            (
              label: _wearLabel,
              value: '${wear.toStringAsFixed(_wearDigits)}%',
              sub: axle == null
                  ? null
                  : '앞 ${axle.front.toStringAsFixed(_wearDigits)}%, 뒤 ${axle.rear.toStringAsFixed(_wearDigits)}%',
              color: stint.wearsFast ? palette.danger : null,
            ),
          if (median != null)
            (
              label: _stintMedianLabel,
              value: formatLapTime(median),
              sub: fieldMedian == null ? null : 'AI는 ${formatLapTime(fieldMedian)}',
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
        _BatteryGauge(label: '최저 ${battery.minStoreLap}랩', fraction: battery.minStoreJ / kErsCapacityJ),
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
            value: '${battery.lowLaps}랩',
            sub: null,
            color: battery.lowLaps >= kErsFlagLaps ? palette.danger : null,
          ),
          (
            label: _fullLapsLabel,
            value: '${battery.fullLaps}랩',
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
    // 두 그래프 모두 같은 랩 설명: 랩 끝 배터리, 쓴 양·채운 양(모두 배터리 게이지 %).
    String lapTooltip(RaceBatteryLap l) {
      final deployed = l.deployedJ;
      final harvested = l.harvestedJ;
      final flow = [
        if (deployed != null) '$_deployLabel ${_batteryPct(deployed)}',
        if (harvested != null) '$_harvestLabel ${_batteryPct(harvested)}',
      ];
      return '${l.lap}랩 끝 $_storeLabel ${_batteryPct(l.storeJ)}'
          '${flow.isEmpty ? '' : '\n${flow.join(', ')}'}';
    }

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
            tooltipOf: (i) => lapTooltip(perLap[i]),
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
            tooltipOf: (i) => lapTooltip(flowLaps[i]),
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
              child: Text(_batteryPct(joules), textAlign: TextAlign.right, style: kTabularStyle),
            ),
          ],
        ),
      );
}

/// 잔량 비율 → 색(거의 바닥 빨강, 가득 노랑, 그 외 초록).
Color _storeColor(double fraction, AppPalette palette) => fraction < kErsLowFraction
    ? palette.danger
    : fraction >= kErsFullFraction
        ? AppColors.wearMedium
        : palette.success;

/// 축 눈금: 범위가 좁으면 1, 넓어질수록 2·5·10 간격. 양 끝은 늘 넣고, 끝에 반 간격보다 가까운 눈금은 뺀다.
List<int> axisTicks(int from, int to) {
  final span = to - from;
  final step = span <= _tickSpanOne
      ? 1
      : span <= _tickSpanTwo
          ? 2
          : span <= _tickSpanFive
              ? 5
              : 10;
  final ticks = {from, to};
  for (var t = (from ~/ step + 1) * step; t < to; t += step) {
    if (t - from >= step / 2 && to - t >= step / 2) {
      ticks.add(t);
    }
  }
  return ticks.toList()..sort();
}

/// 축 눈금 간격을 1·2·5로 둘 최대 범위(넘으면 10).
const int _tickSpanOne = 5;
const int _tickSpanTwo = 12;
const int _tickSpanFive = 40;

/// 랩별 순위 그래프: 위가 1위. 그리드(왼쪽 끝)부터 랩 끝 순위를 잇고, 피트 랩 끝에 점선. 가로는 스틴트 타임라인과 같은 랩 칸.
class _PositionChart extends StatelessWidget {
  const _PositionChart({required this.positions, required this.grid, required this.pitLaps, required this.totalLaps});

  final List<RaceLapPosition> positions;
  final int? grid;
  final List<int> pitLaps;
  final int totalLaps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final all = [?grid, for (final p in positions) p.position];
    final best = all.reduce(math.min);
    final worst = all.reduce(math.max);
    final captionStyle = TextStyle(fontSize: _captionSize, color: palette.textMuted);
    final start = grid;
    // 그래프 점 = 그리드(0랩) + 랩 끝 순위.
    final points = <RaceLapPosition>[
      if (start != null) (lap: 0, position: start),
      ...positions,
    ];
    final positionTicks = axisTicks(best, worst);
    final lapTicks = axisTicks(1, totalLaps);
    final tickStyle = kTabularStyle.merge(captionStyle);
    double yOf(int position) => (position - best) / math.max(1, worst - best) * _positionChartHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_positionChartCaption, style: captionStyle),
        const SizedBox(height: _noteGap),
        SizedBox(
          height: _positionChartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 세로축: 순위 눈금(가로 보조선과 같은 높이).
              SizedBox(
                width: _positionAxisWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final p in positionTicks)
                      Positioned(
                        top: (yOf(p) - _axisLabelHeight / 2).clamp(0, _positionChartHeight - _axisLabelHeight).toDouble(),
                        left: 0,
                        right: _axisLabelGap,
                        height: _axisLabelHeight,
                        child: Text('$p위', textAlign: TextAlign.right, style: tickStyle),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: RaceChartHover(
                  count: points.length,
                  xOf: (i, width) => width * points[i].lap / totalLaps,
                  tooltipOf: (i) => _positionTooltip(points, i),
                  child: CustomPaint(
                    painter: _PositionPainter(
                      positions: positions,
                      grid: grid,
                      pitLaps: pitLaps,
                      totalLaps: totalLaps,
                      best: best,
                      worst: worst,
                      positionTicks: positionTicks,
                      lapTicks: lapTicks,
                      line: AppColors.accent,
                      gridLine: palette.border,
                      pitLine: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 가로축: 랩 눈금(세로 보조선과 같은 자리).
        Padding(
          padding: const EdgeInsets.only(left: _positionAxisWidth, top: _lapChartTickGap),
          child: SizedBox(
            height: _lapTickHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                double leftOf(int lap) =>
                    (width * lap / totalLaps - _lapTickWidth / 2).clamp(0, math.max(0, width - _lapTickWidth)).toDouble();
                // 좁으면 앞 글자와 겹치는 눈금 글자는 뺀다(마지막 랩은 남기고 그 앞을 뺀다).
                final shown = <int>[];
                for (final lap in lapTicks) {
                  if (shown.isNotEmpty && leftOf(lap) - leftOf(shown.last) < _lapTickWidth) {
                    if (lap != lapTicks.last) {
                      continue;
                    }
                    shown.removeLast();
                  }
                  shown.add(lap);
                }
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final lap in shown)
                      Positioned(
                        left: leftOf(lap),
                        width: _lapTickWidth,
                        child: Text(
                          '$lap랩',
                          textAlign: lap == totalLaps ? TextAlign.right : TextAlign.center,
                          style: tickStyle,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 점 하나의 설명: 그리드면 출발 순위, 랩이면 순위·앞 점 대비 변화·피트 랩 여부.
  String _positionTooltip(List<RaceLapPosition> points, int i) {
    final point = points[i];
    if (point.lap == 0) {
      return '$_gridTooltip ${point.position}위';
    }
    final change = i == 0 ? 0 : points[i - 1].position - point.position;
    final parts = [
      '${point.lap}랩 ${point.position}위',
      if (change > 0) '$change계단 올라감',
      if (change < 0) '${-change}계단 내려감',
      if (pitLaps.contains(point.lap)) _pitTooltip,
    ];
    return parts.join(', ');
  }
}

class _PositionPainter extends CustomPainter {
  _PositionPainter({
    required this.positions,
    required this.grid,
    required this.pitLaps,
    required this.totalLaps,
    required this.best,
    required this.worst,
    required this.positionTicks,
    required this.lapTicks,
    required this.line,
    required this.gridLine,
    required this.pitLine,
  });

  final List<RaceLapPosition> positions;
  final int? grid;
  final List<int> pitLaps;
  final int totalLaps;
  final int best;
  final int worst;
  final List<int> positionTicks;
  final List<int> lapTicks;
  final Color line;
  final Color gridLine;
  final Color pitLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalLaps <= 0) {
      return;
    }
    final range = math.max(1, worst - best);
    double y(int position) => (position - best) / range * size.height;
    // 랩 끝 = 그 랩 칸의 오른쪽 끝(타임라인 눈금과 같은 자리), 그리드 = 왼쪽 끝.
    double x(int lap) => size.width * lap / totalLaps;

    // 기준선: 순위 눈금마다 가로선, 랩 눈금마다 세로선. 피트 랩은 점선.
    final gridPaint = Paint()
      ..color = gridLine
      ..strokeWidth = _gridLineWidth;
    for (final p in positionTicks) {
      canvas.drawLine(Offset(0, y(p)), Offset(size.width, y(p)), gridPaint);
    }
    for (final lap in lapTicks) {
      canvas.drawLine(Offset(x(lap), 0), Offset(x(lap), size.height), gridPaint);
    }
    final pitPaint = Paint()
      ..color = pitLine
      ..strokeWidth = _gridLineWidth;
    for (final lap in pitLaps) {
      for (var top = 0.0; top < size.height; top += _pitDash + _pitDashGap) {
        canvas.drawLine(Offset(x(lap), top), Offset(x(lap), math.min(size.height, top + _pitDash)), pitPaint);
      }
    }

    final start = grid;
    final points = [
      if (start != null) Offset(0, y(start)),
      for (final p in positions) Offset(x(p.lap), y(p.position)),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = _positionLineWidth
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = line;
    for (final point in points) {
      canvas.drawCircle(point, _positionDotRadius, dot);
    }
  }

  @override
  bool shouldRepaint(_PositionPainter old) =>
      old.positions != positions ||
      old.grid != grid ||
      old.pitLaps != pitLaps ||
      old.totalLaps != totalLaps ||
      old.line != line ||
      old.gridLine != gridLine ||
      old.pitLine != pitLine;
}

/// 랩별 막대 계열 하나: 랩마다 값, 값 → 색.
typedef _LapSeries = ({List<double> values, Color Function(double value) colorOf});

/// 랩별 막대 그래프: 설명, 막대(계열이 여럿이면 한 랩에 나란히), 아래 첫·가운데·마지막 랩 눈금.
class _LapChart extends StatelessWidget {
  const _LapChart({
    required this.caption,
    required this.laps,
    required this.series,
    required this.maxValue,
    required this.tooltipOf,
  });

  final String caption;
  final List<int> laps;
  final List<_LapSeries> series;
  final double maxValue;

  /// 마우스·터치로 고른 막대([laps] 순번)의 설명.
  final String Function(int index) tooltipOf;

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
          child: RaceChartHover(
            count: laps.length,
            // 막대 칸 가운데.
            xOf: (i, width) => width / laps.length * (i + _half),
            tooltipOf: tooltipOf,
            child: CustomPaint(
              painter: _LapBarsPainter(series: series, maxValue: maxValue, baseline: palette.border),
            ),
          ),
        ),
        const SizedBox(height: _lapChartTickGap),
        Row(
          children: [
            Text('${laps.first}랩', style: tickStyle),
            const Spacer(),
            Text('${laps[laps.length ~/ 2]}랩', style: tickStyle),
            const Spacer(),
            Text('${laps.last}랩', style: tickStyle),
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
