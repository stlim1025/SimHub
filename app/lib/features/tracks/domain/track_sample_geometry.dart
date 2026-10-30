import 'dart:math' as math;
import 'dart:ui';

import 'track_width_profile.dart';

/// 바퀴 가장자리 열이 없는(예전 서버) 응답: 연석을 밟은 쪽 가장자리 = 차들이 달린 끝 + 이만큼(m, 바퀴가 연석에 올라탄 만큼).
const double _kerbEdgeAllowanceM = 0.5;

/// 연석 단서가 없는 구간은 가장 가까운 단서에서 이 거리(m)에 걸쳐 레이싱 라인 = 도로 가운데로 돌아간다.
const double _offsetFadeM = 100;

/// 도로 가운데 이동량을 고르는 이동 평균 반폭(칸).
const int _offsetSmoothBins = 3;

/// 가장자리를 고르는 반폭(칸): 앞뒤 가장 먼 값으로 넓힌 뒤 같은 범위로 평균해 칸마다 튀지 않게 한다(점마다 원래 값 이상).
const int _edgeSmoothBins = 3;

/// 가장자리에서 한두 칸만 튄 값(피트 입구로 갈라지는 차처럼 랩 거리와 자리가 어긋난 표본)을 누르는 가운데값 반폭(칸).
const int _edgeMedianBins = 2;

/// 연석 칸의 가장자리(연석 안쪽 끝)에서 멀어질수록 가장자리가 넓어질 수 있는 기울기(옆 m / 진행 m) — 연석 둘레가 깔때기처럼 풀린다.
const double _kerbFunnelSlope = 0.2;

/// 모든 차 표본으로 서버가 만든 트랙 형상(`GET /tracks/{trackId}/geometry`). 칸 i = 랩 거리 i × [resolutionM].
/// 선([x]·[z])은 레이싱 라인(차들이 달린 위치의 중앙값)이고 도로 한가운데가 아니다. 띠는 그 선에서 차들이 달린 왼쪽·오른쪽 끝(m),
/// 연석은 그 쪽을 밟은 적이 있는지. 왼쪽 = 진행 방향 법선 (−sin, cos) 쪽(앱 서킷 그림과 같은 규칙).
/// 가장자리·연석 바깥·도달 폭도 레이싱 라인에서 그 쪽으로 잰 거리(m)이고, 그런 표본이 없는 칸은 0이다.
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
    this.edgeLeftM,
    this.edgeRightM,
    this.kerbOuterLeftM,
    this.kerbOuterRightM,
    this.reachLeftM,
    this.reachRightM,
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

  /// 아스팔트 가장자리: 네 바퀴가 모두 아스팔트(연석이 아닌 포장 노면)에 있던 차의 바깥 바퀴가 닿은 먼 자리
  /// (표본이 많은 칸은 런오프로 잠깐 나간 가장 먼 1%를 뺀다). [kerbOuterLeftM]·[kerbOuterRightM]은 연석을 밟은 차의
  /// 바깥 바퀴가 닿은 먼 자리 = 연석 바깥 끝(같은 규칙). 예전 서버 응답이면 넷 다 null.
  final List<double>? edgeLeftM;
  final List<double>? edgeRightM;
  final List<double>? kerbOuterLeftM;
  final List<double>? kerbOuterRightM;

  /// 차 몸체가 닿은 가장 먼 자리: 코스를 벗어난 차·멈춘 차까지 모두(방호벽은 이보다 바깥). 예전 서버 응답이면 null.
  final List<double>? reachLeftM;
  final List<double>? reachRightM;

  int get length => x.length;

  /// 피트 레인 점(월드 X·Z). 없으면 빈 목록.
  List<Offset> get pitLine {
    final px = pitX;
    final pz = pitZ;
    return px == null || pz == null ? const [] : [for (var i = 0; i < px.length; i++) Offset(px[i], pz[i])];
  }

  /// 레이싱 라인 점(월드 X·Z).
  List<Offset> get line => [for (var i = 0; i < length; i++) Offset(x[i], z[i])];

  /// 형식이 틀리면(배열 길이가 다르거나 칸이 3개 미만) null. 새 열(가장자리·연석 바깥·도달 폭)은 형식이 틀리면 없는 것으로 본다.
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
    List<double>? column(String key) {
      final values = numbers(json[key]);
      return values != null && values.length == n ? values : null;
    }

    final edgeLeft = column('edgeLeftM');
    final edgeRight = column('edgeRightM');
    final kerbOuterLeft = column('kerbOuterLeftM');
    final kerbOuterRight = column('kerbOuterRightM');
    final hasWheels = edgeLeft != null && edgeRight != null && kerbOuterLeft != null && kerbOuterRight != null;
    final reachLeft = column('reachLeftM');
    final reachRight = column('reachRightM');
    final hasReach = reachLeft != null && reachRight != null;
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
      edgeLeftM: hasWheels ? edgeLeft : null,
      edgeRightM: hasWheels ? edgeRight : null,
      kerbOuterLeftM: hasWheels ? kerbOuterLeft : null,
      kerbOuterRightM: hasWheels ? kerbOuterRight : null,
      reachLeftM: hasReach ? reachLeft : null,
      reachRightM: hasReach ? reachRight : null,
    );
  }
}

/// 표본 형상 → 도로(가운데 선·좌우 폭, 순수 함수). 도로 폭은 [widthM](넓게 달린 곳은 그만큼 넓힌다).
/// 가장자리는 바퀴가 아스팔트를 밟은 먼 자리이고, 연석을 밟은 차가 연석(가장자리 바깥에 [kerbWidthM] 폭으로 그린다) 위에
/// 오도록 연석 바깥 끝 − 연석 폭까지는 넓힌다(바퀴 열이 없는 예전 응답은 차들이 달린 띠 + 여유). 연석이 있는 칸은 연석 안쪽 끝
/// (연석 바깥 끝 − 연석 폭)이 가장자리다 — 그 너머 포장 런오프·탈출로로 나간 차는 도로 밖에 그린다(방호벽은 그 차까지 담는다).
/// 가장자리는 한두 칸만 튄 값을 앞뒤 가운데값으로 누르고, 앞뒤로 넓힌 뒤 평균해 칸마다 튀어 접히지 않게 한 다음,
/// 연석 칸 둘레는 연석에서 멀어질수록 천천히 넓어지게 다시 자른다(연석이 제자리에 남게).
/// 연석을 밟은 칸에서는 그 쪽 가장자리가 그 자리라 보고 도로 가운데를 레이싱 라인에서 옮기고,
/// 단서 사이는 이어 메운다(멀어지면 레이싱 라인 = 가운데로 돌아간다). 그래서 코너에서 레이싱 라인이 바깥 → 안쪽 → 바깥으로 지난다.
/// 차 몸체가 닿은 끝(있으면)은 옮긴 도로 가운데에서 잰 값으로 바꿔 함께 싣는다.
TrackWidthProfile trackProfileFromSamples(TrackSampleGeometry geometry, {required double widthM, required double kerbWidthM}) {
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
  List<double> edge(List<double>? wheels, List<double>? kerbOuter, List<bool> kerbs, List<double> band) {
    // 연석 칸의 가장자리 = 연석 안쪽 끝(그 너머 표본은 연석 위나 연석 밖이다).
    final kerbInner = [
      for (var k = 0; k < n; k++)
        wheels != null && kerbOuter != null && kerbs[k] && kerbOuter[k] > 0 ? kerbOuter[k] - kerbWidthM : null,
    ];
    final raw = [
      for (var k = 0; k < n; k++)
        if (wheels == null || kerbOuter == null)
          band[k] + _kerbEdgeAllowanceM
        else
          kerbInner[k] ?? math.max(wheels[k], kerbOuter[k] - kerbWidthM),
    ];
    final despiked = [
      for (var k = 0; k < n; k++)
        ([for (var j = -_edgeMedianBins; j <= _edgeMedianBins; j++) raw[at(k + j)]]..sort())[_edgeMedianBins],
    ];
    final widened = [
      for (var k = 0; k < n; k++)
        [for (var j = -_edgeSmoothBins; j <= _edgeSmoothBins; j++) despiked[at(k + j)]].reduce(math.max),
    ];
    final smoothed = [
      for (var k = 0; k < n; k++)
        [for (var j = -_edgeSmoothBins; j <= _edgeSmoothBins; j++) widened[at(k + j)]].reduce((a, b) => a + b) /
            (_edgeSmoothBins * 2 + 1),
    ];
    // 연석 칸에서 멀어질수록 칸마다 이만큼씩만 넓어질 수 있다(서킷이 닫혀 있어 두 바퀴 돌며 끝과 처음을 잇는다).
    final step = _kerbFunnelSlope * geometry.resolutionM;
    final funnel = [for (var k = 0; k < n; k++) kerbInner[k] ?? double.infinity];
    for (var round = 0; round < 2; round++) {
      for (var k = 0; k < n; k++) {
        funnel[k] = math.min(funnel[k], funnel[at(k - 1)] + step);
      }
      for (var k = n - 1; k >= 0; k--) {
        funnel[k] = math.min(funnel[k], funnel[at(k + 1)] + step);
      }
    }
    return [for (var k = 0; k < n; k++) math.min(smoothed[k], funnel[k])];
  }

  final leftEdge = edge(geometry.edgeLeftM, geometry.kerbOuterLeftM, geometry.kerbLeft, geometry.bandLeftM);
  final rightEdge = edge(geometry.edgeRightM, geometry.kerbOuterRightM, geometry.kerbRight, geometry.bandRightM);

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

  final reachLeft = geometry.reachLeftM;
  final reachRight = geometry.reachRightM;
  return TrackWidthProfile(
    center: [for (var k = 0; k < n; k++) line[k] + normals[k] * smoothed[k]],
    leftM: [for (var k = 0; k < n; k++) math.max(half, leftEdge[k] - smoothed[k])],
    rightM: [for (var k = 0; k < n; k++) math.max(half, rightEdge[k] + smoothed[k])],
    reachLeftM: reachLeft == null ? null : [for (var k = 0; k < n; k++) reachLeft[k] - smoothed[k]],
    reachRightM: reachRight == null ? null : [for (var k = 0; k < n; k++) reachRight[k] + smoothed[k]],
  );
}
