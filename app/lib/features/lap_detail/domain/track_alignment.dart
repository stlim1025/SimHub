import 'dart:math' as math;
import 'dart:ui';

import '../../tracks/domain/track_width_profile.dart';

/// 정렬 첫 단계에서 두 선을 같은 수의 점으로 나누는 개수(호 길이 기준).
const int _coarseSamples = 150;

/// 가장 가까운 점 맞추기(ICP)로 정렬을 다듬는 횟수.
const int _refineIterations = 20;

/// 실측 서킷과 게임 좌표의 축척이 이 범위를 벗어나면 다른 서킷으로 보고 쓰지 않는다.
const double _minScale = 0.9;
const double _maxScale = 1.1;

/// 실측 중심선에서 이 거리(m) 안에 있는 주행 표본을 "맞는 구간"으로 본다.
const double kTrackAlignInlierM = 12;

/// 주행 표본 가운데 이 비율 이상이 맞아야 쓴다. 레이아웃이 일부 바뀐 서킷(멜버른 등)은 맞는 구간만 실측을 쓰므로 전부 맞을 필요는 없다.
const double _minInlierFraction = 0.7;

/// 다듬기 몇 번째부터 실측선에서 이보다 먼(m) 주행 표본을 빼고 맞춘다(바뀐 구간이 정렬을 끌어당기지 않게).
const double _outlierM = 15;
const int _outlierFromIteration = 3;

/// 게임 월드 좌표에 맞춘 실측 서킷. [leftM]·[rightM]은 [center] 순서로 진행할 때 왼쪽(반시계 방향 법선)·오른쪽 폭(m).
class AlignedTrack {
  const AlignedTrack({required this.center, required this.leftM, required this.rightM});

  final List<Offset> center;
  final List<double> leftM;
  final List<double> rightM;
}

/// 2D 닮음 변환(축척·회전·이동, [reflect]이면 먼저 y를 뒤집는다).
typedef _Similarity = ({double scale, double angle, double tx, double ty, bool reflect});

/// 실측 서킷 [profile]을 주행선 [driving](게임 월드 X/Z, 한 바퀴)에 맞춘다. 맞지 않으면 null(추정 모양을 쓴다).
/// 1) 두 선을 호 길이로 같은 개수로 나눠 뒤집기·방향·시작점을 모두 시도해 가장 잘 맞는 닮음 변환을 찾고
/// 2) 가장 가까운 점끼리 다시 맞추기를 되풀이해 다듬는다(멀리 떨어진 표본은 빼고).
/// 어느 구간이 맞는지는 쓰는 쪽(서킷 모양)이 점마다 다시 판단한다.
AlignedTrack? alignTrackProfile(TrackWidthProfile profile, List<Offset> driving) {
  if (driving.length < _coarseSamples ~/ 10 || profile.length < 3) {
    return null;
  }
  final drive = _resampleClosed(driving, _coarseSamples);
  final real = _resampleClosed(profile.center, _coarseSamples);

  _Similarity? best;
  var bestError = double.infinity;
  for (final reflect in [false, true]) {
    final source = [for (final p in real) reflect ? Offset(p.dx, -p.dy) : p];
    for (final direction in [1, -1]) {
      for (var start = 0; start < _coarseSamples; start++) {
        final matched = [
          for (var i = 0; i < _coarseSamples; i++) source[(start + direction * i) % _coarseSamples],
        ];
        final fit = _fitSimilarity(drive, matched);
        final error = _sumSquaredError(drive, matched, fit);
        if (error < bestError) {
          bestError = error;
          best = (scale: fit.scale, angle: fit.angle, tx: fit.tx, ty: fit.ty, reflect: reflect);
        }
      }
    }
  }
  var transform = best!;

  // 다듬기: 주행 표본마다 가장 가까운 실측 선분 위의 점과 짝지어 닮음 변환을 다시 구한다.
  // (점끼리 짝지으면 점 간격만큼 어긋난 채 멈출 수 있어 선분에 투영한다.)
  final reflected = [for (final p in profile.center) transform.reflect ? Offset(p.dx, -p.dy) : p];
  final m = reflected.length;
  for (var iteration = 0; iteration < _refineIterations; iteration++) {
    final placed = [for (final p in reflected) _apply(transform, p)];
    final targets = <Offset>[];
    final sources = <Offset>[];
    for (final p in driving) {
      final j = _nearestIndex(placed, p);
      var bestSource = reflected[j];
      var bestDistance = double.infinity;
      for (final k in [(j - 1 + m) % m, j]) {
        final a = placed[k];
        final b = placed[(k + 1) % m];
        final ab = b - a;
        final lengthSquared = ab.distanceSquared;
        final t = lengthSquared == 0
            ? 0.0
            : (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared).clamp(0.0, 1.0);
        final d = (Offset.lerp(a, b, t)! - p).distanceSquared;
        if (d < bestDistance) {
          bestDistance = d;
          bestSource = Offset.lerp(reflected[k], reflected[(k + 1) % m], t)!;
        }
      }
      if (iteration >= _outlierFromIteration && bestDistance > _outlierM * _outlierM) {
        continue;
      }
      targets.add(p);
      sources.add(bestSource);
    }
    if (targets.length < 3) {
      return null;
    }
    final fit = _fitSimilarity(targets, sources);
    transform = (scale: fit.scale, angle: fit.angle, tx: fit.tx, ty: fit.ty, reflect: transform.reflect);
  }
  if (transform.scale < _minScale || transform.scale > _maxScale) {
    return null;
  }

  final center = [for (final p in reflected) _apply(transform, p)];
  final inliers = driving.where((p) => (center[_nearestIndex(center, p)] - p).distance <= kTrackAlignInlierM).length;
  if (inliers < driving.length * _minInlierFraction) {
    return null;
  }
  // 뒤집으면 진행 방향의 왼쪽·오른쪽이 바뀐다.
  return AlignedTrack(
    center: center,
    leftM: transform.reflect ? profile.rightM : profile.leftM,
    rightM: transform.reflect ? profile.leftM : profile.rightM,
  );
}

/// [points]에서 [query]와 가장 가까운 점의 번호.
int _nearestIndex(List<Offset> points, Offset query) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < points.length; i++) {
    final d = (points[i] - query).distanceSquared;
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

Offset _apply(_Similarity t, Offset p) {
  final c = math.cos(t.angle);
  final s = math.sin(t.angle);
  return Offset(t.scale * (c * p.dx - s * p.dy) + t.tx, t.scale * (s * p.dx + c * p.dy) + t.ty);
}

/// [source]를 [target]에 맞추는 닮음 변환(최소 제곱, 짝지은 점끼리).
({double scale, double angle, double tx, double ty}) _fitSimilarity(List<Offset> target, List<Offset> source) {
  final n = target.length;
  var ax = 0.0, ay = 0.0, bx = 0.0, by = 0.0;
  for (var i = 0; i < n; i++) {
    ax += target[i].dx;
    ay += target[i].dy;
    bx += source[i].dx;
    by += source[i].dy;
  }
  ax /= n;
  ay /= n;
  bx /= n;
  by /= n;
  var dot = 0.0, cross = 0.0, spread = 0.0;
  for (var i = 0; i < n; i++) {
    final a0 = target[i].dx - ax, a1 = target[i].dy - ay;
    final b0 = source[i].dx - bx, b1 = source[i].dy - by;
    dot += a0 * b0 + a1 * b1;
    cross += a1 * b0 - a0 * b1;
    spread += b0 * b0 + b1 * b1;
  }
  final angle = math.atan2(cross, dot);
  final scale = spread == 0 ? 1.0 : math.sqrt(dot * dot + cross * cross) / spread;
  final c = math.cos(angle), s = math.sin(angle);
  return (scale: scale, angle: angle, tx: ax - scale * (c * bx - s * by), ty: ay - scale * (s * bx + c * by));
}

double _sumSquaredError(List<Offset> target, List<Offset> source, ({double scale, double angle, double tx, double ty}) t) {
  final c = math.cos(t.angle), s = math.sin(t.angle);
  var sum = 0.0;
  for (var i = 0; i < target.length; i++) {
    final x = t.scale * (c * source[i].dx - s * source[i].dy) + t.tx - target[i].dx;
    final y = t.scale * (s * source[i].dx + c * source[i].dy) + t.ty - target[i].dy;
    sum += x * x + y * y;
  }
  return sum;
}

/// 닫힌 선을 호 길이 기준 [count]개의 같은 간격 점으로.
List<Offset> _resampleClosed(List<Offset> points, int count) {
  final loop = [...points, points.first];
  final cumulative = <double>[0];
  for (var i = 1; i < loop.length; i++) {
    cumulative.add(cumulative.last + (loop[i] - loop[i - 1]).distance);
  }
  final total = cumulative.last;
  final result = <Offset>[];
  var j = 0;
  for (var i = 0; i < count; i++) {
    final s = total * i / count;
    while (j < loop.length - 2 && cumulative[j + 1] < s) {
      j++;
    }
    final span = cumulative[j + 1] - cumulative[j];
    final t = span <= 0 ? 0.0 : (s - cumulative[j]) / span;
    result.add(Offset.lerp(loop[j], loop[j + 1], t)!);
  }
  return result;
}
