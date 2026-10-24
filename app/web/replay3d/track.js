// 다시보기 3D 트랙 재질과 하늘. 무늬는 모두 코드로 그린다(외부 이미지 없음).
// 앱이 넘기는 무늬 좌표는 m 단위(U = 길을 따라 잰 거리, V = 옆 거리 또는 벽 높이)라 무늬마다 한 칸 크기(m)로 나눠 반복한다.
import * as THREE from '../vendor/three/three.module.js';

/** 면 종류 번호(앱의 ReplaySurface 순서와 같다). */
export const Surface = Object.freeze({ ground: 0, gravel: 1, asphalt: 2, line: 3, kerb: 4, barrier: 5, fence: 6 });

const ASPHALT_TILE_M = 6;
const GRASS_TILE_M = 24;
const GRAVEL_TILE_M = 3;
const LINE_TILE_M = 3;
/** 연석 줄무늬 한 쌍(빨강 + 흰색) 길이(m). */
const KERB_STRIPE_M = 2;
const KERB_WIDTH_M = 1.5;
const TYRE_WALL_TILE_M = 2;
const CONCRETE_PANEL_M = 4;
const FENCE_TILE_M = 4;
const FENCE_HEIGHT_M = 2.6;
const TRACK_ENV_INTENSITY = 0.25;

const SKY_RADIUS_M = 1500;
const SKY_TOP = 0x3d6fa8;
const SKY_HORIZON = 0xb9ccdd;
const SKY_GROUND = 0x8a9aa8;

/** 고정 씨앗 난수(그릴 때마다 같은 무늬). */
function random(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function canvas(width, height) {
  const c = document.createElement('canvas');
  c.width = width;
  c.height = height;
  return [c, c.getContext('2d')];
}

/** [ctx] 전체에 밝기 [low]~[high](0~255)를 곱한 잔 점을 뿌린다(꼭짓점 색에 곱해지는 회색 무늬). */
function speckle(ctx, width, height, low, high, seed, size = 1) {
  const rand = random(seed);
  const image = ctx.getImageData(0, 0, width, height);
  for (let y = 0; y < height; y += size) {
    for (let x = 0; x < width; x += size) {
      const v = low + (high - low) * rand();
      for (let dy = 0; dy < size; dy++) {
        for (let dx = 0; dx < size; dx++) {
          const o = ((y + dy) * width + x + dx) * 4;
          image.data[o] = (image.data[o] * v) / 255;
          image.data[o + 1] = (image.data[o + 1] * v) / 255;
          image.data[o + 2] = (image.data[o + 2] * v) / 255;
        }
      }
    }
  }
  ctx.putImageData(image, 0, 0);
}

function texture(c, renderer) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = THREE.RepeatWrapping;
  t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function asphaltCanvas() {
  const size = 256;
  const [c, ctx] = canvas(size, size);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, size, size);
  speckle(ctx, size, size, 205, 255, 7);
  // 드문드문 밝은 골재 알갱이와 어두운 얼룩.
  const rand = random(11);
  for (let k = 0; k < 220; k++) {
    ctx.fillStyle = rand() < 0.5 ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.12)';
    ctx.fillRect(rand() * size, rand() * size, 1 + rand() * 2, 1 + rand() * 2);
  }
  return c;
}

/** 잔디: 잔 점 + (줄무늬면) 깎은 방향으로 번갈아 밝고 어두운 띠 두 줄. */
function grassCanvas(stripes) {
  const size = 256;
  const [c, ctx] = canvas(size, size);
  if (stripes) {
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, size / 2, size);
    ctx.fillStyle = '#d6d6d6';
    ctx.fillRect(size / 2, 0, size / 2, size);
  } else {
    ctx.fillStyle = '#f0f0f0';
    ctx.fillRect(0, 0, size, size);
  }
  speckle(ctx, size, size, 200, 255, 3, 2);
  return c;
}

function gravelCanvas() {
  const size = 128;
  const [c, ctx] = canvas(size, size);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, size, size);
  speckle(ctx, size, size, 150, 255, 5);
  const rand = random(17);
  for (let k = 0; k < 400; k++) {
    ctx.fillStyle = `rgba(${rand() < 0.5 ? '255,250,240' : '70,60,50'},0.5)`;
    ctx.beginPath();
    ctx.arc(rand() * size, rand() * size, 0.6 + rand() * 1.2, 0, Math.PI * 2);
    ctx.fill();
  }
  return c;
}

function lineCanvas() {
  const size = 64;
  const [c, ctx] = canvas(size, size);
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, size, size);
  speckle(ctx, size, size, 215, 255, 9);
  return c;
}

/** 연석: 길이 방향으로 빨강·흰색 번갈아(U 앞 절반 빨강). */
function kerbCanvas() {
  const [c, ctx] = canvas(64, 32);
  ctx.fillStyle = '#d62828';
  ctx.fillRect(0, 0, 32, 32);
  ctx.fillStyle = '#f3f4f6';
  ctx.fillRect(32, 0, 32, 32);
  speckle(ctx, 64, 32, 210, 255, 13);
  return c;
}

/** 타이어 배리어: 검은 타이어를 쌓은 벽(아래 3/4), 위는 빨강·흰색 덮개 띠. 캔버스 위쪽이 벽 위(V = 1). */
function tyreWallCanvas() {
  const width = 128;
  const height = 64;
  const [c, ctx] = canvas(width, height);
  ctx.fillStyle = '#121316';
  ctx.fillRect(0, 0, width, height);
  const band = Math.round(height * 0.25);
  const rows = 3;
  const rowH = (height - band) / rows;
  const perRow = 8;
  for (let r = 0; r < rows; r++) {
    for (let k = 0; k < perRow; k++) {
      const x = (k + 0.5) * (width / perRow);
      const y = band + (r + 0.5) * rowH;
      ctx.fillStyle = '#2a2c31';
      ctx.beginPath();
      ctx.arc(x, y, rowH * 0.47, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#0b0c0e';
      ctx.beginPath();
      ctx.arc(x, y, rowH * 0.2, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.fillStyle = '#d62828';
  ctx.fillRect(0, 0, width / 2, band);
  ctx.fillStyle = '#f3f4f6';
  ctx.fillRect(width / 2, 0, width / 2, band);
  return c;
}

/** 콘크리트 벽: 밝은 회색 판, 판 사이 이음매, 위쪽 모서리 그늘. */
function concreteCanvas() {
  const width = 128;
  const height = 64;
  const [c, ctx] = canvas(width, height);
  ctx.fillStyle = '#e4e5e7';
  ctx.fillRect(0, 0, width, height);
  speckle(ctx, width, height, 200, 255, 21);
  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.fillRect(0, 0, 2, height);
  ctx.fillStyle = 'rgba(0,0,0,0.12)';
  ctx.fillRect(0, 0, width, 4);
  return c;
}

/** 철망 펜스(투명 바탕): 마름모 철망, 왼쪽 끝 기둥, 위 가로대. */
function fenceCanvas() {
  const size = 128;
  const [c, ctx] = canvas(size, size);
  ctx.clearRect(0, 0, size, size);
  ctx.strokeStyle = 'rgba(70,74,80,0.55)';
  ctx.lineWidth = 1;
  const step = 8;
  for (let k = -size; k < size * 2; k += step) {
    ctx.beginPath();
    ctx.moveTo(k, 0);
    ctx.lineTo(k + size, size);
    ctx.moveTo(k, size);
    ctx.lineTo(k + size, 0);
    ctx.stroke();
  }
  ctx.fillStyle = 'rgba(60,63,68,1)';
  ctx.fillRect(0, 0, 4, size);
  ctx.fillRect(0, 0, size, 3);
  return c;
}

/** 면 종류마다의 재질. [street]면 바닥은 회색 포장(줄무늬 없음), 벽은 콘크리트. */
export function buildTrackMaterials(renderer, street) {
  const repeat = (t, u, v = u) => {
    t.repeat.set(1 / u, 1 / v);
    return t;
  };
  const standard = (options) => {
    const m = new THREE.MeshStandardMaterial({ roughness: 0.9, metalness: 0, ...options });
    m.envMapIntensity = TRACK_ENV_INTENSITY;
    return m;
  };
  const ground = street
    ? repeat(texture(asphaltCanvas(), renderer), ASPHALT_TILE_M * 2)
    : repeat(texture(grassCanvas(true), renderer), GRASS_TILE_M);
  return {
    [Surface.ground]: standard({ map: ground, vertexColors: true, roughness: 0.95 }),
    [Surface.gravel]: standard({ map: repeat(texture(gravelCanvas(), renderer), GRAVEL_TILE_M), vertexColors: true }),
    [Surface.asphalt]: standard({ map: repeat(texture(asphaltCanvas(), renderer), ASPHALT_TILE_M), vertexColors: true, roughness: 0.82 }),
    [Surface.line]: standard({ map: repeat(texture(lineCanvas(), renderer), LINE_TILE_M), vertexColors: true, roughness: 0.6 }),
    [Surface.kerb]: standard({ map: repeat(texture(kerbCanvas(), renderer), KERB_STRIPE_M, KERB_WIDTH_M), roughness: 0.55 }),
    [Surface.barrier]: street
      ? standard({ map: repeat(texture(concreteCanvas(), renderer), CONCRETE_PANEL_M, 1.6), side: THREE.DoubleSide })
      : standard({ map: repeat(texture(tyreWallCanvas(), renderer), TYRE_WALL_TILE_M, 1), side: THREE.DoubleSide }),
    [Surface.fence]: standard({
      map: repeat(texture(fenceCanvas(), renderer), FENCE_TILE_M, FENCE_HEIGHT_M),
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      roughness: 0.5,
      metalness: 0.4,
    }),
  };
}

/** 트랙 밖 넓은 바닥 재질(잔디 또는 회색 포장). 바닥판은 카메라를 따라 움직이므로 [follow]로 무늬를 월드에 고정한다. */
export function buildGroundMaterial(renderer, street, sizeM) {
  const tile = street ? ASPHALT_TILE_M * 2 : GRASS_TILE_M;
  const map = texture(street ? asphaltCanvas() : grassCanvas(false), renderer);
  map.repeat.set(sizeM / tile, sizeM / tile);
  const material = new THREE.MeshStandardMaterial({ map, roughness: 0.95, metalness: 0 });
  material.envMapIntensity = TRACK_ENV_INTENSITY;
  return {
    material,
    /** 바닥판 가운데가 월드 ([x], [z])에 있을 때 무늬가 제자리에 있게 옮긴다. */
    follow(x, z) {
      map.offset.set((x / tile) % 1, (-z / tile) % 1);
    },
    dispose() {
      map.dispose();
      material.dispose();
    },
  };
}

/** 하늘: 카메라를 감싸는 큰 공(위는 짙은 파랑, 지평선은 옅게). 안개·톤 매핑을 받지 않는다. */
export function buildSky() {
  const geometry = new THREE.SphereGeometry(SKY_RADIUS_M, 32, 16);
  const top = new THREE.Color(SKY_TOP);
  const horizon = new THREE.Color(SKY_HORIZON);
  const below = new THREE.Color(SKY_GROUND);
  const p = geometry.attributes.position;
  const colors = [];
  for (let i = 0; i < p.count; i++) {
    const h = p.getY(i) / SKY_RADIUS_M;
    const c = h >= 0 ? horizon.clone().lerp(top, Math.pow(h, 0.6)) : horizon.clone().lerp(below, Math.min(1, -h * 3));
    colors.push(c.r, c.g, c.b);
  }
  geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  const sky = new THREE.Mesh(
    geometry,
    new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false, depthWrite: false, toneMapped: false }),
  );
  sky.renderOrder = -1;
  return sky;
}

/** 안개 색(하늘 지평선과 같게). */
export const HORIZON_COLOR = SKY_HORIZON;
