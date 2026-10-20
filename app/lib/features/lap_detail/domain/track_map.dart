import 'dart:math' as math;
import 'dart:ui';

import '../../laps/domain/lap_models.dart';
import 'lap_detail_models.dart';

/// 섹터 경계를 셀 때 쓰는 앞 두 섹터 번호(섹터 3은 나머지).
const int _firstSector = 1;
const int _secondSector = 2;

/// 섹터 번호(0부터): 0 = S1, 1 = S2, 2 = S3.
const int _sector1Index = 0;
const int _sector2Index = 1;
const int _sector3Index = 2;

/// m/s → km/h, ms → s.
const double _kphPerMps = 3.6;
const double _msPerSecond = 1000;

/// 트랙 모양이 한 점으로 모일 때(이동 없음) 둘 최소 폭(m, 0으로 나누지 않게).
const double _minExtentM = 1;

/// 트랙 지도 좌표 변환: 월드 X/Z(m)를 상자 [width]×[height]([padding] 안쪽) 안에 가로세로 비율을 지키며 가운데 놓는다.
/// 화면 x = X, 화면 y = +Z로 그린다(화면 y는 아래로 커진다). y = −Z로 그리면 실제 트랙과 좌우가 뒤집힌다(몬트리올 실데이터로 확인).
class TrackProjection {
  TrackProjection._(this._minX, this._minZ, this._scale, this._offsetX, this._offsetY);

  /// [xs]·[zs](같은 길이, 비어 있지 않음)를 담는 변환을 만든다.
  factory TrackProjection.fit({
    required List<double> xs,
    required List<double> zs,
    required double width,
    required double height,
    double padding = 0,
  }) {
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minZ = zs.reduce(math.min);
    final maxZ = zs.reduce(math.max);
    final spanX = math.max(maxX - minX, _minExtentM);
    final spanZ = math.max(maxZ - minZ, _minExtentM);
    final innerWidth = math.max(width - padding * 2, 0.0);
    final innerHeight = math.max(height - padding * 2, 0.0);
    final scale = math.min(innerWidth / spanX, innerHeight / spanZ);
    final offsetX = padding + (innerWidth - spanX * scale) / 2;
    final offsetY = padding + (innerHeight - spanZ * scale) / 2;
    return TrackProjection._(minX, minZ, scale, offsetX, offsetY);
  }

  final double _minX;
  final double _minZ;
  final double _scale;
  final double _offsetX;
  final double _offsetY;

  /// 월드 (x, z) → 화면 좌표. Z가 클수록 아래(화면 y가 크다).
  Offset project(double x, double z) => Offset(_offsetX + (x - _minX) * _scale, _offsetY + (z - _minZ) * _scale);
}

/// 표본마다 섹터 번호(0 = S1, 1 = S2, 2 = S3)를 랩 시간과 섹터 시간으로 정한다: 랩 시간 < S1이면 S1, < S1 + S2이면 S2, 그 밖은 S3.
/// S1·S2 시간을 모르면(또는 0 이하) null — 한 색으로 그린다(순수 함수).
List<int>? sectorIndexesOf(List<int> timeMs, List<LapSector> sectors) {
  int? timeOf(int number) => sectors.where((s) => s.sectorNumber == number).firstOrNull?.sectorTimeMs;
  final s1 = timeOf(_firstSector);
  final s2 = timeOf(_secondSector);
  if (s1 == null || s2 == null || s1 <= 0 || s2 <= 0) {
    return null;
  }
  final s2End = s1 + s2;
  return [
    for (final t in timeMs)
      if (t < s1)
        _sector1Index
      else if (t < s2End)
        _sector2Index
      else
        _sector3Index,
  ];
}

/// 트랙 선 조각 하나: 섹터 번호([sector], 섹터를 모르면 0)와 화면 점들.
typedef TrackSegment = ({int sector, List<Offset> points});

/// 점들을 섹터가 바뀌는 곳에서 나눈다. 다음 조각은 앞 조각의 마지막 점에서 시작해 선이 끊기지 않는다.
/// [sectors]가 null이면 조각 하나(섹터 0). 점이 둘 미만이면 빈 목록(순수 함수).
List<TrackSegment> trackSegments(List<Offset> points, List<int>? sectors) {
  if (points.length < 2) {
    return const [];
  }
  if (sectors == null || sectors.length != points.length) {
    return [(sector: _sector1Index, points: points)];
  }
  final segments = <TrackSegment>[];
  var current = <Offset>[points.first];
  var sector = sectors.first;
  for (var i = 1; i < points.length; i++) {
    current.add(points[i]);
    if (sectors[i] != sector) {
      segments.add((sector: sector, points: current));
      current = <Offset>[points[i]];
      sector = sectors[i];
    }
  }
  if (current.length > 1) {
    segments.add((sector: sector, points: current));
  }
  return segments;
}

/// Lap Telemetry 요약(F1Laps): 최고 속도·평균 속도(km/h), 평균 스로틀·브레이크(%). 빈 트레이스면 모두 0.
typedef LapTelemetryStats = ({double topSpeedKph, double averageSpeedKph, double averageThrottle, double averageBrake});

/// 트레이스로 [LapTelemetryStats]를 만든다. 평균 속도 = 트레이스 거리 ÷ 마지막 표본 시간, 스로틀·브레이크는 표본(거리 간격) 평균(순수 함수).
LapTelemetryStats lapTelemetryStatsOf(LapTrace trace) {
  double average(List<int> values) => values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  final elapsedMs = trace.isEmpty ? 0 : trace.timeMs.last;
  return (
    topSpeedKph: trace.speedKph.isEmpty ? 0 : trace.speedKph.reduce(math.max).toDouble(),
    averageSpeedKph: elapsedMs <= 0 ? 0 : trace.lengthM / (elapsedMs / _msPerSecond) * _kphPerMps,
    averageThrottle: average(trace.throttle),
    averageBrake: average(trace.brake),
  );
}
