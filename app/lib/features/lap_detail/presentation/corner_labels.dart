import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../domain/lap_corners.dart';

/// 코너 번호 자리: 바깥쪽 방향을 잴 앞뒤 거리(m), 코너가 거의 곧을 때(바깥쪽을 못 잴 때) 기준(px).
const double _outwardSpanM = 30;
const double _minOutward = 0.5;

/// 배지 후보: 코너 둘레 방향 수, 배지 가장자리와 코너 지점 사이 거리 후보(px, 가까운 것부터).
const int _labelDirections = 16;
const List<double> _labelGaps = [5, 10, 16, 24, 34, 46, 60];

/// 후보 고르기: 바깥쪽에서 벗어난 각도(라디안)당 비용을 거리(px)로 친 값.
const double _anglePenaltyPx = 8;

/// 배지끼리·배지와 트랙 선 사이 여유(px), 트랙 선 검사에 쓸 점 간격(px).
const double _labelClearance = 2;
const double _trackClearance = 1;
const double _trackSampleStepPx = 2;

/// 배지가 이보다 멀리(px, 배지 가장자리 기준) 놓이면 코너까지 선과 점을 긋는다.
const double _leaderMinGap = 7;
const double _anchorDotRadius = 2;
const double _leaderWidth = 1;

/// 이웃 코너를 셀 반경(px): 코너가 몰린 곳부터 자리를 잡는다.
const double _crowdRadiusPx = 40;

/// 코너 번호 글자·배지.
const double _labelFontSize = 10;
const double _labelPadH = 4;
const double _labelPadV = 1.5;
const double _labelRadius = 6;
const double _labelBorder = 1;

/// 트랙 지도에 코너 번호를 그릴 때 상자 가장자리 여백(px, 번호가 들어갈 자리를 남긴다).
const double kCornerLabelMapPadding = 24;

/// 코너 번호 배지 모양: 글자(앱 글꼴·글자색), 배지 바탕색, 테두리·지시선 색.
typedef CornerLabelStyle = ({TextStyle text, Color background, Color border});

/// 지금 테마의 코너 번호 배지 모양.
CornerLabelStyle cornerLabelStyleOf(BuildContext context) {
  final palette = context.palette;
  return (
    text: (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: palette.textPrimary,
      fontSize: _labelFontSize,
      fontWeight: FontWeight.w700,
      height: 1,
    ),
    background: palette.surface,
    border: palette.textMuted,
  );
}

/// 코너 번호 하나: 글자, 트랙 위 지점, 배지 가운데.
typedef CornerLabelPlacement = ({String text, Offset anchor, Offset center});

/// 코너 번호 배지 자리(순수 계산). 배지끼리 겹치지 않고 트랙 선([trackHalfWidth] 두께의 반)도 덮지 않게 놓는다.
/// 후보는 코너 가운데 지점 둘레 [_labelDirections]방향 × [_labelGaps] 거리이고, 코너 바깥쪽(앞뒤 [_outwardSpanM] 점을 이은 선에서
/// 멀어지는 쪽)에 가깝고 코너에 가까운 자리부터 고른다. 상자 [size] 밖으로 나가는 후보는 쓰지 않는다.
/// 코너가 몰린 곳([_crowdRadiusPx] 안 이웃이 많은 코너)부터 자리를 잡는다. 트랙을 덮지 않는 자리 중 지시선이 다른 트랙 줄을
/// 가로지르지 않는 자리를 먼저 고르고, 그런 자리가 없으면 트랙을 덜 덮는 자리, 그래도 없으면 바깥쪽 가장 가까운 자리. 결과는 [corners] 순서다.
/// [points]는 표본마다 화면 점(칸 i = 랩 거리 i × [resolutionM]), [sizeOf]는 글자마다 배지 크기.
List<CornerLabelPlacement> placeCornerLabels({
  required List<Offset> points,
  required double resolutionM,
  required List<LapCorner> corners,
  required Size size,
  required Size Function(String text) sizeOf,
  double trackHalfWidth = 0,
}) {
  if (points.length < 3 || corners.isEmpty || resolutionM <= 0) {
    return const [];
  }
  final n = points.length;
  final span = math.max(1, (_outwardSpanM / resolutionM).round());
  final trackPoints = _thinned(points);
  final trackReach = trackHalfWidth + _trackClearance;
  final bounds = Offset.zero & size;

  final anchors = <Offset>[];
  final outwards = <Offset>[];
  for (final corner in corners) {
    final i = ((corner.startM + corner.endM) / 2 / resolutionM).round().clamp(0, n - 1);
    final anchor = points[i];
    final before = points[(i - span).clamp(0, n - 1)];
    final after = points[(i + span).clamp(0, n - 1)];
    var outward = anchor - (before + after) / 2;
    if (outward.distance < _minOutward) {
      final along = after - before;
      outward = Offset(-along.dy, along.dx);
    }
    anchors.add(anchor);
    outwards.add(outward.distance == 0 ? const Offset(0, -1) : outward / outward.distance);
  }
  int crowd(int k) => [for (final a in anchors) if ((a - anchors[k]).distance <= _crowdRadiusPx) a].length;
  final order = [for (var k = 0; k < corners.length; k++) k]..sort((a, b) {
      final byCrowd = crowd(b).compareTo(crowd(a));
      return byCrowd != 0 ? byCrowd : a.compareTo(b);
    });

  int trackHits(Rect rect) {
    var hits = 0;
    for (final p in trackPoints) {
      final dx = math.max(math.max(rect.left - p.dx, 0.0), p.dx - rect.right);
      final dy = math.max(math.max(rect.top - p.dy, 0.0), p.dy - rect.bottom);
      if (dx * dx + dy * dy < trackReach * trackReach) {
        hits++;
      }
    }
    return hits;
  }

  // 코너 지점에서 배지까지 선에 닿는 트랙 점 수(코너 지점 둘레의 제 트랙은 뺀다).
  int leaderCrossings(Offset anchor, Rect rect) {
    final end = _nearestOnRect(rect, anchor);
    final along = end - anchor;
    final length = along.distance;
    final ownReach = trackReach + _leaderMinGap;
    if (length <= ownReach) {
      return 0;
    }
    var crossings = 0;
    for (final p in trackPoints) {
      if ((p - anchor).distance <= ownReach) {
        continue;
      }
      final t = (((p - anchor).dx * along.dx + (p - anchor).dy * along.dy) / (length * length)).clamp(0.0, 1.0);
      if ((anchor + along * t - p).distance < trackReach) {
        crossings++;
      }
    }
    return crossings;
  }

  final rects = List<Rect?>.filled(corners.length, null);
  for (final k in order) {
    final labelSize = sizeOf(corners[k].label);
    final anchor = anchors[k];
    final base = math.atan2(outwards[k].dy, outwards[k].dx);
    final candidates = <({Rect rect, double cost})>[];
    for (var d = 0; d < _labelDirections; d++) {
      // 0, +1, −1, +2, −2 … 칸: 바깥쪽에서 가까운 방향부터.
      final step = (d + 1) ~/ 2 * (d.isOdd ? 1 : -1);
      final angle = base + step * 2 * math.pi / _labelDirections;
      final unit = Offset(math.cos(angle), math.sin(angle));
      // 배지 가운데에서 그 방향 가장자리까지 거리.
      final extent = labelSize.width / 2 * unit.dx.abs() + labelSize.height / 2 * unit.dy.abs();
      for (final gap in _labelGaps) {
        final rect = Rect.fromCenter(
          center: anchor + unit * (extent + gap),
          width: labelSize.width,
          height: labelSize.height,
        );
        if (bounds.contains(rect.topLeft) && bounds.contains(rect.bottomRight)) {
          candidates.add((rect: rect, cost: gap + step.abs() * 2 * math.pi / _labelDirections * _anglePenaltyPx));
        }
      }
    }
    candidates.sort((a, b) => a.cost.compareTo(b.cost));
    final free = candidates.where((c) => !rects.any((r) => r != null && r.inflate(_labelClearance).overlaps(c.rect)));
    // 트랙을 덮지 않는 자리 → 그중 지시선이 다른 트랙 줄을 가로지르지 않는 자리 → 가까운 자리 순.
    Rect? chosen;
    var best = (hits: 0, crossings: 0);
    for (final c in free) {
      final score = (hits: trackHits(c.rect), crossings: leaderCrossings(anchor, c.rect));
      if (chosen == null ||
          score.hits < best.hits ||
          (score.hits == best.hits && score.crossings < best.crossings)) {
        chosen = c.rect;
        best = score;
        if (score.hits == 0 && score.crossings == 0) {
          break;
        }
      }
    }
    rects[k] = chosen ??
        candidates.firstOrNull?.rect ??
        Rect.fromCenter(center: anchor, width: labelSize.width, height: labelSize.height);
  }
  return [
    for (var k = 0; k < corners.length; k++) (text: corners[k].label, anchor: anchors[k], center: rects[k]!.center),
  ];
}

/// 트랙 지도 그림 위에 코너 번호 배지를 그린다: [placeCornerLabels]로 자리를 잡고, 멀리 놓인 배지는 코너까지 선과 점을 그은 뒤
/// 배지를 그 위에 그린다(선이 다른 배지를 가로지르지 않게). [points]는 표본마다 화면 점, [trackHalfWidth]는 덮지 않을 트랙 선 두께의 반.
void paintCornerLabels(
  Canvas canvas, {
  required List<Offset> points,
  required double resolutionM,
  required List<LapCorner> corners,
  required Size size,
  required CornerLabelStyle style,
  required double trackHalfWidth,
}) {
  if (corners.isEmpty) {
    return;
  }
  final texts = <String, TextPainter>{};
  TextPainter textOf(String label) => texts.putIfAbsent(
        label,
        () => TextPainter(text: TextSpan(text: label, style: style.text), textDirection: TextDirection.ltr)..layout(),
      );
  Size badgeSize(String label) {
    final text = textOf(label);
    return Size(text.width + _labelPadH * 2, text.height + _labelPadV * 2);
  }

  final labels = placeCornerLabels(
    points: points,
    resolutionM: resolutionM,
    corners: corners,
    size: size,
    sizeOf: badgeSize,
    trackHalfWidth: trackHalfWidth,
  );
  Rect rectOf(CornerLabelPlacement label) {
    final size = badgeSize(label.text);
    return Rect.fromCenter(center: label.center, width: size.width, height: size.height);
  }

  final leader = Paint()
    ..color = style.border
    ..style = PaintingStyle.stroke
    ..strokeWidth = _leaderWidth;
  final dot = Paint()..color = style.border;
  for (final label in labels) {
    final end = _nearestOnRect(rectOf(label), label.anchor);
    if ((end - label.anchor).distance > _leaderMinGap) {
      canvas
        ..drawLine(label.anchor, end, leader)
        ..drawCircle(label.anchor, _anchorDotRadius, dot);
    }
  }
  final fill = Paint()..color = style.background;
  final border = Paint()
    ..color = style.border
    ..style = PaintingStyle.stroke
    ..strokeWidth = _labelBorder;
  for (final label in labels) {
    final text = textOf(label.text);
    final rect = rectOf(label);
    final badge = RRect.fromRectAndRadius(rect, const Radius.circular(_labelRadius));
    canvas
      ..drawRRect(badge, fill)
      ..drawRRect(badge, border);
    text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
  }
}

/// 트랙 선 검사용으로 [_trackSampleStepPx]보다 촘촘한 점을 덜어 낸다(모양은 그대로).
List<Offset> _thinned(List<Offset> points) {
  final result = <Offset>[points.first];
  for (final p in points.skip(1)) {
    if ((p - result.last).distance >= _trackSampleStepPx) {
      result.add(p);
    }
  }
  return result;
}

/// [rect]에서 [p]에 가장 가까운 점(지시선 끝).
Offset _nearestOnRect(Rect rect, Offset p) => Offset(p.dx.clamp(rect.left, rect.right), p.dy.clamp(rect.top, rect.bottom));
