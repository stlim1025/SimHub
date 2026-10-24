// 다시보기 3D 화면(three.js). 무엇을 그릴지는 앱(Dart)이 정하고, 이 모듈은 받은 트랙 메시와 매 프레임 상태를 그리기만 한다.
// 프레임 상태(Float32Array): [눈 XYZ, 목표 XYZ, 세로 화각(rad), 차 수, 차마다 (X, Y, Z, 진행 방향, 기울기, R, G, B, 불투명도,
// 스티어 −1~1, 달린 거리(m), 타이어 띠 R, G, B(모르면 R = −1))].
import * as THREE from '../vendor/three/three.module.js';
import { buildCarAssets, buildEnvironment, makeCar } from './car.js';

const CAMERA_FIELDS = 7;
const HEADER_FIELDS = CAMERA_FIELDS + 1;
const CAR_STRIDE = 14;

const NEAR_M = 0.3;
const FAR_M = 2500;
const FOG_START_M = 120;
const FOG_END_M = 900;
const GROUND_SIZE_M = 8000;
const GROUND_BELOW_M = 0.3;
const MAX_PIXEL_RATIO = 2;

const SKY_COLOR = 0xb9ccdd;

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
  const canvas = renderer.domElement;
  canvas.style.width = '100%';
  canvas.style.height = '100%';
  canvas.style.display = 'block';
  container.style.pointerEvents = 'none';
  container.appendChild(canvas);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(SKY_COLOR);
  scene.fog = new THREE.Fog(SKY_COLOR, FOG_START_M, FOG_END_M);
  scene.add(new THREE.HemisphereLight(0xdfe9f5, 0x3a4a30, 1.6));
  const sun = new THREE.DirectionalLight(0xffffff, 2.2);
  sun.position.set(0.35, 0.85, 0.4);
  scene.add(sun);
  // 차 칠(물리 기반 재질)에만 비치는 하늘. 트랙(램버트 재질)은 영향을 받지 않는다.
  scene.environment = buildEnvironment(renderer, sun.position);
  const carAssets = buildCarAssets();

  const camera = new THREE.PerspectiveCamera(55, 1, NEAR_M, FAR_M);
  let track = null;
  let ground = null;
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

  function setTrack(positions, colors, groundRgb, minElevation) {
    if (track) {
      scene.remove(track);
      track.geometry.dispose();
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(toLinear(colors), 3));
    geometry.computeVertexNormals();
    track = new THREE.Mesh(
      geometry,
      new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide }),
    );
    scene.add(track);

    if (!ground) {
      ground = new THREE.Mesh(
        new THREE.PlaneGeometry(GROUND_SIZE_M, GROUND_SIZE_M).rotateX(-Math.PI / 2),
        new THREE.MeshLambertMaterial(),
      );
      scene.add(ground);
    }
    ground.material.color.setRGB(groundRgb[0], groundRgb[1], groundRgb[2], THREE.SRGBColorSpace);
    ground.position.y = minElevation - GROUND_BELOW_M;
  }

  function draw(state) {
    if (lost) return;
    resize();
    const start = performance.now();
    camera.position.set(state[0], state[1], state[2]);
    camera.fov = (state[6] * 180) / Math.PI;
    camera.updateProjectionMatrix();
    camera.lookAt(state[3], state[4], state[5]);
    if (ground) ground.position.set(state[3], ground.position.y, state[5]);

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
      for (const car of cars) car.dispose();
      renderer.dispose();
      // 브라우저가 한 번에 여는 WebGL 컨텍스트 수에 한도가 있어, 시점을 오가며 쌓이지 않게 바로 돌려준다.
      renderer.forceContextLoss();
      canvas.remove();
    },
  };
}
