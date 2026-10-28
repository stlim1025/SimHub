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

/// 공식 코너가 감지한 회전 구간 밖(직선의 킹크 등)에 있을 때 공식 지점 앞뒤로 잡는 코너 구간 반폭(m),
/// 공식 지점이 회전 구간에서 이만큼(m) 안이면 그 구간의 코너로 본다, 방향을 잴 앞뒤 거리(m).
const double _officialHalfSpanM = 25;
const double _officialRunSlackM = 40;
const double _officialTurnSpanM = 30;

/// 랩의 코너 하나: 번호(공식 번호, 공식 데이터가 없는 트랙은 출발선부터 센 번호)·글자(`A` 등, 없으면 빈 글자),
/// 랩 거리 구간(m), 방향.
class LapCorner {
  const LapCorner({
    required this.number,
    required this.startM,
    required this.endM,
    required this.direction,
    this.letter = '',
  });

  final int number;
  final String letter;
  final double startM;
  final double endM;
  final CornerDirection direction;

  /// 화면 이름(`T7`·`T12A`).
  String get label => 'T$number$letter';

  bool contains(double distanceM) => distanceM >= startM && distanceM <= endM;
}

/// 공식 코너 하나: 번호·글자, 랩 거리 비율(결승선부터 잰 거리 / 랩 길이).
typedef OfficialCorner = ({int number, String letter, double fraction});

/// 공식 코너 asset(`tracks` → 트랙 이름 → `corners`)을 읽는다. 형식이 틀린 트랙·코너는 건너뛴다.
Map<String, List<OfficialCorner>> parseTrackCorners(Map<String, dynamic> json) {
  final result = <String, List<OfficialCorner>>{};
  final tracks = json['tracks'];
  if (tracks is! Map<String, dynamic>) {
    return result;
  }
  for (final MapEntry(:key, :value) in tracks.entries) {
    final corners = value is Map<String, dynamic> ? value['corners'] : null;
    if (corners is! List) {
      continue;
    }
    result[key] = [
      for (final c in corners)
        if (c is Map<String, dynamic> && c['number'] is int && c['fraction'] is num)
          (number: c['number'] as int, letter: (c['letter'] as String?) ?? '', fraction: (c['fraction'] as num).toDouble()),
    ];
  }
  return result;
}

/// 회전 구간(표본 번호 [from, to], 방향 부호)과 표본마다 진행 방향(라디안).
typedef _Runs = ({List<({int from, int to, int sign, double turn})> runs, List<double> headings});

double _wrap(double a) => a - _fullTurn * ((a + math.pi) / _fullTurn).floorToDouble();

/// 진행 방향 변화율(곡률)이 기준보다 큰 같은 방향 구간들. 각 구간의 방향 변화 합(라디안)도 함께.
_Runs _curvatureRuns(LapTrace trace) {
  final n = trace.length;
  final res = trace.resolutionM.toDouble();
  final span = math.max(1, (_headingSpanM / res).round());
  int at(int i) => i.clamp(0, n - 1);
  final headings = [
    for (var i = 0; i < n; i++)
      math.atan2(trace.worldPosZ[at(i + span)] - trace.worldPosZ[at(i - span)],
          trace.worldPosX[at(i + span)] - trace.worldPosX[at(i - span)]),
  ];
  final raw = [for (var i = 0; i < n; i++) _wrap(headings[at(i + 1)] - headings[at(i - 1)]) / (2 * res)];
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

  final runs = <({int from, int to, int sign, double turn})>[];
  for (var i = 0; i < n; i++) {
    final sign = curvature[i].abs() < _cornerCurvature ? 0 : curvature[i].sign.toInt();
    if (sign == 0) {
      continue;
    }
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.sign == sign && (i - last.to) * res <= _mergeGapM) {
      var turn = last.turn;
      for (var k = last.to + 1; k <= i; k++) {
        turn += curvature[k] * res;
      }
      runs[runs.length - 1] = (from: last.from, to: i, sign: sign, turn: turn);
    } else {
      runs.add((from: i, to: i, sign: sign, turn: curvature[i] * res));
    }
  }
  return (runs: runs, headings: headings);
}

/// [trace] 주행선의 코너(순수 계산): 진행 방향 변화율(곡률)이 기준보다 큰 구간을 같은 방향끼리 묶고,
/// 충분히 꺾인 구간만 출발선부터 차례로 번호를 매긴다. 방향이 바뀌는 시케인은 코너 둘이다. 위치가 없으면 빈 목록.
/// 공식 코너 데이터가 없는 트랙에서만 쓴다([resolveLapCorners]).
List<LapCorner> detectLapCorners(LapTrace trace) {
  if (!trace.hasPositions || trace.length < 3) {
    return const [];
  }
  final corners = <LapCorner>[];
  for (final run in _curvatureRuns(trace).runs) {
    if (run.turn.abs() < _minTurnRad) {
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

/// 공식 코너([official], 랩 거리 비율)를 [trace]에 올린다(순수 계산). 공식 지점 = 비율 × 이 랩 길이.
/// 그 지점이 회전 구간 안(또는 [_officialRunSlackM] 안)이면 그 구간을 코너 구간으로 쓰고, 한 구간에 공식 코너가 여럿이면
/// 이웃 공식 지점과의 가운데에서 나눈다. 회전 구간 밖(직선의 킹크)이면 지점 앞뒤 [_officialHalfSpanM]. 방향은 그 구간의 회전 방향.
List<LapCorner> officialLapCorners(LapTrace trace, List<OfficialCorner> official) {
  if (!trace.hasPositions || trace.length < 3 || official.isEmpty) {
    return const [];
  }
  final (:runs, :headings) = _curvatureRuns(trace);
  final lapM = trace.lengthM;
  final apexes = [for (final c in official) (c.fraction * lapM).clamp(0.0, lapM)];
  final corners = <LapCorner>[];
  for (var k = 0; k < official.length; k++) {
    final apex = apexes[k];
    // 공식 지점에 가장 가까운 회전 구간(안에 있으면 거리 0). 두 구간 사이면 더 가까운 쪽.
    ({int from, int to, int sign, double turn})? run;
    var bestGap = _officialRunSlackM;
    for (final r in runs) {
      final gap = math.max(0.0, math.max(trace.distanceAt(r.from) - apex, apex - trace.distanceAt(r.to)));
      if (gap <= bestGap) {
        bestGap = gap;
        run = r;
        if (gap == 0) {
          break;
        }
      }
    }
    var start = run == null ? apex - _officialHalfSpanM : trace.distanceAt(run.from);
    var end = run == null ? apex + _officialHalfSpanM : trace.distanceAt(run.to);
    if (k > 0) {
      start = math.max(start, (apexes[k - 1] + apex) / 2);
    }
    if (k < official.length - 1) {
      end = math.min(end, (apex + apexes[k + 1]) / 2);
    }
    start = math.min(math.max(0, start), apex);
    end = math.max(math.min(lapM, end), apex);

    // 방향 = 이 코너 구간(한 회전 구간을 나눴으면 나뉜 부분)에서의 진행 방향 변화. 구간이 짧으면 공식 지점 앞뒤로 잰다.
    final from = end - start < _officialTurnSpanM ? apex - _officialTurnSpanM / 2 : start;
    final to = end - start < _officialTurnSpanM ? apex + _officialTurnSpanM / 2 : end;
    int index(double d) => (d / trace.resolutionM).round().clamp(0, trace.length - 1);
    // 헤어핀처럼 180° 가까이 돌아도 부호가 뒤집히지 않게 한 칸씩 누적한다.
    var turn = 0.0;
    for (var i = index(from); i < index(to); i++) {
      turn += _wrap(headings[i + 1] - headings[i]);
    }
    corners.add(LapCorner(
      number: official[k].number,
      letter: official[k].letter,
      startM: start,
      endM: end,
      direction: turn >= 0 ? CornerDirection.right : CornerDirection.left,
    ));
  }
  return corners;
}

/// 이 랩의 코너: 트랙의 공식 코너([official])가 있으면 공식 번호로, 없으면 주행선에서 찾아 번호를 매긴다.
List<LapCorner> resolveLapCorners(LapTrace trace, List<OfficialCorner>? official) =>
    official == null || official.isEmpty ? detectLapCorners(trace) : officialLapCorners(trace, official);

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
