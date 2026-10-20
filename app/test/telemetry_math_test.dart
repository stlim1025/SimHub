import 'package:flutter_test/flutter_test.dart';
import 'package:simcenter_app/features/lap_detail/domain/lap_detail_models.dart';
import 'package:simcenter_app/features/lap_detail/domain/telemetry_math.dart';

LapTrace _trace(List<int> timeMs, {int resolutionM = 10, List<int>? speed}) => LapTrace(
      lapId: 'x',
      resolutionM: resolutionM,
      timeMs: timeMs,
      speedKph: speed ?? List.filled(timeMs.length, 200),
      throttle: List.filled(timeMs.length, 0),
      brake: List.filled(timeMs.length, 0),
      steer: List.filled(timeMs.length, 0),
      gear: List.filled(timeMs.length, 0),
      rpm: List.filled(timeMs.length, 0),
    );

void main() {
  group('interpolateTimeMs', () {
    final trace = _trace([0, 100, 300]); // 0m, 10m, 20m

    test('표본 위치는 그 값', () {
      expect(interpolateTimeMs(trace, 0), 0);
      expect(interpolateTimeMs(trace, 10), 100);
      expect(interpolateTimeMs(trace, 20), 300);
    });

    test('표본 사이는 선형 보간', () {
      expect(interpolateTimeMs(trace, 5), 50);
      expect(interpolateTimeMs(trace, 15), 200);
    });

    test('범위 밖(음수·마지막 표본 너머)·빈 트레이스는 null', () {
      expect(interpolateTimeMs(trace, -1), isNull);
      expect(interpolateTimeMs(trace, 20.5), isNull);
      expect(interpolateTimeMs(_trace(const []), 0), isNull);
    });
  });

  group('deltaSeconds (이 랩 시간 − 비교 랩 시간, 같은 거리)', () {
    test('해상도가 다른 비교 랩도 거리로 맞춰 뺀다', () {
      final lap = _trace([0, 120, 260], resolutionM: 10); // 0, 10, 20m
      final reference = _trace([0, 50, 100, 150, 200], resolutionM: 5); // 0..20m

      expect(deltaSeconds(lap, reference), [0.0, 0.02, 0.06]);
    });

    test('비교 랩이 짧아 그 거리에 값이 없으면 null', () {
      final lap = _trace([0, 100, 200], resolutionM: 10);
      final reference = _trace([0, 90], resolutionM: 10);

      expect(deltaSeconds(lap, reference), [0.0, 0.01, null]);
    });
  });

  group('sampleIndexAt (십자선 거리 → 가장 가까운 표본)', () {
    final trace = _trace([0, 1, 2, 3], resolutionM: 5); // 0..15m

    test('반올림한 표본 번호', () {
      expect(sampleIndexAt(trace, 0), 0);
      expect(sampleIndexAt(trace, 2.4), 0);
      expect(sampleIndexAt(trace, 2.6), 1);
      expect(sampleIndexAt(trace, 15), 3);
    });

    test('트레이스 끝을 반 칸 넘게 지나거나 음수면 null', () {
      expect(sampleIndexAt(trace, 17.4), 3);
      expect(sampleIndexAt(trace, 17.6), isNull);
      expect(sampleIndexAt(trace, -3), isNull);
      expect(sampleIndexAt(_trace(const []), 0), isNull);
    });
  });

  group('valueRangeOf', () {
    test('고정 범위가 있으면 그대로', () {
      final range = valueRangeOf([5, 50], fixedMin: 0, fixedMax: 100);

      expect(range.min, 0);
      expect(range.max, 100);
    });

    test('자동 범위는 최솟값~최댓값(null 무시), 최솟값만 고정할 수 있다', () {
      final range = valueRangeOf([120, null, 310], fixedMin: 0);

      expect(range.min, 0);
      expect(range.max, 310);
    });

    test('대칭 범위는 0을 가운데 둔다', () {
      final range = valueRangeOf([-0.2, 0.5], symmetric: true);

      expect(range.min, -0.5);
      expect(range.max, 0.5);
    });

    test('값이 하나뿐이거나 모두 같으면 폭 1을 둔다(0으로 나누지 않게)', () {
      final range = valueRangeOf([7, 7]);

      expect(range.max - range.min, 1);
      expect(valueRangeOf(const []).max - valueRangeOf(const []).min, 1);
    });
  });

  group('ChartGeometry', () {
    const geometry = ChartGeometry(width: 200, height: 100, maxDistanceM: 1000, range: ValueRange(0, 50));

    test('거리 → x, 값 → y(위가 큰 값)', () {
      expect(geometry.xFor(0), 0);
      expect(geometry.xFor(500), 100);
      expect(geometry.xFor(1000), 200);
      expect(geometry.yFor(0), 100);
      expect(geometry.yFor(50), 0);
      expect(geometry.yFor(25), 50);
    });

    test('x → 거리(범위 안으로 자른다)', () {
      expect(geometry.distanceAtX(100), 500);
      expect(geometry.distanceAtX(-20), 0);
      expect(geometry.distanceAtX(400), 1000);
    });
  });

  group('축 눈금', () {
    test('niceTickStep: 눈금 수를 넘지 않는 가장 작은 1·2·2.5·5 × 10^k 간격', () {
      expect(niceTickStep(330, 7), 50);
      expect(niceTickStep(100, 7), 20);
      expect(niceTickStep(100, 11), 10);
      expect(niceTickStep(200, 7), 50);
      expect(niceTickStep(12000, 7), 2000);
      expect(niceTickStep(10, 5), 2.5);
      expect(niceTickStep(0.6, 7), closeTo(0.1, 1e-12));
      expect(niceTickStep(0, 7), 1);
    });

    test('axisDecimals: 간격을 쓰는 데 필요한 소수 자릿수', () {
      expect(axisDecimals(50), 0);
      expect(axisDecimals(0.2), 1);
      expect(axisDecimals(0.25), 2);
    });

    test('axisTicks: 간격의 배수만, 범위 안, 오차·−0 없음', () {
      expect(axisTicks(const ValueRange(0, 330), maxTicks: 7), [0, 50, 100, 150, 200, 250, 300]);
      expect(axisTicks(const ValueRange(-1, 8), maxTicks: 7), [0, 2, 4, 6, 8]);
      expect(axisTicks(const ValueRange(-0.3, 0.3), maxTicks: 7), [-0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3]);
      expect(axisTicks(const ValueRange(-0.3, 0.3), maxTicks: 7)[3].isNegative, isFalse);
      expect(axisTicks(const ValueRange(0, 0), maxTicks: 7), isEmpty);
    });
  });

  test('kphToMph', () {
    expect(kphToMph(100), closeTo(62.137, 0.001));
    expect(kphToMph(0), 0);
  });
}
