import 'dart:math' as math;

import 'lap_corners.dart';
import 'lap_detail_models.dart';

/// 코너 구간: 코너 시작 전 브레이킹을 볼 거리, 코너 끝 뒤 탈출을 볼 거리(m). 앞뒤 코너와는 겹치지 않게 자른다.
const double _brakeLookbackM = 250;
const double _exitLookM = 150;

/// 브레이크·풀 가속으로 볼 페달 값(%).
const int _brakeOnPct = 20;
const int _throttleFullPct = 90;

/// 피드백으로 말할 만한 차이: 브레이크 지점·가속 시작(m), 속도(km/h).
const double _pointDiffM = 8;
const double _throttleDiffM = 12;
const double _speedDiffKph = 4;

/// 다른 요인이 없을 때 말할 만한 구간 평균 속도 차이(km/h).
const double _averageSpeedDiffKph = 2;

/// 최대 브레이크 압력 차이(%p), 에이펙스 앞에서 브레이크를 일찍 뗀 거리(m).
const double _brakePeakDiffPct = 15;
const double _brakeReleaseDiffM = 15;

/// 코스팅(브레이크·스로틀 모두 거의 안 밟음) 판정 페달 값(%)과 말할 만한 길이 차이(m).
const int _coastBrakePct = 5;
const int _coastThrottlePct = 10;
const double _coastDiffM = 15;

/// 브레이킹 중 스로틀 겹침: 겹침으로 볼 스로틀(%)·말할 만한 길이 차이(m).
const int _overlapThrottlePct = 20;
const double _overlapDiffM = 5;

/// 에이펙스(최저속도 지점) 위치 차이(m)·라인 옆 차이(m). 라인을 맞댈 때 기준 에이펙스 앞뒤로 찾는 거리(m), 진행 방향을 잴 앞뒤 거리(m).
const double _apexShiftM = 10;
const double _apexShiftMaxSpeedKph = 200;
const double _lineOffsetM = 1.0;
const double _lineSearchM = 60;
const double _headingSpanM = 5;

/// 탈출 스로틀: 일찍 열었다 뗀 것으로 볼 최고값(%)·떨어진 폭(%p). 기준 랩이 뗀 폭은 이보다 작아야 한다(%p).
const int _liftFromPct = 50;
const double _liftDropPct = 30;
const double _referenceLiftPct = 15;

/// 기준 랩이 풀 스로틀인 곳에서 이 랩이 이 값(%) 아래인 길이가 이 이상(m)이면 덜 밟은 것.
const int _partialThrottlePct = 80;
const double _partialThrottleM = 20;

/// 이 이상 잃은(초) 코너만 피드백한다.
const double kCornerLossThresholdS = 0.05;

/// 최저속도를 찾을 때 코너 시작 앞으로 더 보는 거리(m, 브레이킹 끝).
const double _minSpeedLeadM = 30;

/// ERS: 배터리 용량(J, F1 게임 4MJ), 바닥으로 볼 잔량 비율, 직선으로 볼 최소 길이(m), 말할 만한 배포 차이(J)·직선에서 잃은 시간(초).
const double kErsCapacityJ = 4000000;
const double _ersEmptyFraction = 0.02;
const double _straightMinM = 250;
const double _ersDeployDiffJ = 150000;
const double _straightLossS = 0.03;

const double _msPerSecond = 1000;
const double _kphPerMps = 3.6;

/// 거리 위 표본을 앞뒤 값으로 보간(순수 함수). 범위 밖은 양 끝 값.
double _valueAt(List<num> values, int resolutionM, double distanceM) {
  final position = (distanceM / resolutionM).clamp(0, values.length - 1).toDouble();
  final lower = position.floor();
  if (lower >= values.length - 1) {
    return values.last.toDouble();
  }
  final fraction = position - lower;
  return values[lower] + (values[lower + 1] - values[lower]) * fraction;
}

double _timeAt(LapTrace t, double d) => _valueAt(t.timeMs, t.resolutionM, d);

/// 두 랩이 [from]~[to]에 쓴 시간 차(초, 이 랩 − 기준).
double _lossS(LapTrace lap, LapTrace reference, double from, double to) =>
    ((_timeAt(lap, to) - _timeAt(lap, from)) - (_timeAt(reference, to) - _timeAt(reference, from))) / _msPerSecond;

/// [from]~[to]에서 [values]가 [test]를 처음 만족하는 거리(1m 간격). 없으면 null.
double? _firstWhere(List<num> values, int resolutionM, double from, double to, bool Function(double v) test) {
  for (var d = from; d <= to; d++) {
    if (test(_valueAt(values, resolutionM, d))) {
      return d;
    }
  }
  return null;
}

/// [from]~[to]의 최저 속도와 그 거리.
({double speed, double at}) _minSpeed(LapTrace t, double from, double to) {
  var best = double.infinity;
  var at = from;
  for (var d = from; d <= to; d++) {
    final v = _valueAt(t.speedKph, t.resolutionM, d);
    if (v < best) {
      best = v;
      at = d;
    }
  }
  return (speed: best, at: at);
}

/// 코너 한 곳에서 기준 랩과 다른 점(양은 늘 양수).
enum CornerFactorKind {
  /// 브레이크를 더 늦게 밟았다(m).
  brakeLater,

  /// 브레이크를 더 일찍 밟았다(m).
  brakeEarlier,

  /// 기준 랩은 브레이크 없이 지난 코너에서 브레이크를 밟았다.
  brakeNotNeeded,

  /// 최대 브레이크 압력이 낮다(%p).
  brakeLighter,

  /// 에이펙스 앞에서 브레이크를 일찍 뗐다(m) — 트레일 브레이킹 부족.
  brakeReleasedEarly,

  /// 브레이크도 스로틀도 거의 안 밟은 구간이 길다(m).
  coasting,

  /// 브레이킹 중 스로틀을 함께 밟았다(m).
  throttleWhileBraking,

  /// 에이펙스(최저속도 지점)가 늦다(m) — 깊게 들어갔다.
  apexLater,

  /// 에이펙스가 이르다(m) — 일찍 꺾었다.
  apexEarlier,

  /// 에이펙스에서 기준 라인보다 바깥(m) — 넓게 돌았다.
  wideAtApex,

  /// 에이펙스에서 기준 라인보다 안쪽(m) — 과하게 깎았다.
  tightAtApex,

  /// 코너 최저속도가 낮다(km/h).
  slowerApex,

  /// 탈출에서 스로틀을 일찍 열었다가 뗐다(%p).
  throttleLift,

  /// 기준 랩은 풀 스로틀인 곳에서 덜 밟았다(m).
  partialThrottle,

  /// 풀 가속을 늦게 시작했다(m).
  throttleLater,

  /// 탈출 속도가 낮다(km/h).
  slowerExit,

  /// 다른 요인 없이 구간 전체 평균 속도가 낮다(km/h) — 라인·리듬 차이.
  slowerThrough,
}

typedef CornerFactor = ({CornerFactorKind kind, double amount});

/// 코너 하나의 비교: 그 구간에서 잃은 시간(초, 음수면 번 시간)과 기준 랩과 다른 점(브레이킹 → 코너 → 탈출 순).
class CornerAnalysis {
  const CornerAnalysis({required this.corner, required this.lossS, required this.factors});

  final LapCorner corner;
  final double lossS;
  final List<CornerFactor> factors;
}

/// 두 코너 사이 직선의 ERS 비교: 배포량 차이(J, 이 랩 − 기준), 잃은 시간(초).
class StraightErs {
  const StraightErs({required this.after, required this.before, required this.deployDiffJ, required this.lossS});

  /// 직선 앞 코너(없으면 출발선)·뒤 코너(없으면 결승선).
  final LapCorner? after;
  final LapCorner? before;
  final double deployDiffJ;
  final double lossS;
}

/// 랩 전체 ERS 비교: 랩 시작·끝 배터리(0~1), 이 랩에서만 배터리가 바닥난 첫 자리, 덜 써서 잃은 직선들.
class ErsAnalysis {
  const ErsAnalysis({
    required this.startFraction,
    required this.endFraction,
    required this.referenceStartFraction,
    required this.referenceEndFraction,
    required this.emptyAtM,
    required this.emptyNear,
    required this.underusedStraights,
  });

  final double startFraction;
  final double endFraction;
  final double referenceStartFraction;
  final double referenceEndFraction;

  /// 바닥난 자리(랩 거리 m)와 그 앞 마지막 코너(출발 직후면 null). 바닥나지 않았으면 둘 다 null.
  final double? emptyAtM;
  final LapCorner? emptyNear;
  final List<StraightErs> underusedStraights;
}

/// 랩 비교 분석: 코너별 비교(코너 순서), ERS 비교(두 랩 모두 ERS 채널이 있을 때만).
class LapAnalysis {
  const LapAnalysis({required this.corners, required this.ers});

  final List<CornerAnalysis> corners;
  final ErsAnalysis? ers;

  /// 기준보다 [kCornerLossThresholdS] 넘게 잃은 코너(많이 잃은 순).
  List<CornerAnalysis> get losses =>
      corners.where((c) => c.lossS >= kCornerLossThresholdS).toList()..sort((a, b) => b.lossS.compareTo(a.lossS));

  /// 기준보다 [kCornerLossThresholdS] 넘게 번 코너(많이 번 순).
  List<CornerAnalysis> get gains =>
      corners.where((c) => c.lossS <= -kCornerLossThresholdS).toList()..sort((a, b) => a.lossS.compareTo(b.lossS));
}

/// [lap]을 [reference]와 코너([corners] — [lap]에서 찾은 것)마다 비교한다(순수 계산). 같은 랩 거리끼리 맞대므로
/// 두 랩이 같은 트랙이어야 한다. 코너 구간 = 앞 브레이킹(최대 [_brakeLookbackM]) ~ 뒤 탈출(최대 [_exitLookM]), 앞뒤 코너에서 자른다.
LapAnalysis analyzeLap(LapTrace lap, LapTrace reference, List<LapCorner> corners) {
  final endM = math.min(lap.lengthM, reference.lengthM);
  final results = <CornerAnalysis>[];
  for (var k = 0; k < corners.length; k++) {
    final corner = corners[k];
    if (corner.endM > endM) {
      break;
    }
    final previousEnd = k == 0 ? 0.0 : corners[k - 1].endM;
    final nextStart = k == corners.length - 1 ? endM : corners[k + 1].startM;
    final a = math.max(previousEnd, corner.startM - _brakeLookbackM);
    final b = math.min(nextStart, corner.endM + _exitLookM);
    results.add(CornerAnalysis(
      corner: corner,
      lossS: _lossS(lap, reference, a, b),
      factors: _factors(lap, reference, corner, a, b),
    ));
  }
  return LapAnalysis(corners: results, ers: _ers(lap, reference, corners, endM));
}

/// [from]~[to]에서 [values]가 [test]를 마지막으로 만족하는 거리(1m 간격). 없으면 null.
double? _lastWhere(List<num> values, int resolutionM, double from, double to, bool Function(double v) test) {
  double? last;
  for (var d = from; d <= to; d++) {
    if (test(_valueAt(values, resolutionM, d))) {
      last = d;
    }
  }
  return last;
}

/// [from]~[to]에서 [test](브레이크, 스로틀)를 만족하는 길이(m, 1m 간격).
double _lengthWhere(LapTrace t, double from, double to, bool Function(double brake, double throttle) test) {
  var meters = 0.0;
  for (var d = from; d <= to; d++) {
    if (test(_valueAt(t.brake, t.resolutionM, d), _valueAt(t.throttle, t.resolutionM, d))) {
      meters++;
    }
  }
  return meters;
}

/// [from]~[to]의 최대 브레이크(%).
double _peakBrake(LapTrace t, double from, double to) {
  var peak = 0.0;
  for (var d = from; d <= to; d++) {
    peak = math.max(peak, _valueAt(t.brake, t.resolutionM, d));
  }
  return peak;
}

/// [from]~[to]에서 스로틀이 [_liftFromPct] 넘게 오른 뒤 가장 크게 떨어진 폭(%p).
double _throttleLift(LapTrace t, double from, double to) {
  var high = 0.0;
  var drop = 0.0;
  for (var d = from; d <= to; d++) {
    final v = _valueAt(t.throttle, t.resolutionM, d);
    high = math.max(high, v);
    if (high >= _liftFromPct) {
      drop = math.max(drop, high - v);
    }
  }
  return drop;
}

({double x, double z}) _positionAt(LapTrace t, double d) =>
    (x: _valueAt(t.worldPosX, t.resolutionM, d), z: _valueAt(t.worldPosZ, t.resolutionM, d));

/// 기준 랩 에이펙스([apexM])에서 이 랩이 기준 라인보다 코너 안쪽으로 들어가 있는 거리(m, 음수 = 바깥).
/// 진행 방향 각이 커지는 쪽 = 오른쪽(코너 방향과 같은 기준). 두 랩 모두 위치가 있어야 한다.
double? _insideOffset(LapTrace lap, LapTrace reference, double apexM, CornerDirection direction) {
  if (!lap.hasPositions || !reference.hasPositions) {
    return null;
  }
  final p = _positionAt(reference, apexM);
  final behind = _positionAt(reference, apexM - _headingSpanM);
  final ahead = _positionAt(reference, apexM + _headingSpanM);
  final fx = ahead.x - behind.x;
  final fz = ahead.z - behind.z;
  final length = math.sqrt(fx * fx + fz * fz);
  if (length == 0) {
    return null;
  }
  var best = double.infinity;
  var nearest = p;
  for (var d = apexM - _lineSearchM; d <= apexM + _lineSearchM; d++) {
    final q = _positionAt(lap, d);
    final dist = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z);
    if (dist < best) {
      best = dist;
      nearest = q;
    }
  }
  // 오른쪽 단위 벡터 = (−fz, fx) / |f|.
  final right = ((nearest.x - p.x) * -fz + (nearest.z - p.z) * fx) / length;
  return direction == CornerDirection.right ? right : -right;
}

List<CornerFactor> _factors(LapTrace lap, LapTrace reference, LapCorner corner, double a, double b) {
  final factors = <CornerFactor>[];
  final apexFrom = math.max(a, corner.startM - _minSpeedLeadM);
  final mine = _minSpeed(lap, apexFrom, corner.endM);
  final theirs = _minSpeed(reference, apexFrom, corner.endM);

  bool braking(double v) => v >= _brakeOnPct;
  final brakeMine = _firstWhere(lap.brake, lap.resolutionM, a, mine.at, braking);
  final brakeRef = _firstWhere(reference.brake, reference.resolutionM, a, theirs.at, braking);
  if (brakeMine != null && brakeRef == null) {
    factors.add((kind: CornerFactorKind.brakeNotNeeded, amount: 0));
  } else if (brakeMine != null && brakeRef != null) {
    final diff = brakeMine - brakeRef;
    if (diff >= _pointDiffM) {
      factors.add((kind: CornerFactorKind.brakeLater, amount: diff));
    } else if (-diff >= _pointDiffM) {
      factors.add((kind: CornerFactorKind.brakeEarlier, amount: -diff));
    }
    final peakDiff = _peakBrake(reference, a, theirs.at) - _peakBrake(lap, a, mine.at);
    if (peakDiff >= _brakePeakDiffPct) {
      factors.add((kind: CornerFactorKind.brakeLighter, amount: peakDiff));
    }
    // 에이펙스에서 얼마나 앞에서 뗐는지로 비교한다(에이펙스 위치 차이는 따로 본다).
    final releaseMine = _lastWhere(lap.brake, lap.resolutionM, brakeMine, mine.at, braking);
    final releaseRef = _lastWhere(reference.brake, reference.resolutionM, brakeRef, theirs.at, braking);
    if (releaseMine != null && releaseRef != null) {
      final early = (mine.at - releaseMine) - (theirs.at - releaseRef);
      if (early >= _brakeReleaseDiffM) {
        factors.add((kind: CornerFactorKind.brakeReleasedEarly, amount: early));
      }
    }
  }
  bool coast(double brake, double throttle) => brake < _coastBrakePct && throttle < _coastThrottlePct;
  final coastDiff = _lengthWhere(lap, a, mine.at, coast) - _lengthWhere(reference, a, theirs.at, coast);
  if (coastDiff >= _coastDiffM) {
    factors.add((kind: CornerFactorKind.coasting, amount: coastDiff));
  }
  bool overlap(double brake, double throttle) => brake >= _brakeOnPct && throttle >= _overlapThrottlePct;
  final overlapDiff = _lengthWhere(lap, a, b, overlap) - _lengthWhere(reference, a, b, overlap);
  if (overlapDiff >= _overlapDiffM) {
    factors.add((kind: CornerFactorKind.throttleWhileBraking, amount: overlapDiff));
  }

  // 라인: 에이펙스 위치, 기준 에이펙스에서의 옆 위치, 최저속도.
  // 빠른 코너는 최저속도 지점이 뚜렷하지 않아 에이펙스 위치를 따지지 않는다.
  final apexShift = mine.at - theirs.at;
  if (theirs.speed < _apexShiftMaxSpeedKph && apexShift >= _apexShiftM) {
    factors.add((kind: CornerFactorKind.apexLater, amount: apexShift));
  } else if (theirs.speed < _apexShiftMaxSpeedKph && -apexShift >= _apexShiftM) {
    factors.add((kind: CornerFactorKind.apexEarlier, amount: -apexShift));
  }
  final inside = _insideOffset(lap, reference, theirs.at, corner.direction);
  if (inside != null && -inside >= _lineOffsetM) {
    factors.add((kind: CornerFactorKind.wideAtApex, amount: -inside));
  } else if (inside != null && inside >= _lineOffsetM) {
    factors.add((kind: CornerFactorKind.tightAtApex, amount: inside));
  }
  final apexDiff = theirs.speed - mine.speed;
  if (apexDiff >= _speedDiffKph) {
    factors.add((kind: CornerFactorKind.slowerApex, amount: apexDiff));
  }

  // 탈출 스로틀: 일찍 열었다 뗌 > 덜 밟음 > 늦게 밟음 가운데 하나.
  bool full(double v) => v >= _throttleFullPct;
  final lift = _throttleLift(lap, mine.at, b);
  var partial = 0.0;
  for (var d = mine.at; d <= b; d++) {
    if (_valueAt(reference.throttle, reference.resolutionM, d) >= _throttleFullPct &&
        _valueAt(lap.throttle, lap.resolutionM, d) < _partialThrottlePct) {
      partial++;
    }
  }
  final throttleMine = _firstWhere(lap.throttle, lap.resolutionM, mine.at, b, full);
  final throttleRef = _firstWhere(reference.throttle, reference.resolutionM, theirs.at, b, full);
  if (lift >= _liftDropPct && _throttleLift(reference, theirs.at, b) < _referenceLiftPct) {
    factors.add((kind: CornerFactorKind.throttleLift, amount: lift));
  } else if (partial >= _partialThrottleM) {
    factors.add((kind: CornerFactorKind.partialThrottle, amount: partial));
  } else if (throttleMine != null && throttleRef != null && throttleMine - throttleRef >= _throttleDiffM) {
    factors.add((kind: CornerFactorKind.throttleLater, amount: throttleMine - throttleRef));
  }

  final exitDiff = _valueAt(reference.speedKph, reference.resolutionM, b) - _valueAt(lap.speedKph, lap.resolutionM, b);
  if (exitDiff >= _speedDiffKph) {
    factors.add((kind: CornerFactorKind.slowerExit, amount: exitDiff));
  }
  if (factors.isEmpty) {
    final averageDiff = (b - a) / ((_timeAt(lap, b) - _timeAt(lap, a)) / _msPerSecond) -
        (b - a) / ((_timeAt(reference, b) - _timeAt(reference, a)) / _msPerSecond);
    final kph = -averageDiff * _kphPerMps;
    if (kph >= _averageSpeedDiffKph) {
      factors.add((kind: CornerFactorKind.slowerThrough, amount: kph));
    }
  }
  return factors;
}

ErsAnalysis? _ers(LapTrace lap, LapTrace reference, List<LapCorner> corners, double endM) {
  if (!lap.hasErs || !reference.hasErs) {
    return null;
  }
  double store(LapTrace t, double d) => _valueAt(t.ersStoreJ, t.resolutionM, d) / kErsCapacityJ;
  double deployed(LapTrace t, double d) => _valueAt(t.ersDeployedJ, t.resolutionM, d);
  bool empty(double fraction) => fraction <= _ersEmptyFraction;

  double? emptyAt;
  for (var d = 0.0; d <= endM; d++) {
    if (empty(store(lap, d)) && !empty(store(reference, d))) {
      emptyAt = d;
      break;
    }
  }
  final at = emptyAt;
  final near = at == null ? null : corners.where((c) => c.startM <= at).lastOrNull;

  // 코너 사이 직선(출발선 ~ 첫 코너, 코너 끝 ~ 다음 코너 시작, 마지막 코너 끝 ~ 결승선)마다 배포량·시간 비교.
  final straights = <StraightErs>[];
  for (var k = 0; k <= corners.length; k++) {
    final from = k == 0 ? 0.0 : corners[k - 1].endM;
    final to = math.min(k == corners.length ? endM : corners[k].startM, endM);
    if (to - from < _straightMinM) {
      continue;
    }
    final diff = (deployed(lap, to) - deployed(lap, from)) - (deployed(reference, to) - deployed(reference, from));
    final loss = _lossS(lap, reference, from, to);
    if (diff <= -_ersDeployDiffJ && loss >= _straightLossS) {
      straights.add(StraightErs(
        after: k == 0 ? null : corners[k - 1],
        before: k == corners.length ? null : corners[k],
        deployDiffJ: diff,
        lossS: loss,
      ));
    }
  }

  return ErsAnalysis(
    startFraction: store(lap, 0),
    endFraction: store(lap, endM),
    referenceStartFraction: store(reference, 0),
    referenceEndFraction: store(reference, endM),
    emptyAtM: emptyAt,
    emptyNear: near,
    underusedStraights: straights,
  );
}
