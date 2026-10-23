import 'dart:math' as math;
import 'dart:ui';

import '../domain/ghost_replay.dart';

/// 서킷 중심선을 구할 때 앞뒤로 평균하는 거리(m). 레이싱 라인은 코너마다 바깥 → 에이펙스 → 바깥으로 오가므로
/// 이 거리만큼 평균하면 도로 가운데쯤이 되고, 차는 그 도로 안에서 좌우로 움직여 보인다.
const double kCircuitCenterSmoothM = 30;

/// 직선 도로 폭(m). 코너에서는 곡률에 따라 [kCircuitCornerExtraWidthM]까지 넓어진다.
const double kCircuitBaseWidthM = 13;
const double kCircuitCornerExtraWidthM = 3;

/// 곡률(1/m) × 이 값 = 코너에서 넓어지는 폭(m, [kCircuitCornerExtraWidthM]까지).
const double _cornerWidthGain = 150;

/// 이 곡률(1/m, 반지름 약 125m)보다 급한 구간 양쪽 가장자리에 연석을 그린다.
const double kCircuitKerbCurvature = 0.008;

/// 이 곡률(1/m, 반지름 약 80m)보다 급한 코너 바깥쪽에 그래블(자갈) 구역을 그린다.
const double kCircuitGravelCurvature = 0.0125;

/// 연석 폭(m)·그래블 폭(m).
const double kCircuitKerbWidthM = 1.5;
const double kCircuitGravelWidthM = 12;

/// 첫·마지막 표본이 이 거리(m)보다 가까우면 한 바퀴로 이어진 닫힌 서킷으로 본다.
const double _closedLoopM = 40;

/// 도로 중심에서 주행선이 벗어날 수 있는 최대 거리(m). 직선 폭의 절반보다 조금 작게 두어 차가 늘 아스팔트 위에 있다.
const double kCircuitMaxLateralOffsetM = 4.5;

/// 중심선을 다듬는 이동 평균 반폭(표본 수)·곡률을 고르는 이동 평균 반폭(표본 수).
const int _centerTidySamples = 2;
const int _curvatureSmoothSamples = 3;

/// 도로 폭을 고르는 이동 평균 반폭(표본 수)·연석·그래블로 그릴 최소 연속 표본 수.
const int _widthSmoothSamples = 6;
const int _minFeatureRunSamples = 4;

/// 연석 줄무늬 한 칸을 표본 간격의 몇 등분으로 나눌지(빨강·흰색이 번갈아).
const int _kerbStripesPerSegment = 2;

/// 고스트 재생 화면의 서킷 모양(월드 좌표 m). 내 랩(+ 있으면 비교 랩) 주행선을 평균·평활해 중심선을 만들고,
/// 곡률로 도로 폭·연석·그래블을 정한다. 실제 노면 데이터가 없어 주행 기록에서 추정한 모양이다.
class ReplayCircuit {
  ReplayCircuit._({
    required this.center,
    required this.widths,
    required this.curvatures,
    required this.asphalt,
    required this.leftEdge,
    required this.rightEdge,
    required this.kerbRed,
    required this.kerbWhite,
    required this.gravel,
  });

  /// 중심선 점(표본 간격).
  final List<Offset> center;

  /// 표본별 도로 폭(m)·곡률(1/m, 부호 = 도는 방향).
  final List<double> widths;
  final List<double> curvatures;

  /// 칠할 모양들(채움: 아스팔트·연석·그래블, 선: 가장자리).
  final Path asphalt;
  final Path leftEdge;
  final Path rightEdge;
  final Path kerbRed;
  final Path kerbWhite;
  final Path gravel;

  /// [player] 주행선(과 [ghost] 주행선의 평균)으로 서킷 모양을 만든다.
  factory ReplayCircuit.build(LapReplay player, [LapReplay? ghost]) {
    final trace = player.trace;
    final n = trace.length;
    final raw = [for (var i = 0; i < n; i++) Offset(trace.worldPosX[i], trace.worldPosZ[i])];
    final other = ghost?.trace;
    if (other != null && other.resolutionM == trace.resolutionM) {
      final m = math.min(n, other.length);
      for (var i = 0; i < m; i++) {
        raw[i] = Offset((raw[i].dx + other.worldPosX[i]) / 2, (raw[i].dy + other.worldPosZ[i]) / 2);
      }
    }
    final closed = n > 2 && (raw.first - raw.last).distance < _closedLoopM;
    int at(int i) => closed ? (i % n + n) % n : i.clamp(0, n - 1);

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
    // 그 차이를 [kCircuitMaxLateralOffsetM]으로 자른 만큼만 빼서, 차는 늘 도로 안에서 좌우로 움직이게 한다.
    final window = math.max(1, (kCircuitCenterSmoothM / trace.resolutionM).round());
    final smooth = movingAverage(raw, window);
    final shifted = <Offset>[
      for (var i = 0; i < n; i++)
        () {
          final d = raw[i] - smooth[i];
          final length = d.distance;
          final clamped = length > kCircuitMaxLateralOffsetM ? d * (kCircuitMaxLateralOffsetM / length) : d;
          return raw[i] - clamped;
        }(),
    ];
    final center = movingAverage(shifted, _centerTidySamples);

    double headingAt(int i) {
      final d = center[at(i + 1)] - center[at(i - 1)];
      return math.atan2(d.dy, d.dx);
    }

    final headings = [for (var i = 0; i < n; i++) headingAt(i)];
    final rawCurvatures = [
      for (var i = 0; i < n; i++)
        _angleDiff(headings[at(i + 1)], headings[at(i - 1)]) / (2 * trace.resolutionM),
    ];
    // 곡률은 앞뒤 몇 칸 평균으로 튀는 값을 없앤다(연석·그래블이 조각조각 생기지 않게).
    final curvatures = [
      for (var i = 0; i < n; i++)
        () {
          var sum = 0.0;
          for (var j = i - _curvatureSmoothSamples; j <= i + _curvatureSmoothSamples; j++) {
            sum += rawCurvatures[at(j)];
          }
          return sum / (_curvatureSmoothSamples * 2 + 1);
        }(),
    ];
    final rawWidths = [
      for (final k in curvatures)
        kCircuitBaseWidthM + math.min(kCircuitCornerExtraWidthM, k.abs() * _cornerWidthGain),
    ];
    // 폭은 더 넓게 평균해 가장자리가 들쭉날쭉하지 않고 서서히 넓어졌다 좁아지게 한다.
    final widths = [
      for (var i = 0; i < n; i++)
        () {
          var sum = 0.0;
          for (var j = i - _widthSmoothSamples; j <= i + _widthSmoothSamples; j++) {
            sum += rawWidths[at(j)];
          }
          return sum / (_widthSmoothSamples * 2 + 1);
        }(),
    ];
    final kerbAt = _dropShortRuns([for (final k in curvatures) k.abs() >= kCircuitKerbCurvature], closed: closed);
    final gravelAt = _dropShortRuns([for (final k in curvatures) k.abs() >= kCircuitGravelCurvature], closed: closed);

    // 왼쪽 법선(진행 방향에서 +90°).
    Offset normal(int i) => Offset(-math.sin(headings[i]), math.cos(headings[i]));
    final left = [for (var i = 0; i < n; i++) center[i] + normal(i) * (widths[i] / 2)];
    final right = [for (var i = 0; i < n; i++) center[i] - normal(i) * (widths[i] / 2)];

    final asphalt = Path();
    final kerbRed = Path();
    final kerbWhite = Path();
    final gravel = Path();
    final segments = closed ? n : n - 1;
    for (var i = 0; i < segments; i++) {
      final j = at(i + 1);
      _quad(asphalt, left[i], left[j], right[j], right[i]);

      final k = curvatures[i];
      if (kerbAt[i]) {
        for (final (edge, side) in [(left, 1.0), (right, -1.0)]) {
          final outI = normal(i) * (side * kCircuitKerbWidthM);
          final outJ = normal(j) * (side * kCircuitKerbWidthM);
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
      }
      if (gravelAt[i]) {
        // 곡률 중심이 왼쪽(k > 0)이면 바깥은 오른쪽.
        final side = k > 0 ? -1.0 : 1.0;
        final edge = k > 0 ? right : left;
        final innerI = edge[i] + normal(i) * (side * kCircuitKerbWidthM);
        final innerJ = edge[j] + normal(j) * (side * kCircuitKerbWidthM);
        final outerI = innerI + normal(i) * (side * kCircuitGravelWidthM);
        final outerJ = innerJ + normal(j) * (side * kCircuitGravelWidthM);
        _quad(gravel, innerI, innerJ, outerJ, outerI);
      }
    }

    return ReplayCircuit._(
      center: center,
      widths: widths,
      curvatures: curvatures,
      asphalt: asphalt,
      leftEdge: _polyline(left, closed: closed),
      rightEdge: _polyline(right, closed: closed),
      kerbRed: kerbRed,
      kerbWhite: kerbWhite,
      gravel: gravel,
    );
  }

  /// [_minFeatureRunSamples]칸보다 짧게 이어진 true 구간을 false로 바꾼다(조각난 연석·그래블 없애기).
  static List<bool> _dropShortRuns(List<bool> flags, {required bool closed}) {
    final n = flags.length;
    final result = List<bool>.of(flags);
    if (n == 0 || flags.every((f) => f)) {
      return result;
    }
    // 닫힌 서킷이면 false 칸에서 시작해 한 바퀴 돈다(시작·끝에 걸친 구간을 한 구간으로).
    final start = closed ? flags.indexOf(false) : 0;
    var i = 0;
    while (i < n) {
      final at = (start + i) % n;
      if (!flags[at]) {
        i++;
        continue;
      }
      var length = 0;
      while (i + length < n && flags[(start + i + length) % n]) {
        length++;
      }
      if (length < _minFeatureRunSamples) {
        for (var j = 0; j < length; j++) {
          result[(start + i + j) % n] = false;
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
