import 'dart:math' as math;
import 'dart:ui';

/// 그림의 부품 순서(색 목록도 이 순서). Engine Damage는 그림 대신 목록에만 있다(docs/15 §11.3).
enum EnginePart { ice, turboCharger, mguH, mguK, energyStore, controlElectronics, gearbox }

// F1 V6 하이브리드 파워 유닛을 3D 상자·원기둥으로 만들고(단위 = 대략 m), 앞-왼쪽 위에서 비스듬히 본 투영으로 그린다.
// x = 오른쪽, y = 위, z = 뒤(앞이 -z). 배치는 실제 파워 유닛을 따른다: V자 골 위에 MGU-H, 그 축 앞뒤에 터보 컴프레서·터빈,
// 크랭크케이스 왼쪽 앞에 MGU-K, 엔진 앞 아래에 Energy Store, 따로 떨어진 Control Electronics(ECU), 뒤에 기어박스.

/// 보는 방향(도): 세로축으로 돌린 뒤 앞으로 숙인다.
const double _yawDegrees = -38;
const double _pitchDegrees = 33;

/// 원기둥 둘레를 나누는 면 수.
const int _cylinderSegments = 20;

/// 세부 선(터보 허브 고리·점화 플러그)을 면보다 앞에 두려고 바깥으로 띄우는 거리.
const double _detailLift = 0.004;

/// V 뱅크 각(한쪽, 도) — F1 V6는 90°.
const double _bankHalfAngleDegrees = 45;

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

/// 면을 그리는 방식.
enum FaceStyle {
  /// 채움 + 네온 테두리(상자 면·원기둥 뚜껑).
  solid,

  /// 채움만(원기둥 옆면 — 띠마다 선을 그으면 톱니처럼 보여 윤곽은 [outline]으로 따로 그린다).
  fillOnly,

  /// 선만(허브 고리·점화 플러그·원기둥 윤곽).
  outline,
}

/// 3D 면 하나: 꼭짓점들 + 바깥 법선. 원기둥 옆면은 [cylinder] 번호로 묶어 투영 뒤 윤곽을 만든다.
class EngineFace {
  const EngineFace(this.part, this.points, this.normal, {this.style = FaceStyle.solid, this.cylinder});

  final EnginePart part;
  final List<Vec3> points;
  final Vec3 normal;
  final FaceStyle style;
  final int? cylinder;
}

/// 투영된 면: 모델 전체를 감싸는 상자 기준 단위 좌표(0~1) + 깊이(클수록 가깝다).
class ProjectedFace {
  const ProjectedFace(this.part, this.points, this.depth, {this.style = FaceStyle.solid});

  final EnginePart part;
  final List<Offset> points;
  final double depth;
  final FaceStyle style;
}

double _rad(double degrees) => degrees * math.pi / 180;

/// 중심 [c]와 서로 수직인 반축 [u]·[v]·[w]로 만든 상자의 여섯 면.
List<EngineFace> _box(EnginePart part, Vec3 c, Vec3 u, Vec3 v, Vec3 w) {
  Vec3 p(int a, int b, int d) => c + u * a.toDouble() + v * b.toDouble() + w * d.toDouble();
  return [
    EngineFace(part, [p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), p(1, -1, 1)], u),
    EngineFace(part, [p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1)], u * -1),
    EngineFace(part, [p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1)], v),
    EngineFace(part, [p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1)], v * -1),
    EngineFace(part, [p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)], w),
    EngineFace(part, [p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), p(1, -1, -1)], w * -1),
  ];
}

/// 축에 맞춘 상자(중심·반 크기).
List<EngineFace> _aabb(EnginePart part, Vec3 c, double hx, double hy, double hz) =>
    _box(part, c, Vec3(hx, 0, 0), Vec3(0, hy, 0), Vec3(0, 0, hz));

/// 중심 [c], 축 방향 [axis], 반지름 [r], 길이 [length]인 원기둥(옆면 + 양 끝 뚜껑). [hubRatio]가 있으면 양 끝에 허브 고리.
/// [id]는 원기둥마다 다른 번호(투영 뒤 윤곽을 만들 때 옆면을 묶는다).
List<EngineFace> _cylinder(int id, EnginePart part, Vec3 c, Vec3 axis, double r, double length, {double? hubRatio}) {
  final a = axis.unit;
  final helper = a.y.abs() < 0.9 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
  final e1 = a.cross(helper).unit;
  final e2 = a.cross(e1).unit;
  final half = a * (length / 2);
  Vec3 radial(double t) => e1 * math.cos(t) + e2 * math.sin(t);
  List<Vec3> ring(Vec3 center, double radius) => [
        for (var i = 0; i < _cylinderSegments; i++) center + radial(2 * math.pi * i / _cylinderSegments) * radius,
      ];
  final front = ring(c - half, r);
  final back = ring(c + half, r);
  final faces = <EngineFace>[
    for (var i = 0; i < _cylinderSegments; i++)
      EngineFace(
        part,
        [front[i], front[(i + 1) % _cylinderSegments], back[(i + 1) % _cylinderSegments], back[i]],
        radial(2 * math.pi * (i + 0.5) / _cylinderSegments),
        style: FaceStyle.fillOnly,
        cylinder: id,
      ),
    EngineFace(part, front, a * -1, cylinder: id),
    EngineFace(part, back, a, cylinder: id),
  ];
  if (hubRatio != null) {
    faces
      ..add(EngineFace(part, ring(c - half - a * _detailLift, r * hubRatio), a * -1, style: FaceStyle.outline))
      ..add(EngineFace(part, ring(c + half + a * _detailLift, r * hubRatio), a, style: FaceStyle.outline));
  }
  return faces;
}

/// 두 점 [from]→[to]를 잇는 원기둥(배기관 토막).
List<EngineFace> _pipe(int id, EnginePart part, Vec3 from, Vec3 to, double r) =>
    _cylinder(id, part, (from + to) * 0.5, to - from, r, (to - from).length);

/// 배기관 굵기와 꺾이는 점들(뱅크 바깥 아래를 따라 뒤로 → 뒤 터빈으로 올라간다). x는 오른쪽 기준, 왼쪽은 부호를 뒤집는다.
const double _exhaustRadius = 0.028;
const Vec3 _exhaustFront = Vec3(0.4, 0.34, -0.22);
const Vec3 _exhaustRear = Vec3(0.4, 0.34, 0.24);
const Vec3 _exhaustTurbine = Vec3(0.09, 0.62, 0.3);

/// 한쪽 배기관 두 토막(터빈으로 가는 배기 — 터보 색). [side]는 왼쪽 -1, 오른쪽 1, [firstId]부터 번호 둘을 쓴다.
List<EngineFace> _exhaust(int side, int firstId) {
  Vec3 sided(Vec3 p) => Vec3(p.x * side, p.y, p.z);
  return [
    ..._pipe(firstId, EnginePart.turboCharger, sided(_exhaustFront), sided(_exhaustRear), _exhaustRadius),
    ..._pipe(firstId + 1, EnginePart.turboCharger, sided(_exhaustRear), sided(_exhaustTurbine), _exhaustRadius),
  ];
}

/// 한쪽 실린더 뱅크(블록 + 캠 커버 + 점화 플러그 3개). [side]는 왼쪽 -1, 오른쪽 1.
List<EngineFace> _bank(int side) {
  final angle = _rad(_bankHalfAngleDegrees);
  final up = Vec3(side * math.sin(angle), math.cos(angle), 0);
  final across = Vec3(math.cos(angle), -side * math.sin(angle), 0);
  const depth = Vec3(0, 0, 1);
  const base = Vec3(0, 0.3, 0.02);
  final block = base + up * 0.2;
  final cover = base + up * 0.36;
  final faces = [
    ..._box(EnginePart.ice, block, up * 0.12, across * 0.13, depth * 0.3),
    ..._box(EnginePart.ice, cover, up * 0.04, across * 0.1, depth * 0.27),
  ];
  for (final z in const [-0.17, 0.0, 0.17]) {
    final top = cover + up * (0.04 + _detailLift) + depth * z;
    faces.add(EngineFace(
      EnginePart.ice,
      [
        for (var i = 0; i < _cylinderSegments; i++)
          top +
              across * (0.035 * math.cos(2 * math.pi * i / _cylinderSegments)) +
              depth * (0.035 * math.sin(2 * math.pi * i / _cylinderSegments)),
      ],
      up,
      style: FaceStyle.outline,
    ));
  }
  return faces;
}

/// 파워 유닛 3D 면 전부(그리는 순서는 투영 뒤 깊이로 정한다).
List<EngineFace> engineFaces() => [
      // ICE: 크랭크케이스 + 좌우 뱅크 + V 골의 흡기 플레넘.
      ..._aabb(EnginePart.ice, const Vec3(0, 0.15, 0.02), 0.25, 0.15, 0.32),
      ..._bank(-1),
      ..._bank(1),
      ..._aabb(EnginePart.ice, const Vec3(0, 0.5, 0.02), 0.09, 0.07, 0.24),
      // 배기관: 양쪽 뱅크 바깥에서 뒤 터빈으로.
      ..._exhaust(-1, 4),
      ..._exhaust(1, 6),
      // MGU-H: V 골 위 앞뒤로 누운 원기둥, 그 앞(컴프레서)·뒤(터빈) 터보 달팽이.
      ..._cylinder(0, EnginePart.mguH, const Vec3(0, 0.66, 0.03), const Vec3(0, 0, 1), 0.065, 0.3),
      ..._cylinder(1, EnginePart.turboCharger, const Vec3(0, 0.66, -0.25), const Vec3(0, 0, 1), 0.13, 0.11, hubRatio: 0.38),
      ..._cylinder(2, EnginePart.turboCharger, const Vec3(0, 0.66, 0.31), const Vec3(0, 0, 1), 0.12, 0.1, hubRatio: 0.38),
      // MGU-K: 크랭크케이스 왼쪽 앞 아래.
      ..._cylinder(3, EnginePart.mguK, const Vec3(-0.34, 0.13, -0.2), const Vec3(0, 0, 1), 0.075, 0.24, hubRatio: 0.45),
      // Energy Store: 엔진 앞 아래 납작한 팩.
      ..._aabb(EnginePart.energyStore, const Vec3(0, 0.06, -0.58), 0.22, 0.06, 0.13),
      // Control Electronics(ECU): 왼쪽에 떨어진 상자 + 위 칩.
      ..._aabb(EnginePart.controlElectronics, const Vec3(-0.82, 0.04, -0.35), 0.14, 0.035, 0.11),
      ..._aabb(EnginePart.controlElectronics, const Vec3(-0.82, 0.095, -0.35), 0.06, 0.02, 0.05),
      // 기어박스: 뒤쪽으로 길게, 끝으로 갈수록 좁아지는 두 토막.
      ..._aabb(EnginePart.gearbox, const Vec3(0, 0.16, 0.5), 0.16, 0.13, 0.16),
      ..._aabb(EnginePart.gearbox, const Vec3(0, 0.15, 0.78), 0.11, 0.1, 0.13),
    ];

/// 보는 방향으로 돌린 좌표(z가 클수록 보는 사람 쪽).
Vec3 _view(Vec3 p) {
  final yaw = _rad(_yawDegrees);
  final pitch = _rad(_pitchDegrees);
  final x1 = p.x * math.cos(yaw) + p.z * math.sin(yaw);
  final z1 = -p.x * math.sin(yaw) + p.z * math.cos(yaw);
  final y2 = p.y * math.cos(pitch) + z1 * math.sin(pitch);
  final z2 = -p.y * math.sin(pitch) + z1 * math.cos(pitch);
  return Vec3(x1, y2, -z2);
}

/// 투영 결과: 보이는 쪽을 향한 면만 먼 것부터(뒤 → 앞) + 모델의 가로/세로 비율.
class EngineProjection {
  const EngineProjection(this.faces, this.aspect);

  final List<ProjectedFace> faces;
  final double aspect;
}

/// 파워 유닛을 정해진 시점으로 투영한다(순수 함수 — 같은 결과라 그림은 한 번만 계산해 둔다).
EngineProjection projectEngine() {
  final viewed = [
    for (final f in engineFaces()) (face: f, points: [for (final p in f.points) _view(p)], normal: _view(f.normal)),
  ];
  var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
  for (final v in viewed) {
    for (final p in v.points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
  }
  final w = maxX - minX;
  final h = maxY - minY;
  Offset unit(Vec3 p) => Offset((p.x - minX) / w, (maxY - p.y) / h);
  double depth(List<Vec3> pts) => pts.fold(0.0, (s, p) => s + p.z) / pts.length;
  final faces = [
    for (final v in viewed)
      if (v.normal.z > 0) ProjectedFace(v.face.part, [for (final p in v.points) unit(p)], depth(v.points), style: v.face.style),
  ];
  // 원기둥마다 투영된 모든 점의 볼록 껍질 = 화면에서의 윤곽. 원기둥에서 가장 가까운 점보다 살짝 앞에 둬 옆면 채움 위에 그린다.
  final byCylinder = <int, List<({EngineFace face, List<Vec3> points})>>{};
  for (final v in viewed) {
    final id = v.face.cylinder;
    if (id != null) {
      (byCylinder[id] ??= []).add((face: v.face, points: v.points));
    }
  }
  for (final group in byCylinder.values) {
    final points = [for (final g in group) ...g.points];
    final nearest = points.fold(-double.infinity, (m, p) => math.max(m, p.z));
    faces.add(ProjectedFace(
      group.first.face.part,
      convexHull([for (final p in points) unit(p)]),
      nearest + _detailLift,
      style: FaceStyle.outline,
    ));
  }
  faces.sort((a, b) => a.depth.compareTo(b.depth));
  return EngineProjection(faces, w / h);
}

/// 점들의 볼록 껍질(반시계, 단조 사슬). 점이 셋 미만이면 그대로.
List<Offset> convexHull(List<Offset> points) {
  if (points.length < 3) {
    return points;
  }
  final sorted = [...points]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double turn(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[];
  for (final p in sorted) {
    while (lower.length >= 2 && turn(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 && turn(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}
