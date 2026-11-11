import 'dart:math' as math;
import 'dart:ui';

import 'track_width_profile.dart';

/// 바퀴 가장자리 열이 없는(예전 서버) 응답: 연석을 밟은 쪽 가장자리 = 차들이 달린 끝 + 이만큼(m, 바퀴가 연석에 올라탄 만큼).
const double _kerbEdgeAllowanceM = 0.5;

/// 차 몸체 반폭(m, 서버 형상의 BodyHalfWidthM·리플레이가 그리는 차와 같다).
const double _carHalfWidthM = 1.0;

/// 연석 단서가 없는 구간은 가장 가까운 단서에서 이 거리(m)에 걸쳐 레이싱 라인 = 도로 가운데로 돌아간다.
const double _offsetFadeM = 100;

/// 도로 가운데 이동량을 고르는 이동 평균 반폭(칸). 연석 단서가 칸마다 조금씩 달라 가운데가 좌우로 흔들리지 않게 넓게 고른다.
/// 한 번 평균한 이동량은 단서가 끊기는 자리마다 꺾인 계단이 되므로(양쪽 도로 끝이 같이 삐뚤어진다) 좁게 한 번 더 평균해 둥글게 잇는다.
const int _offsetSmoothBins = 6;
const int _offsetRoundBins = 3;

/// 마지막 도로 끝(레이싱 라인에서 잰 왼쪽·오른쪽)을 두 번 고르는 이동 평균 반폭(칸).
const int _endRoundBins = 1;

/// 도로 가운데 선은 양쪽 도로 끝에서 적어도 이만큼(m) 안쪽에 둔다.
const double _centerInsideM = 2;

/// 연석 안쪽 끝(연석 바깥 끝 − 연석 폭)을 고르는 가운데값 반폭(칸, 연석 칸끼리만): 칸마다 튀는 연석 측정값이 가장자리를 톱니처럼 만들지 않게.
const int _kerbMedianBins = 2;

/// 마지막 가장자리를 고르는 이동 평균 반폭(칸): 연석 깔때기로 자른 계단과 남은 잔물결을 둥글게 편다.
const int _edgeFinalSmoothBins = 2;

/// 가장자리를 고르는 반폭(칸): 앞뒤 가장 먼 값으로 넓힌 뒤 같은 범위로 평균해 칸마다 튀지 않게 한다(점마다 원래 값 이상).
const int _edgeSmoothBins = 3;

/// 가장자리에서 한두 칸만 튄 값(피트 입구로 갈라지는 차처럼 랩 거리와 자리가 어긋난 표본)을 누르는 가운데값 반폭(칸).
const int _edgeMedianBins = 2;

/// 연석 칸의 가장자리(연석 안쪽 끝)에서 멀어질수록 가장자리가 넓어질 수 있는 기울기(옆 m / 진행 m) — 연석 둘레가 깔때기처럼 풀린다.
const double _kerbFunnelSlope = 0.2;

/// 포장 런오프 끝을 고르는 반폭(칸): 앞뒤 가장 먼 값으로 넓힌 뒤 같은 범위로 평균한다(칸마다 원래 값 이상 — 포장 노면을 달린 차를 놓치지 않게).
const int _runoffSmoothBins = 2;

/// 양쪽 연석이 다 밟힌 칸: 앞뒤 이 칸 수로 잰 굽는 정도(1/m)가 이 이상이면 안쪽 연석만 따른다(덜 굽으면 두 쪽을 평균한다).
const int _apexCurvatureBins = 2;
const double _apexSideCurvature = 0.002;

/// 도로 끝을 안쪽 연석에 붙이는 에이펙스: 이 곡률(1/m, 반지름 약 1km)보다 굽는 칸의 안쪽 연석만. 위에서 보면 거의 곧은
/// 고속 코너(Spa Eau Rouge·Raidillon)도 차들이 연석을 타고 지나므로 붙인다.
const double _apexPinCurvature = 0.001;

/// 아스팔트 바퀴 끝이 연석 안쪽 끝보다 이 거리(m) 넘게 바깥이면 그 칸 연석은 붙이지 않는다(반대쪽 연석을 밟은 차의 바퀴가 섞인 값).
const double _apexKerbWheelSlackM = 1.3;

/// 에이펙스 칸에 붙일 안쪽 연석이 없으면(밟은 기록이 없거나, 연석이 1.5m보다 좁아 아스팔트 바퀴가 잰 연석 안쪽 끝보다 바깥에 있으면)
/// 이 곡률(1/m, 반지름 약 125m)보다 급한 코너는 도로 끝을 아스팔트 바퀴 끝에 붙인다. 차들이 연석을 타지 않는 코너(Hungaroring T12·T13)나
/// 연석이 꼭짓점 일부에만 잡힌 코너는 연석 단서가 모자라 도로 가운데가 레이싱 라인에 머물고, 라인이 에이펙스에서 안쪽 도로 끝과 3~8m
/// 떨어져 보인다. 완만한 코너는 안쪽까지 붙여 달리지 않고 반대쪽 연석을 밟은 바퀴가 섞이므로(Spa 블랑쉬몽) 붙이지 않는다.
const double _apexTarmacCurvature = 0.008;

/// 이 칸 수보다 짧게 이어진 에이펙스 연석은 붙이지 않고, 붙는 구간 사이가 이 칸 수 이하로 비면 이어 메운다.
const int _apexMinRunBins = 3;
const int _apexGapFillBins = 6;

/// 에이펙스는 코너 꼭짓점 둘레만: 앞뒤 이 칸 수 안에서 가장 급한 곡률의 이 비율 이상인 칸의 연석만 붙인다.
/// 코너를 빠져나가며 레이싱 라인이 반대쪽으로 건너가는 중에 밟힌 안쪽 연석(Spa Bus Stop 출구)까지 붙이면 그 자리에서 도로 끝이 라인 쪽으로 움푹 꺾인다.
const int _apexPeakBins = 6;
const double _apexPeakFraction = 0.5;

/// 에이펙스 연석에서 멀어질 때 붙인 끝이 풀리는 기울기(옆 m / 진행 m). 레이싱 라인은 에이펙스를 지나면 반대쪽 트랙아웃으로 빠르게
/// 건너가므로, 라인에서 잰 끝이 연석 깔때기처럼 천천히 풀리면 라인에 끌려 직선 쪽 도로 끝과 방호벽이 길로 들어온다(Spa Bus Stop 뒤).
const double _apexFunnelSlope = 0.35;

/// 모자란 폭은 덜 붙은 쪽에 주되, 양쪽 에이펙스 깔때기 차이가 이 값(m)의 두 배 안이면 차이에 비례해 나눈다 —
/// 시케인(Spa Bus Stop)처럼 에이펙스가 한쪽에서 반대쪽으로 바뀌는 칸에서 한 칸 만에 넘기면 도로가 옆으로 몇 m씩 튄다.
const double _apexShareSpanM = 8;

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
    this.bankSlope,
    this.pavedOuterLeftM,
    this.pavedOuterRightM,
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

  /// 노면 옆 기울기(뱅크): 레이싱 라인에서 왼쪽(법선 (−sin, cos))으로 1m 갈 때 높아지는 높이(m). 예전 서버 응답이면 null.
  final List<double>? bankSlope;

  /// 포장 노면 끝: 네 바퀴가 모두 포장 노면(아스팔트·연석)에 있던 차의 바깥 바퀴가 닿은 가장 먼 자리(빼는 표본 없이).
  /// 도로 끝 너머 이 자리까지를 포장 런오프로 그린다. 예전 서버 응답이면 null.
  final List<double>? pavedOuterLeftM;
  final List<double>? pavedOuterRightM;

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
      bankSlope: column('bankSlope'),
      pavedOuterLeftM: column('pavedOuterLeftM'),
      pavedOuterRightM: column('pavedOuterRightM'),
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
/// 굽은 안쪽 연석(에이펙스) 둘레는 고른 가운데 이동이 꼭짓점에서 무뎌지므로 그 쪽 끝을 연석 안쪽 끝에 붙이고, 모자란 폭은 반대쪽에 준다.
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
  // 칸마다 레이싱 라인이 굽는 정도(1/m, + = 왼쪽으로 굽는다 = 왼쪽이 코너 안쪽).
  double headingAt(int k) {
    final d = line[at(k + 1)] - line[at(k - 1)];
    return math.atan2(d.dy, d.dx);
  }

  double curvatureAt(int k) {
    final turn = headingAt(k + _apexCurvatureBins) - headingAt(k - _apexCurvatureBins);
    final wrapped = (turn + math.pi) % (2 * math.pi) - math.pi;
    return wrapped / (2 * _apexCurvatureBins * geometry.resolutionM);
  }

  final curvatures = [for (var k = 0; k < n; k++) curvatureAt(k)];
  // 앞뒤 [_apexPeakBins] 칸 안에서 [inside] 쪽으로 가장 급하게 굽는 정도(1/m).
  double insidePeak(int k, int inside) =>
      [for (var j = -_apexPeakBins; j <= _apexPeakBins; j++) inside * curvatures[at(k + j)]].reduce(math.max);
  // 연석 칸에서 멀어질수록 칸마다 이만큼씩만 넓어질 수 있다(서킷이 닫혀 있어 두 바퀴 돌며 끝과 처음을 잇는다).
  List<double> funnelFrom(List<double?> limits, {double slope = _kerbFunnelSlope}) {
    final step = slope * geometry.resolutionM;
    final funnel = [for (final limit in limits) limit ?? double.infinity];
    for (var round = 0; round < 2; round++) {
      for (var k = 0; k < n; k++) {
        funnel[k] = math.min(funnel[k], funnel[at(k - 1)] + step);
      }
      for (var k = n - 1; k >= 0; k--) {
        funnel[k] = math.min(funnel[k], funnel[at(k + 1)] + step);
      }
    }
    return funnel;
  }

  /// 도로 끝을 붙일 에이펙스 연석 안쪽 끝(칸마다, 붙이지 않는 칸은 null): 코너 꼭짓점 둘레에서 안쪽으로 굽는 칸의 연석 가운데
  /// 아스팔트 바퀴 끝([wheels])이 연석 안쪽 끝 가까이에 있는 것만 — 그보다 훨씬 바깥까지 아스팔트를 밟았다면 그 쪽 연석 표본은
  /// 반대쪽 연석을 밟은 차의 바퀴다(Spa 블랑쉬몽: 양쪽 "연석"이 다 레이싱 라인 0.5m 안). 한두 칸만 붙는 연석은 빼고(그 자리만 도로 끝이
  /// V자로 파인다), 붙는 구간 사이의 짧은 틈은 앞뒤 값을 이어 메운다(틈에서 끝이 풀렸다 다시 붙어 삐쭉해지지 않게).
  /// 붙일 연석이 없는 칸은 급한 코너([_apexTarmacCurvature])의 꼭짓점이면 아스팔트 바퀴 끝([tarmac])에 붙인다.
  List<double?> apexPins(List<double?> kerbInner, List<double>? wheels, List<double>? tarmac, int inside) {
    bool atApex(int k, double minCurvature) =>
        inside * curvatures[k] >= math.max(minCurvature, _apexPeakFraction * insidePeak(k, inside));
    final pins = [
      for (var k = 0; k < n; k++)
        switch (kerbInner[k]) {
          final inner? when atApex(k, _apexPinCurvature) && (wheels == null || wheels[k] <= inner + _apexKerbWheelSlackM) =>
            inner,
          _ when tarmac != null && atApex(k, _apexTarmacCurvature) => tarmac[k],
          _ => null,
        },
    ];
    // 붙는 칸이 이어진 구간(서킷은 닫혀 있다). 시작 칸에서 앞으로 센다.
    final runs = <(int, int)>[];
    final start = pins.indexWhere((p) => p == null);
    if (start < 0) {
      return pins;
    }
    for (var s = 0; s < n; s++) {
      final k = at(start + s);
      if (pins[k] == null) {
        continue;
      }
      if (runs.isNotEmpty && at(runs.last.$1 + runs.last.$2) == k) {
        runs[runs.length - 1] = (runs.last.$1, runs.last.$2 + 1);
      } else {
        runs.add((k, 1));
      }
    }
    final kept = [for (final run in runs) if (run.$2 >= _apexMinRunBins) run];
    final out = List<double?>.filled(n, null);
    for (final (first, length) in kept) {
      for (var s = 0; s < length; s++) {
        out[at(first + s)] = pins[at(first + s)];
      }
    }
    for (var r = 0; r < kept.length; r++) {
      final (first, length) = kept[r];
      final last = at(first + length - 1);
      final next = kept[(r + 1) % kept.length].$1;
      final gap = (next - last - 1 + n) % n;
      if (gap == 0 || gap > _apexGapFillBins || (kept.length == 1 && gap >= n - length)) {
        continue;
      }
      final from = out[last]!;
      final to = out[next]!;
      for (var s = 1; s <= gap; s++) {
        out[at(last + s)] = from + (to - from) * s / (gap + 1);
      }
    }
    return out;
  }

  /// 한쪽 가장자리([inside] = 그 쪽이 코너 안쪽인 곡률 부호: 왼쪽 1, 오른쪽 −1)와,
  /// 굽은 안쪽 연석(에이펙스) 칸에서만 퍼지는 연석 깔때기(`apex`, 그런 연석이 없으면 무한대).
  ({List<double> edge, List<double> apex}) edge(
    List<double>? wheels,
    List<double>? kerbOuter,
    List<bool> kerbs,
    List<double> band,
    int inside,
  ) {
    // 연석 칸의 가장자리 = 연석 안쪽 끝(그 너머 표본은 연석 위나 연석 밖이다). 칸마다 튀는 측정값은 앞뒤 연석 칸의 가운데값으로 누른다.
    final rawKerbInner = [
      for (var k = 0; k < n; k++)
        wheels != null && kerbOuter != null && kerbs[k] && kerbOuter[k] > 0 ? kerbOuter[k] - kerbWidthM : null,
    ];
    final kerbInner = [
      for (var k = 0; k < n; k++)
        rawKerbInner[k] == null
            ? null
            : () {
                final near = [
                  for (var j = -_kerbMedianBins; j <= _kerbMedianBins; j++) ?rawKerbInner[at(k + j)],
                ]..sort();
                return near[near.length ~/ 2];
              }(),
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
    final funnel = funnelFrom(kerbInner);
    final limited = [for (var k = 0; k < n; k++) math.min(smoothed[k], funnel[k])];
    return (
      edge: [
        for (var k = 0; k < n; k++)
          [for (var j = -_edgeFinalSmoothBins; j <= _edgeFinalSmoothBins; j++) limited[at(k + j)]]
                  .reduce((a, b) => a + b) /
              (_edgeFinalSmoothBins * 2 + 1),
      ],
      apex: funnelFrom(
        apexPins(kerbInner, wheels, wheels == null || kerbOuter == null ? null : despiked, inside),
        slope: _apexFunnelSlope,
      ),
    );
  }

  final left = edge(geometry.edgeLeftM, geometry.kerbOuterLeftM, geometry.kerbLeft, geometry.bandLeftM, 1);
  final right = edge(geometry.edgeRightM, geometry.kerbOuterRightM, geometry.kerbRight, geometry.bandRightM, -1);
  final leftEdge = left.edge;
  final rightEdge = right.edge;

  // 연석 단서가 있는 칸의 도로 가운데 이동량(+ = 왼쪽). 양쪽 다 밟힌 칸(코너 꼭짓점 — S자에서 차마다 어느 쪽 연석을 밟느냐가 다르다)은
  // 굽는 안쪽 연석을 따른다. 둘을 평균하면 가운데가 레이싱 라인으로 돌아와 꼭짓점에서 차가 연석이 아니라 도로 한가운데를 지나 보인다.
  final known = <int, double>{};
  for (var k = 0; k < n; k++) {
    final both = geometry.kerbLeft[k] && geometry.kerbRight[k];
    final curvature = both ? curvatures[k] : 0.0;
    final insideLeft = both && curvature >= _apexSideCurvature;
    final insideRight = both && curvature <= -_apexSideCurvature;
    final values = [
      if (geometry.kerbLeft[k] && !insideRight) leftEdge[k] - half,
      if (geometry.kerbRight[k] && !insideLeft) half - rightEdge[k],
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
  List<double> average(List<double> values, int bins) => [
        for (var k = 0; k < n; k++)
          [for (var j = -bins; j <= bins; j++) values[at(k + j)]].reduce((a, b) => a + b) / (bins * 2 + 1),
      ];
  final smoothed = average(average(offsets, _offsetSmoothBins), _offsetRoundBins);

  // 레이싱 라인에서 왼쪽·오른쪽 도로 끝(m). 기본은 옮긴 가운데에서 반폭이지만, 굽은 안쪽 연석(에이펙스) 둘레는 그 쪽 끝을
  // 연석 안쪽 끝에 붙인다 — 가운데 이동은 넓게 고르므로 꼭짓점에서 무뎌져, 반폭만으로는 레이싱 라인이 에이펙스 연석에서 떨어져 보인다.
  // 도로 폭은 [widthM]보다 좁아지지 않게, 모자란 폭은 덜 붙은 쪽(에이펙스에서 먼 쪽)으로 넘긴다([_apexShareSpanM]).
  // (그 쪽 연석에서 막으면 양쪽 연석이 다 밟힌 구간 — Spa 블랑쉬몽 뒤 — 도로가 반으로 좁아지고 방호벽이 길로 튀어나온다.)
  final leftEnd = List<double>.filled(n, 0);
  final rightEnd = List<double>.filled(n, 0);
  for (var k = 0; k < n; k++) {
    var l = math.max(leftEdge[k], math.min(half + smoothed[k], left.apex[k]));
    var r = math.max(rightEdge[k], math.min(half - smoothed[k], right.apex[k]));
    final deficit = widthM - l - r;
    if (deficit > 0) {
      final a = left.apex[k];
      final b = right.apex[k];
      final toLeft = a == b ? 0.5 : ((a - b) / (2 * _apexShareSpanM) + 0.5).clamp(0.0, 1.0);
      l += deficit * toLeft;
      r += deficit * (1 - toLeft);
    }
    leftEnd[k] = l;
    rightEnd[k] = r;
  }
  // 에이펙스에 붙는 칸에서는 안쪽 끝이 한두 칸 만에 연석으로 들어오고 모자란 폭이 반대쪽으로 넘어가 도로 전체가 옆으로 꺾이므로,
  // 두 끝을 좁게 두 번 평균해 둥글게 잇는다(두 쪽 합은 평균해도 [widthM] 이상). 차들이 달린 가장자리 안으로는 들이지 않는다.
  final leftRounded = average(average(leftEnd, _endRoundBins), _endRoundBins);
  final rightRounded = average(average(rightEnd, _endRoundBins), _endRoundBins);
  for (var k = 0; k < n; k++) {
    leftEnd[k] = math.max(leftEdge[k], leftRounded[k]);
    rightEnd[k] = math.max(rightEdge[k], rightRounded[k]);
  }
  // 도로 가운데는 두 끝에서 [_centerInsideM] 안에 둔다. 에이펙스에 붙인 안쪽 끝은 넓게 고른 가운데 이동보다 라인에 가까워
  // 가운데가 도로 밖으로 나갈 수 있다(그 쪽 폭이 음수가 되면 서킷이 0으로 잘라 도로 끝을 가운데에 그린다).
  // 자른 자리가 꺾이지 않게 좁게 고른 뒤 한 번 더 자른다.
  List<double> inside(List<double> values) => [
        for (var k = 0; k < n; k++) values[k].clamp(_centerInsideM - rightEnd[k], leftEnd[k] - _centerInsideM),
      ];
  final shift = inside(average(average(inside(smoothed), _endRoundBins), _endRoundBins));

  final reachLeft = geometry.reachLeftM;
  final reachRight = geometry.reachRightM;
  // 피트를 드나들지 않는 차가 포장 노면으로 달린 자리: 띠 끝(차 가운데) + 차 반폭. 바퀴 끝(가장 먼 1% 제외)은 표본이 적은 칸에서
  // 피트 상태 없이 피트 레인을 지난 차 하나로 30m 넘게 튀므로(Austria·Catalunya 결승선 앞) 쓰지 않는다.
  List<double> paved(List<double> band, int sign) => [for (var k = 0; k < n; k++) band[k] + _carHalfWidthM - sign * shift[k]];
  // 포장 런오프 끝(레이싱 라인에서 m): 네 바퀴가 포장 노면에 있던 차의 바깥 바퀴가 닿은 자리 — 서버가 준 가장 먼 값([outer], 새 응답),
  // 없으면 아스팔트만 밟은 차(가장 먼 1% 제외)·연석을 밟은 차·차들이 달린 띠 + 차 반폭 가운데 가장 먼 값. 도로 끝보다 안쪽이면 도로 끝이다.
  // [outer]가 null이면 평소 값(가장 먼 1%를 뺀 값)만으로 만든다 — 가장 먼 값이 피트 레인에 걸리는 칸에서 서킷이 대신 쓴다.
  List<double>? runoff(List<double>? wheels, List<double>? kerbOuter, List<double> band, List<double> end, List<double>? outer) {
    if (wheels == null || kerbOuter == null) {
      return null;
    }
    final raw = [
      for (var k = 0; k < n; k++)
        [wheels[k], kerbOuter[k], band[k] + _carHalfWidthM, outer?[k] ?? 0.0].reduce(math.max),
    ];
    final widened = [
      for (var k = 0; k < n; k++)
        [for (var j = -_runoffSmoothBins; j <= _runoffSmoothBins; j++) raw[at(k + j)]].reduce(math.max),
    ];
    final smooth = average(widened, _runoffSmoothBins);
    return [for (var k = 0; k < n; k++) math.max(end[k], smooth[k])];
  }

  final runoffLeft = runoff(geometry.edgeLeftM, geometry.kerbOuterLeftM, geometry.bandLeftM, leftEnd, null);
  final runoffRight = runoff(geometry.edgeRightM, geometry.kerbOuterRightM, geometry.bandRightM, rightEnd, null);
  final farLeft = geometry.pavedOuterLeftM;
  final farRight = geometry.pavedOuterRightM;
  final runoffFarLeft =
      farLeft == null ? null : runoff(geometry.edgeLeftM, geometry.kerbOuterLeftM, geometry.bandLeftM, leftEnd, farLeft);
  final runoffFarRight =
      farRight == null ? null : runoff(geometry.edgeRightM, geometry.kerbOuterRightM, geometry.bandRightM, rightEnd, farRight);
  return TrackWidthProfile(
    center: [for (var k = 0; k < n; k++) line[k] + normals[k] * shift[k]],
    leftM: [for (var k = 0; k < n; k++) leftEnd[k] - shift[k]],
    rightM: [for (var k = 0; k < n; k++) rightEnd[k] + shift[k]],
    reachLeftM: reachLeft == null ? null : [for (var k = 0; k < n; k++) reachLeft[k] - shift[k]],
    reachRightM: reachRight == null ? null : [for (var k = 0; k < n; k++) reachRight[k] + shift[k]],
    pavedLeftM: paved(geometry.bandLeftM, 1),
    pavedRightM: paved(geometry.bandRightM, -1),
    runoffLeftM: runoffLeft == null ? null : [for (var k = 0; k < n; k++) runoffLeft[k] - shift[k]],
    runoffRightM: runoffRight == null ? null : [for (var k = 0; k < n; k++) runoffRight[k] + shift[k]],
    runoffFarLeftM: runoffFarLeft == null ? null : [for (var k = 0; k < n; k++) runoffFarLeft[k] - shift[k]],
    runoffFarRightM: runoffFarRight == null ? null : [for (var k = 0; k < n; k++) runoffFarRight[k] + shift[k]],
  );
}
