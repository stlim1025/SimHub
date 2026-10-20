import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'lap_detail_models.dart';

/// km/h → mph 환산 계수.
const double _mphPerKph = 0.621371;

/// ms → s.
const double _msPerSecond = 1000;

/// 값 범위가 0일 때 둘 최소 폭(0으로 나누지 않게).
const double _minRangeSpan = 1;

/// 십자선이 트레이스 끝을 넘어도 마지막 표본으로 보는 거리(표본 간격의 절반).
const double _halfSample = 0.5;

/// 눈금 간격 후보의 가수(× 10^k): 1·2·2.5·5.
const List<double> _niceMantissas = [1, 2, 2.5, 5];

/// 10진 자릿수 계산의 밑.
const int _decimalBase = 10;

/// 눈금 계산의 부동소수 오차 허용치.
const double _tickEpsilon = 1e-6;

/// 눈금 글자의 최대 소수 자릿수.
const int _maxAxisDecimals = 6;

/// km/h → mph(순수 함수).
double kphToMph(num kph) => kph * _mphPerKph;

/// [distanceM]에서의 랩 시간(ms)을 앞뒤 표본으로 선형 보간한다. 음수·마지막 표본 너머·빈 트레이스면 null(순수 함수).
double? interpolateTimeMs(LapTrace trace, double distanceM) {
  if (trace.isEmpty || distanceM < 0 || distanceM > trace.lengthM) {
    return null;
  }
  final position = distanceM / trace.resolutionM;
  final lower = position.floor();
  if (lower >= trace.length - 1) {
    return trace.timeMs.last.toDouble();
  }
  final fraction = position - lower;
  final start = trace.timeMs[lower];
  final end = trace.timeMs[lower + 1];
  return start + (end - start) * fraction;
}

/// Delta(초) = 이 랩 시간 − 같은 거리의 비교 랩 시간(docs/15 §2.3). 표본마다 하나, 비교 랩에 그 거리가 없으면 null.
/// 음수면 이 랩이 그 지점에서 앞서 있다(순수 함수).
List<double?> deltaSeconds(LapTrace lap, LapTrace reference) => [
      for (var i = 0; i < lap.length; i++)
        switch (interpolateTimeMs(reference, lap.distanceAt(i))) {
          final referenceMs? => (lap.timeMs[i] - referenceMs) / _msPerSecond,
          null => null,
        },
    ];

/// 십자선 거리 → 가장 가까운 표본 번호. 음수·트레이스 끝을 반 칸 넘게 지난 거리·빈 트레이스면 null(순수 함수).
int? sampleIndexAt(LapTrace trace, double distanceM) =>
    seriesIndexAt(length: trace.length, resolutionM: trace.resolutionM, distanceM: distanceM);

/// 표본 [length]개·간격 [resolutionM]m인 계열에서 [distanceM]에 가장 가까운 표본 번호. 범위 밖이면 null(순수 함수).
int? seriesIndexAt({required int length, required int resolutionM, required double distanceM}) {
  if (length == 0 || distanceM < 0 || resolutionM <= 0) {
    return null;
  }
  final position = distanceM / resolutionM;
  if (position > length - 1 + _halfSample) {
    return null;
  }
  return math.min(position.round(), length - 1);
}

/// 그래프 세로축 범위.
@immutable
class ValueRange {
  const ValueRange(this.min, this.max);

  final double min;
  final double max;

  double get span => max - min;
}

/// 값들의 세로축 범위. [fixedMin]·[fixedMax]가 있으면 그 값을 쓰고, [symmetric]이면 0을 가운데 둔다(Delta).
/// 범위 폭이 0이면 [_minRangeSpan]을 둔다(순수 함수).
ValueRange valueRangeOf(
  Iterable<num?> values, {
  double? fixedMin,
  double? fixedMax,
  bool symmetric = false,
}) {
  final present = values.whereType<num>().map((v) => v.toDouble()).toList();
  var low = fixedMin ?? (present.isEmpty ? 0.0 : present.reduce(math.min));
  var high = fixedMax ?? (present.isEmpty ? 0.0 : present.reduce(math.max));
  if (symmetric) {
    final extent = math.max(low.abs(), high.abs());
    low = -extent;
    high = extent;
  }
  if (high - low <= 0) {
    return symmetric
        ? const ValueRange(-_minRangeSpan / 2, _minRangeSpan / 2)
        : ValueRange(low, low + _minRangeSpan);
  }
  return ValueRange(low, high);
}

/// 그래프 한 장의 좌표 변환: 가로 = 랩 거리(0~[maxDistanceM]), 세로 = 값([range], 위가 큰 값).
@immutable
class ChartGeometry {
  const ChartGeometry({
    required this.width,
    required this.height,
    required this.maxDistanceM,
    required this.range,
  });

  final double width;
  final double height;
  final double maxDistanceM;
  final ValueRange range;

  double xFor(double distanceM) => maxDistanceM <= 0 ? 0 : distanceM / maxDistanceM * width;

  double yFor(double value) => height - (value - range.min) / range.span * height;

  /// 가로 픽셀 → 랩 거리(0~[maxDistanceM]로 자른다).
  double distanceAtX(double x) {
    if (width <= 0) {
      return 0;
    }
    return (x / width * maxDistanceM).clamp(0, maxDistanceM).toDouble();
  }
}

/// 축 눈금 간격: 폭 [span]에 눈금이 [maxTicks]개를 넘지 않는 가장 작은 "보기 좋은" 간격(1·2·2.5·5 × 10^k).
/// 예: 0~330, 7개 → 50 · 0~100, 7개 → 20 · 0~100, 11개 → 10. [span]이 0 이하거나 [maxTicks]가 2 미만이면 [span](또는 1)(순수 함수).
double niceTickStep(double span, int maxTicks) {
  if (span <= 0) {
    return 1;
  }
  if (maxTicks < 2) {
    return span;
  }
  final raw = span / (maxTicks - 1);
  // raw보다 한 자리 작은 곳부터 올라가며 처음으로 눈금 수가 맞는 간격을 고른다.
  var exponent = (math.log(raw) / math.ln10).floor() - 1;
  while (true) {
    final magnitude = math.pow(_decimalBase, exponent).toDouble();
    for (final mantissa in _niceMantissas) {
      final step = mantissa * magnitude;
      if ((span / step + _tickEpsilon).floor() + 1 <= maxTicks) {
        return step;
      }
    }
    exponent++;
  }
}

/// 눈금 간격 [step]을 글자로 쓸 때 필요한 소수 자릿수(50 → 0, 0.2 → 1, 0.25 → 2)(순수 함수).
int axisDecimals(double step) {
  for (var digits = 0; digits < _maxAxisDecimals; digits++) {
    final scaled = step * math.pow(_decimalBase, digits);
    if ((scaled - scaled.round()).abs() < _tickEpsilon) {
      return digits;
    }
  }
  return _maxAxisDecimals;
}

/// [range] 안의 눈금 값들(간격 = [niceTickStep], [step]의 배수만, 오름차순). 범위 폭이 0 이하면 빈 목록(순수 함수).
List<double> axisTicks(ValueRange range, {required int maxTicks}) {
  if (range.span <= 0) {
    return const [];
  }
  final step = niceTickStep(range.span, maxTicks);
  final decimals = axisDecimals(step);
  final first = (range.min / step - _tickEpsilon).ceil();
  final last = (range.max / step + _tickEpsilon).floor();
  return [
    // 0.6000000000000001 같은 오차와 −0을 없앤다.
    for (var k = first; k <= last; k++) double.parse((k * step).toStringAsFixed(decimals)) + 0.0,
  ];
}
