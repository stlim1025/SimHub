import 'dart:math' as math;

import '../../laps/domain/lap_models.dart';
import 'lap_detail_models.dart';
import 'telemetry_math.dart';

/// 진행 방향을 잴 때 현재 거리 앞뒤로 보는 거리(m). 표본 하나하나의 위치 흔들림이 방향에 그대로 드러나지 않게 넓게 본다.
const double kReplayHeadingLookM = 8;

/// 방향 벡터 길이가 이보다 짧으면(움직임 없음) 방향을 정할 수 없다고 본다.
const double _minHeadingVectorM = 1e-6;

/// 고스트 재생의 한 순간 한 랩의 상태.
/// [heading]은 월드 X/Z 평면의 진행 방향(라디안, `atan2(dZ, dX)` — 화면 x = X, y = +Z 기준).
typedef ReplayFrame = ({
  double x,
  double z,
  double heading,
  double distanceM,
  double speedKph,
  int gear,
  int rpm,
  int throttle,
  int brake,
  bool finished,
  double? batteryPercent,
  double? ersFlowKw,
});

/// ERS 배터리 최대 저장량(J, 4 MJ).
const double kErsStoreMaxJ = 4000000;

/// ERS 충전·사용 출력 막대의 가득(kW). F1 26 MGU-K 최대 출력 350 kW 기준.
const double kErsMaxFlowKw = 350;

/// ERS 출력을 구할 때 앞뒤로 보는 표본 수(표본 하나의 흔들림을 줄인다).
const int _ersFlowWindowSamples = 2;

const double _percent = 100;

/// 위치가 있는 랩 트레이스를 시간으로 따라가는 재생기(순수 계산). [trace]는 `hasPositions`여야 한다.
/// 표본은 거리 간격이고 표본마다 랩 시간이 있으므로(거리에 따라 단조 증가) 시간 → 거리를 이분 탐색으로 찾고 앞뒤 표본을 선형 보간한다.
class LapReplay {
  LapReplay(this.trace) : assert(trace.hasPositions, '위치가 있는 트레이스만 재생한다.');

  final LapTrace trace;

  /// 랩을 다 도는 데 걸린 시간(ms) = 마지막 표본의 시간.
  int get durationMs => trace.timeMs.last;

  /// 경과 시간 [elapsedMs]의 표본 위치(소수 표본 번호, 0 ~ length−1). 시작 전은 0, 끝난 뒤는 마지막 표본.
  double samplePositionAt(double elapsedMs) {
    final times = trace.timeMs;
    if (elapsedMs <= times.first) {
      return 0;
    }
    final last = trace.length - 1;
    if (elapsedMs >= times[last]) {
      return last.toDouble();
    }
    // times[low] <= elapsed < times[high]인 가장 가까운 두 표본.
    var low = 0;
    var high = last;
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (times[mid] <= elapsedMs) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = times[high] - times[low];
    final fraction = span <= 0 ? 0.0 : (elapsedMs - times[low]) / span;
    return low + fraction;
  }

  /// 랩 거리 [distanceM]의 월드 위치(앞뒤 표본 선형 보간, 0 ~ 랩 끝으로 자른다).
  ({double x, double z}) positionAtDistance(double distanceM) {
    final position = (distanceM.clamp(0, trace.lengthM) / trace.resolutionM).toDouble();
    return (x: _lerpAt(trace.worldPosX, position), z: _lerpAt(trace.worldPosZ, position));
  }

  /// 랩 거리 [distanceM]의 진행 방향: [lookM] 뒤 위치 → [lookM] 앞 위치 벡터의 각도(랩 시작·끝에서는 한쪽만 본다).
  /// 움직임이 없어 정할 수 없으면 0.
  double headingAtDistance(double distanceM, {double lookM = kReplayHeadingLookM}) {
    final behind = positionAtDistance(distanceM - lookM);
    final ahead = positionAtDistance(distanceM + lookM);
    final dx = ahead.x - behind.x;
    final dz = ahead.z - behind.z;
    if (dx.abs() < _minHeadingVectorM && dz.abs() < _minHeadingVectorM) {
      return 0;
    }
    return math.atan2(dz, dx);
  }

  /// 경과 시간 [elapsedMs]의 상태. 랩을 끝냈으면 결승점에 멈춰 있다([ReplayFrame.finished]).
  ReplayFrame frameAt(double elapsedMs) {
    final position = samplePositionAt(elapsedMs);
    final distance = position * trace.resolutionM;
    final lower = position.floor();
    final point = positionAtDistance(distance);
    return (
      x: point.x,
      z: point.z,
      heading: headingAtDistance(distance),
      distanceM: distance,
      speedKph: _lerpAt(trace.speedKph, position),
      gear: trace.gear[lower],
      rpm: _lerpAt(trace.rpm, position).round(),
      throttle: _lerpAt(trace.throttle, position).round(),
      brake: _lerpAt(trace.brake, position).round(),
      finished: elapsedMs >= durationMs,
      batteryPercent: trace.hasErs ? (_lerpAt(trace.ersStoreJ, position) / kErsStoreMaxJ * _percent).clamp(0.0, _percent) : null,
      ersFlowKw: trace.hasErs ? _ersFlowKwAt(lower) : null,
    );
  }

  /// 표본 [index] 앞뒤 [_ersFlowWindowSamples]칸의 배터리 잔량 변화 ÷ 시간 = ERS 출력(J/ms = kW).
  /// + 충전(회수가 더 많음), − 사용(배포가 더 많음). ±[kErsMaxFlowKw]로 자른다.
  double _ersFlowKwAt(int index) {
    final last = trace.length - 1;
    final from = math.max(0, index - _ersFlowWindowSamples);
    final to = math.min(last, index + _ersFlowWindowSamples);
    final dt = trace.timeMs[to] - trace.timeMs[from];
    if (dt <= 0) {
      return 0;
    }
    final dE = trace.ersStoreJ[to] - trace.ersStoreJ[from];
    return (dE / dt).clamp(-kErsMaxFlowKw, kErsMaxFlowKw);
  }

  static double _lerpAt(List<num> values, double position) {
    final lower = position.floor();
    if (lower >= values.length - 1) {
      return values.last.toDouble();
    }
    final fraction = position - lower;
    return values[lower] + (values[lower + 1] - values[lower]) * fraction;
  }
}

/// 재생 시계의 끝(ms) = 두 랩 중 늦게 끝나는 쪽. 비교 랩이 없으면 이 랩 시간(순수 함수).
int replayDurationMs(LapReplay player, LapReplay? ghost) => math.max(player.durationMs, ghost?.durationMs ?? 0);

/// 이 랩이 [distanceM]에 있을 때의 시간 차(ms) = 이 랩이 그 거리에 닿은 시간 − 비교 랩이 같은 거리에 닿은 시간.
/// 음수면 이 랩이 앞선다. 어느 한쪽에 그 거리가 없으면 null(순수 함수).
double? replayGapMs(LapTrace player, LapTrace reference, double distanceM) {
  final playerMs = interpolateTimeMs(player, distanceM);
  final referenceMs = interpolateTimeMs(reference, distanceM);
  if (playerMs == null || referenceMs == null) {
    return null;
  }
  return playerMs - referenceMs;
}

/// 섹터 비교 한 줄: 섹터 번호, 그 섹터를 지났으면 이 랩·비교 랩의 섹터 시간(ms, 아직이면 null).
typedef ReplaySectorRow = ({int sector, int? playerMs, int? referenceMs});

/// 경과 시간 [elapsedMs]까지 지난 섹터만 시간을 채운 섹터 비교 줄(순수 함수). 섹터를 지났는지는 그 랩의 섹터 누적 시간으로 본다.
/// 두 랩에 있는 섹터 번호를 모두 1부터 차례로 보인다(한쪽에만 있으면 다른 쪽은 늘 null).
List<ReplaySectorRow> replaySectorRows(List<LapSector> player, List<LapSector> reference, double elapsedMs) {
  Map<int, int> passed(List<LapSector> sectors) {
    final ordered = [...sectors]..sort((a, b) => a.sectorNumber.compareTo(b.sectorNumber));
    final result = <int, int>{};
    var cumulative = 0;
    for (final sector in ordered) {
      cumulative += sector.sectorTimeMs;
      if (cumulative <= elapsedMs) {
        result[sector.sectorNumber] = sector.sectorTimeMs;
      }
    }
    return result;
  }

  final numbers = {for (final s in player) s.sectorNumber, for (final s in reference) s.sectorNumber}.toList()..sort();
  final playerPassed = passed(player);
  final referencePassed = passed(reference);
  return [
    for (final n in numbers) (sector: n, playerMs: playerPassed[n], referenceMs: referencePassed[n]),
  ];
}

/// ms → s.
const double _msPerSecond = 1000;

/// 시간 차 글자(초, 소수 셋째 자리): `-0.214`(앞섬)·`+0.381`(뒤처짐)·`0.000`(순수 함수).
String formatReplayGap(double gapMs) {
  final text = (gapMs.abs() / _msPerSecond).toStringAsFixed(3);
  if (text == '0.000') {
    return text;
  }
  return '${gapMs < 0 ? '-' : '+'}$text';
}
