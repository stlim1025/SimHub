// 다시보기 3D 화면(three.js). 무엇을 그릴지는 앱(Dart)이 정하고, 이 모듈은 받은 트랙 메시와 매 프레임 상태를 그리기만 한다.
// 프레임 상태(Float32Array): [눈 XYZ, 목표 XYZ, 세로 화각(rad), 차 수, 차마다 (X, Y, Z, 진행 방향, 기울기, R, G, B, 불투명도,
// 스티어 −1~1, 달린 거리(m), 타이어 띠 R, G, B(모르면 R = −1))].
import * as THREE from '../vendor/three/three.module.js';
import { buildCarAssets, buildEnvironment, makeCar } from './car.js';
import { HORIZON_COLOR, Surface, buildGroundMaterial, buildSky, buildTrackMaterials } from './track.js';

const CAMERA_FIELDS = 7;
const HEADER_FIELDS = CAMERA_FIELDS + 1;
const CAR_STRIDE = 14;

const NEAR_M = 0.3;
const FAR_M = 2500;
const FOG_START_M = 150;
const FOG_END_M = 1100;
const GROUND_SIZE_M = 8000;
const GROUND_BELOW_M = 0.3;
const MAX_PIXEL_RATIO = 2;
const EXPOSURE = 1.05;

/** 해 방향(위쪽 앞에서 비스듬히). */
const SUN_DIRECTION = new THREE.Vector3(0.35, 0.85, 0.4).normalize();
const SUN_DISTANCE_M = 150;
/** 그림자를 드리우는 범위: 카메라가 보는 곳 둘레 반경(m)과 그림자 지도 해상도. */
const SHADOW_RADIUS_M = 45;
const SHADOW_MAP_SIZE = 2048;
const SHADOW_BIAS = -0.0004;
const SHADOW_NORMAL_BIAS = 0.03;

/** sRGB(0~1) 꼭짓점 색 배열을 three.js 작업 색 공간(선형)으로 바꾼다. */
function toLinear(colors) {
  const out = new Float32Array(colors.length);
  const c = new THREE.Color();
  for (let i = 0; i < colors.length; i += 3) {
    c.setRGB(colors[i], colors[i + 1], colors[i + 2], THREE.SRGBColorSpace);
    out[i] = c.r;
    out[i + 1] = c.g;
    out[i + 2] = c.b;
  }
  return out;
}

/**
 * [container] 안에 캔버스를 만들고 장면 핸들을 돌려준다. WebGL을 못 쓰면 ok = false(앱이 예전 그림으로 돌아간다).
 */
export function createReplayScene(container) {
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ antialias: true });
  } catch (e) {
    console.warn('replay3d: WebGL unavailable', e);
    return { ok: false, setTrack() {}, render() {}, lastFrameMs() { return 0; }, dispose() {} };
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, MAX_PIXEL_RATIO));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = EXPOSURE;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const canvas = renderer.domElement;
  canvas.style.width = '100%';
  canvas.style.height = '100%';
  canvas.style.display = 'block';
  container.style.pointerEvents = 'none';
  container.appendChild(canvas);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(HORIZON_COLOR);
  scene.fog = new THREE.Fog(HORIZON_COLOR, FOG_START_M, FOG_END_M);
  const sky = buildSky();
  scene.add(sky);
  scene.add(new THREE.HemisphereLight(0xdfe9f5, 0x4a5a40, 1.3));
  const sun = new THREE.DirectionalLight(0xfff4e5, 2.8);
  sun.castShadow = true;
  sun.shadow.mapSize.set(SHADOW_MAP_SIZE, SHADOW_MAP_SIZE);
  sun.shadow.bias = SHADOW_BIAS;
  sun.shadow.normalBias = SHADOW_NORMAL_BIAS;
  Object.assign(sun.shadow.camera, {
    left: -SHADOW_RADIUS_M,
    right: SHADOW_RADIUS_M,
    top: SHADOW_RADIUS_M,
    bottom: -SHADOW_RADIUS_M,
    near: 1,
    far: SUN_DISTANCE_M * 2,
  });
  sun.shadow.camera.updateProjectionMatrix();
  scene.add(sun, sun.target);
  // 물리 기반 재질(차 칠·트랙)에 비치는 하늘.
  scene.environment = buildEnvironment(renderer, SUN_DIRECTION);
  const carAssets = buildCarAssets();

  // 그림자 지도 한 칸 단위로 해를 옮겨, 카메라가 움직여도 그림자 가장자리가 떨리지 않게 한다.
  const lightRight = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), SUN_DIRECTION).normalize();
  const lightUp = new THREE.Vector3().crossVectors(SUN_DIRECTION, lightRight).normalize();
  const shadowTexel = (SHADOW_RADIUS_M * 2) / SHADOW_MAP_SIZE;
  const aim = new THREE.Vector3();
  const snapped = new THREE.Vector3();
  function placeSun(x, y, z) {
    aim.set(x, y, z);
    const a = Math.round(aim.dot(lightRight) / shadowTexel) * shadowTexel;
    const b = Math.round(aim.dot(lightUp) / shadowTexel) * shadowTexel;
    const c = aim.dot(SUN_DIRECTION);
    snapped.copy(lightRight).multiplyScalar(a).addScaledVector(lightUp, b).addScaledVector(SUN_DIRECTION, c);
    sun.target.position.copy(snapped);
    sun.position.copy(snapped).addScaledVector(SUN_DIRECTION, SUN_DISTANCE_M);
  }

  const camera = new THREE.PerspectiveCamera(55, 1, NEAR_M, FAR_M);
  let trackMeshes = [];
  let trackMaterials = null;
  let ground = null;
  let groundMaterial = null;
  const cars = [];
  let lost = false;
  let lastState = null;
  let frameMs = 0;

  canvas.addEventListener('webglcontextlost', (e) => {
    e.preventDefault();
    lost = true;
  });

  function resize() {
    const w = Math.max(1, container.clientWidth);
    const h = Math.max(1, container.clientHeight);
    const size = renderer.getSize(new THREE.Vector2());
    if (size.x !== w || size.y !== h) {
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    }
  }
  const observer = new ResizeObserver(() => {
    resize();
    if (lastState) draw(lastState);
  });
  observer.observe(container);

  function clearTrack() {
    for (const mesh of trackMeshes) {
      scene.remove(mesh);
      mesh.geometry.dispose();
    }
    trackMeshes = [];
    if (trackMaterials) {
      for (const m of Object.values(trackMaterials)) {
        m.map?.dispose();
        m.dispose();
      }
      trackMaterials = null;
    }
    if (ground) {
      scene.remove(ground);
      ground.geometry.dispose();
      groundMaterial.dispose();
      ground = null;
    }
  }

  /** 면 종류별 층(같은 순서의 배열: 종류 번호, 위치, 무늬 좌표, 꼭짓점 색), 넓은 바닥 색, 가장 낮은 노면 높이, 시가지인지. */
  function setTrack(surfaces, positions, uvs, colors, groundRgb, minElevation, street) {
    clearTrack();
    trackMaterials = buildTrackMaterials(renderer, street);
    for (let k = 0; k < surfaces.length; k++) {
      const surface = surfaces[k];
      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions[k]), 3));
      geometry.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(uvs[k]), 2));
      geometry.setAttribute('color', new THREE.BufferAttribute(toLinear(colors[k]), 3));
      geometry.computeVertexNormals();
      const mesh = new THREE.Mesh(geometry, trackMaterials[surface]);
      mesh.receiveShadow = surface !== Surface.fence;
      // 펜스(반투명)는 불투명한 면 다음에 그린다.
      if (surface === Surface.fence) mesh.renderOrder = 1;
      scene.add(mesh);
      trackMeshes.push(mesh);
    }

    groundMaterial = buildGroundMaterial(renderer, street, GROUND_SIZE_M);
    groundMaterial.material.color.setRGB(groundRgb[0], groundRgb[1], groundRgb[2], THREE.SRGBColorSpace);
    ground = new THREE.Mesh(new THREE.PlaneGeometry(GROUND_SIZE_M, GROUND_SIZE_M).rotateX(-Math.PI / 2), groundMaterial.material);
    ground.position.y = minElevation - GROUND_BELOW_M;
    ground.receiveShadow = true;
    scene.add(ground);
  }

  function draw(state) {
    if (lost) return;
    resize();
    const start = performance.now();
    camera.position.set(state[0], state[1], state[2]);
    camera.fov = (state[6] * 180) / Math.PI;
    camera.updateProjectionMatrix();
    camera.lookAt(state[3], state[4], state[5]);
    sky.position.copy(camera.position);
    placeSun(state[3], state[4], state[5]);
    if (ground) {
      ground.position.set(state[3], ground.position.y, state[5]);
      groundMaterial.follow(state[3], state[5]);
    }

    const count = state[CAMERA_FIELDS];
    while (cars.length < count) {
      const car = makeCar(carAssets);
      scene.add(car.group);
      cars.push(car);
    }
    for (let k = 0; k < cars.length; k++) {
      const car = cars[k];
      car.group.visible = k < count;
      if (k >= count) continue;
      const o = HEADER_FIELDS + k * CAR_STRIDE;
      car.group.position.set(state[o], state[o + 1], state[o + 2]);
      // 앞이 +X인 차: 진행 방향(X → Z)만큼 Y축으로, 오르막만큼 차 옆축(Z)으로 돌린다.
      car.group.rotation.set(0, -state[o + 3], state[o + 4]);
      car.setColor(state[o + 5], state[o + 6], state[o + 7]);
      car.setOpacity(state[o + 8]);
      car.setWheels(state[o + 9], state[o + 10]);
      car.setTyre(state[o + 11], state[o + 12], state[o + 13]);
    }
    renderer.render(scene, camera);
    frameMs = performance.now() - start;
  }

  return {
    ok: true,
    setTrack,
    render(state) {
      lastState = state;
      draw(state);
    },
    /** 마지막 그리기에 든 시간(ms, 측정용). */
    lastFrameMs() {
      return frameMs;
    },
    dispose() {
      observer.disconnect();
      clearTrack();
      for (const car of cars) car.dispose();
      renderer.dispose();
      // 브라우저가 한 번에 여는 WebGL 컨텍스트 수에 한도가 있어, 시점을 오가며 쌓이지 않게 바로 돌려준다.
      renderer.forceContextLoss();
      canvas.remove();
    },
  };
}
