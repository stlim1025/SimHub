// 다시보기 3D 차 모델(코드로 만든 F1 스타일, 로고·번호·스폰서 없음). 모양은 한 번 만들어 모든 차가 함께 쓰고, 재질만 차마다 따로 둔다.
// 차 기준 좌표: +X = 앞, +Y = 위, +Z = 오른쪽(m). 기준점은 노면 위 차 가운데. 치수는 캔버스 그림(ghost_replay_3d_painter.dart)과 같다.
import * as THREE from '../vendor/three/three.module.js';

const FRONT_AXLE_M = 1.65;
const REAR_AXLE_M = -1.95;
const FRONT_TYRE = { radius: 0.36, width: 0.3, center: 0.82 };
const REAR_TYRE = { radius: 0.37, width: 0.4, center: 0.77 };
const RIM_RADIUS_M = 0.25;
const BAND_INNER_M = 0.27;
const BAND_OUTER_M = 0.3;
const SHOULDER_M = 0.045;
const DECAL_OFFSET_M = 0.004;
const WHEEL_SEGMENTS = 40;
/** 스티어 ±1(가득 꺾음)일 때 앞바퀴 각도(rad, 약 22°). */
const MAX_STEER_RAD = 0.38;

const RING_SAMPLES = 24;
const LOFT_STEPS = 5;
const HALO_RADIUS_M = 0.034;
const ARM_RADIUS_M = 0.016;
const SHADOW_LIFT_M = 0.075;
const SHADOW_OPACITY = 0.55;
/** 카본 무늬 한 칸 크기(m). */
const CARBON_TILE_M = 0.06;

/** 몸체 단면(앞 → 뒤): 앞뒤 위치와 오른쪽 절반 윤곽 [옆, 위](아래 바깥 → 옆 아래 → 옆 위 → 위). 왼쪽은 거울로 잇는다. */
const BODY_SECTIONS = [
  [2.62, [[0.05, 0.17], [0.08, 0.2], [0.08, 0.25], [0.04, 0.28]]],
  [2.1, [[0.09, 0.16], [0.13, 0.2], [0.13, 0.33], [0.07, 0.38]]],
  [1.5, [[0.13, 0.15], [0.19, 0.21], [0.19, 0.44], [0.11, 0.52]]],
  [0.9, [[0.19, 0.11], [0.29, 0.17], [0.29, 0.53], [0.17, 0.6]]],
  [0.45, [[0.28, 0.07], [0.42, 0.13], [0.42, 0.56], [0.2, 0.64]]],
  [0.15, [[0.5, 0.07], [0.78, 0.22], [0.76, 0.5], [0.28, 0.63]]],
  [-0.5, [[0.46, 0.07], [0.72, 0.18], [0.66, 0.46], [0.15, 0.8]]],
  [-1.2, [[0.32, 0.07], [0.47, 0.14], [0.41, 0.38], [0.1, 0.72]]],
  [-1.9, [[0.18, 0.09], [0.25, 0.14], [0.23, 0.32], [0.07, 0.55]]],
  [-2.45, [[0.09, 0.13], [0.12, 0.17], [0.11, 0.3], [0.04, 0.4]]],
];

/** 에어박스(롤 후프 위로 솟은 흡기구 덮개) 단면. */
const AIRBOX_SECTIONS = [
  [-0.06, [[0.09, 0.62], [0.11, 0.7], [0.11, 0.86], [0.05, 0.92]]],
  [-0.3, [[0.1, 0.62], [0.12, 0.72], [0.12, 0.9], [0.06, 0.97]]],
  [-0.75, [[0.08, 0.62], [0.1, 0.7], [0.09, 0.84], [0.04, 0.9]]],
  [-1.3, [[0.05, 0.6], [0.06, 0.66], [0.05, 0.72], [0.02, 0.76]]],
];

/** 날개판(익형 단면을 옆으로 밀어 낸 것): 앞전 [앞, 위], 시위, 받음각(뒷전이 올라가는 쪽 +, rad), 두께 비, 옆 범위. */
const WING_ELEMENTS = [
  // 앞날개: 주 날개 + 플랩 두 장(노즈 양옆).
  { le: [2.9, 0.06], chord: 0.48, aoa: 0.1, thick: 0.09, span: [-0.97, 0.97] },
  { le: [2.5, 0.11], chord: 0.3, aoa: 0.42, thick: 0.1, span: [0.2, 0.96] },
  { le: [2.5, 0.11], chord: 0.3, aoa: 0.42, thick: 0.1, span: [-0.96, -0.2] },
  { le: [2.3, 0.19], chord: 0.22, aoa: 0.72, thick: 0.1, span: [0.28, 0.96] },
  { le: [2.3, 0.19], chord: 0.22, aoa: 0.72, thick: 0.1, span: [-0.96, -0.28] },
  // 뒷날개: 주 날개 + DRS 플랩, 아래 빔 윙.
  { le: [-2.48, 0.8], chord: 0.42, aoa: 0.16, thick: 0.1, span: [-0.73, 0.73] },
  { le: [-2.6, 0.9], chord: 0.3, aoa: 0.62, thick: 0.1, span: [-0.73, 0.73] },
  { le: [-2.55, 0.4], chord: 0.3, aoa: 0.2, thick: 0.1, span: [-0.5, 0.5] },
];

const WING_PROFILE_POINTS = 14;

/** sRGB(0~1) 색. */
function srgb(material, r, g, b) {
  material.color.setRGB(r, g, b, THREE.SRGBColorSpace);
}

/** 단면들을 이어 매끈한 몸통을 만든다(단면 둘레와 앞뒤 모두 곡선으로 보간, 앞뒤 끝은 막는다). */
function loft(sections) {
  const rings = sections.map(([x, half]) => {
    const control = [
      ...half.map(([side, up]) => new THREE.Vector3(x, up, side)),
      ...[...half].reverse().map(([side, up]) => new THREE.Vector3(x, up, -side)),
    ];
    return new THREE.CatmullRomCurve3(control, true, 'centripetal').getPoints(RING_SAMPLES).slice(0, RING_SAMPLES);
  });
  const rows = (sections.length - 1) * LOFT_STEPS + 1;
  const grid = [];
  for (let j = 0; j < RING_SAMPLES; j++) {
    grid.push(new THREE.CatmullRomCurve3(rings.map((ring) => ring[j]), false, 'centripetal').getPoints(rows - 1));
  }
  const positions = [];
  for (let i = 0; i < rows; i++) {
    for (let j = 0; j < RING_SAMPLES; j++) positions.push(grid[j][i].x, grid[j][i].y, grid[j][i].z);
  }
  const index = [];
  const at = (i, j) => i * RING_SAMPLES + (j % RING_SAMPLES);
  for (let i = 0; i < rows - 1; i++) {
    for (let j = 0; j < RING_SAMPLES; j++) {
      const a = at(i, j);
      const b = at(i + 1, j);
      const c = at(i, j + 1);
      const d = at(i + 1, j + 1);
      index.push(a, c, b, c, d, b);
    }
  }
  const side = new THREE.BufferGeometry();
  side.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  side.setIndex(index);
  side.computeVertexNormals();

  // 앞뒤 마개는 꼭짓점을 따로 둬 평평하게 칠한다.
  const caps = [];
  for (const [row, front] of [[0, true], [rows - 1, false]]) {
    const ring = [];
    for (let j = 0; j < RING_SAMPLES; j++) ring.push(grid[j][row]);
    const center = ring.reduce((s, p) => s.add(p), new THREE.Vector3()).multiplyScalar(1 / ring.length);
    const cap = [];
    for (let j = 0; j < RING_SAMPLES; j++) {
      const p = ring[j];
      const q = ring[(j + 1) % RING_SAMPLES];
      const tri = front ? [center, q, p] : [center, p, q];
      for (const v of tri) cap.push(v.x, v.y, v.z);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(cap, 3));
    g.computeVertexNormals();
    caps.push(g);
  }
  return [side, ...caps];
}

/** 익형 단면(아래로 볼록한 역날개)을 [span] 범위로 밀어 낸 날개판. */
function wing({ le, chord, aoa, thick, span }) {
  const shape = new THREE.Shape();
  const upper = [];
  const lower = [];
  for (let k = 0; k <= WING_PROFILE_POINTS; k++) {
    const u = (1 - Math.cos((Math.PI * k) / WING_PROFILE_POINTS)) / 2;
    // NACA 4자리 두께 분포 + 아래로 휜 캠버(뒤집힌 날개라 다운포스).
    const t = 5 * thick * (0.2969 * Math.sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u ** 3 - 0.1036 * u ** 4);
    const camber = -0.06 * 4 * u * (1 - u);
    upper.push([u, camber + t]);
    lower.push([u, camber - t]);
  }
  const outline = [...upper, ...lower.reverse().slice(1, -1)];
  const cos = Math.cos(aoa);
  const sin = Math.sin(aoa);
  outline.forEach(([u, v], k) => {
    // 시위를 뒤(−X)로 두고, 앞전을 축으로 뒷전이 올라가게 돌린다.
    const x = -u * chord * cos - v * chord * sin;
    const y = u * chord * sin + v * chord * cos;
    if (k === 0) shape.moveTo(le[0] + x, le[1] + y);
    else shape.lineTo(le[0] + x, le[1] + y);
  });
  const g = new THREE.ExtrudeGeometry(shape, { depth: span[1] - span[0], bevelEnabled: false, curveSegments: 1 });
  g.translate(0, 0, span[0]);
  return g;
}

/** 축에 맞춘 상자 [x0, x1]·[y0, y1](위)·[z0, z1](옆). */
function box(x0, x1, y0, y1, z0, z1) {
  const g = new THREE.BoxGeometry(x1 - x0, y1 - y0, z1 - z0);
  g.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
  return g;
}

/** 두 점 [a]·[b]([앞, 위, 옆])를 잇는 가는 원기둥. */
function rod(a, b, radius = ARM_RADIUS_M) {
  const from = new THREE.Vector3(...a);
  const to = new THREE.Vector3(...b);
  const length = from.distanceTo(to);
  const g = new THREE.CylinderGeometry(radius, radius, length, 8, 1);
  const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), to.clone().sub(from).normalize());
  g.applyQuaternion(q);
  const mid = from.add(to).multiplyScalar(0.5);
  g.translate(mid.x, mid.y, mid.z);
  return g;
}

/** 옆(Z)을 뒤집은 복사본. */
function mirrorZ(g) {
  const m = g.clone();
  m.scale(1, 1, -1);
  // 거울에 비치면 면 방향이 뒤집히므로 삼각형 순서를 바꾼다.
  const index = m.index;
  if (index) {
    for (let i = 0; i < index.count; i += 3) {
      const t = index.getX(i + 1);
      index.setX(i + 1, index.getX(i + 2));
      index.setX(i + 2, t);
    }
  } else {
    flipTriangles(m);
  }
  m.computeVertexNormals();
  return m;
}

function flipTriangles(g) {
  for (const name of Object.keys(g.attributes)) {
    const a = g.attributes[name];
    for (let i = 0; i < a.count; i += 3) {
      for (let c = 0; c < a.itemSize; c++) {
        const t = a.getComponent(i + 1, c);
        a.setComponent(i + 1, c, a.getComponent(i + 2, c));
        a.setComponent(i + 2, c, t);
      }
    }
  }
}

function both(g) {
  return [g, mirrorZ(g)];
}

/**
 * 같은 재질로 칠하는 부품들을 한 덩어리로 합친다(그리기 호출을 줄인다). 위치·법선·UV만 남긴다.
 * [planarUv]면 UV를 면 방향에 맞춘 평면 투영(m ÷ [CARBON_TILE_M])으로 다시 매겨 카본 무늬 크기를 부품끼리 맞춘다.
 */
function merge(parts, planarUv = false) {
  const flat = parts.map((g) => {
    if (!g.attributes.normal) g.computeVertexNormals();
    return g.index ? g.toNonIndexed() : g;
  });
  const count = flat.reduce((n, g) => n + g.attributes.position.count, 0);
  const position = new Float32Array(count * 3);
  const normal = new Float32Array(count * 3);
  const uv = new Float32Array(count * 2);
  let offset = 0;
  for (const g of flat) {
    const p = g.attributes.position;
    const n = g.attributes.normal;
    const t = g.attributes.uv;
    for (let i = 0; i < p.count; i++) {
      const o = offset + i;
      position.set([p.getX(i), p.getY(i), p.getZ(i)], o * 3);
      normal.set([n.getX(i), n.getY(i), n.getZ(i)], o * 3);
      if (planarUv) {
        const ax = Math.abs(n.getX(i));
        const ay = Math.abs(n.getY(i));
        const az = Math.abs(n.getZ(i));
        const [u, v] = ay >= ax && ay >= az ? [p.getX(i), p.getZ(i)] : az >= ax ? [p.getX(i), p.getY(i)] : [p.getZ(i), p.getY(i)];
        uv.set([u / CARBON_TILE_M, v / CARBON_TILE_M], o * 2);
      } else if (t) {
        uv.set([t.getX(i), t.getY(i)], o * 2);
      }
    }
    offset += p.count;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(position, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(normal, 3));
  out.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  out.computeBoundingSphere();
  return out;
}

/** 능직 카본 무늬(코드로 그린 작은 타일, 반복). */
function carbonTexture() {
  const size = 32;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const half = size / 2;
  for (let cy = 0; cy < 2; cy++) {
    for (let cx = 0; cx < 2; cx++) {
      const vertical = (cx + cy) % 2 === 0;
      const grad = vertical
        ? ctx.createLinearGradient(cx * half, 0, cx * half + half, 0)
        : ctx.createLinearGradient(0, cy * half, 0, cy * half + half);
      grad.addColorStop(0, '#15161a');
      grad.addColorStop(0.5, '#34373d');
      grad.addColorStop(1, '#15161a');
      ctx.fillStyle = grad;
      ctx.fillRect(cx * half, cy * half, half, half);
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = THREE.RepeatWrapping;
  texture.wrapT = THREE.RepeatWrapping;
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return texture;
}

/** 휠 커버(회전이 보이게 밝은 홈 몇 줄과 가운데 너트). */
function wheelCoverTexture() {
  const size = 128;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const c = size / 2;
  const grad = ctx.createRadialGradient(c, c, 4, c, c, c);
  grad.addColorStop(0, '#4a4d54');
  grad.addColorStop(0.75, '#25272c');
  grad.addColorStop(1, '#141518');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);
  ctx.strokeStyle = '#6b6f78';
  ctx.lineWidth = 3;
  for (let k = 0; k < 5; k++) {
    const a = (k / 5) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(c + Math.cos(a) * c * 0.3, c + Math.sin(a) * c * 0.3);
    ctx.lineTo(c + Math.cos(a) * c * 0.85, c + Math.sin(a) * c * 0.85);
    ctx.stroke();
  }
  ctx.fillStyle = '#9a9ea6';
  ctx.beginPath();
  ctx.arc(c, c, c * 0.14, 0, Math.PI * 2);
  ctx.fill();
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

/** 차 아래 그림자(가운데가 짙고 가장자리로 옅어지는 얼룩). */
function shadowTexture() {
  const size = 64;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  const grad = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grad.addColorStop(0, 'rgba(0,0,0,1)');
  grad.addColorStop(0.6, 'rgba(0,0,0,0.6)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, size, size);
  return new THREE.CanvasTexture(canvas);
}

/** 타이어 단면(둥근 숄더)을 축(Z) 둘레로 돌린 회전체. */
function tyreGeometry({ radius, width }) {
  const w = width / 2;
  const points = [new THREE.Vector2(RIM_RADIUS_M, -w + 0.01), new THREE.Vector2(radius - SHOULDER_M, -w)];
  const arc = 4;
  for (let k = 1; k <= arc; k++) {
    const a = (k / arc) * (Math.PI / 2);
    points.push(new THREE.Vector2(radius - SHOULDER_M + SHOULDER_M * Math.sin(a), -w + SHOULDER_M - SHOULDER_M * Math.cos(a)));
  }
  for (let k = 0; k <= arc; k++) {
    const a = (k / arc) * (Math.PI / 2);
    points.push(new THREE.Vector2(radius - SHOULDER_M + SHOULDER_M * Math.cos(a), w - SHOULDER_M + SHOULDER_M * Math.sin(a)));
  }
  points.push(new THREE.Vector2(radius - SHOULDER_M, w), new THREE.Vector2(RIM_RADIUS_M, w - 0.01));
  const g = new THREE.LatheGeometry(points, WHEEL_SEGMENTS);
  g.rotateX(Math.PI / 2);
  return g;
}

/** 바퀴 양옆 면에 붙이는 원판·띠(바깥 +Z, 안쪽 −Z). */
function sideDecal(geometry, width) {
  const outer = geometry.clone().translate(0, 0, width / 2 + DECAL_OFFSET_M);
  const inner = geometry.clone().rotateY(Math.PI).translate(0, 0, -width / 2 - DECAL_OFFSET_M);
  return merge([outer, inner]);
}

/** 모든 차가 함께 쓰는 모양·무늬(한 번 만든다). */
export function buildCarAssets() {
  const body = [
    ...loft(BODY_SECTIONS),
    ...loft(AIRBOX_SECTIONS),
    // 샤크 핀.
    (() => {
      const s = new THREE.Shape();
      s.moveTo(-1.0, 0.7);
      s.lineTo(-1.25, 0.84);
      s.lineTo(-2.42, 0.86);
      s.lineTo(-2.5, 0.5);
      s.lineTo(-1.6, 0.55);
      const g = new THREE.ExtrudeGeometry(s, { depth: 0.02, bevelEnabled: false });
      return g.translate(0, 0, -0.01);
    })(),
    // 미러.
    ...both(box(0.5, 0.6, 0.62, 0.7, 0.43, 0.6)),
    // 앞뒤 날개 끝판.
    ...both(box(2.1, 2.92, 0.03, 0.32, 0.965, 0.985)),
    ...both(box(-3.0, -2.4, 0.38, 1.04, 0.73, 0.755)),
  ];

  const carbon = [
    // 플로어: 앞이 좁고 뒤가 넓은 판.
    (() => {
      const s = new THREE.Shape();
      const outline = [[1.4, 0.3], [0.9, 0.5], [0.35, 0.82], [-2.0, 0.82], [-2.3, 0.62]];
      s.moveTo(outline[0][0], outline[0][1]);
      for (const [x, z] of outline.slice(1)) s.lineTo(x, z);
      for (const [x, z] of [...outline].reverse()) s.lineTo(x, -z);
      const g = new THREE.ExtrudeGeometry(s, { depth: 0.035, bevelEnabled: false });
      g.rotateX(Math.PI / 2);
      return g.translate(0, 0.065, 0);
    })(),
    // 디퓨저: 뒤로 갈수록 올라가는 판.
    (() => {
      const g = new THREE.BoxGeometry(0.6, 0.02, 1.1);
      g.rotateZ(-0.42);
      return g.translate(-2.5, 0.16, 0);
    })(),
    ...WING_ELEMENTS.map(wing),
    // 헤일로: 가운데 기둥 + 머리를 두르는 고리.
    new THREE.TubeGeometry(
      new THREE.CatmullRomCurve3([new THREE.Vector3(0.95, 0.57, 0), new THREE.Vector3(0.82, 0.76, 0), new THREE.Vector3(0.72, 0.86, 0)]),
      8, HALO_RADIUS_M, 8, false,
    ),
    new THREE.TubeGeometry(
      new THREE.CatmullRomCurve3(
        [[-0.15, 0.6, -0.25], [0.05, 0.77, -0.25], [0.45, 0.86, -0.2], [0.72, 0.86, 0], [0.45, 0.86, 0.2], [0.05, 0.77, 0.25], [-0.15, 0.6, 0.25]]
          .map(([x, y, z]) => new THREE.Vector3(x, y, z)),
        false,
        'centripetal',
      ),
      40, HALO_RADIUS_M, 8, false,
    ),
    // 미러 기둥, 노즈 기둥, 뒷날개 기둥.
    ...both(rod([0.56, 0.55, 0.3], [0.56, 0.65, 0.46])),
    ...both(rod([2.42, 0.17, 0.07], [2.52, 0.08, 0.07], 0.02)),
    rod([-2.3, 0.32, 0], [-2.66, 0.82, 0], 0.025),
  ];
  // 서스펜션 암(위·아래 위시본, 앞뒤로 갈라진 두 가닥).
  for (const [x, inner, outer, hubUp, hubLow] of [[FRONT_AXLE_M, 0.18, 0.7, 0.5, 0.2], [REAR_AXLE_M, 0.24, 0.62, 0.5, 0.2]]) {
    for (const dx of [-0.3, 0.25]) {
      carbon.push(...both(rod([x + dx, 0.46, inner], [x, hubUp, outer])));
      carbon.push(...both(rod([x + dx, 0.2, inner], [x, hubLow, outer])));
    }
    carbon.push(...both(rod([x + 0.12, 0.3, inner], [x + 0.05, 0.36, outer])));
  }

  const dark = [
    // 조종석 구멍과 에어박스 흡기구.
    (() => {
      const g = new THREE.SphereGeometry(1, 24, 8);
      g.scale(0.34, 0.035, 0.19);
      g.rotateZ(0.07);
      return g.translate(0.55, 0.625, 0);
    })(),
    (() => {
      const g = new THREE.SphereGeometry(1, 16, 8);
      g.scale(0.02, 0.07, 0.07);
      return g.translate(-0.06, 0.83, 0);
    })(),
    // 사이드포드 흡기구.
    ...both((() => {
      const g = new THREE.SphereGeometry(1, 16, 8);
      // 앞쪽 바깥을 보는 사이드포드 앞면 기울기에 맞춰 눕힌 납작한 타원.
      g.scale(0.03, 0.11, 0.17);
      g.rotateY(-0.85);
      return g.translate(0.27, 0.4, 0.6);
    })()),
  ];

  const helmet = new THREE.SphereGeometry(0.12, 24, 16).translate(0.38, 0.74, 0);
  const visor = new THREE.SphereGeometry(0.123, 24, 6, Math.PI - 0.95, 1.9, 1.2, 0.38).translate(0.38, 0.74, 0);

  const cover = new THREE.CircleGeometry(RIM_RADIUS_M, WHEEL_SEGMENTS);
  const band = new THREE.RingGeometry(BAND_INNER_M, BAND_OUTER_M, WHEEL_SEGMENTS);
  const shadow = new THREE.PlaneGeometry(6.4, 2.5).rotateX(-Math.PI / 2).translate(-0.15, SHADOW_LIFT_M, 0);

  return {
    body: merge(body),
    carbon: merge(carbon, true),
    dark: merge(dark),
    helmet: merge([helmet]),
    visor: merge([visor]),
    wheels: [FRONT_TYRE, REAR_TYRE].map((tyre) => ({
      tyre: tyreGeometry(tyre),
      cover: sideDecal(cover, tyre.width),
      band: sideDecal(band, tyre.width),
    })),
    shadow,
    carbonMap: carbonTexture(),
    coverMap: wheelCoverTexture(),
    shadowMap: shadowTexture(),
  };
}

/** 차 한 대: [assets]의 모양을 쓰고 재질은 따로(팀 색·투명도가 차마다 다르다). */
export function makeCar(assets) {
  const group = new THREE.Group();
  group.rotation.order = 'YZX';
  const materials = {
    body: new THREE.MeshPhysicalMaterial({ roughness: 0.32, metalness: 0.15, clearcoat: 1, clearcoatRoughness: 0.06 }),
    carbon: new THREE.MeshStandardMaterial({ map: assets.carbonMap, roughness: 0.42, metalness: 0.25 }),
    dark: new THREE.MeshStandardMaterial({ color: 0x0b0c0e, roughness: 0.75 }),
    helmet: new THREE.MeshPhysicalMaterial({ color: 0xf1f2f4, roughness: 0.3, clearcoat: 1, clearcoatRoughness: 0.05 }),
    visor: new THREE.MeshStandardMaterial({ color: 0x15171c, roughness: 0.1, metalness: 0.8 }),
    tyre: new THREE.MeshStandardMaterial({ color: 0x1a1b1e, roughness: 0.92, side: THREE.DoubleSide }),
    cover: new THREE.MeshStandardMaterial({ map: assets.coverMap, roughness: 0.45, metalness: 0.5 }),
    band: new THREE.MeshStandardMaterial({ roughness: 0.6 }),
    shadow: new THREE.MeshBasicMaterial({
      color: 0x000000,
      alphaMap: assets.shadowMap,
      transparent: true,
      opacity: SHADOW_OPACITY,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -2,
    }),
  };
  for (const name of ['body', 'carbon', 'dark', 'helmet', 'visor']) {
    group.add(new THREE.Mesh(assets[name], materials[name]));
  }
  group.add(new THREE.Mesh(assets.shadow, materials.shadow));

  const wheels = [];
  for (const [axle, front, set] of [[FRONT_AXLE_M, true, assets.wheels[0]], [REAR_AXLE_M, false, assets.wheels[1]]]) {
    const tyre = front ? FRONT_TYRE : REAR_TYRE;
    for (const side of [1, -1]) {
      // 꺾는 축(위아래) 안에 도는 축(옆)을 둔다.
      const pivot = new THREE.Group();
      pivot.position.set(axle, tyre.radius, side * tyre.center);
      const spin = new THREE.Group();
      spin.add(new THREE.Mesh(set.tyre, materials.tyre));
      spin.add(new THREE.Mesh(set.cover, materials.cover));
      const band = new THREE.Mesh(set.band, materials.band);
      spin.add(band);
      pivot.add(spin);
      group.add(pivot);
      wheels.push({ pivot, spin, band, front, radius: tyre.radius });
    }
  }

  let opacity = -1;
  return {
    group,
    /** 팀 색(sRGB 0~1). */
    setColor(r, g, b) {
      srgb(materials.body, r, g, b);
    },
    /** 타이어 옆 띠 색(컴파운드, sRGB 0~1). r < 0이면 띠를 숨긴다. */
    setTyre(r, g, b) {
      const show = r >= 0;
      for (const w of wheels) w.band.visible = show;
      if (show) srgb(materials.band, r, g, b);
    },
    /** 앞바퀴 조향([steer] −1~1, + = 오른쪽)과 바퀴 회전(달린 거리 [distanceM]만큼 굴러간 각). */
    setWheels(steer, distanceM) {
      for (const w of wheels) {
        // 앞이 +X인 차에서 Z축 음의 방향으로 돌아야 바퀴 윗면이 앞으로 굴러간다.
        w.spin.rotation.z = -((distanceM / w.radius) % (Math.PI * 2));
        // 오른쪽(+Z)으로 꺾으려면 Y축으로 음의 방향.
        if (w.front) w.pivot.rotation.y = -steer * MAX_STEER_RAD;
      }
    },
    setOpacity(value) {
      if (value === opacity) return;
      opacity = value;
      const transparent = value < 1;
      for (const [name, m] of Object.entries(materials)) {
        if (name === 'shadow') {
          m.opacity = SHADOW_OPACITY * value;
          continue;
        }
        m.transparent = transparent;
        m.opacity = value;
        m.needsUpdate = true;
      }
    },
    dispose() {
      for (const m of Object.values(materials)) m.dispose();
    },
  };
}

/** 차 칠에 비칠 하늘(위는 밝은 하늘, 아래는 어두운 땅, 해 쪽이 밝다). 한 번 만들어 장면 환경으로 쓴다. */
export function buildEnvironment(renderer, sunDirection) {
  const envScene = new THREE.Scene();
  const sky = new THREE.SphereGeometry(10, 32, 16);
  const colors = [];
  const top = new THREE.Color(0x9fbfe6);
  const horizon = new THREE.Color(0xeef3f7);
  const ground = new THREE.Color(0x4b5046);
  const p = sky.attributes.position;
  for (let i = 0; i < p.count; i++) {
    const y = p.getY(i) / 10;
    const c = y >= 0 ? horizon.clone().lerp(top, Math.min(1, y * 1.4)) : horizon.clone().lerp(ground, Math.min(1, -y * 4));
    colors.push(c.r, c.g, c.b);
  }
  sky.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  envScene.add(new THREE.Mesh(sky, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));
  const sun = new THREE.Mesh(new THREE.SphereGeometry(0.9, 16, 8), new THREE.MeshBasicMaterial({ color: 0xffffff }));
  sun.position.copy(sunDirection).normalize().multiplyScalar(8);
  envScene.add(sun);
  const pmrem = new THREE.PMREMGenerator(renderer);
  const texture = pmrem.fromScene(envScene, 0.02).texture;
  pmrem.dispose();
  sky.dispose();
  return texture;
}
