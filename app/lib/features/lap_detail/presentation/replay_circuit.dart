import 'dart:math' as math;
import 'dart:ui';

import '../../tracks/domain/track_sample_geometry.dart';
import '../../tracks/domain/track_width_profile.dart';
import '../domain/ghost_replay.dart';
import '../domain/lap_detail_models.dart';
import '../domain/track_alignment.dart';

/// 서킷 중심선을 구할 때 앞뒤로 평균하는 거리(m). 레이싱 라인은 코너마다 바깥 → 에이펙스 → 바깥으로 오가므로
/// 이 거리만큼 평균하면 도로 가운데쯤이 되고, 차는 그 도로 안에서 좌우로 움직여 보인다(실측 서킷이 없을 때).
const double kCircuitCenterSmoothM = 30;

/// 실측 서킷이 없을 때의 직선 도로 폭(m). 코너에서는 곡률에 따라 [kCircuitCornerExtraWidthM]까지 넓어진다.
const double kCircuitBaseWidthM = 13;
const double kCircuitCornerExtraWidthM = 3;

/// 곡률(1/m) × 이 값 = 코너에서 넓어지는 폭(m, [kCircuitCornerExtraWidthM]까지).
const double _cornerWidthGain = 150;

/// 노면 기록이 없을 때 이 곡률(1/m, 반지름 약 125m)보다 급한 구간 양쪽 가장자리에 연석을 그린다.
const double kCircuitKerbCurvature = 0.008;

/// 이 곡률(1/m, 반지름 약 80m)보다 급한 코너 바깥쪽에 그래블(자갈) 구역을 그린다.
const double kCircuitGravelCurvature = 0.0125;

/// 연석 폭(m)·그래블 폭(m).
const double kCircuitKerbWidthM = 1.5;
const double kCircuitGravelWidthM = 12;

/// 피트 레인 폭(m).
const double kCircuitPitLaneWidthM = 7;

/// 첫·마지막 표본이 이 거리(m)보다 가까우면 한 바퀴로 이어진 닫힌 서킷으로 본다.
const double _closedLoopM = 40;

/// 추정 모양에서 주행선이 도로 중심에서 벗어날 수 있는 거리 = 직선 반폭 − 이 값(m). 차가 늘 아스팔트 위에 있게 한다.
const double _lateralMarginM = 2;

/// 코너 안쪽 반폭의 상한 = 곡률 반지름 × 이 비율.
const double _innerRadiusFraction = 0.8;

/// 차 폭의 절반(m): 연석을 밟지 않은 표본은 차 가운데가 가장자리에서 이만큼 안쪽에 있어야 한다.
const double _carHalfWidthM = 1;

/// 차 길이의 절반(m, 그림의 차와 같다): 비스듬히 선 차는 옆으로 반폭~반길이만큼 닿는다.
const double _carHalfLengthM = 2.8;

/// 연석을 밟은 표본은 차 가운데가 가장자리 밖으로 이만큼(m)까지 나가도 된다(바깥 바퀴가 연석 위).
const double _kerbCarAllowanceM = 0.5;

/// 실측 중심선을 좌우로 옮기는 보정이 앞뒤로 퍼지는 거리(m) — 갑자기 꺾이지 않게.
const double _shiftSpreadM = 20;

/// 도로 안에 들어야 할 자리(출발 그리드 등)를 덮을 때 차 반폭 바깥으로 더 남기는 폭(m).
const double _coverMarginM = 1;

/// 추정 중심선 점이 실측 중심선에서 이 거리(m) 안이면 같은 길로 보고 실측 중심·폭을 쓴다(멀면 레이아웃이 바뀐 구간).
const double _measuredMatchM = 15;

/// 실측 구간과 추정 구간 경계를 섞는 거리(m, 앞뒤로).
const double _measuredBlendM = 30;

/// 밟은 연석 한 점이 앞뒤로 이어지는 거리(m)·이보다 짧게 끊긴 연석 틈(m)은 이어 그린다.
const double _kerbSpreadM = 6;
const double _kerbGapFillM = 12;

/// 급한 코너의 안쪽 연석 기록이 코너 길이의 이 비율보다 적으면 곡률로 코너 내내 안쪽 연석을 그린다
/// (게임이 연석을 연석 노면으로 알려 주지 않아 한두 칸만 잡힌 곳 — 모나코 라스카스 등).
const double _insideKerbMinCoverage = 0.25;

/// 중심선을 다듬는 이동 평균 반폭(표본 수)·곡률을 고르는 이동 평균 반폭(표본 수).
const int _centerTidySamples = 2;
const int _curvatureSmoothSamples = 3;

/// 추정 도로 폭을 고르는 이동 평균 반폭(표본 수)·곡률 연석·그래블로 그릴 최소 연속 표본 수.
const int _widthSmoothSamples = 6;
const int _minFeatureRunSamples = 4;

/// 노면 높이를 고르는 이동 평균 반폭(표본 수, 서스펜션·연석으로 튀는 높이를 없앤다).
const int _elevationSmoothSamples = 4;

/// 주행 표본을 중심선 점에 짝지을 때 앞 표본의 짝 둘레로 찾는 범위(점 수)·그 안에서 이보다 멀면(m) 전체에서 다시 찾는다.
const int _matchWindow = 40;
const double _rematchM = 30;

/// 연석 줄무늬 한 칸을 표본 간격의 몇 등분으로 나눌지(빨강·흰색이 번갈아).
const int _kerbStripesPerSegment = 2;

/// 고스트 재생 화면의 서킷 모양(월드 좌표 m). 실측 서킷([TrackWidthProfile])을 주행선에 맞출 수 있으면 그 중심선·좌우 폭을 쓰고,
/// 없거나 맞지 않으면 내 랩(+ 비교 랩) 주행선을 평활해 중심선과 폭을 추정한다.
/// 연석은 바퀴 노면 기록에서 실제로 밟은 자리에 그리고(기록이 없으면 곡률로 추정), 그래블은 곡률로 정한 코너 바깥에 그린다.
class ReplayCircuit {
  ReplayCircuit._({
    required this.center,
    required this.leftWidths,
    required this.rightWidths,
    required this.curvatures,
    required this.isMeasured,
    required this.street,
    required this.closed,
    required this.leftPoints,
    required this.rightPoints,
    required this.kerbLeft,
    required this.kerbRight,
    required this.gravelAt,
    required this.elevations,
    required this.asphalt,
    required this.leftEdge,
    required this.rightEdge,
    required this.kerbRed,
    required this.kerbWhite,
    required this.gravel,
    required this.startPoint,
    required this.startHeading,
    required this.startLeftM,
    required this.startRightM,
    required this.reachLeftM,
    required this.reachRightM,
    this.pitLane = const [],
    this.pitElevations = const [],
    this.pitNormals = const [],
    Path? pitAsphalt,
  }) : pitAsphalt = pitAsphalt ?? Path();

  /// 중심선 점.
  final List<Offset> center;

  /// 점마다 중심선에서 왼쪽(진행 방향 반시계)·오른쪽 가장자리까지 거리(m)·곡률(1/m, 부호 = 도는 방향).
  final List<double> leftWidths;
  final List<double> rightWidths;
  final List<double> curvatures;

  /// 실측 서킷 폭을 썼는지(아니면 주행 기록으로 추정).
  final bool isMeasured;

  /// 시가지 서킷인지(그래블 없이 도로 바로 옆에 방호벽).
  final bool street;

  /// 중심선이 한 바퀴 닫혔는지(마지막 점 → 첫 점도 길).
  final bool closed;

  /// 점마다 왼쪽·오른쪽 가장자리 위치, 그 쪽 가장자리 바깥에 연석이 있는지, 코너 바깥에 그래블이 있는지
  /// (점 i → 다음 점 구간 기준, 3D 시점이 면을 세운다).
  final List<Offset> leftPoints;
  final List<Offset> rightPoints;
  final List<bool> kerbLeft;
  final List<bool> kerbRight;
  final List<bool> gravelAt;

  /// 점마다 노면 높이(m, 월드 Y). 내 랩에 높이 채널이 없으면 모두 0.
  final List<double> elevations;

  /// 칠할 모양들(채움: 아스팔트·연석·그래블, 선: 가장자리).
  final Path asphalt;
  final Path leftEdge;
  final Path rightEdge;
  final Path kerbRed;
  final Path kerbWhite;
  final Path gravel;

  /// 출발·결승선: 내 랩 첫 위치에 가장 가까운 중심선 점, 진행 방향(라디안), 왼쪽·오른쪽 폭(m).
  final Offset startPoint;
  final double startHeading;
  final double startLeftM;
  final double startRightM;

  /// 점마다 중심선에서 차 몸체가 닿은 가장 먼 자리(m, 왼쪽·오른쪽): 표본 형상의 모든 차와 내 랩·비교 랩 차.
  /// 방호벽은 이보다 바깥에 세운다(차가 벽을 뚫고 지나가 보이지 않게). 아무 차도 닿지 않은 쪽은 0.
  final List<double> reachLeftM;
  final List<double> reachRightM;

  /// 피트 레인 선(입구 → 출구, 월드 X·Z)·점마다 노면 높이·왼쪽 법선, 그리고 2D로 칠할 피트 레인 면. 표본 형상에 피트 레인이 없으면 비어 있다.
  final List<Offset> pitLane;
  final List<double> pitElevations;
  final List<Offset> pitNormals;
  final Path pitAsphalt;

  /// [player](와 [ghost]) 주행 기록으로 서킷 모양을 만든다. [samples](모든 차 표본으로 만든 트랙 형상)가 있으면
  /// 그것으로 만든 도로를 그 칸 그대로 쓴다 — 게임 좌표·레이아웃 그대로라 [real](지도 실측)보다 맞고(카탈루냐는 지도가 옛 레이아웃),
  /// 주행선에 다시 맞추거나 주행선 점으로 옮겨 담지 않아 어긋나거나 뭉개지지 않는다. 주행선은 폭만 넓혀 도로 안에 담는다.
  /// 표본 형상이 없고 [real]이 있고 주행선에 맞으면 실측 중심선·폭을 쓴다.
  /// 높이·연석은 [samples]가 있으면 그것을 먼저 쓴다(내 랩 하나보다 여러 차·여러 랩이 고르다).
  /// [baseWidthM]은 실측이 없는 구간의 직선 도로 폭(트랙마다 다를 수 있다, 기본 [kCircuitBaseWidthM]).
  /// [street](시가지 서킷)이면 코너 바깥 그래블을 깔지 않는다.
  /// [cover](월드 X·Z — 출발 그리드에 선 차 자리 등)는 차가 통째로 도로 안에 들도록 그 둘레 폭을 넓힌다.
  factory ReplayCircuit.build(
    LapReplay player, {
    LapReplay? ghost,
    TrackWidthProfile? real,
    TrackSampleGeometry? samples,
    double baseWidthM = kCircuitBaseWidthM,
    bool street = false,
    List<Offset> cover = const [],
  }) {
    final lines = [player.trace, if (ghost != null) ghost.trace];
    final playerLine = _positions(player.trace);
    final sampled =
        samples == null ? null : trackProfileFromSamples(samples, widthM: baseWidthM, kerbWidthM: kCircuitKerbWidthM);
    // 지도 실측만 좌표계가 달라 주행선에 맞춘다.
    final aligned = sampled != null || real == null ? null : alignTrackProfile(real, playerLine);
    final geometry = _covering(
      sampled != null
          ? _coveringLines((center: sampled.center, left: sampled.leftM, right: sampled.rightM, closed: true), lines)
          : () {
              final estimated = _estimated(player, ghost, baseWidthM);
              return aligned == null ? estimated : _keepLinesInside(_withMeasured(estimated, aligned), lines);
            }(),
      cover,
    );
    final center = geometry.center;
    final n = center.length;
    final closed = geometry.closed;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);

    double headingAt(int i) {
      final d = center[at(i + 1)] - center[at(i - 1)];
      return math.atan2(d.dy, d.dx);
    }

    final headings = [for (var i = 0; i < n; i++) headingAt(i)];
    final spacing = _spacing(center, closed: closed);
    final rawCurvatures = [
      for (var i = 0; i < n; i++) _angleDiff(headings[at(i + 1)], headings[at(i - 1)]) / (2 * spacing),
    ];
    // 곡률은 앞뒤 몇 칸 평균으로 튀는 값을 없앤다(연석·그래블이 조각조각 생기지 않게).
    final curvatures = _movingAverage(rawCurvatures, _curvatureSmoothSamples, at);
    // 급한 코너 안쪽 반폭은 곡률 반지름보다 작아야 한다(아니면 안쪽 가장자리가 뒤집혀 접힌다 — 모나코 헤어핀).
    // 평균한 곡률은 꼭짓점에서 작아지므로 앞뒤 몇 칸 가운데 가장 급한 값으로 잰다.
    double innerLimit(int i) {
      var sharpest = 0.0;
      for (var k = i - _curvatureSmoothSamples; k <= i + _curvatureSmoothSamples; k++) {
        sharpest = math.max(sharpest, rawCurvatures[at(k)].abs());
      }
      return sharpest == 0 ? double.infinity : _innerRadiusFraction / sharpest;
    }

    final leftWidths = [
      for (var i = 0; i < n; i++) curvatures[i] > 0 ? math.min(geometry.left[i], innerLimit(i)) : geometry.left[i],
    ];
    final rightWidths = [
      for (var i = 0; i < n; i++) curvatures[i] < 0 ? math.min(geometry.right[i], innerLimit(i)) : geometry.right[i],
    ];

    // 왼쪽 법선(진행 방향에서 +90°).
    final normals = [for (final h in headings) Offset(-math.sin(h), math.cos(h))];
    final left = [for (var i = 0; i < n; i++) center[i] + normals[i] * leftWidths[i]];
    final right = [for (var i = 0; i < n; i++) center[i] - normals[i] * rightWidths[i]];

    final reach = _reach(sampled, lines, center, normals, closed: closed);
    final traceKerbs = _kerbSides(lines, center, normals, curvatures, spacing: spacing, closed: closed);
    final sampleKerbs = samples == null ? null : _sampleKerbs(samples, center, spacing: spacing, closed: closed);
    // 안쪽 연석 기록이 하나도 없는 급한 코너는 곡률로 안쪽 연석을 그린다 — 게임이 연석을 연석 노면으로 알려 주지 않는 곳(모나코 라스카스 등).
    // 몇 m만 잡힌 연석 조각(한두 칸만 밟힌 자리)은 빼서 연석이 끊어진 토막으로 흩어져 보이지 않게 한다.
    final kerbs = _withInsideKerbs(
      sampleKerbs == null
          ? traceKerbs
          : (
              left: _dropShortRuns([for (var i = 0; i < n; i++) traceKerbs.left[i] || sampleKerbs.left[i]], closed: closed),
              right: _dropShortRuns([for (var i = 0; i < n; i++) traceKerbs.right[i] || sampleKerbs.right[i]], closed: closed),
            ),
      curvatures,
      closed: closed,
    );
    final gravelAt = street
        ? List.filled(n, false)
        : _dropShortRuns([for (final k in curvatures) k.abs() >= kCircuitGravelCurvature], closed: closed);

    final asphalt = Path();
    final kerbRed = Path();
    final kerbWhite = Path();
    final gravel = Path();
    final segments = closed ? n : n - 1;
    for (var i = 0; i < segments; i++) {
      final j = at(i + 1);
      _quad(asphalt, left[i], left[j], right[j], right[i]);

      for (final (edge, side, flags) in [(left, 1.0, kerbs.left), (right, -1.0, kerbs.right)]) {
        if (!flags[i]) {
          continue;
        }
        final outI = normals[i] * (side * kCircuitKerbWidthM);
        final outJ = normals[j] * (side * kCircuitKerbWidthM);
        for (var s = 0; s < _kerbStripesPerSegment; s++) {
          final t0 = s / _kerbStripesPerSegment;
          final t1 = (s + 1) / _kerbStripesPerSegment;
          final a = Offset.lerp(edge[i], edge[j], t0)!;
          final b = Offset.lerp(edge[i], edge[j], t1)!;
          final oa = Offset.lerp(outI, outJ, t0)!;
          final ob = Offset.lerp(outI, outJ, t1)!;
          _quad((i * _kerbStripesPerSegment + s).isEven ? kerbRed : kerbWhite, a, b, b + ob, a + oa);
        }
      }
      if (gravelAt[i]) {
        // 곡률 중심이 왼쪽(k > 0)이면 바깥은 오른쪽. 그 쪽에 연석이 있으면 연석 바깥부터.
        final outerIsRight = curvatures[i] > 0;
        final side = outerIsRight ? -1.0 : 1.0;
        final edge = outerIsRight ? right : left;
        final kerbed = (outerIsRight ? kerbs.right : kerbs.left)[i];
        final inset = kerbed ? kCircuitKerbWidthM : 0.0;
        final innerI = edge[i] + normals[i] * (side * inset);
        final innerJ = edge[j] + normals[j] * (side * inset);
        final outerI = innerI + normals[i] * (side * kCircuitGravelWidthM);
        final outerJ = innerJ + normals[j] * (side * kCircuitGravelWidthM);
        _quad(gravel, innerI, innerJ, outerJ, outerI);
      }
    }

    final start = _nearestIndex(center, playerLine.first);
    final elevations = _elevations(player.trace, playerLine, center, at, samples);
    final pitLane = samples?.pitLine ?? const <Offset>[];
    final pitNormals = [
      for (var i = 0; i < pitLane.length; i++)
        () {
          final d = pitLane[math.min(i + 1, pitLane.length - 1)] - pitLane[math.max(i - 1, 0)];
          return d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance;
        }(),
    ];
    final pitAsphalt = Path();
    for (var i = 0; i + 1 < pitLane.length; i++) {
      final a = pitNormals[i] * (kCircuitPitLaneWidthM / 2);
      final b = pitNormals[i + 1] * (kCircuitPitLaneWidthM / 2);
      _quad(pitAsphalt, pitLane[i] + a, pitLane[i + 1] + b, pitLane[i + 1] - b, pitLane[i] - a);
    }
    final pitHeights = samples?.pitY;
    return ReplayCircuit._(
      pitLane: pitLane,
      pitNormals: pitNormals,
      pitElevations: [
        for (var i = 0; i < pitLane.length; i++) pitHeights?[i] ?? elevations[_nearestIndex(center, pitLane[i])],
      ],
      pitAsphalt: pitAsphalt,
      center: center,
      leftWidths: leftWidths,
      rightWidths: rightWidths,
      curvatures: curvatures,
      isMeasured: sampled != null || aligned != null,
      street: street,
      closed: closed,
      leftPoints: left,
      rightPoints: right,
      kerbLeft: kerbs.left,
      kerbRight: kerbs.right,
      gravelAt: gravelAt,
      elevations: elevations,
      asphalt: asphalt,
      leftEdge: _polyline(left, closed: closed),
      rightEdge: _polyline(right, closed: closed),
      kerbRed: kerbRed,
      kerbWhite: kerbWhite,
      gravel: gravel,
      startPoint: center[start],
      startHeading: headings[start],
      startLeftM: leftWidths[start],
      startRightM: rightWidths[start],
      reachLeftM: reach.left,
      reachRightM: reach.right,
    );
  }

  /// 추정 모양 [base]의 점마다 실측 중심선([real])에 투영해, 가까우면(같은 길) 그 자리의 실측 중심·폭을 쓰고
  /// 멀면(게임 레이아웃이 바뀐 구간) 추정 모양을 그대로 둔다. 두 구간의 경계는 앞뒤로 섞어 끊김 없이 잇는다.
  static _Geometry _withMeasured(_Geometry base, AlignedTrack real) {
    final n = base.center.length;
    int at(int i) => base.closed ? (i % n + n) % n : i.clamp(0, n - 1);
    final m = real.center.length;
    final matcher = _SequentialMatcher(real.center, closed: true);
    final targets = <Offset>[];
    final lefts = <double>[];
    final rights = <double>[];
    final matched = <double>[];
    for (var i = 0; i < n; i++) {
      final p = base.center[i];
      final j = matcher.match(p);
      // 이웃 두 선분 가운데 가까운 쪽에 투영(점 간격만큼 계단지지 않게).
      var best = (point: real.center[j], k: j, t: 0.0);
      var bestDistance = double.infinity;
      for (final k in [(j - 1 + m) % m, j]) {
        final a = real.center[k];
        final b = real.center[(k + 1) % m];
        final ab = b - a;
        final lengthSquared = ab.distanceSquared;
        final t = lengthSquared == 0
            ? 0.0
            : (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared).clamp(0.0, 1.0);
        final q = Offset.lerp(a, b, t)!;
        final d = (q - p).distanceSquared;
        if (d < bestDistance) {
          bestDistance = d;
          best = (point: q, k: k, t: t);
        }
      }
      final k1 = (best.k + 1) % m;
      final realTangent = real.center[k1] - real.center[best.k];
      final baseTangent = base.center[at(i + 1)] - base.center[at(i - 1)];
      // 진행 방향이 실측 점 순서와 반대면 왼쪽·오른쪽이 바뀐다.
      final sameDirection = realTangent.dx * baseTangent.dx + realTangent.dy * baseTangent.dy >= 0;
      final realLeft = _lerp(real.leftM[best.k], real.leftM[k1], best.t);
      final realRight = _lerp(real.rightM[best.k], real.rightM[k1], best.t);
      final isMatch = bestDistance <= _measuredMatchM * _measuredMatchM;
      targets.add(isMatch ? best.point : p);
      lefts.add(isMatch ? (sameDirection ? realLeft : realRight) : base.left[i]);
      rights.add(isMatch ? (sameDirection ? realRight : realLeft) : base.right[i]);
      matched.add(isMatch ? 1 : 0);
    }
    final half = math.max(1, (_measuredBlendM / _spacing(base.center, closed: base.closed)).round());
    final blend = _movingAverage(_movingAverage(matched, half, at), half, at);
    final center = [for (var i = 0; i < n; i++) Offset.lerp(base.center[i], targets[i], blend[i])!];
    // 투영점이 실측 점 사이를 건너뛰며 생기는 작은 꺾임을 고른다.
    return (
      center: [
        for (var i = 0; i < n; i++)
          () {
            var sum = Offset.zero;
            for (var k = i - _centerTidySamples; k <= i + _centerTidySamples; k++) {
              sum += center[at(k)];
            }
            return sum / (_centerTidySamples * 2 + 1).toDouble();
          }(),
      ],
      left: _movingAverage([for (var i = 0; i < n; i++) _lerp(base.left[i], lefts[i], blend[i])], _centerTidySamples, at),
      right: _movingAverage([for (var i = 0; i < n; i++) _lerp(base.right[i], rights[i], blend[i])], _centerTidySamples, at),
      closed: base.closed,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 중심선 점마다 가장 가까운 표본 형상 칸의 연석(그 칸에서 차들이 그 쪽 연석을 밟은 적이 있으면).
  /// [_kerbGapFillM]보다 짧게 끊긴 틈은 이어 그린다(한 연석이 조각나 보이지 않게).
  static ({List<bool> left, List<bool> right}) _sampleKerbs(
    TrackSampleGeometry samples,
    List<Offset> center, {
    required double spacing,
    required bool closed,
  }) {
    final matcher = _SequentialMatcher(samples.line, closed: true);
    final nearest = [for (final p in center) matcher.match(p)];
    final gap = math.max(1, (_kerbGapFillM / spacing).round());
    return (
      left: _fillShortGaps([for (final j in nearest) samples.kerbLeft[j]], gap, closed: closed),
      right: _fillShortGaps([for (final j in nearest) samples.kerbRight[j]], gap, closed: closed),
    );
  }

  /// 한쪽으로 [kCircuitKerbCurvature]보다 급하게 굽는 코너([_minFeatureRunSamples]칸 이상)에 안쪽 연석 기록이
  /// 코너 길이의 [_insideKerbMinCoverage]에 못 미치면 코너 내내 안쪽(굽는 쪽) 연석을 그린다. 기록이 충분한 코너는 그대로 둔다.
  static ({List<bool> left, List<bool> right}) _withInsideKerbs(
    ({List<bool> left, List<bool> right}) kerbs,
    List<double> curvatures, {
    required bool closed,
  }) {
    final left = List<bool>.of(kerbs.left);
    final right = List<bool>.of(kerbs.right);
    for (final (bends, recorded, result) in [
      (_dropShortRuns([for (final k in curvatures) k >= kCircuitKerbCurvature], closed: closed), kerbs.left, left),
      (_dropShortRuns([for (final k in curvatures) k <= -kCircuitKerbCurvature], closed: closed), kerbs.right, right),
    ]) {
      for (final run in _runs(bends, closed: closed)) {
        if (run.where((i) => recorded[i]).length < run.length * _insideKerbMinCoverage) {
          for (final i in run) {
            result[i] = true;
          }
        }
      }
    }
    return (left: left, right: right);
  }

  /// true가 이어진 구간들(점 번호 순). 닫힌 서킷이면 끝과 처음에 걸친 구간을 한 구간으로 본다.
  static List<List<int>> _runs(List<bool> flags, {required bool closed}) {
    final n = flags.length;
    if (!flags.contains(true)) {
      return const [];
    }
    if (!flags.contains(false)) {
      return [List<int>.generate(n, (i) => i)];
    }
    final start = closed ? flags.indexOf(false) : 0;
    final runs = <List<int>>[];
    var current = <int>[];
    for (var j = 0; j < n; j++) {
      final i = (start + j) % n;
      if (flags[i]) {
        current.add(i);
      } else if (current.isNotEmpty) {
        runs.add(current);
        current = <int>[];
      }
    }
    if (current.isNotEmpty) {
      runs.add(current);
    }
    return runs;
  }

  /// 중심선 점마다 노면 높이를 앞뒤 몇 칸 평균한 값: 표본 형상에 높이가 있으면 가장 가까운 형상 칸, 없으면 가장 가까운 내 랩 표본.
  /// 둘 다 없으면 모두 0.
  static List<double> _elevations(
    LapTrace trace,
    List<Offset> line,
    List<Offset> center,
    int Function(int) at,
    TrackSampleGeometry? samples,
  ) {
    final heights = samples?.y;
    if (samples != null && heights != null) {
      final matcher = _SequentialMatcher(samples.line, closed: true);
      return _movingAverage([for (final p in center) heights[matcher.match(p)]], _elevationSmoothSamples, at);
    }
    if (!trace.hasElevation) {
      return List.filled(center.length, 0);
    }
    final matcher = _SequentialMatcher(line, closed: false);
    final raw = [for (final p in center) trace.worldPosY[matcher.match(p)]];
    return _movingAverage(raw, _elevationSmoothSamples, at);
  }

  /// 주행선이 (연석을 밟은 곳을 빼고) 도로 안에 들도록 중심선을 좌우로 조금씩 옮긴다.
  /// 실측 중심선은 지도 GPS를 평활한 것이라 몇 m 어긋날 수 있어서다. 폭은 그대로.
  static _Geometry _keepLinesInside(_Geometry geometry, List<LapTrace> lines) {
    final center = geometry.center;
    final n = center.length;
    final closed = geometry.closed;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
    final normals = [
      for (var i = 0; i < n; i++)
        () {
          final d = center[at(i + 1)] - center[at(i - 1)];
          final h = math.atan2(d.dy, d.dx);
          return Offset(-math.sin(h), math.cos(h));
        }(),
    ];
    final push = List<double>.filled(n, 0);
    final pull = List<double>.filled(n, 0);
    for (final line in lines.where((l) => l.hasPositions)) {
      final matcher = _SequentialMatcher(center, closed: closed);
      for (var i = 0; i < line.length; i++) {
        final p = Offset(line.worldPosX[i], line.worldPosZ[i]);
        final j = matcher.match(p);
        final lateral = (p.dx - center[j].dx) * normals[j].dx + (p.dy - center[j].dy) * normals[j].dy;
        final onKerb = line.hasKerbContact && line.kerbContact[i];
        final margin = onKerb ? _kerbCarAllowanceM : -_carHalfWidthM;
        final leftLimit = geometry.left[j] + margin;
        final rightLimit = geometry.right[j] + margin;
        if (lateral > leftLimit) {
          push[j] = math.max(push[j], lateral - leftLimit);
        } else if (-lateral > rightLimit) {
          pull[j] = math.min(pull[j], lateral + rightLimit);
        }
      }
    }
    final spread = math.max(1, (_shiftSpreadM / _spacing(center, closed: closed)).round());
    // 가장 크게 벗어난 값을 앞뒤로 넓힌 뒤(팽창) 평균해 부드럽게 옮긴다.
    final raw = [for (var j = 0; j < n; j++) push[j] + pull[j]];
    final dilated = [
      for (var j = 0; j < n; j++)
        () {
          var best = 0.0;
          for (var k = j - spread; k <= j + spread; k++) {
            final v = raw[at(k)];
            if (v.abs() > best.abs()) {
              best = v;
            }
          }
          return best;
        }(),
    ];
    // 두 번 평균해 램프 양 끝이 꺾이지 않고 둥글게 이어지게 한다.
    final shift = _movingAverage(_movingAverage(dilated, spread, at), spread, at);
    return (
      center: [for (var j = 0; j < n; j++) center[j] + normals[j] * shift[j]],
      left: geometry.left,
      right: geometry.right,
      closed: closed,
    );
  }

  /// [points]가 (차 반폭 + 여유까지) 도로 안에 들도록 그 쪽 폭을 넓힌다. 앞뒤로 퍼뜨린 뒤 평균해 폭이 부드럽게 늘고 준다.
  static _Geometry _covering(_Geometry geometry, List<Offset> points) {
    if (points.isEmpty) {
      return geometry;
    }
    final center = geometry.center;
    final n = center.length;
    final closed = geometry.closed;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
    final needLeft = List<double>.filled(n, 0);
    final needRight = List<double>.filled(n, 0);
    for (final p in points) {
      final j = _nearestIndex(center, p);
      final d = center[at(j + 1)] - center[at(j - 1)];
      if (d.distance == 0) {
        continue;
      }
      final normal = Offset(-d.dy, d.dx) / d.distance;
      final lateral = (p.dx - center[j].dx) * normal.dx + (p.dy - center[j].dy) * normal.dy;
      final need = lateral.abs() + _carHalfWidthM + _coverMarginM;
      if (lateral >= 0) {
        needLeft[j] = math.max(needLeft[j], need);
      } else {
        needRight[j] = math.max(needRight[j], need);
      }
    }
    return _widened(geometry, needLeft, needRight);
  }

  /// 주행선(내 랩·비교 랩)이 도로 안에 들도록 그 쪽 폭만 넓힌다(가운데는 그대로 — 표본 형상의 다른 차들이 제자리에 남게).
  /// 연석을 밟은 표본은 차 가운데가 가장자리 밖 [_kerbCarAllowanceM]까지 나가도 되고, 아니면 차 반폭만큼 안쪽에 들어야 한다.
  static _Geometry _coveringLines(_Geometry geometry, List<LapTrace> lines) {
    final center = geometry.center;
    final n = center.length;
    final closed = geometry.closed;
    final normals = _normals(center, closed: closed);
    final needLeft = List<double>.filled(n, 0);
    final needRight = List<double>.filled(n, 0);
    for (final line in lines.where((l) => l.hasPositions)) {
      final matcher = _SequentialMatcher(center, closed: closed);
      for (var i = 0; i < line.length; i++) {
        final p = Offset(line.worldPosX[i], line.worldPosZ[i]);
        final j = matcher.match(p);
        final lateral = (p.dx - center[j].dx) * normals[j].dx + (p.dy - center[j].dy) * normals[j].dy;
        final onKerb = line.hasKerbContact && line.kerbContact[i];
        final need = lateral.abs() + (onKerb ? -_kerbCarAllowanceM : _carHalfWidthM);
        if (lateral >= 0) {
          needLeft[j] = math.max(needLeft[j], need);
        } else {
          needRight[j] = math.max(needRight[j], need);
        }
      }
    }
    return _widened(geometry, needLeft, needRight);
  }

  /// 점마다 그 쪽에 있어야 할 폭([needLeft]·[needRight], m)만큼 폭을 넓힌다. 앞뒤로 퍼뜨린 뒤 평균해 폭이 부드럽게 늘고 준다
  /// (퍼뜨린 범위 안에서 평균하므로 넓힌 폭은 점마다 필요한 폭 이상이다).
  static _Geometry _widened(_Geometry geometry, List<double> needLeft, List<double> needRight) {
    final center = geometry.center;
    final n = center.length;
    final closed = geometry.closed;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
    final spread = math.max(1, (_shiftSpreadM / _spacing(center, closed: closed)).round());
    List<double> widen(List<double> base, List<double> need) {
      final dilated = [
        for (var j = 0; j < n; j++)
          () {
            var best = 0.0;
            for (var k = j - spread; k <= j + spread; k++) {
              best = math.max(best, need[at(k)]);
            }
            return best;
          }(),
      ];
      final smooth = _movingAverage(dilated, spread, at);
      return [for (var j = 0; j < n; j++) math.max(base[j], smooth[j])];
    }

    return (
      center: center,
      left: widen(geometry.left, needLeft),
      right: widen(geometry.right, needRight),
      closed: closed,
    );
  }

  /// 점마다 중심선에서 차 몸체가 닿은 가장 먼 자리(m, 왼쪽·오른쪽): 표본 형상의 모든 차([sampled]의 도달 폭 — 그때 중심선은
  /// 표본 칸 그대로다)와 주행선(내 랩·비교 랩) 차 몸체(진행 방향에 따라 옆으로 반폭~반길이).
  static ({List<double> left, List<double> right}) _reach(
    TrackWidthProfile? sampled,
    List<LapTrace> lines,
    List<Offset> center,
    List<Offset> normals, {
    required bool closed,
  }) {
    final n = center.length;
    final sampledLeft = sampled?.reachLeftM;
    final sampledRight = sampled?.reachRightM;
    final left = [for (var i = 0; i < n; i++) sampledLeft == null ? 0.0 : sampledLeft[i]];
    final right = [for (var i = 0; i < n; i++) sampledRight == null ? 0.0 : sampledRight[i]];
    final halfDiagonal = math.sqrt(_carHalfWidthM * _carHalfWidthM + _carHalfLengthM * _carHalfLengthM);
    for (final line in lines.where((l) => l.hasPositions)) {
      final matcher = _SequentialMatcher(center, closed: closed);
      final m = line.length;
      Offset position(int i) => Offset(line.worldPosX[i.clamp(0, m - 1)], line.worldPosZ[i.clamp(0, m - 1)]);
      for (var i = 0; i < m; i++) {
        final p = position(i);
        final j = matcher.match(p);
        final normal = normals[j];
        final lateral = (p.dx - center[j].dx) * normal.dx + (p.dy - center[j].dy) * normal.dy;
        // 진행 방향이 트랙과 이루는 각만큼 옆으로 더 닿는다(움직이지 않았으면 어느 쪽이든 대각선 반길이).
        final heading = position(i + 1) - position(i - 1);
        final along = (heading.dx * normal.dy - heading.dy * normal.dx).abs();
        final across = (heading.dx * normal.dx + heading.dy * normal.dy).abs();
        final body = heading.distance == 0
            ? halfDiagonal
            : (_carHalfWidthM * along + _carHalfLengthM * across) / heading.distance;
        left[j] = math.max(left[j], lateral + body);
        right[j] = math.max(right[j], -lateral + body);
      }
    }
    return (left: left, right: right);
  }

  /// 점마다 왼쪽 단위 법선(진행 방향에서 +90°). 앞뒤 점이 겹치면 0.
  static List<Offset> _normals(List<Offset> center, {required bool closed}) {
    final n = center.length;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
    return [
      for (var i = 0; i < n; i++)
        () {
          final d = center[at(i + 1)] - center[at(i - 1)];
          return d.distance == 0 ? Offset.zero : Offset(-d.dy, d.dx) / d.distance;
        }(),
    ];
  }

  /// 실측 서킷이 없을 때: 주행선(과 비교 랩 주행선의 평균)을 평활해 중심선을 만들고 곡률로 폭을 정한다.
  static _Geometry _estimated(LapReplay player, LapReplay? ghost, double baseWidthM) {
    final trace = player.trace;
    final n = trace.length;
    final raw = _positions(trace);
    final other = ghost?.trace;
    if (other != null && other.resolutionM == trace.resolutionM) {
      final m = math.min(n, other.length);
      for (var i = 0; i < m; i++) {
        raw[i] = Offset((raw[i].dx + other.worldPosX[i]) / 2, (raw[i].dy + other.worldPosZ[i]) / 2);
      }
    }
    final closed = n > 2 && (raw.first - raw.last).distance < _closedLoopM;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);
    final maxLateral = math.max(0.0, baseWidthM / 2 - _lateralMarginM);

    List<Offset> movingAverage(List<Offset> points, int half) => [
          for (var i = 0; i < n; i++)
            () {
              var sum = Offset.zero;
              for (var j = i - half; j <= i + half; j++) {
                sum += points[at(j)];
              }
              return sum / (half * 2 + 1).toDouble();
            }(),
        ];

    // 주행선 − 크게 평활한 선 = 도로 안에서의 좌우 위치(추정). 급한 코너에서는 평활선이 안쪽으로 크게 당겨지므로
    // 그 차이를 (반폭 − [_lateralMarginM])으로 자른 만큼만 빼서, 차는 늘 도로 안에서 좌우로 움직이게 한다.
    final window = math.max(1, (kCircuitCenterSmoothM / trace.resolutionM).round());
    final smooth = movingAverage(raw, window);
    final shifted = <Offset>[
      for (var i = 0; i < n; i++)
        () {
          final d = raw[i] - smooth[i];
          final length = d.distance;
          final clamped = length > maxLateral ? d * (maxLateral / length) : d;
          return raw[i] - clamped;
        }(),
    ];
    final center = movingAverage(shifted, _centerTidySamples);
    final headings = [
      for (var i = 0; i < n; i++)
        () {
          final d = center[at(i + 1)] - center[at(i - 1)];
          return math.atan2(d.dy, d.dx);
        }(),
    ];
    final curvatures = _movingAverage([
      for (var i = 0; i < n; i++) _angleDiff(headings[at(i + 1)], headings[at(i - 1)]) / (2 * trace.resolutionM),
    ], _curvatureSmoothSamples, at);
    // 폭은 넓게 평균해 가장자리가 들쭉날쭉하지 않고 서서히 넓어졌다 좁아지게 한다.
    final halves = _movingAverage([
      for (final k in curvatures) (baseWidthM + math.min(kCircuitCornerExtraWidthM, k.abs() * _cornerWidthGain)) / 2,
    ], _widthSmoothSamples, at);
    return (center: center, left: halves, right: halves, closed: closed);
  }

  /// 연석이 있는 중심선 구간(왼쪽·오른쪽). 바퀴 노면 기록이 있으면 연석을 밟은 표본의 위치(중심선 왼쪽/오른쪽)에 그리고,
  /// 기록이 하나도 없으면 곡률이 급한 구간 양쪽에 그린다.
  static ({List<bool> left, List<bool> right}) _kerbSides(
    List<LapTrace> lines,
    List<Offset> center,
    List<Offset> normals,
    List<double> curvatures, {
    required double spacing,
    required bool closed,
  }) {
    final n = center.length;
    final recorded = lines.where((l) => l.hasPositions && l.hasKerbContact).toList();
    if (recorded.isEmpty) {
      final flags = _dropShortRuns([for (final k in curvatures) k.abs() >= kCircuitKerbCurvature], closed: closed);
      return (left: flags, right: List.of(flags));
    }
    final left = List<bool>.filled(n, false);
    final right = List<bool>.filled(n, false);
    final spread = math.max(1, (_kerbSpreadM / spacing).round());
    void mark(List<bool> flags, int j) {
      for (var k = j - spread; k < j + spread; k++) {
        if (closed || (k >= 0 && k < n)) {
          flags[(k % n + n) % n] = true;
        }
      }
    }

    for (final line in recorded) {
      final matcher = _SequentialMatcher(center, closed: closed);
      for (var i = 0; i < line.length; i++) {
        final p = Offset(line.worldPosX[i], line.worldPosZ[i]);
        final j = matcher.match(p);
        if (!line.kerbContact[i]) {
          continue;
        }
        final lateral = (p.dx - center[j].dx) * normals[j].dx + (p.dy - center[j].dy) * normals[j].dy;
        mark(lateral >= 0 ? left : right, j);
      }
    }
    final gap = math.max(1, (_kerbGapFillM / spacing).round());
    return (left: _fillShortGaps(left, gap, closed: closed), right: _fillShortGaps(right, gap, closed: closed));
  }

  static List<Offset> _positions(LapTrace trace) => [
        for (var i = 0; i < trace.length; i++) Offset(trace.worldPosX[i], trace.worldPosZ[i]),
      ];

  /// 중심선 점 사이 평균 간격(m).
  static double _spacing(List<Offset> points, {required bool closed}) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    if (closed) {
      total += (points.first - points.last).distance;
    }
    final segments = closed ? points.length : points.length - 1;
    return segments <= 0 || total <= 0 ? 1 : total / segments;
  }

  static List<double> _movingAverage(List<double> values, int half, int Function(int) at) => [
        for (var i = 0; i < values.length; i++)
          () {
            var sum = 0.0;
            for (var j = i - half; j <= i + half; j++) {
              sum += values[at(j)];
            }
            return sum / (half * 2 + 1);
          }(),
      ];

  static int _nearestIndex(List<Offset> points, Offset query) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - query).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  /// [_minFeatureRunSamples]칸보다 짧게 이어진 true 구간을 false로 바꾼다(조각난 연석·그래블 없애기).
  static List<bool> _dropShortRuns(List<bool> flags, {required bool closed}) =>
      _replaceShortRuns(flags, value: true, maxLength: _minFeatureRunSamples - 1, closed: closed);

  /// [maxGap]칸 이하로 끊긴 false 틈을 true로 메운다(한 연석이 조각나 보이지 않게).
  static List<bool> _fillShortGaps(List<bool> flags, int maxGap, {required bool closed}) =>
      _replaceShortRuns(flags, value: false, maxLength: maxGap, closed: closed);

  /// [value]가 [maxLength]칸 이하로 이어진 구간을 반대 값으로 바꾼다. 닫힌 서킷이면 시작·끝에 걸친 구간을 한 구간으로 본다.
  static List<bool> _replaceShortRuns(List<bool> flags, {required bool value, required int maxLength, required bool closed}) {
    final n = flags.length;
    final result = List<bool>.of(flags);
    if (n == 0 || flags.every((f) => f == value)) {
      return result;
    }
    final start = closed ? flags.indexOf(!value) : 0;
    var i = 0;
    while (i < n) {
      if (flags[(start + i) % n] != value) {
        i++;
        continue;
      }
      var length = 0;
      while (i + length < n && flags[(start + i + length) % n] == value) {
        length++;
      }
      // 열린 선의 처음·끝에 붙은 틈은 메우지 않는다(양쪽에 연석이 있을 때만 틈이다).
      final touchesEnd = !closed && !value && (start + i == 0 || start + i + length == n);
      if (length <= maxLength && !touchesEnd) {
        for (var j = 0; j < length; j++) {
          result[(start + i + j) % n] = !value;
        }
      }
      i += length;
    }
    return result;
  }

  static void _quad(Path path, Offset a, Offset b, Offset c, Offset d) {
    path
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
  }

  static Path _polyline(List<Offset> points, {required bool closed}) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (closed) {
      path.close();
    }
    return path;
  }

  /// a − b를 −π ~ π로.
  static double _angleDiff(double a, double b) {
    var d = a - b;
    while (d > math.pi) {
      d -= 2 * math.pi;
    }
    while (d < -math.pi) {
      d += 2 * math.pi;
    }
    return d;
  }
}

/// 중심선·좌우 폭(m)·닫힌 서킷인지.
typedef _Geometry = ({List<Offset> center, List<double> left, List<double> right, bool closed});

/// 주행 표본을 차례로 중심선 점에 짝짓는다. 앞 표본의 짝 둘레만 찾아서 빠르고, 입체 교차(스즈카)에서 다른 길로 튀지 않는다.
class _SequentialMatcher {
  _SequentialMatcher(this.points, {required this.closed});

  final List<Offset> points;
  final bool closed;
  int? _last;

  int match(Offset p) {
    final last = _last;
    final n = points.length;
    var best = -1;
    var bestDistance = double.infinity;
    if (last != null) {
      for (var k = last - _matchWindow; k <= last + _matchWindow; k++) {
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
    }
    if (best < 0 || bestDistance > _rematchM * _rematchM) {
      best = ReplayCircuit._nearestIndex(points, p);
    }
    return _last = best;
  }
}
