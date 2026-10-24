import 'dart:math' as math;
import 'dart:ui';

import 'track_width_profile.dart';

/// 연석을 밟은 쪽 가장자리 = 차들이 달린 끝 + 이만큼(m, 바퀴가 연석에 올라탄 만큼).
const double _kerbEdgeAllowanceM = 0.5;

/// 연석 단서가 없는 구간은 가장 가까운 단서에서 이 거리(m)에 걸쳐 레이싱 라인 = 도로 가운데로 돌아간다.
const double _offsetFadeM = 100;

/// 도로 가운데 이동량을 고르는 이동 평균 반폭(칸).
const int _offsetSmoothBins = 3;

/// 모든 차 표본으로 서버가 만든 트랙 형상(`GET /tracks/{trackId}/geometry`). 칸 i = 랩 거리 i × [resolutionM].
/// 선([x]·[z])은 레이싱 라인(차들이 달린 위치의 중앙값)이고 도로 한가운데가 아니다. 띠는 그 선에서 차들이 달린 왼쪽·오른쪽 끝(m),
/// 연석은 그 쪽을 밟은 적이 있는지. 왼쪽 = 진행 방향 법선 (−sin, cos) 쪽(앱 서킷 그림과 같은 규칙).
class TrackSampleGeometry {
  const TrackSampleGeometry({
    required this.resolutionM,
    required this.sessionCount,
    required this.x,
    required this.z,
    required this.y,
    required this.bandLeftM,
    required this.bandRightM,
    required this.kerbLeft,
    required this.kerbRight,
    this.pitX,
    this.pitZ,
    this.pitY,
  });

  final double resolutionM;
  final int sessionCount;
  final List<double> x;
  final List<double> z;

  /// 높이(m). 모으지 못했으면 null.
  final List<double>? y;
  final List<double> bandLeftM;
  final List<double> bandRightM;
  final List<bool> kerbLeft;
  final List<bool> kerbRight;

  /// 피트 레인 선(입구 → 출구, 월드 X·Z·높이). 피트 레인 표본이 모자라면 null.
  final List<double>? pitX;
  final List<double>? pitZ;
  final List<double>? pitY;

  int get length => x.length;

  /// 피트 레인 점(월드 X·Z). 없으면 빈 목록.
  List<Offset> get pitLine {
    final px = pitX;
    final pz = pitZ;
    return px == null || pz == null ? const [] : [for (var i = 0; i < px.length; i++) Offset(px[i], pz[i])];
  }

  /// 레이싱 라인 점(월드 X·Z).
  List<Offset> get line => [for (var i = 0; i < length; i++) Offset(x[i], z[i])];

  /// 형식이 틀리면(배열 길이가 다르거나 칸이 3개 미만) null.
  static TrackSampleGeometry? fromJsonOrNull(Map<String, dynamic> json) {
    List<double>? numbers(Object? raw) =>
        raw is List && raw.every((e) => e is num) ? [for (final e in raw) (e as num).toDouble()] : null;
    List<bool>? flags(Object? raw) => raw is List && raw.every((e) => e is bool) ? raw.cast<bool>().toList() : null;

    final x = numbers(json['x']);
    final z = numbers(json['z']);
    final y = numbers(json['y']);
    final left = numbers(json['bandLeftM']);
    final right = numbers(json['bandRightM']);
    final kerbLeft = flags(json['kerbLeft']);
    final kerbRight = flags(json['kerbRight']);
    final resolution = json['resolutionM'];
    if (x == null || z == null || left == null || right == null || kerbLeft == null || kerbRight == null || resolution is! num) {
      return null;
    }
    final n = x.length;
    if (n < 3 || [z, left, right].any((l) => l.length != n) || kerbLeft.length != n || kerbRight.length != n) {
      return null;
    }
    final pitX = numbers(json['pitX']);
    final pitZ = numbers(json['pitZ']);
    final pitY = numbers(json['pitY']);
    final hasPit = pitX != null && pitZ != null && pitX.length >= 2 && pitZ.length == pitX.length;
    return TrackSampleGeometry(
      pitX: hasPit ? pitX : null,
      pitZ: hasPit ? pitZ : null,
      pitY: hasPit && pitY != null && pitY.length == pitX.length ? pitY : null,
      resolutionM: resolution.toDouble(),
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      x: x,
      z: z,
      y: y != null && y.length == n ? y : null,
      bandLeftM: left,
      bandRightM: right,
      kerbLeft: kerbLeft,
      kerbRight: kerbRight,
    );
  }
}

/// 표본 형상 → 도로(가운데 선·좌우 폭, 순수 함수). 도로 폭은 [widthM](넓게 달린 곳은 그만큼 넓힌다).
/// 연석을 밟은 칸에서는 그 쪽 가장자리가 차들이 달린 끝 바로 바깥이라 보고 도로 가운데를 레이싱 라인에서 옮기고,
/// 단서 사이는 이어 메운다(멀어지면 레이싱 라인 = 가운데로 돌아간다). 그래서 코너에서 레이싱 라인이 바깥 → 안쪽 → 바깥으로 지난다.
TrackWidthProfile trackProfileFromSamples(TrackSampleGeometry geometry, {required double widthM}) {
  final n = geometry.length;
  final half = widthM / 2;
  final line = geometry.line;
  int at(int i) => (i % n + n) % n;
  final normals = [
    for (var k = 0; k < n; k++)
      () {
        final d = line[at(k + 1)] - line[at(k - 1)];
        return d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance;
      }(),
  ];
  final leftEdge = [for (var k = 0; k < n; k++) geometry.bandLeftM[k] + _kerbEdgeAllowanceM];
  final rightEdge = [for (var k = 0; k < n; k++) geometry.bandRightM[k] + _kerbEdgeAllowanceM];

  // 연석 단서가 있는 칸의 도로 가운데 이동량(+ = 왼쪽).
  final known = <int, double>{};
  for (var k = 0; k < n; k++) {
    final values = [
      if (geometry.kerbLeft[k]) leftEdge[k] - half,
      if (geometry.kerbRight[k]) half - rightEdge[k],
    ];
    if (values.isNotEmpty) {
      known[k] = values.reduce((a, b) => a + b) / values.length;
    }
  }

  final fadeBins = _offsetFadeM / geometry.resolutionM;
  final offsets = List<double>.filled(n, 0);
  if (known.isNotEmpty) {
    final keys = known.keys.toList()..sort();
    for (var k = 0; k < n; k++) {
      // 앞뒤 가장 가까운 단서(서킷은 닫혀 있다).
      final before = keys.lastWhere((j) => j <= k, orElse: () => keys.last - n);
      final after = keys.firstWhere((j) => j >= k, orElse: () => keys.first + n);
      final from = known[at(before)]!;
      final to = known[at(after)]!;
      final value = after == before ? from : from + (to - from) * (k - before) / (after - before);
      final gap = math.min(k - before, after - k);
      offsets[k] = value * (1 - gap / fadeBins).clamp(0.0, 1.0);
    }
  }
  // 차들이 달린 띠가 도로 안에 들게(띠가 도로보다 넓으면 가운데에 둔다).
  for (var k = 0; k < n; k++) {
    final low = leftEdge[k] - half;
    final high = half - rightEdge[k];
    offsets[k] = low > high ? (low + high) / 2 : offsets[k].clamp(low, high);
  }
  final smoothed = [
    for (var k = 0; k < n; k++)
      [for (var j = -_offsetSmoothBins; j <= _offsetSmoothBins; j++) offsets[at(k + j)]].reduce((a, b) => a + b) /
          (_offsetSmoothBins * 2 + 1),
  ];

  return TrackWidthProfile(
    center: [for (var k = 0; k < n; k++) line[k] + normals[k] * smoothed[k]],
    leftM: [for (var k = 0; k < n; k++) math.max(half, leftEdge[k] - smoothed[k])],
    rightM: [for (var k = 0; k < n; k++) math.max(half, rightEdge[k] + smoothed[k])],
  );
}
