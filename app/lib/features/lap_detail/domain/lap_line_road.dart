import 'dart:math' as math;
import 'dart:ui';

import 'lap_detail_models.dart';

/// 주행선으로 추정한 도로: 가운데 선(주행선을 따라 고른 간격으로 찍은 점 — 표본 수와 다를 수 있다), 점마다 가운데에서
/// 왼쪽·오른쪽 도로 끝까지 거리(m), 한 바퀴로 닫혔는지.
typedef LapLineRoad = ({List<Offset> center, List<double> leftM, List<double> rightM, bool closed});

/// 첫·마지막 표본이 이 거리(m)보다 가까우면 한 바퀴로 이어진 닫힌 서킷으로 본다.
const double _closedLoopM = 40;

/// 곡률(1/m) × 이 값 = 코너에서 넓어지는 폭(m).
const double _cornerWidthGain = 150;

/// 추정 도로 폭을 고르는 이동 평균 반폭(표본 수).
const int _widthSmoothSamples = 6;

/// 주행선 곡률을 고르는 이동 평균 반폭(m): 조향을 고쳐 잡느라 생긴 잔물결을 없앤다.
const double _curvatureSmoothM = 10;

/// 주행선이 이 곡률(1/m, 반지름 약 330m)보다 굽은 구간을 코너로 본다. [_cornerMinM](m)보다 짧게 이어진 구간은 코너가 아니다.
const double _cornerCurvature = 0.003;
const double _cornerMinM = 15;

/// 코너에서 주행선이 꺾는 각(도)이 [_fullSwingDeg] 이상이면 도로 폭을 다 쓰고(바깥 → 안쪽 → 바깥),
/// [_noSwingDeg] 이하면 도로 가운데로 지난다고 본다(그 사이는 비례).
const double _noSwingDeg = 10;
const double _fullSwingDeg = 30;

/// 에이펙스: 코너에서 가장 굽은 곡률의 이 비율 이상으로 굽은 구간의 한가운데 표본 — 레이싱 라인은 코너 내내 거의 같은 반지름으로
/// 굽지만 안쪽 도로 끝에는 한 점에서만 스친다. 그 자리에서 주행선은 안쪽 도로 끝에서 [_apexGapM](m) 떨어져 있다.
const double _apexPlateau = 0.85;
const double _apexGapM = 1.2;

/// 코너 앞뒤로 [_outsideLeadM](m) 떨어진 자리(진입 전·탈출 뒤)에서 주행선은 바깥 도로 끝에서 [_outsideGapM](m) 떨어져 있다.
const double _outsideLeadM = 40;
const double _outsideGapM = 2;

/// 반대쪽으로 굽는 두 코너 사이에서 한쪽 바깥 끝에서 반대편 바깥 끝으로 건너가는 데 드는 거리(m).
const double _crossM = 100;

/// 연석 쪽 바퀴만 연석을 밟은 표본: 차 가운데가 그 쪽 도로 끝에서 이만큼(m) 안쪽에 있다(바깥 바퀴가 연석 위에 0.7m쯤 올라탄 자리).
const double _kerbGapM = 0.3;

/// 연석을 밟은 표본에서 이 거리(m) 안의 추정 단서(에이펙스·진입·탈출)는 버린다(잰 값과 추정이 엇갈려 도로 끝이 흔들리지 않게).
const double _measuredClearM = 20;

/// 단서에서 [_holdM](m)까지는 그 값을 그대로 쓰고, 더 멀어지면 [_fadeM](m)에 걸쳐 주행선 = 도로 가운데로 돌아간다(긴 직선).
const double _holdM = 50;
const double _fadeM = 100;

/// 도로 가운데 이동량을 고르는 이동 평균 반폭(m). 단서 사이는 이미 부드럽게 이었으므로 칸마다 조금씩 다른 잰 단서만 고르면 된다 —
/// 넓게 고르면 연석을 밟은 짧은 구간에서 도로 끝이 차에서 떨어진다.
const double _offsetSmoothM = 5;

/// 도로 가운데가 주행선에서 옆으로 멀어지거나 다가오는 기울기 상한(옆 m / 진행 m, 약 17°). 코너 하나를 바깥 → 안쪽으로 지나는 기울기는
/// 이보다 완만하다.
const double _maxSlewSlope = 0.3;

/// 도로 가운데가 주행선에서 이 거리(m) 넘게 떨어져 있으면 주행선이 붙어 있는 쪽 도로 끝만 지킨다(그 안에서는 두 쪽이 나눠 맡는다).
const double _sideBlendM = 2;

/// 연석을 밟은 표본에서 이 거리(m)까지 그 쪽 도로 끝을 지킨다(멀어질수록 덜).
const double _pinFadeM = 15;

/// 한쪽 도로 폭(가운데에서 도로 끝까지)의 하한(m).
const double _minSideM = 1;

/// 혼자 옆으로 튄 위치 표본: 앞뒤 표본을 이은 선에서 이 거리(m) 넘게, 이웃 표본이 벗어난 거리의 이 배수 넘게 벗어난 표본.
const double _spikeMinM = 0.6;
const double _spikeRatio = 1.2;

/// 닫힌 주행선의 끝과 처음이 옆으로 어긋난 폭을 나눠 옮기는 거리(m, 끝 쪽·처음 쪽 각각).
const double _seamBlendM = 80;

/// 비교 랩 표본을 내 랩 주행선 표본에 짝지을 때 같은 랩 거리 둘레로 찾는 범위(표본 수).
const int _matchWindow = 40;

/// 연석을 밟은 표본 하나: 표본 번호, 연석이 서킷 그림의 왼쪽 도로 끝에 있는지(아니면 오른쪽), 차 가운데에서 그 쪽 도로 끝까지 거리
/// (m — 음수면 차 가운데가 도로 끝을 넘어 연석 위나 그 너머에 있다).
typedef KerbTouch = ({int sample, bool left, double gapM});

/// [lap]에서 연석을 밟은 표본들(표본 순서대로)과 그 연석이 어느 쪽 도로 끝에 있는지. 바퀴 쪽 기록이 없으면 빈 목록.
/// 접촉이 이어진 구간(한 표본 빈 틈은 같은 구간)은 연석 하나를 밟은 것으로 보고, 처음으로 한쪽 바퀴만 닿은 표본의 그 쪽에 연석이 있다고 본다 —
/// 시케인을 깊게 타면 안쪽 바퀴 → 네 바퀴 → 바깥 바퀴 순으로 닿는데, 밟은 바퀴 쪽을 표본마다 따로 보면 연석이 양쪽을 오간다.
/// 그 쪽 바퀴만 닿았으면 차 가운데는 도로 끝 [_kerbGapM] 안쪽, 양쪽 다 닿았으면 연석([kerbWidthM] 폭) 한가운데,
/// 반대쪽 바퀴만 닿았으면(차가 연석을 넘어갔다) 연석 바깥 끝 너머에 있다.
/// 게임 월드 X·Z 평면에서는 운전대를 오른쪽으로 꺾을 때 주행선이 법선 (−sin, cos) 쪽으로 굽는다 — 서킷 그림이 "왼쪽"이라 부르는
/// 그 법선 쪽이 운전자에게는 오른쪽이라, 운전자 오른쪽 바퀴가 밟은 연석은 그림의 왼쪽 도로 끝에, 왼쪽 바퀴는 오른쪽 끝에 있다.
List<KerbTouch> kerbTouches(LapTrace lap, {required double kerbWidthM}) {
  if (!lap.hasKerbSides) {
    return const [];
  }
  final n = lap.length;
  bool onLeft(int i) => lap.kerbContactRight[i];
  bool onRight(int i) => lap.kerbContactLeft[i];
  bool touching(int i) => i < n && (onLeft(i) || onRight(i));
  final touches = <KerbTouch>[];
  var i = 0;
  while (i < n) {
    if (!touching(i)) {
      i++;
      continue;
    }
    var end = i;
    while (touching(end + 1) || touching(end + 2)) {
      end++;
    }
    final first = [for (var k = i; k <= end; k++) k].where((k) => onLeft(k) != onRight(k)).firstOrNull;
    if (first != null) {
      final left = onLeft(first);
      for (var k = i; k <= end; k++) {
        final near = left ? onLeft(k) : onRight(k);
        final far = left ? onRight(k) : onLeft(k);
        if (near || far) {
          final gap = !far ? _kerbGapM : (near ? -kerbWidthM / 2 : -(kerbWidthM + _kerbGapM));
          touches.add((sample: k, left: left, gapM: gap));
        }
      }
    }
    i = end + 1;
  }
  return touches;
}

/// 주행선의 코너 하나: 표본 범위([start]~[end] — 닫힌 서킷이면 [end]가 표본 수를 넘을 수 있어 쓸 때 나머지로 접는다),
/// 굽는 쪽([sign]: 1 = 왼쪽), 에이펙스 표본([apex]), 도로 폭을 쓰는 정도([swing], 0~1).
typedef _Corner = ({int start, int end, int sign, int apex, double swing});

/// 실측 서킷도 모든 차 표본 형상도 없는 트랙에서, 내 랩([player])과 비교 랩([ghost]) 주행선만으로 도로를 추정한다(순수 함수).
/// 레이싱 라인은 코너마다 바깥 → 에이펙스 안쪽 → 바깥으로 도로 폭을 다 쓰므로, 주행선이 굽는 모양에서 코너를 찾아
/// 진입 전·탈출 뒤에는 바깥 도로 끝을, 에이펙스에서는 안쪽 도로 끝을 주행선 옆에 두고 그 사이를 이어 도로 가운데를 정한다
/// (주행선을 길게 평균한 선을 가운데로 쓰면 차가 늘 도로 한가운데를 달려 보이고, 에이펙스에서는 오히려 바깥쪽에 놓인다).
/// 연석을 밟은 표본([kerbTouches])은 그 쪽 도로 끝이 바로 그 자리라는 잰 단서라 추정보다 먼저 쓴다.
/// 도로 폭은 [widthM]이고 코너에서는 곡률에 따라 [cornerExtraWidthM]까지 넓어진다. 연석 폭은 [kerbWidthM](도로 끝 바깥에 그리는 폭).
/// 왼쪽 = 진행 방향 법선 (−sin, cos) 쪽.
LapLineRoad roadFromLapLines(
  LapTrace player, {
  LapTrace? ghost,
  required double widthM,
  required double cornerExtraWidthM,
  required double kerbWidthM,
}) {
  final positions = _despiked([for (var i = 0; i < player.length; i++) Offset(player.worldPosX[i], player.worldPosZ[i])]);
  final closed = positions.length > 2 && (positions.first - positions.last).distance < _closedLoopM;
  final nominal = player.resolutionM.toDouble();
  // 위치 표본은 랩 거리 칸마다 가장 가까운 게임 프레임의 값이라 간격이 고르지 않다(같은 자리가 겹치거나 두 칸만큼 벌어진다).
  // 그대로 도로 가운데로 쓰면 겹친 자리에서 도로 끝이 접히므로, 지나간 길을 따라 고른 간격으로 다시 찍는다.
  final even = _evenly(closed ? _seamless(positions, nominal) : positions, nominal, closed: closed);
  final resolution = even.spacing;
  final line = even.points;
  final n = line.length;
  int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
  int samples(double meters) => math.max(1, (meters / resolution).round());

  final headings = [
    for (var i = 0; i < n; i++)
      () {
        final d = line[at(i + 1)] - line[at(i - 1)];
        return math.atan2(d.dy, d.dx);
      }(),
  ];
  final normals = [for (final h in headings) Offset(-math.sin(h), math.cos(h))];
  final curvatures = _average(
    [for (var i = 0; i < n; i++) _angleDiff(headings[at(i + 1)], headings[at(i - 1)]) / (2 * resolution)],
    samples(_curvatureSmoothM),
    at,
  );
  // 폭은 넓게 평균해 가장자리가 들쭉날쭉하지 않고 서서히 넓어졌다 좁아지게 한다.
  final halves = _average(
    [for (final k in curvatures) (widthM + math.min(cornerExtraWidthM, k.abs() * _cornerWidthGain)) / 2],
    _widthSmoothSamples,
    at,
  );

  // 추정 단서(표본 → 도로 가운데가 주행선에서 왼쪽으로 떨어진 거리 m): 에이펙스에서는 주행선이 안쪽 끝 옆, 진입 전·탈출 뒤에는 바깥 끝 옆.
  final corners = _corners(curvatures, resolution, closed: closed);
  final prior = <int, double>{};
  for (final corner in corners) {
    final k = at(corner.apex);
    prior[k] = -corner.sign * corner.swing * (halves[k] - _apexGapM);
  }
  final lead = samples(_outsideLeadM);
  double outside(_Corner corner, int k, [double share = 1]) =>
      corner.sign * corner.swing * share * (halves[k] - _outsideGapM);
  for (var c = 0; c < corners.length; c++) {
    final current = corners[c];
    final isLast = c + 1 == corners.length;
    if (isLast && !closed) {
      final exit = current.end + lead;
      if (exit < n) {
        prior[exit] = outside(current, exit);
      }
      continue;
    }
    final next = corners[(c + 1) % corners.length];
    final nextStart = isLast ? next.start + n : next.start;
    final between = nextStart - current.end - 1;
    if (between >= 2 * lead) {
      // 두 코너 사이가 넉넉하다: 앞 코너를 빠져나와 바깥 끝에 닿고, 다음 코너 앞에서 다시 바깥 끝에 선다.
      // 반대쪽으로 굽는 코너면 두 바깥 끝이 서로 반대편이라 그 사이에서 도로를 건너야 한다 — 건널 거리([_crossM])가 모자란 만큼
      // 두 자리 모두 덜 벌린다(붙어 있으면 도로 가운데로 지난다). 그대로 두면 이웃한 두 단서 사이에서 도로가 옆으로 튄다.
      final share = current.sign == next.sign ? 1.0 : ((between - 2 * lead) * resolution / _crossM).clamp(0.0, 1.0);
      final exit = at(current.end + lead);
      prior[exit] = outside(current, exit, share);
      final entry = at(nextStart - lead);
      prior[entry] = outside(next, entry, share);
    } else if (current.sign == next.sign && between > 0) {
      // 같은 쪽으로 굽는 두 코너가 붙어 있다: 사이에서 바깥으로 조금만 풀렸다 다시 들어온다(사이가 짧을수록 덜).
      final k = at(current.end + 1 + between ~/ 2);
      prior[k] = current.sign * math.min(current.swing, next.swing) * (between / (2 * lead)) * (halves[k] - _outsideGapM);
    }
    // 반대쪽으로 굽는 두 코너가 붙어 있으면(S자) 사이 단서 없이 에이펙스에서 에이펙스로 곧장 건너간다.
  }
  if (!closed && corners.isNotEmpty) {
    final entry = corners.first.start - lead;
    if (entry >= 0) {
      prior[entry] = outside(corners.first, entry);
    }
  }

  // 잰 단서: 연석을 밟은 표본의 그 쪽 도로 끝(주행선에서 그 쪽으로 m). 여러 표본이 겹치면 주행선에 가까운 쪽.
  final leftEnds = <int, double>{};
  final rightEnds = <int, double>{};
  for (final lap in [player, ?ghost]) {
    if (!lap.hasPositions) {
      continue;
    }
    for (final touch in kerbTouches(lap, kerbWidthM: kerbWidthM)) {
      final i = touch.sample;
      var k = identical(lap, player) ? even.bins[i] : 0;
      var lateral = 0.0;
      if (!identical(lap, player)) {
        final p = Offset(lap.worldPosX[i], lap.worldPosZ[i]);
        k = _nearest(line, p, (i * lap.resolutionM / resolution).round(), closed: closed);
        lateral = (p.dx - line[k].dx) * normals[k].dx + (p.dy - line[k].dy) * normals[k].dy;
      }
      final ends = touch.left ? leftEnds : rightEnds;
      final end = touch.gapM + (touch.left ? lateral : -lateral);
      ends[k] = math.min(ends[k] ?? double.infinity, end);
    }
  }
  final clues = <int, double>{};
  for (final k in {...leftEnds.keys, ...rightEnds.keys}) {
    final left = leftEnds[k];
    final right = rightEnds[k];
    final values = [if (left != null) left - halves[k], if (right != null) halves[k] - right];
    clues[k] = values.reduce((a, b) => a + b) / values.length;
  }
  final measured = clues.keys.toList();
  final clear = samples(_measuredClearM);
  int apart(int a, int b) {
    final d = (a - b).abs();
    return closed ? math.min(d, n - d) : d;
  }

  prior.forEach((k, value) {
    if (!measured.any((m) => apart(k, m) <= clear)) {
      clues[k] = value;
    }
  });

  // 단서 사이를 잇고, 단서에서 멀어지면 주행선 = 도로 가운데로 돌아간다.
  final offsets = List<double>.filled(n, 0);
  if (clues.isNotEmpty) {
    final keys = clues.keys.toList()..sort();
    for (var k = 0; k < n; k++) {
      final before = keys.lastWhere((j) => j <= k, orElse: () => closed ? keys.last - n : -1);
      final after = keys.firstWhere((j) => j >= k, orElse: () => closed ? keys.first + n : -1);
      final hasBefore = closed || before >= 0;
      final hasAfter = closed || after >= 0;
      final from = hasBefore ? clues[at(before)]! : clues[after]!;
      final to = hasAfter ? clues[at(after)]! : from;
      final double value;
      final int gap;
      if (!hasBefore) {
        value = to;
        gap = after - k;
      } else if (!hasAfter) {
        value = from;
        gap = k - before;
      } else {
        // 단서에서는 기울기 0으로 떠나고 닿는다(부드러운 계단): 주행선은 에이펙스에서 안쪽 끝에, 진입·탈출에서 바깥 끝에 스치듯 닿았다가
        // 멀어진다. 곧게 이으면 단서마다 도로 끝이 주행선 쪽으로 뾰족하게 꺾인다.
        final t = after == before ? 0.0 : (k - before) / (after - before);
        value = from + (to - from) * t * t * (3 - 2 * t);
        gap = math.min(k - before, after - k);
      }
      offsets[k] = value * (1 - (gap * resolution - _holdM) / _fadeM).clamp(0.0, 1.0);
    }
  }
  // 양쪽 연석을 연달아 밟는 좁은 시케인에서는 가운데가 몇 십 m 만에 도로 폭만큼 옆으로 가야 해 도로가 지그재그로 튄다.
  // 가운데가 옆으로 가는 기울기를 묶고, 연석을 밟은 표본 둘레에서는 못 따라간 만큼 주행선이 붙어 있는 쪽 폭을 줄여 그 쪽 도로 끝(연석)을
  // 제자리에 둔다 — 실제로도 그런 곳은 도로가 좁다. 추정 단서(에이펙스·진입·탈출)는 가운데를 이끌 뿐 도로를 좁히지 않는다.
  final smooth = samples(_offsetSmoothM);
  final wanted = _average(offsets, smooth, at);
  final shift = _average(_slewLimited(offsets, _maxSlewSlope * resolution, closed: closed), smooth, at);
  final pinned = List<double>.filled(n, 0);
  final pinReach = samples(_pinFadeM);
  for (final m in measured) {
    for (var d = -pinReach; d <= pinReach; d++) {
      if (!closed && (m + d < 0 || m + d >= n)) {
        continue;
      }
      final t = 1 - d.abs() / (pinReach + 1);
      pinned[at(m + d)] = math.max(pinned[at(m + d)], t * t * (3 - 2 * t));
    }
  }
  final leftM = <double>[];
  final rightM = <double>[];
  for (var k = 0; k < n; k++) {
    // 주행선이 왼쪽 끝에 붙어 있으면(가운데가 주행선 오른쪽) 왼쪽 끝을, 오른쪽이면 오른쪽 끝을 지킨다. 가운데 둘레에서는 나눠 맡는다.
    final keepLeft = (0.5 - wanted[k] / (2 * _sideBlendM)).clamp(0.0, 1.0);
    final lag = (wanted[k] - shift[k]) * pinned[k];
    leftM.add(math.max(_minSideM, halves[k] + keepLeft * lag));
    rightM.add(math.max(_minSideM, halves[k] - (1 - keepLeft) * lag));
  }
  return (
    center: [for (var k = 0; k < n; k++) line[k] + normals[k] * shift[k]],
    leftM: leftM,
    rightM: rightM,
    closed: closed,
  );
}

/// [values]를 이웃 표본 사이 변화가 [step]을 넘지 않게 고친 값: 원래 값 이하인 가장 큰 것(위에서 누른 것)과
/// 원래 값 이상인 가장 작은 것(아래에서 받친 것)의 가운데 — 한쪽으로 치우치지 않는다.
List<double> _slewLimited(List<double> values, double step, {required bool closed}) {
  final n = values.length;
  final upper = List<double>.of(values);
  final lower = List<double>.of(values);
  // 닫힌 서킷은 두 바퀴 돌며 끝과 처음을 잇는다.
  for (var round = 0; round < (closed ? 2 : 1); round++) {
    for (var k = closed ? 0 : 1; k < n; k++) {
      final previous = (k - 1 + n) % n;
      upper[k] = math.min(upper[k], upper[previous] + step);
      lower[k] = math.max(lower[k], lower[previous] - step);
    }
    for (var k = closed ? n - 1 : n - 2; k >= 0; k--) {
      final next = (k + 1) % n;
      upper[k] = math.min(upper[k], upper[next] + step);
      lower[k] = math.max(lower[k], lower[next] - step);
    }
  }
  return [for (var k = 0; k < n; k++) (upper[k] + lower[k]) / 2];
}

/// 곡률([curvatures], 1/m — + = 왼쪽으로 굽는다)에서 도로 폭을 쓰는 코너들을 찾는다(표본 순서대로).
/// 닫힌 서킷은 굽지 않은 표본에서 세기 시작해 끝과 처음에 걸친 코너를 한 코너로 본다.
List<_Corner> _corners(List<double> curvatures, double resolution, {required bool closed}) {
  final n = curvatures.length;
  double bend(int i) => curvatures[i % n];
  bool bends(int i) => bend(i).abs() >= _cornerCurvature;
  final straight = closed ? curvatures.indexWhere((k) => k.abs() < _cornerCurvature) : 0;
  final origin = math.max(0, straight);
  final corners = <_Corner>[];
  var s = 0;
  while (s < n) {
    final first = origin + s;
    if (!bends(first)) {
      s++;
      continue;
    }
    final sign = bend(first) > 0 ? 1 : -1;
    var length = 1;
    while (s + length < n && bends(first + length) && bend(first + length) * sign > 0) {
      length++;
    }
    s += length;
    final last = first + length - 1;
    var turn = 0.0;
    var peak = first;
    for (var i = first; i <= last; i++) {
      turn += bend(i).abs() * resolution;
      if (bend(i).abs() > bend(peak).abs()) {
        peak = i;
      }
    }
    final swing = ((turn * 180 / math.pi - _noSwingDeg) / (_fullSwingDeg - _noSwingDeg)).clamp(0.0, 1.0);
    // 한 바퀴 내내 한쪽으로 굽으면(원) 진입도 탈출도 없어 에이펙스를 정할 수 없다.
    if (length * resolution < _cornerMinM || swing == 0 || length == n) {
      continue;
    }
    final floor = bend(peak).abs() * _apexPlateau;
    var apexStart = peak;
    while (apexStart > first && bend(apexStart - 1).abs() >= floor) {
      apexStart--;
    }
    var apexEnd = peak;
    while (apexEnd < last && bend(apexEnd + 1).abs() >= floor) {
      apexEnd++;
    }
    corners.add((start: first, end: last, sign: sign, apex: (apexStart + apexEnd) ~/ 2, swing: swing));
  }
  return corners;
}

/// 주행선 표본([raw])이 지나간 길을 따라 [resolution](m)에 가까운 고른 간격으로 다시 찍은 점들, 그 간격(m),
/// 그리고 원래 표본마다 가장 가까운 새 점 번호([bins]). 길이가 한 칸에 못 미치면 원래 표본을 그대로 돌려준다.
({List<Offset> points, double spacing, List<int> bins}) _evenly(List<Offset> raw, double resolution, {required bool closed}) {
  final along = <double>[0];
  for (var i = 1; i < raw.length; i++) {
    along.add(along.last + (raw[i] - raw[i - 1]).distance);
  }
  final total = along.last + (closed ? (raw.first - raw.last).distance : 0);
  if (raw.length < 2 || total < resolution) {
    return (points: raw, spacing: resolution, bins: [for (var i = 0; i < raw.length; i++) i]);
  }
  final count = closed ? math.max(3, (total / resolution).round()) : math.max(2, (total / resolution).round() + 1);
  final spacing = closed ? total / count : total / (count - 1);
  final points = <Offset>[];
  var segment = 0;
  for (var j = 0; j < count; j++) {
    final d = j * spacing;
    while (segment < raw.length - 1 && along[segment + 1] < d) {
      segment++;
    }
    // 마지막 표본 뒤는 닫힌 서킷이면 첫 표본으로 이어지는 구간이다.
    final hasNext = segment + 1 < raw.length;
    final a = raw[segment];
    final b = hasNext ? raw[segment + 1] : (closed ? raw.first : raw.last);
    final end = hasNext ? along[segment + 1] : total;
    final t = end > along[segment] ? ((d - along[segment]) / (end - along[segment])).clamp(0.0, 1.0) : 0.0;
    points.add(Offset.lerp(a, b, t)!);
  }
  return (
    points: points,
    spacing: spacing,
    bins: [for (final d in along) closed ? (d / spacing).round() % count : (d / spacing).round().clamp(0, count - 1)],
  );
}

/// 한 표본만 옆으로 튄 위치(게임이 가끔 다른 순간의 값을 섞어 보낸 표본)를 앞뒤 표본을 이은 선 위로 되돌린다.
/// 튄 표본은 앞뒤 표본을 이은 선에서 [_spikeMinM] 넘게 벗어나 있고, 그 이웃 표본들은 (튄 표본에 끌려) 반대쪽으로 그 절반쯤 벗어나 있다 —
/// 실제로 굽은 길은 이웃 표본들이 같은 쪽으로 벗어나므로 건드리지 않는다.
List<Offset> _despiked(List<Offset> points) {
  final n = points.length;
  // 표본 i가 앞뒤 표본을 이은 선에서 옆으로 벗어난 거리(m, 부호 = 벗어난 쪽).
  double deviation(int i) {
    final chord = points[i + 1] - points[i - 1];
    final offset = points[i] - points[i - 1];
    return chord.distance == 0 ? 0 : (chord.dx * offset.dy - chord.dy * offset.dx) / chord.distance;
  }

  final result = List<Offset>.of(points);
  for (var i = 2; i < n - 2; i++) {
    final here = deviation(i);
    final before = deviation(i - 1);
    final after = deviation(i + 1);
    final alone = here * before <= 0 && here * after <= 0 && here.abs() >= _spikeRatio * math.max(before.abs(), after.abs());
    if (here.abs() < _spikeMinM || !alone) {
      continue;
    }
    final chord = points[i + 1] - points[i - 1];
    final offset = points[i] - points[i - 1];
    final t = ((offset.dx * chord.dx + offset.dy * chord.dy) / chord.distanceSquared).clamp(0.0, 1.0);
    result[i] = points[i - 1] + chord * t;
  }
  return result;
}

/// 닫힌 주행선([points], 간격 [spacing] m)의 끝과 처음을 옆으로 어긋남 없이 잇는다. 랩을 시작할 때와 마칠 때 결승선을 지나는
/// 좌우 자리가 달라 끝 → 처음에서 주행선이 옆으로 몇 m 튀는데, 그대로 두면 그 자리에 가짜 코너가 잡히고 도로가 꺾인다.
/// 어긋난 폭의 절반씩을 끝 쪽·처음 쪽 [_seamBlendM](m)에 걸쳐 부드럽게 나눠 옮긴다.
List<Offset> _seamless(List<Offset> points, double spacing) {
  final n = points.length;
  final ramp = math.min(n ~/ 4, math.max(1, (_seamBlendM / spacing).round()));
  if (ramp < 2) {
    return points;
  }
  // [from]에서 [step] 쪽(−1 = 뒤로, 1 = 앞으로)으로 한 칸 넘게 떨어진 표본까지의 진행 방향(겹친 표본은 건너뛴다).
  Offset? heading(int from, int step) {
    for (var s = 1; s <= ramp; s++) {
      final d = (points[from + step * s] - points[from]) * step.toDouble();
      if (d.distance >= spacing) {
        return d / d.distance;
      }
    }
    return null;
  }

  // 결승선을 지나는 방향: 끝 쪽과 처음 쪽 진행 방향을 더한 것(이음매를 건너는 구간은 쓰지 않는다).
  final before = heading(n - 1, -1);
  final after = heading(0, 1);
  if (before == null || after == null) {
    return points;
  }
  final direction = before + after;
  if (direction.distance == 0) {
    return points;
  }
  final normal = Offset(-direction.dy, direction.dx) / direction.distance;
  final gap = points[0] - points[n - 1];
  final half = (gap.dx * normal.dx + gap.dy * normal.dy) / 2;
  double eased(double t) => t * t * (3 - 2 * t);
  return [
    for (var k = 0; k < n; k++)
      if (k >= n - ramp)
        points[k] + normal * (half * eased((k - (n - 1 - ramp)) / ramp))
      else if (k < ramp)
        points[k] - normal * (half * eased(1 - k / ramp))
      else
        points[k],
  ];
}

/// [around] 표본 둘레 [_matchWindow] 안에서 [p]에 가장 가까운 [points] 점 번호.
int _nearest(List<Offset> points, Offset p, int around, {required bool closed}) {
  final n = points.length;
  var best = closed ? (around % n + n) % n : around.clamp(0, n - 1);
  var bestDistance = double.infinity;
  for (var k = around - _matchWindow; k <= around + _matchWindow; k++) {
    if (!closed && (k < 0 || k >= n)) {
      continue;
    }
    final j = (k % n + n) % n;
    final d = (points[j] - p).distanceSquared;
    if (d < bestDistance) {
      bestDistance = d;
      best = j;
    }
  }
  return best;
}

List<double> _average(List<double> values, int half, int Function(int) at) => [
      for (var i = 0; i < values.length; i++)
        () {
          var sum = 0.0;
          for (var j = i - half; j <= i + half; j++) {
            sum += values[at(j)];
          }
          return sum / (half * 2 + 1);
        }(),
    ];

/// a − b를 −π ~ π로.
double _angleDiff(double a, double b) {
  var d = a - b;
  while (d > math.pi) {
    d -= 2 * math.pi;
  }
  while (d < -math.pi) {
    d += 2 * math.pi;
  }
  return d;
}
