import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../domain/race_highlights.dart' show standingAbbreviation;
import '../domain/session_board.dart';
import '../domain/session_models.dart';
import 'session_widgets.dart';
import 'tyre_stint_cards.dart' show stintLineColor;

// -- 공통 ---------------------------------------------------------------------------

const double _tagFontSize = 14;
const double _tagLetterSpacing = 0.6;

/// 카드 제목 오른쪽의 흐린 보조 글자(`내 순위 변화`, `핵심 장면`).
class _CardTag extends StatelessWidget {
  const _CardTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: _tagFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: _tagLetterSpacing,
              color: context.palette.textMuted,
            ),
      );
}

// -- Position · 내 순위 변화 --------------------------------------------------------------

const String _positionTitle = 'Position';
const String _positionTag = '내 순위 변화';

/// 높이가 정해지지 않은 칸(2열·1열)에서의 그래프 기본 높이.
const double kPositionChartHeight = 280;

/// 순위 그래프 카드(B안 보드 오른쪽 위): 출발 그리드부터 랩마다 내 순위(위가 P1), 피트 랩은 세로 점선 + 새 컴파운드 점.
/// 모든 차의 랩별 순위는 없어서 내 순위만 그린다. 보드에서는 옆 칸 높이에 맞춰 늘어난다.
class PositionChartCard extends StatelessWidget {
  const PositionChartCard({super.key, required this.trace, this.height = kPositionChartHeight});

  final PositionTrace trace;

  /// 높이가 정해지지 않았을 때의 그래프 높이(보드는 낮게 주고 옆 칸 높이만큼 늘린다).
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final chart = Semantics(
      label: '내 순위 그래프: 출발 ${trace.grid == null ? '' : 'P${trace.grid}, '}마지막 랩 P${trace.finalPosition}',
      child: CustomPaint(
        key: const ValueKey('position-chart'),
        size: Size.infinite,
        painter: PositionChartPainter(
          trace: trace,
          lineColor: palette.link,
          fillColor: AppColors.playerRow,
          gridColor: palette.border,
          mutedColor: palette.textMuted,
          surfaceColor: palette.surface,
          pitColors: [for (final stop in trace.pitStops) _compoundColor(stop.toCompound, palette)],
          labelStyle: (textTheme.labelSmall ?? const TextStyle()).copyWith(color: palette.textMuted),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.hasBoundedHeight
          ? SessionCard(title: _positionTitle, trailing: const _CardTag(_positionTag), fill: true, child: chart)
          : SessionCard(
              title: _positionTitle,
              trailing: const _CardTag(_positionTag),
              child: SizedBox(height: height, child: chart),
            ),
    );
  }

  static Color _compoundColor(String? compound, AppPalette palette) =>
      compound == null ? palette.textMuted : stintLineColor(compound, palette);
}

/// 그림 영역 바깥 여백: 왼쪽 `P10` 눈금, 위 `PIT` 글자, 오른쪽 마지막 순위 글자, 아래 랩 번호.
const double _leftGutter = 34;
const double _topGutter = 18;
const double _rightGutter = 36;
const double _bottomGutter = 22;
const double _labelGap = 6;
const double _axisLabelGap = 8;
const double _positionLabelGap = 10;

/// 세로 눈금 글자 사이 최소 간격(이보다 붙으면 그 눈금은 선만 긋고 글자는 건너뛴다).
const double _minPositionLabelSpacing = 20;
const double _lineWidth = 2.5;
const double _gridLineWidth = 1;
const double _dotRadius = 5;
const double _endDotRadius = 4.5;
const double _ringWidth = 2;
const double _dashLength = 4;
const double _pitLineAlpha = 0.6;
const double _finalLabelScale = 1.25;
const String _pitLabel = 'PIT';
const String _gridLabel = 'Grid';

/// 내 순위 그래프 그림(순수 그리기: 그리드 가로선 + P 눈금 · 랩 눈금 · 피트 점선 · 순위 아래 옅은 면 · 순위 선 · 끝 순위 글자).
class PositionChartPainter extends CustomPainter {
  PositionChartPainter({
    required this.trace,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.mutedColor,
    required this.surfaceColor,
    required this.pitColors,
    required this.labelStyle,
  });

  final PositionTrace trace;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color mutedColor;
  final Color surfaceColor;

  /// 피트 스톱마다 새 컴파운드 색([PositionTrace.pitStops]와 같은 순서).
  final List<Color> pitColors;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_leftGutter, _topGutter, size.width - _rightGutter, size.height - _bottomGutter);
    if (plot.width <= 0 || plot.height <= 0) {
      return;
    }
    final minLap = trace.minLap;
    final lapSpan = math.max(1, trace.maxLap - minLap);
    final positionSpan = math.max(1, trace.maxPosition - 1);
    double x(num lap) => plot.left + (lap - minLap) / lapSpan * plot.width;
    double y(num position) => plot.top + (position - 1) / positionSpan * plot.height;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = _gridLineWidth;
    double? lastLabel;
    for (final position in positionTicks(trace.maxPosition)) {
      final dy = y(position);
      canvas.drawLine(Offset(plot.left, dy), Offset(plot.right, dy), grid);
      if (lastLabel == null || dy - lastLabel >= _minPositionLabelSpacing) {
        _text(canvas, 'P$position', Offset(plot.left - _positionLabelGap, dy), align: _Align.rightMiddle);
        lastLabel = dy;
      }
    }
    for (final lap in lapTicks(minLap, trace.maxLap)) {
      _text(canvas, lap == 0 ? _gridLabel : '$lap', Offset(x(lap), plot.bottom + _axisLabelGap), align: _Align.topCenter);
    }

    final points = [
      if (trace.grid case final grid?) Offset(x(0), y(grid)),
      for (final point in trace.points) Offset(x(point.lap), y(point.position)),
    ];

    // 피트 랩: 세로 점선 + 위에 PIT.
    final pitLine = Paint()
      ..color = mutedColor.withValues(alpha: _pitLineAlpha)
      ..strokeWidth = _gridLineWidth;
    for (final stop in trace.pitStops) {
      final dx = x(stop.lap);
      for (var dy = plot.top; dy < plot.bottom; dy += _dashLength * 2) {
        canvas.drawLine(Offset(dx, dy), Offset(dx, math.min(dy + _dashLength, plot.bottom)), pitLine);
      }
      _text(canvas, _pitLabel, Offset(dx, plot.top - _labelGap), align: _Align.bottomCenter);
    }

    // 순위 아래 옅은 면 + 순위 선.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    // 선 바로 아래가 가장 짙고 아래로 갈수록 투명해지는 면.
    final top = points.map((p) => p.dy).reduce(math.min);
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillColor, fillColor.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(plot.left, top, plot.right, plot.bottom)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _lineWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 피트 랩 점(새 컴파운드 색), 출발 점(속 빈 원), 끝 점 + 끝 순위.
    for (final (i, stop) in trace.pitStops.indexed) {
      final point = trace.points.where((p) => p.lap == stop.lap).firstOrNull;
      if (point != null) {
        _dot(canvas, Offset(x(point.lap), y(point.position)), i < pitColors.length ? pitColors[i] : mutedColor);
      }
    }
    if (trace.grid != null) {
      canvas.drawCircle(
        points.first,
        _endDotRadius,
        Paint()
          ..color = mutedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringWidth,
      );
    }
    canvas.drawCircle(points.last, _endDotRadius, Paint()..color = lineColor);
    _text(
      canvas,
      'P${trace.finalPosition}',
      Offset(points.last.dx + _labelGap, points.last.dy),
      align: _Align.leftMiddle,
      style: labelStyle.copyWith(
        color: lineColor,
        fontWeight: FontWeight.w800,
        fontSize: (labelStyle.fontSize ?? _defaultLabelSize) * _finalLabelScale,
      ),
    );
  }

  void _dot(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(center, _dotRadius + _ringWidth, Paint()..color = surfaceColor);
    canvas.drawCircle(center, _dotRadius, Paint()..color = color);
  }

  void _text(Canvas canvas, String text, Offset anchor, {required _Align align, TextStyle? style}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style ?? labelStyle), textDirection: TextDirection.ltr)
      ..layout();
    final size = painter.size;
    final offset = switch (align) {
      _Align.rightMiddle => Offset(anchor.dx - size.width, anchor.dy - size.height / 2),
      _Align.leftMiddle => Offset(anchor.dx, anchor.dy - size.height / 2),
      _Align.topCenter => Offset(anchor.dx - size.width / 2, anchor.dy),
      _Align.bottomCenter => Offset(anchor.dx - size.width / 2, anchor.dy - size.height),
    };
    painter.paint(canvas, offset);
    painter.dispose();
  }

  @override
  bool shouldRepaint(PositionChartPainter old) =>
      old.trace != trace ||
      old.lineColor != lineColor ||
      old.fillColor != fillColor ||
      old.gridColor != gridColor ||
      old.mutedColor != mutedColor ||
      old.surfaceColor != surfaceColor ||
      old.labelStyle != labelStyle;
}

/// 글자 기준점 위치.
enum _Align { rightMiddle, leftMiddle, topCenter, bottomCenter }

/// 글자 크기를 모를 때(테마 labelSmall 없음)의 기본값.
const double _defaultLabelSize = 12;

// -- Tyre Stints · 모든 차 ------------------------------------------------------------

const String _stintsTitle = 'Tyre Stints';
const String _stintsEmpty = '이 세션에는 타이어 스틴트 데이터가 없어요.';
const double _stintRowHeight = 20;
const double _stintBarHeight = 14;
const double _stintGap = 2;
const double _stintPositionWidth = 22;
const double _stintNameWidth = 40;
const double _stintColumnGap = 8;
const double _stintLetterSize = 10;
const double _stintAxisGap = 6;

/// 모든 차 타이어 스틴트 카드(B안 보드): 순위 순으로 차마다 한 줄, 스틴트 막대 길이 = 그 스틴트 랩 수(전체 랩 기준),
/// 막대 안에 컴파운드 글자. 내 줄은 강조 배경 + 앰버 이름.
class FieldTyreStintsCard extends StatelessWidget {
  const FieldTyreStintsCard({super.key, required this.results, required this.totalLaps});

  final List<SessionResult> results;

  /// 세션 전체 랩 수(막대 끝). 결과의 최대 랩 수가 더 크면 그것을 쓴다.
  final int totalLaps;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final row in results)
        if (stintSegmentsOf(row) case final segments when segments.isNotEmpty) (row: row, segments: segments),
    ];
    if (rows.isEmpty) {
      return const SessionCard(title: _stintsTitle, child: SessionEmptyText(_stintsEmpty));
    }
    final maxLaps = rows.fold(totalLaps, (laps, r) => math.max(laps, r.row.numLaps));
    final muted = TextStyle(color: context.palette.textMuted);
    return SessionCard(
      title: _stintsTitle,
      trailing: _CardTag('${rows.length}대'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows) _StintRow(row: r.row, segments: r.segments, maxLaps: maxLaps),
          const SizedBox(height: _stintAxisGap),
          Row(
            children: [
              const SizedBox(width: _stintPositionWidth + _stintNameWidth + 2 * _stintColumnGap),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('L1', style: muted.merge(kTabularStyle)),
                    Text('L$maxLaps', style: muted.merge(kTabularStyle)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StintRow extends StatelessWidget {
  const _StintRow({required this.row, required this.segments, required this.maxLaps});

  final SessionResult row;
  final List<StintSegment> segments;
  final int maxLaps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final covered = segments.last.endLap;
    final name = standingAbbreviation(row.isPlayer ? kPlayerName : row.name);
    return Container(
      key: ValueKey('field-stints-${row.carIndex}'),
      height: _stintRowHeight,
      color: row.isPlayer ? AppColors.playerRow : null,
      child: Row(
        children: [
          SizedBox(
            width: _stintPositionWidth,
            child: Text(
              '${row.position}',
              textAlign: TextAlign.right,
              style: kTabularStyle.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(width: _stintColumnGap),
          SizedBox(
            width: _stintNameWidth,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontWeight: row.isPlayer ? FontWeight.w800 : FontWeight.w600,
                color: row.isPlayer ? palette.link : palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: _stintColumnGap),
          Expanded(
            child: Row(
              children: [
                for (final (i, segment) in segments.indexed) ...[
                  if (i > 0) const SizedBox(width: _stintGap),
                  Expanded(
                    flex: segment.endLap - segment.startLap + 1,
                    child: _StintBar(segment: segment),
                  ),
                ],
                if (maxLaps > covered) Spacer(flex: maxLaps - covered),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 스틴트 막대 한 칸: 컴파운드 색 + 가운데 한 글자(색만으로 구분하지 않게), 툴팁 `Medium · L1–L19`.
class _StintBar extends StatelessWidget {
  const _StintBar({required this.segment});

  final StintSegment segment;

  @override
  Widget build(BuildContext context) {
    final color = stintLineColor(segment.compound, context.palette);
    final letterColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? AppColors.textPrimary : AppColors.background;
    return Tooltip(
      message: '${segment.compound} · L${segment.startLap}–L${segment.endLap}',
      child: Container(
        height: _stintBarHeight,
        color: color,
        alignment: Alignment.center,
        child: Text(
          compoundLetter(segment.compound),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: _stintLetterSize, height: 1, fontWeight: FontWeight.w800, color: letterColor),
        ),
      ),
    );
  }
}

// -- Race Review · 핵심 장면 -----------------------------------------------------------

const String _momentsTitle = 'Race Review';
const String _momentsTag = '핵심 장면';
const double _momentRowHeight = 36;
const double _momentLapWidth = 44;
const double _momentDeltaGap = 8;
const EdgeInsets _momentPadding = EdgeInsets.symmetric(horizontal: 24);

/// 핵심 장면 카드(B안 보드): 랩 · 장면(`출발 P7 → P5`, `추월 RUSSELL`, `피트 M → H`, `패널티 · …`) · 순위 변화(`+2` 초록,
/// `−1` 빨강, 시간 벌칙 `+5s` 빨강, 그 밖 `-`).
class KeyMomentsCard extends StatelessWidget {
  const KeyMomentsCard({super.key, required this.moments});

  final List<KeyMoment> moments;

  @override
  Widget build(BuildContext context) {
    return SessionCard(
      title: _momentsTitle,
      trailing: const _CardTag(_momentsTag),
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, moment) in moments.indexed) ...[
            const Divider(height: 1),
            _MomentRow(key: ValueKey('key-moment-$i'), moment: moment),
          ],
        ],
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({super.key, required this.moment});

  final KeyMoment moment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final delta = keyMomentDeltaText(moment);
    final positionDelta = moment.positionDelta;
    final deltaColor = moment.kind == KeyMomentKind.penalty
        ? palette.danger
        : positionDelta == null || positionDelta == 0
            ? palette.textMuted
            : positionDelta > 0
                ? palette.success
                : palette.danger;
    return Container(
      height: _momentRowHeight,
      padding: _momentPadding,
      child: Row(
        children: [
          SizedBox(
            width: _momentLapWidth,
            child: Text('L${moment.lap}', style: kTabularStyle.copyWith(color: palette.textMuted)),
          ),
          Expanded(child: Text(keyMomentText(moment), maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: _momentDeltaGap),
          Text(
            delta ?? '-',
            style: kTabularStyle.copyWith(color: delta == null ? palette.textMuted : deltaColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
