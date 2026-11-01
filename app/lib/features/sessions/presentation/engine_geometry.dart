import 'dart:math' as math;
import 'dart:ui';

/// 그림의 부품 순서(색 목록도 이 순서). Engine Damage는 그림 대신 목록에만 있다(docs/15 §11.3).
enum EnginePart { ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox }

// F1 V6 하이브리드 파워 유닛을 앞-왼쪽 위에서 비스듬히 본 선화. 부품마다 3D 기준점(단위 ≈ m, x 오른쪽 · y 위 · z 뒤)을
// 투영한 뒤 둥근 상자·원통·나선 볼류트·굵은 관 같은 곡선 모양으로 그린다. 그리는 순서(뒤 → 앞)는 이 시점에 맞춰 직접 정한다.
// 배치는 실제 파워 유닛: V자 골 위 MGU-H, 그 축 앞 컴프레서·뒤 터빈, 양쪽 뱅크 바깥에서 터빈으로 가는 배기관,
// 크랭크케이스 왼쪽 앞 MGU-K, 앞 아래 Energy Store, 따로 떨어진 Control Electronics(ECU), 뒤 기어박스.

/// 보는 방향(도): 세로축으로 돌린 뒤 앞으로 숙인다.
const double _yawDegrees = -40;
const double _pitchDegrees = 30;

/// 둥근 모서리·원·나선을 나누는 점 수.
const int _arcSteps = 8;
const int _circleSteps = 36;
const int _spiralSteps = 48;

/// V 뱅크 각(한쪽, 도) — F1 V6는 90°.
const double _bankHalfAngleDegrees = 45;

/// 볼류트 나선이 한 바퀴에 커지는 비율·출구 길이(반지름 배수)·흡입구 원 크기(반지름 배수).
const double _voluteGrowth = 0.45;
const double _voluteOutlet = 0.9;
const double _voluteEye = 0.55;
const double _voluteHub = 0.22;
const double _voluteEyeLift = 0.01;

/// 3D 벡터.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get unit => this * (1 / length);
}

/// 그리는 방식.
enum StrokeKind {
  /// 표면 색으로 채우고 네온 테두리(부품 몸통 윤곽).
  body,

  /// 네온 선만(캠 커버 윤곽·허브·띠·나선 등 세부).
  line,

  /// 굵은 관: 네온 테두리 두 줄 사이를 표면 색으로(배기관·흡기관). [EngineStroke.tubeWidth]가 굵기.
  tube,
}

/// 그림 한 획: 단위 좌표(0~1, 그림 상자 기준) 점들. [closed]면 닫힌 모양.
class EngineStroke {
  const EngineStroke(this.part, this.kind, this.points, {this.closed = true, this.tubeWidth = 0});

  final EnginePart part;
  final StrokeKind kind;
  final List<Offset> points;
  final bool closed;

  /// [StrokeKind.tube]의 굵기(그림 폭에 대한 비율).
  final double tubeWidth;
}

/// 투영 결과: 뒤 → 앞 순서의 획들 + 그림의 가로/세로 비율.
class EngineDrawing {
  const EngineDrawing(this.strokes, this.aspect);

  final List<EngineStroke> strokes;
  final double aspect;
}

double _rad(double degrees) => degrees * math.pi / 180;

/// 보는 방향으로 돌려 화면 평면으로 투영(y는 위가 +).
Offset _project(Vec3 p) {
  final yaw = _rad(_yawDegrees);
  final pitch = _rad(_pitchDegrees);
  final x1 = p.x * math.cos(yaw) + p.z * math.sin(yaw);
  final z1 = -p.x * math.sin(yaw) + p.z * math.cos(yaw);
  final y2 = p.y * math.cos(pitch) + z1 * math.sin(pitch);
  return Offset(x1, y2);
}

(Vec3, Vec3) _basis(Vec3 axis) {
  final a = axis.unit;
  final helper = a.y.abs() < 0.9 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
  final e1 = a.cross(helper).unit;
  return (e1, a.cross(e1).unit);
}

/// [center]에서 [u]·[v] 평면 위 반 크기 [hu]×[hv], 모서리 반경 [r]인 둥근 직사각형 둘레 점.
List<Vec3> _roundedRect(Vec3 center, Vec3 u, Vec3 v, double hu, double hv, double r) {
  final points = <Vec3>[];
  final corners = [(hu - r, hv - r, 0.0), (-(hu - r), hv - r, 90.0), (-(hu - r), -(hv - r), 180.0), (hu - r, -(hv - r), 270.0)];
  for (final (cu, cv, start) in corners) {
    for (var i = 0; i <= _arcSteps; i++) {
      final t = _rad(start + 90.0 * i / _arcSteps);
      points.add(center + u * (cu + r * math.cos(t)) + v * (cv + r * math.sin(t)));
    }
  }
  return points;
}

/// 수평 둥근 직사각형(윗면).
List<Vec3> _flatRect(Vec3 center, double hx, double hz, double r) =>
    _roundedRect(center, const Vec3(1, 0, 0), const Vec3(0, 0, 1), hx, hz, r);

/// [center]에서 [axis]에 수직인 원(반지름 [r]) 둘레 점.
List<Vec3> _circle(Vec3 center, Vec3 axis, double r) {
  final (e1, e2) = _basis(axis);
  return [
    for (var i = 0; i < _circleSteps; i++)
      center + e1 * (r * math.cos(2 * math.pi * i / _circleSteps)) + e2 * (r * math.sin(2 * math.pi * i / _circleSteps)),
  ];
}

/// 터보 볼류트(달팽이 하우징) 나선: 반지름이 한 바퀴에 걸쳐 커지고 끝에서 접선으로 출구가 뻗는다.
List<Vec3> _spiral(Vec3 center, Vec3 axis, double r0) {
  final (e1, e2) = _basis(axis);
  final points = <Vec3>[
    for (var i = 0; i <= _spiralSteps; i++)
      center +
          e1 * (r0 * (1 + _voluteGrowth * i / _spiralSteps) * math.cos(2 * math.pi * i / _spiralSteps)) +
          e2 * (r0 * (1 + _voluteGrowth * i / _spiralSteps) * math.sin(2 * math.pi * i / _spiralSteps)),
  ];
  final end = points.last;
  points
    ..add(end + e2 * (r0 * _voluteOutlet))
    ..add(center + e1 * r0 + e2 * (r0 * _voluteOutlet))
    ..add(center + e1 * r0);
  return points;
}

/// 투영 전 획.
class _Stroke3 {
  _Stroke3(this.part, this.kind, this.points, {this.closed = true, this.tubeWidth = 0, this.hull = false});

  final EnginePart part;
  final StrokeKind kind;
  final List<Vec3> points;
  final bool closed;
  final double tubeWidth;

  /// 투영 뒤 볼록 껍질로 바꾼다(입체의 화면 윤곽).
  final bool hull;
}

/// 윗면 둘레 [top]을 [down]만큼 내린 입체: 화면 윤곽(껍질) + 윗면 선.
List<_Stroke3> _prism(EnginePart part, List<Vec3> top, Vec3 down) => [
      _Stroke3(part, StrokeKind.body, [...top, for (final p in top) p + down], hull: true),
      _Stroke3(part, StrokeKind.line, top),
    ];

/// 원통: 화면 윤곽 + 가까운 끝 원 + (선택) 허브 원·띠.
List<_Stroke3> _cylinder(EnginePart part, Vec3 center, Vec3 axis, double r, double length,
    {double? hub, List<double> bands = const []}) {
  final a = axis.unit;
  final near = center - a * (length / 2);
  final far = center + a * (length / 2);
  return [
    _Stroke3(part, StrokeKind.body, [..._circle(near, a, r), ..._circle(far, a, r)], hull: true),
    _Stroke3(part, StrokeKind.line, _circle(near, a, r)),
    if (hub != null) _Stroke3(part, StrokeKind.line, _circle(near, a, r * hub)),
    for (final b in bands) _Stroke3(part, StrokeKind.line, _circle(near + a * (length * b), a, r)),
  ];
}

/// 볼류트 하우징: 두께 [width]의 나선 입체 + 앞 나선 선 + 가운데 흡입구 원 두 개. [axis]는 보는 쪽을 향한다.
List<_Stroke3> _volute(EnginePart part, Vec3 center, Vec3 axis, double r0, double width) {
  final a = axis.unit;
  final front = _spiral(center - a * (width / 2), a, r0);
  final back = _spiral(center + a * (width / 2), a, r0);
  final eye = center - a * (width / 2 + _voluteEyeLift);
  return [
    _Stroke3(part, StrokeKind.body, [...front, ...back], hull: true),
    _Stroke3(part, StrokeKind.line, front),
    _Stroke3(part, StrokeKind.line, _circle(eye, a, r0 * _voluteEye)),
    _Stroke3(part, StrokeKind.line, _circle(eye, a, r0 * _voluteHub)),
  ];
}

/// 3D 꺾은선을 따라가는 굵은 관.
_Stroke3 _tube(EnginePart part, List<Vec3> path, double width) =>
    _Stroke3(part, StrokeKind.tube, path, closed: false, tubeWidth: width);

/// 한쪽 실린더 뱅크: 블록(둥근 상자) + 캠 커버 윤곽 + 점화 플러그 3개. [side]는 왼쪽 -1, 오른쪽 1.
List<_Stroke3> _bank(int side) {
  final angle = _rad(_bankHalfAngleDegrees);
  final up = Vec3(side * math.sin(angle), math.cos(angle), 0);
  final across = Vec3(math.cos(angle), -side * math.sin(angle), 0);
  const along = Vec3(0, 0, 1);
  const base = Vec3(0, 0.28, 0.0);
  final top = base + up * 0.34;
  return [
    ..._prism(EnginePart.ice, _roundedRect(top, across, along, 0.11, 0.31, 0.06), up * -0.26),
    _Stroke3(EnginePart.ice, StrokeKind.line, _roundedRect(top + up * 0.005, across, along, 0.075, 0.27, 0.05)),
    for (final z in const [-0.17, 0.0, 0.17])
      _Stroke3(EnginePart.ice, StrokeKind.line, _circle(top + up * 0.006 + along * z, up, 0.028)),
  ];
}

/// 배기관 굵기와 꺾이는 점들(뱅크 바깥 아래를 따라 뒤로 → 뒤 터빈으로 올라간다). x는 오른쪽 기준.
const double _exhaustWidth = 0.05;
const double _intakeWidth = 0.05;
const List<Vec3> _exhaustRight = [Vec3(0.37, 0.34, -0.26), Vec3(0.4, 0.36, 0.16), Vec3(0.2, 0.62, 0.3), Vec3(0.06, 0.7, 0.32)];

List<Vec3> _sided(List<Vec3> points, int side) => [for (final p in points) Vec3(p.x * side, p.y, p.z)];

/// 뒤 → 앞 순서의 획(투영 전).
List<_Stroke3> _strokes() => [
      // 기어박스(뒤, 가장 멀다): 둥근 상자 두 토막.
      ..._prism(EnginePart.gearbox, _flatRect(const Vec3(0, 0.3, 0.68), 0.1, 0.16, 0.04), const Vec3(0, -0.2, 0)),
      ..._prism(EnginePart.gearbox, _flatRect(const Vec3(0, 0.32, 0.44), 0.15, 0.12, 0.04), const Vec3(0, -0.26, 0)),
      // 터빈 볼류트(뒤)와 오른쪽(먼 쪽) 배기관.
      ..._volute(EnginePart.turboCharger, const Vec3(0, 0.74, 0.34), const Vec3(0, 0, -1), 0.085, 0.09),
      _tube(EnginePart.turboCharger, _sided(_exhaustRight, 1), _exhaustWidth),
      // 크랭크케이스.
      ..._prism(EnginePart.ice, _flatRect(const Vec3(0, 0.3, 0.0), 0.25, 0.33, 0.06), const Vec3(0, -0.28, 0)),
      // 오른쪽 뱅크 → V 골의 플레넘 → MGU-H → 왼쪽(가까운) 뱅크.
      ..._bank(1),
      ..._prism(EnginePart.ice, _flatRect(const Vec3(0, 0.6, 0.0), 0.085, 0.25, 0.05), const Vec3(0, -0.14, 0)),
      ..._cylinder(EnginePart.mguH, const Vec3(0, 0.74, 0.04), const Vec3(0, 0, 1), 0.058, 0.3, hub: 0.5, bands: [0.33, 0.66]),
      // 왼쪽(가까운) 배기관은 뱅크 바깥을 지나 뒤로 올라가므로 뱅크보다 먼저 그려 겹치는 부분을 뱅크가 가린다.
      _tube(EnginePart.turboCharger, _sided(_exhaustRight, -1), _exhaustWidth),
      ..._bank(-1),
      // 컴프레서(앞) + 플레넘으로 가는 흡기관.
      _tube(EnginePart.turboCharger, const [Vec3(0.11, 0.74, -0.26), Vec3(0.12, 0.7, -0.12), Vec3(0.06, 0.66, -0.06)], _intakeWidth),
      ..._volute(EnginePart.turboCharger, const Vec3(0, 0.74, -0.27), const Vec3(0, 0, -1), 0.085, 0.08),
      // MGU-K(왼쪽 앞 아래, 기어 허브).
      ..._cylinder(EnginePart.mguK, const Vec3(-0.34, 0.12, -0.2), const Vec3(0, 0, 1), 0.07, 0.22, hub: 0.45, bands: [0.5]),
      // Energy Store(앞 아래 팩, 셀 줄).
      ..._prism(EnginePart.energyStore, _flatRect(const Vec3(0, 0.1, -0.6), 0.22, 0.12, 0.03), const Vec3(0, -0.09, 0)),
      for (final x in const [-0.11, 0.0, 0.11])
        _Stroke3(EnginePart.energyStore, StrokeKind.line, [Vec3(x, 0.1, -0.7), Vec3(x, 0.1, -0.5)], closed: false),
      // Control Electronics(ECU): 왼쪽에 떨어진 납작한 상자 + 위 칩.
      ..._prism(EnginePart.controlElectronics, _flatRect(const Vec3(-0.86, 0.08, -0.42), 0.14, 0.11, 0.02), const Vec3(0, -0.07, 0)),
      ..._prism(EnginePart.controlElectronics, _flatRect(const Vec3(-0.86, 0.12, -0.42), 0.06, 0.05, 0.01), const Vec3(0, -0.04, 0)),
    ];

/// 파워 유닛 선화(순수 함수 — 시점이 고정이라 그림은 한 번만 계산해 둔다).
EngineDrawing drawEngine() {
  final raw = [for (final s in _strokes()) (stroke: s, points: [for (final p in s.points) _project(p)])];
  var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
  for (final r in raw) {
    final pad = r.stroke.tubeWidth / 2;
    for (final p in r.points) {
      minX = math.min(minX, p.dx - pad);
      maxX = math.max(maxX, p.dx + pad);
      minY = math.min(minY, p.dy - pad);
      maxY = math.max(maxY, p.dy + pad);
    }
  }
  final w = maxX - minX;
  final h = maxY - minY;
  Offset unit(Offset p) => Offset((p.dx - minX) / w, (maxY - p.dy) / h);
  return EngineDrawing(
    [
      for (final r in raw)
        EngineStroke(
          r.stroke.part,
          r.stroke.kind,
          r.stroke.hull ? convexHull([for (final p in r.points) unit(p)]) : [for (final p in r.points) unit(p)],
          closed: r.stroke.closed,
          tubeWidth: r.stroke.tubeWidth / w,
        ),
    ],
    w / h,
  );
}

/// 점들의 볼록 껍질(단조 사슬). 점이 셋 미만이면 그대로.
List<Offset> convexHull(List<Offset> points) {
  if (points.length < 3) {
    return points;
  }
  final sorted = [...points]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double turn(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  List<Offset> chain(Iterable<Offset> ordered) {
    final out = <Offset>[];
    for (final p in ordered) {
      while (out.length >= 2 && turn(out[out.length - 2], out.last, p) <= 0) {
        out.removeLast();
      }
      out.add(p);
    }
    return out..removeLast();
  }

  return [...chain(sorted), ...chain(sorted.reversed)];
}
