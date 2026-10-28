import 'dart:math' as math;

import 'lap_detail_models.dart';

/// 진행 방향을 잴 때 앞뒤로 떨어진 거리(m) — 표본 하나하나의 흔들림을 누른다.
const double _headingSpanM = 10;

/// 곡률을 평균하는 앞뒤 거리(m).
const double _curvatureSmoothM = 15;

/// 이보다 급하게(곡률 반지름 200m 아래) 돌면 코너 안으로 본다(1/m).
const double _cornerCurvature = 1 / 200;

/// 같은 방향으로 도는 두 구간 사이가 이보다 짧으면 한 코너로 묶는다(m).
const double _mergeGapM = 25;

/// 코너로 셀 최소 방향 변화(라디안, 20°). 이보다 작으면 직선의 살짝 꺾임으로 본다.
const double _minTurnRad = 20 * math.pi / 180;

const double _fullTurn = 2 * math.pi;

/// 코너 도는 방향. 진행 방향 각이 커지는 쪽 = 오른쪽(다시보기 차 자세와 같은 기준).
enum CornerDirection { left, right }

/// 랩 주행선에서 찾은 코너 하나: 출발선부터 센 번호(1부터), 랩 거리 구간(m), 방향.
/// 번호는 주행선의 꺾임으로 매기므로 공식 코너 번호와 다를 수 있다.
class LapCorner {
  const LapCorner({required this.number, required this.startM, required this.endM, required this.direction});

  final int number;
  final double startM;
  final double endM;
  final CornerDirection direction;

  /// 화면 이름(`T7`).
  String get label => 'T$number';

  bool contains(double distanceM) => distanceM >= startM && distanceM <= endM;
}

/// [trace] 주행선의 코너(순수 계산): 진행 방향 변화율(곡률)이 기준보다 큰 구간을 같은 방향끼리 묶고,
/// 충분히 꺾인 구간만 출발선부터 차례로 번호를 매긴다. 방향이 바뀌는 시케인은 코너 둘이다. 위치가 없으면 빈 목록.
List<LapCorner> detectLapCorners(LapTrace trace) {
  if (!trace.hasPositions || trace.length < 3) {
    return const [];
  }
  final n = trace.length;
  final res = trace.resolutionM.toDouble();
  final span = math.max(1, (_headingSpanM / res).round());
  int at(int i) => i.clamp(0, n - 1);
  final headings = [
    for (var i = 0; i < n; i++)
      math.atan2(trace.worldPosZ[at(i + span)] - trace.worldPosZ[at(i - span)],
          trace.worldPosX[at(i + span)] - trace.worldPosX[at(i - span)]),
  ];
  double wrap(double a) => a - _fullTurn * ((a + math.pi) / _fullTurn).floorToDouble();
  final raw = [for (var i = 0; i < n; i++) wrap(headings[at(i + 1)] - headings[at(i - 1)]) / (2 * res)];
  final smooth = math.max(1, (_curvatureSmoothM / res).round());
  final curvature = [
    for (var i = 0; i < n; i++)
      () {
        var sum = 0.0;
        var count = 0;
        for (var k = i - smooth; k <= i + smooth; k++) {
          if (k >= 0 && k < n) {
            sum += raw[k];
            count++;
          }
        }
        return sum / count;
      }(),
  ];

  // 기준을 넘는 같은 방향 구간들(표본 번호 [from, to]).
  final runs = <({int from, int to, int sign})>[];
  for (var i = 0; i < n; i++) {
    final sign = curvature[i].abs() < _cornerCurvature ? 0 : curvature[i].sign.toInt();
    if (sign == 0) {
      continue;
    }
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.sign == sign && (i - last.to) * res <= _mergeGapM) {
      runs[runs.length - 1] = (from: last.from, to: i, sign: sign);
    } else {
      runs.add((from: i, to: i, sign: sign));
    }
  }

  final corners = <LapCorner>[];
  for (final run in runs) {
    var turn = 0.0;
    for (var i = run.from; i <= run.to; i++) {
      turn += curvature[i] * res;
    }
    if (turn.abs() < _minTurnRad) {
      continue;
    }
    corners.add(LapCorner(
      number: corners.length + 1,
      startM: trace.distanceAt(run.from),
      endM: trace.distanceAt(run.to),
      direction: run.sign > 0 ? CornerDirection.right : CornerDirection.left,
    ));
  }
  return corners;
}

/// [distanceM]이 들어 있는 코너. 직선이면 null.
LapCorner? cornerAt(List<LapCorner> corners, double distanceM) {
  for (final corner in corners) {
    if (corner.contains(distanceM)) {
      return corner;
    }
  }
  return null;
}

/// 월드 위치([x]·[z])에서 가장 가까운 [trace] 표본의 랩 거리(m). 위치가 없으면 null.
double? nearestLapDistance(LapTrace trace, double x, double z) {
  if (!trace.hasPositions) {
    return null;
  }
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < trace.length; i++) {
    final dx = trace.worldPosX[i] - x;
    final dz = trace.worldPosZ[i] - z;
    final d = dx * dx + dz * dz;
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return trace.distanceAt(best);
}
