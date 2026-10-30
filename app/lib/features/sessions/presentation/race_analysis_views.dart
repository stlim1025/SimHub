import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/race_analysis.dart';
import 'session_widgets.dart';
import 'tyre_stints_view.dart';

// Race Review 각 항목 아래에 붙는 심층 분석 그림(서버 `race-analysis`): 코너별 타이어 부담, 구간별 배터리(AI와), 타이어로 본 스톱·대안 전략, 랩별 페이스 기준.

const double _gap = 8;
const double _rowGap = 6;
const double _captionSize = 11;
const double _labelWidth = 92;
const double _valueWidth = 64;
const double _barHeight = 10;
const double _barRadius = 5;
const double _chipRadius = 8;
const EdgeInsets _chipPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);
const double _chipCircle = 14;
const double _markerWidth = 2;
const double _markerOverhang = 3;
const double _stripHeight = 20;
const double _stripRadius = 5;
const double _stripLabelSize = 11;
const int _stripLapsMin = 4;
const double _paceChartHeight = 96;
const double _paceBarMaxWidth = 10;
const double _paceBarFill = 0.7;
const int _paceCapMs = 1500;
const double _zeroLineWidth = 1;
const double _dimAlpha = 0.35;
const int _frontWheels = 2;

const double _msPerSecond = 1000;

/// 작은 회색 설명 글자.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: _captionSize, color: context.palette.textMuted));
}

/// 스틴트 고르기 칩(컴파운드 원 + 랩 범위).
class _StintChip extends StatelessWidget {
  const _StintChip({required this.stint, required this.selected, required this.onTap});

  final RaceStintDriving stint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      key: ValueKey('analysis-stint-${stint.startLap}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(_chipRadius),
      child: Container(
        padding: _chipPadding,
        decoration: BoxDecoration(
          color: selected ? palette.tableHeader : null,
          border: Border.all(color: selected ? AppColors.accent : palette.border),
          borderRadius: BorderRadius.circular(_chipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TyreCompoundCircle(compound: stint.compound, tooltip: stint.compound, size: _chipCircle),
            const SizedBox(width: _gap / 2),
            Text('L${stint.startLap}–${stint.endLap}', style: kTabularStyle.copyWith(fontWeight: selected ? FontWeight.w700 : null)),
          ],
        ),
      ),
    );
  }
}

/// 가로 막대(바탕 + 채움 + 세로 표시선). [reverse]면 오른쪽에서 왼쪽으로 찬다.
class _Bar extends StatelessWidget {
  const _Bar({required this.factor, required this.color, this.marker, this.reverse = false});

  final double factor;
  final Color color;

  /// 0~1 위치의 세로 표시선(AI 값 등).
  final double? marker;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final marker = this.marker;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final markerAt = marker == null ? null : width * marker.clamp(0, 1).toDouble();
        return SizedBox(
          height: _barHeight + _markerOverhang * 2,
          child: Stack(
            alignment: reverse ? Alignment.centerRight : Alignment.centerLeft,
            children: [
              Container(
                height: _barHeight,
                decoration: BoxDecoration(color: palette.tableHeader, borderRadius: BorderRadius.circular(_barRadius)),
              ),
              Container(
                width: width * factor.clamp(0, 1).toDouble(),
                height: _barHeight,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_barRadius)),
              ),
              if (markerAt != null)
                Positioned(
                  left: ((reverse ? width - markerAt : markerAt) - _markerWidth / 2).clamp(0, math.max(0, width - _markerWidth)).toDouble(),
                  top: 0,
                  bottom: 0,
                  child: Container(width: _markerWidth, color: palette.textPrimary),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 타이어: 스틴트를 골라 리미터 바퀴의 코너별 마찰 일(kJ/랩)과 부담이 큰 코너의 입력 원인, 바퀴 네 개 랩당 일·마모.
class TyreLoadView extends StatefulWidget {
  const TyreLoadView({super.key, required this.analysis, required this.labels});

  final RaceAnalysis analysis;
  final List<String> labels;

  @override
  State<TyreLoadView> createState() => _TyreLoadViewState();
}

class _TyreLoadViewState extends State<TyreLoadView> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stints = widget.analysis.drivenStints;
    final limiter = tyreLimiterWheel(widget.analysis);
    if (stints.isEmpty || limiter == null) {
      return const SizedBox.shrink();
    }
    final stint = stints[_selected.clamp(0, stints.length - 1)];
    final corners = [
      for (final s in widget.analysis.segments)
        if (s.isCorner)
          if (stint.segment(s.index) case final d?) (segment: s, driving: d, load: d.wheelWorkKj?[limiter] ?? 0.0),
    ];
    final maxLoad = corners.fold(0.0, (m, c) => math.max(m, c.load));
    final top = ([...corners]..sort((a, b) => b.load.compareTo(a.load))).take(kTopLoadCorners).map((c) => c.segment.index).toSet();
    final work = stint.wheelWorkKj;
    final wear = stint.wheelWearPerLapPct;
    final front = limiter < _frontWheels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final (i, s) in stints.indexed)
              _StintChip(stint: s, selected: identical(s, stint), onTap: () => setState(() => _selected = i)),
          ],
        ),
        if (work != null) ...[
          const SizedBox(height: _gap),
          Wrap(
            spacing: _gap * 2,
            runSpacing: _gap / 2,
            children: [
              for (var w = 0; w < kWheelNames.length; w++)
                Text(
                  '${kWheelNames[w]} ${work[w].round()}kJ${wear == null ? '' : ' · ${wear[w].toStringAsFixed(1)}%p'}',
                  style: kTabularStyle.copyWith(
                    fontWeight: w == limiter ? FontWeight.w700 : null,
                    color: w == limiter ? palette.danger : palette.textMuted,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: _gap),
        _Caption('코너별 ${kWheelNames[limiter]} 마찰 일(랩당) — 클수록 타이어를 더 갈아'),
        const SizedBox(height: _rowGap),
        for (final c in corners) ...[
          Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(widget.labels[c.segment.index], maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: _Bar(
                  factor: maxLoad <= 0 ? 0 : c.load / maxLoad,
                  color: top.contains(c.segment.index) ? palette.danger : palette.textMuted.withValues(alpha: _dimAlpha),
                ),
              ),
              SizedBox(
                width: _valueWidth,
                child: Text('${c.load.round()}kJ', textAlign: TextAlign.right, style: kTabularStyle),
              ),
            ],
          ),
          if (top.contains(c.segment.index))
            if (cornerCauses(c.driving, front: front) case final causes when causes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: _labelWidth, bottom: _rowGap),
                child: _Caption(causes.map((x) => x.fact).join(' · ')),
              ),
        ],
      ],
    );
  }
}

/// 배터리: 구간마다 씀(왼쪽)·채움(오른쪽) 막대(레이스 평균), 세로선 = AI 중앙값, 오른쪽 숫자 = 순 변화(kJ).
class BatterySegmentsView extends StatelessWidget {
  const BatterySegmentsView({super.key, required this.analysis, required this.labels});

  final RaceAnalysis analysis;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final driven = [for (final s in analysis.stints) if (s.segments.any((d) => d.deployKj != null)) s];
    if (driven.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = [
      for (final s in analysis.segments)
        (
          segment: s,
          deploy: segmentAverage(driven, s.index, (d) => d.deployKj) ?? 0.0,
          harvest: segmentAverage(driven, s.index, (d) => d.harvestKj) ?? 0.0,
          ai: analysis.fieldErsAt(s.index),
        ),
    ];
    final scale = rows.fold(1.0, (m, r) => [m, r.deploy, r.harvest, r.ai?.deployKj ?? 0.0, r.ai?.harvestKj ?? 0.0].reduce(math.max));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Caption('구간별 배터리(랩당 kJ) — 왼쪽 씀 · 오른쪽 채움${analysis.fieldErs.isEmpty ? '' : ' · 세로선 AI'}'),
        const SizedBox(height: _rowGap),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: _rowGap),
            child: Row(
              children: [
                SizedBox(width: _labelWidth, child: Text(labels[r.segment.index], maxLines: 1, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: _Bar(
                    factor: r.deploy / scale,
                    color: palette.danger,
                    marker: r.ai == null ? null : r.ai!.deployKj / scale,
                    reverse: true,
                  ),
                ),
                const SizedBox(width: _gap / 2),
                Expanded(
                  child: _Bar(
                    factor: r.harvest / scale,
                    color: palette.success,
                    marker: r.ai == null ? null : r.ai!.harvestKj / scale,
                  ),
                ),
                SizedBox(
                  width: _valueWidth,
                  child: Text(
                    '${r.harvest - r.deploy >= 0 ? '+' : '−'}${(r.harvest - r.deploy).abs().round()}',
                    textAlign: TextAlign.right,
                    style: kTabularStyle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 전략: 스톱마다 타이어 사정, 실제 전략과 추정 대안(스틴트 띠 + 실제 대비 시간).
class StrategyAnalysisView extends StatelessWidget {
  const StrategyAnalysisView({super.key, required this.strategy});

  final RaceStrategyAnalysis strategy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final options = [...strategy.options]..sort((a, b) => a.isActual
        ? -1
        : b.isActual
            ? 1
            : a.deltaMs.compareTo(b.deltaMs));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stop in strategy.stops)
          Padding(
            padding: const EdgeInsets.only(bottom: _rowGap),
            child: Wrap(
              spacing: _gap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('L${stop.lap}', style: kTabularStyle.copyWith(fontWeight: FontWeight.w700)),
                TyreCompoundCircle(compound: stop.fromCompound, tooltip: stop.fromCompound, size: _chipCircle),
                Icon(Icons.arrow_right_alt, size: _chipCircle, color: palette.textMuted),
                TyreCompoundCircle(compound: stop.toCompound, tooltip: stop.toCompound, size: _chipCircle),
                if (stop.wearPct case final wear?) Text('마모 ${wear.round()}%', style: kTabularStyle),
                if (stop.lifeLapsLeft case final life?) Text('남은 수명 $life랩', style: kTabularStyle.copyWith(color: palette.textMuted)),
                if (stop.newSetGainMs case final gain? when gain > 0)
                  Text('새 세트 −${(gain / _msPerSecond).toStringAsFixed(2)}초/랩', style: kTabularStyle.copyWith(color: palette.success)),
              ],
            ),
          ),
        if (options.length > 1) ...[
          const SizedBox(height: _gap),
          const _Caption('전략 비교(추정 — 게임 타이어 델타·내 마모·내 스톱 손실 기준)'),
          const SizedBox(height: _rowGap),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: _rowGap),
              child: Row(
                children: [
                  Expanded(child: _StintStrip(option: option)),
                  SizedBox(
                    width: _valueWidth + _gap * 2,
                    child: Text(
                      option.isActual ? '실제' : '${option.deltaMs < 0 ? '−' : '+'}${(option.deltaMs.abs() / _msPerSecond).toStringAsFixed(1)}초',
                      textAlign: TextAlign.right,
                      style: kTabularStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: option.isActual
                            ? null
                            : option.deltaMs < 0
                                ? palette.success
                                : palette.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// 전략 하나의 스틴트 띠(컴파운드 색, 랩 수 글자).
class _StintStrip extends StatelessWidget {
  const _StintStrip({required this.option});

  final RaceStrategyOption option;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_stripRadius),
      child: SizedBox(
        height: _stripHeight,
        child: Row(
          children: [
            for (final (i, s) in option.stints.indexed)
              Expanded(
                flex: math.max(1, s.laps),
                child: Container(
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
                  color: tyreColorOf(s.compound),
                  alignment: Alignment.center,
                  child: Text(
                    s.laps >= _stripLapsMin && s.compound.isNotEmpty ? '${s.compound[0]}${s.laps}' : '${s.laps}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(fontSize: _stripLabelSize, fontWeight: FontWeight.w700, color: AppColors.background),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 랩별 페이스 기준.
enum PaceBasis { sameLap, sameTyre }

/// 랩별 페이스: 같은 타이어 / 같은 랩 AI 대비(위 = 느림·빨강, 아래 = 빠름·초록). 깨끗하지 않은 랩(피트·1랩·세이프티카)은 흐리게.
class LapPaceView extends StatefulWidget {
  const LapPaceView({super.key, required this.analysis});

  final RaceAnalysis analysis;

  @override
  State<LapPaceView> createState() => _LapPaceViewState();
}

class _LapPaceViewState extends State<LapPaceView> {
  var _basis = PaceBasis.sameTyre;

  /// 고른 기준 대비 랩타임 차(ms, +면 느림). 기준 값이 없으면 null.
  int? _gapOf(RaceLapPace p) {
    final basis = _basis == PaceBasis.sameLap ? p.fieldSameLapMs : p.fieldSameTyreMs;
    return basis == null ? null : p.lapTimeMs - basis;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final laps = widget.analysis.lapPace;
    if (laps.isEmpty) {
      return const SizedBox.shrink();
    }
    final cap = laps.where((p) => p.isClean).map(_gapOf).whereType<int>().fold(0, (m, g) => math.max(m, g.abs())).clamp(1, _paceCapMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Caption('랩별 AI 대비(±${(cap / _msPerSecond).toStringAsFixed(1)}초) — 위가 느림'),
            SegmentedButton<PaceBasis>(
              key: const ValueKey('analysis-pace-basis'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: PaceBasis.sameTyre, label: Text('같은 타이어')),
                ButtonSegment(value: PaceBasis.sameLap, label: Text('같은 랩')),
              ],
              selected: {_basis},
              onSelectionChanged: (s) => setState(() => _basis = s.first),
            ),
          ],
        ),
        const SizedBox(height: _rowGap),
        SizedBox(
          height: _paceChartHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / laps.length;
              final barWidth = math.min(_paceBarMaxWidth, slot * _paceBarFill);
              final half = constraints.maxHeight / 2;
              return Stack(
                children: [
                  Positioned(left: 0, right: 0, top: half, child: Container(height: _zeroLineWidth, color: palette.border)),
                  for (final (i, p) in laps.indexed)
                    if (_gapOf(p) case final g?)
                      Positioned(
                        left: slot * i + (slot - barWidth) / 2,
                        width: barWidth,
                        top: g >= 0 ? half - half * (g.clamp(0, cap) / cap) : half,
                        height: math.max(1, half * (g.abs().clamp(0, cap) / cap)),
                        child: Tooltip(
                          message: 'L${p.lap} ${g >= 0 ? '+' : '−'}${(g.abs() / _msPerSecond).toStringAsFixed(3)}초',
                          child: Container(
                            color: (g >= 0 ? palette.danger : palette.success).withValues(alpha: p.isClean ? 1 : _dimAlpha),
                          ),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('L${laps.first.lap}', style: kTabularStyle.copyWith(fontSize: _captionSize, color: palette.textMuted)),
            Text('L${laps.last.lap}', style: kTabularStyle.copyWith(fontSize: _captionSize, color: palette.textMuted)),
          ],
        ),
      ],
    );
  }
}
