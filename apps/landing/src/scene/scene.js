// Port of Nooki/Scene/DioramaScene.swift. Coordinates are meters; the floor's top surface sits at y = 0.
// Keep the build functions in the same order and with the same numbers as the Swift file, so the two diff easily.
import * as THREE from "three";
import { Clay, quat, box, sphere, cylinder, group } from "./kit.js";
import { CatRoom, pointLight, lumensToCandela } from "./cat-room.js";

const Tone = {
  wood: 0xb46c3c,
  woodDark: 0x8c4f2b,
  woodLight: 0xcf8e58,
  wall: 0xf6e4c8,
  snow: 0xfffbf5,
  blanket: 0xe98a5b,
  plush: 0xfbf1e3,
  plushShade: 0xeadbc6,
  rug: 0xddb98a,
  rugEdge: 0xc39a69,
  leaf: 0x93a86a,
  leafDark: 0x6f8a4e,
  pot: 0xc7744a,
  ink: 0x5b3a28,
  windowGlow: 0xffe0a0,
  bulb: 0xffd27a,
  flame: 0xffb347,
};

// RealityKit's lumen-based intensities and its exposure don't carry over to three.js, so the web light is tuned
// by eye for a soft warm room: cream walls, honey wood, a gentle window glow, visible sun shadows.
const Lighting = {
  exposure: 0.95,
  environment: { top: "#fff1dc", bottom: "#d8b08a", intensity: 0.8 },
  sun: { color: 0xfff0dc, intensity: 3.0 },
  window: 0xffc98a,
};

const wallHeight = 0.8;
const bedCenter = [0.06, 0.014, -0.04];
const bedScale = 0.65;

export class DioramaScene extends CatRoom {
  constructor() {
    super();
    this.bulbs = [];

    this.buildFloor();
    this.buildWalls();
    this.buildWindow();
    this.buildShelf();
    this.buildFairyLights();
    this.buildRug();
    this.buildCatBed();
    this.buildCat();

    this.buildCatTree();
    this.buildNightstand();
    this.buildCornerProps();
    this.buildMotes();
    this.buildLighting();
  }

  tick(dt) {
    this.tickRoom(dt);
    const t = this.time;

    const flicker = 1 + 0.12 * Math.sin(t * 13) + 0.08 * Math.sin(t * 7.3 + 1);
    this.flame.scale.set(0.85, 1.45 * flicker, 0.85);
    this.candleLight.intensity = 900 * lumensToCandela * flicker;

    this.bulbs.forEach((bulb, i) => {
      const s = 1 + 0.22 * Math.sin(t * 2.1 + i * 1.3);
      bulb.scale.set(s, s, s);
    });

    this.tickMotes(dt);
  }

  buildFloor() {
    const pivot = this.pivot;
    box(pivot, 1.14, 0.1, 1.14, 0.03, Clay.matte(Tone.woodDark), [-0.01, -0.05, -0.01]);
    for (let i = 0; i < 7; i++) {
      const z = -0.45 + i * 0.15;
      const tone = i % 2 === 0 ? Tone.wood : Tone.woodLight;
      box(pivot, 1.04, 0.014, 0.146, 0.005, Clay.matte(tone, 0.7), [0, 0.007, z]);
    }
  }

  buildWalls() {
    const pivot = this.walls;
    const h = wallHeight;
    const wall = Clay.matte(Tone.wall, 0.95);
    const wood = Clay.matte(Tone.wood);
    const snow = Clay.matte(Tone.snow, 0.6);

    box(pivot, 0.05, h, 1.06, 0.01, wall, [-0.525, h / 2, -0.03]);
    box(pivot, 1.06, h, 0.05, 0.01, wall, [-0.03, h / 2, -0.525]);

    box(pivot, 0.014, 0.05, 1.0, 0.004, wood, [-0.493, 0.025, 0]);
    box(pivot, 1.0, 0.05, 0.014, 0.004, wood, [0, 0.025, -0.493]);

    for (const [x, z] of [
      [-0.535, 0.52],
      [-0.535, -0.535],
      [0.52, -0.535],
    ]) {
      box(pivot, 0.075, h + 0.06, 0.075, 0.012, wood, [x, (h + 0.06) / 2, z]);
    }
    box(pivot, 0.085, 0.065, 1.13, 0.015, wood, [-0.535, h + 0.02, -0.01]);
    box(pivot, 1.13, 0.065, 0.085, 0.015, wood, [-0.01, h + 0.02, -0.535]);

    box(pivot, 0.12, 0.05, 0.42, 0.024, snow, [-0.535, h + 0.07, 0.22]);
    box(pivot, 0.11, 0.04, 0.3, 0.019, snow, [-0.535, h + 0.065, -0.28]);
    sphere(pivot, 0.04, snow, [-0.535, h + 0.075, 0.0], { scale: [1.2, 0.8, 1.4] });
    box(pivot, 0.44, 0.05, 0.12, 0.024, snow, [0.24, h + 0.07, -0.535]);
    box(pivot, 0.26, 0.04, 0.11, 0.019, snow, [-0.3, h + 0.065, -0.535]);
    sphere(pivot, 0.045, snow, [-0.535, h + 0.08, -0.535], { scale: [1.3, 0.9, 1.3] });
  }

  buildWindow() {
    const pivot = this.walls;
    const center = [-0.49, 0.47, 0.02];
    const facingX = quat.z(Math.PI / 2);
    const wood = Clay.matte(Tone.wood);

    cylinder(pivot, 0.03, 0.215, wood, center, { rotation: facingX });
    cylinder(
      pivot,
      0.032,
      0.172,
      Clay.glow(Tone.windowGlow, 2.6),
      [center[0] + 0.003, center[1], center[2]],
      { rotation: facingX },
    );

    for (const dz of [-0.06, 0.06])
      box(pivot, 0.014, 0.34, 0.016, 0.004, wood, [-0.466, center[1], center[2] + dz]);
    for (const dy of [-0.06, 0.06])
      box(pivot, 0.014, 0.016, 0.34, 0.004, wood, [-0.466, center[1] + dy, center[2]]);

    box(pivot, 0.09, 0.022, 0.4, 0.008, Clay.matte(Tone.woodLight), [-0.465, 0.262, 0.02]);
    cylinder(pivot, 0.05, 0.022, Clay.matte(Tone.pot), [-0.46, 0.298, -0.1]);
    sphere(pivot, 0.03, Clay.matte(Tone.leaf), [-0.46, 0.34, -0.1], { scale: [1, 0.8, 1] });
    cylinder(pivot, 0.045, 0.018, Clay.matte(0xf2e6d2, 0.4), [-0.46, 0.295, 0.14]);
  }

  buildShelf() {
    const pivot = this.walls;
    const wood = Clay.matte(Tone.wood);
    const c = [0.27, 0.6, -0.44];
    box(pivot, 0.3, 0.25, 0.014, 0.004, Clay.matte(Tone.woodDark), [c[0], c[1], -0.494]);
    for (const dy of [-0.125, 0, 0.125])
      box(pivot, 0.33, 0.02, 0.12, 0.006, wood, [c[0], c[1] + dy, c[2]]);
    for (const dx of [-0.155, 0.155])
      box(pivot, 0.02, 0.27, 0.12, 0.006, wood, [c[0] + dx, c[1], c[2]]);

    const bookTones = [0xc0563a, 0x7c9a7e, 0xe3b45c, 0x9a7bb8, 0xda8e6b, 0x6f8fb0];
    let x = c[0] - 0.13;
    bookTones.forEach((tone, i) => {
      const h = 0.075 + (i % 3) * 0.012;
      box(pivot, 0.024, h, 0.085, 0.004, Clay.matte(tone), [x, c[1] - 0.115 + h / 2, c[2]]);
      x += 0.028;
    });
    box(pivot, 0.12, 0.022, 0.085, 0.004, Clay.matte(0xe3b45c), [c[0] - 0.06, c[1] + 0.021, c[2]]);
    box(pivot, 0.11, 0.022, 0.08, 0.004, Clay.matte(0xc0563a), [c[0] - 0.06, c[1] + 0.043, c[2]]);
    cylinder(pivot, 0.07, 0.025, Clay.glow(0xffe7b8, 0.6), [c[0] + 0.08, c[1] + 0.045, c[2]]);

    const facingZ = quat.x(Math.PI / 2);
    cylinder(pivot, 0.02, 0.075, wood, [-0.2, 0.58, -0.49], { rotation: facingZ });
    cylinder(pivot, 0.022, 0.058, Clay.matte(0xfbebd3, 0.3), [-0.2, 0.58, -0.488], {
      rotation: facingZ,
    });
  }

  buildFairyLights() {
    const material = Clay.glow(Tone.bulb, 4);
    const top = wallHeight - 0.05;
    const count = 13;
    for (let i = 0; i < count; i++) {
      const t = i / (count - 1);
      const sag = 0.05 * Math.abs(Math.sin(t * Math.PI * 2));
      this.bulbs.push(sphere(this.walls, 0.011, material, [-0.47 + t * 0.94, top - sag, -0.47]));
      this.bulbs.push(sphere(this.walls, 0.011, material, [-0.47, top - sag, -0.47 + t * 0.94]));
    }
  }

  buildRug() {
    cylinder(this.pivot, 0.006, 0.33, Clay.matte(Tone.rugEdge, 1), [0.0, 0.016, 0.04]);
    cylinder(this.pivot, 0.008, 0.31, Clay.matte(Tone.rug, 1), [0.0, 0.019, 0.04]);
  }

  buildCatBed() {
    const bed = group(this.pivot, bedCenter);
    bed.scale.setScalar(bedScale);
    cylinder(bed, 0.05, 0.19, Clay.matte(Tone.plushShade, 1), [0, 0.03, 0]);
    cylinder(bed, 0.03, 0.15, Clay.matte(Tone.plush, 1), [0, 0.06, 0]);
    const lumps = 24;
    for (let i = 0; i < lumps; i++) {
      const a = (i / lumps) * 2 * Math.PI;
      const wobble = 1 + 0.06 * Math.sin(i * 2.7);
      sphere(
        bed,
        0.06 * wobble,
        Clay.matte(i % 2 === 0 ? Tone.plush : Tone.plushShade, 1),
        [Math.cos(a) * 0.165, 0.085, Math.sin(a) * 0.165],
        { scale: [1, 0.82, 1] },
      );
    }
    for (let i = 0; i < 40; i++) {
      const a = (i / 40) * 2 * Math.PI + 0.08;
      const r = 0.165 + 0.02 * Math.sin(i * 5.1);
      sphere(bed, 0.022, Clay.matte(Tone.plush, 1), [
        Math.cos(a) * r,
        0.128 + 0.008 * Math.sin(i * 3.3),
        Math.sin(a) * r,
      ]);
    }
  }

  /** Mochi sits inside the bed's ring of lumps. */
  buildCat() {
    super.buildCat(
      [bedCenter[0], bedCenter[1] + 0.072 * bedScale, bedCenter[2] + 0.01],
      0.75 + Math.PI,
    );
  }

  buildCatTree() {
    const tree = group(this.pivot, [0.36, 0.014, -0.36]);
    const rope = Clay.matte(0xd9b98c, 1);
    const carpet = Clay.matte(Tone.plushShade, 1);
    box(tree, 0.2, 0.03, 0.2, 0.012, carpet, [0, 0.015, 0]);
    cylinder(tree, 0.32, 0.032, rope, [0, 0.18, 0]);
    for (let y = 0.05; y < 0.34; y += 0.025)
      cylinder(tree, 0.006, 0.034, Clay.matte(0xc8a576, 1), [0, y, 0]);
    cylinder(tree, 0.03, 0.1, carpet, [0, 0.35, 0]);
    cylinder(tree, 0.018, 0.075, Clay.matte(Tone.blanket, 1), [0, 0.373, 0]);
    cylinder(tree, 0.12, 0.002, Clay.matte(Tone.ink), [0.08, 0.28, 0.04]);
    sphere(tree, 0.022, Clay.matte(Tone.blanket), [0.08, 0.21, 0.04]);
  }

  buildNightstand() {
    const wood = Clay.matte(Tone.wood);
    const n = group(this.pivot, [-0.39, 0.0, 0.33]);
    box(n, 0.2, 0.2, 0.22, 0.012, wood, [0, 0.112, 0]);
    for (const y of [0.07, 0.155]) {
      box(n, 0.012, 0.072, 0.18, 0.004, Clay.matte(Tone.woodLight), [0.104, y, 0]);
      sphere(n, 0.01, Clay.matte(Tone.woodDark), [0.114, y, 0]);
    }

    cylinder(n, 0.06, 0.022, Clay.matte(0xfff3e0, 0.6), [-0.02, 0.242, 0.05]);
    this.flame = sphere(n, 0.011, Clay.glow(Tone.flame, 8), [-0.02, 0.287, 0.05], {
      scale: [0.85, 1.45, 0.85],
    });
    this.candleLight = pointLight(n, [0.02, 0.33, 0.05], 0xffaa55, 900, 0.7);

    cylinder(n, 0.06, 0.034, Clay.matte(Tone.pot), [0.0, 0.242, -0.06]);
    for (let i = 0; i < 6; i++) {
      const a = (i / 6) * 2 * Math.PI;
      sphere(
        n,
        0.03,
        Clay.matte(i % 2 === 0 ? Tone.leaf : Tone.leafDark),
        [Math.cos(a) * 0.022, 0.3 + (i % 2) * 0.02, -0.06 + Math.sin(a) * 0.022],
        {
          scale: [0.55, 1.1, 0.55],
          rotation: quat.z(Math.cos(a) * 0.5).multiply(quat.x(Math.sin(a) * 0.5)),
        },
      );
    }
  }

  buildCornerProps() {
    const pivot = this.pivot;
    const corner = group(pivot, [-0.4, 0.014, -0.4]);
    cylinder(corner, 0.1, 0.055, Clay.matte(Tone.pot), [0, 0.05, 0]);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * 2 * Math.PI;
      const tilt = 0.35 + (i % 3) * 0.12;
      sphere(
        corner,
        0.06,
        Clay.matte(i % 2 === 0 ? Tone.leaf : Tone.leafDark),
        [Math.cos(a) * 0.035, 0.17 + (i % 3) * 0.03, Math.sin(a) * 0.035],
        { scale: [0.35, 1.3, 0.12], rotation: quat.y(-a).multiply(quat.z(-tilt)) },
      );
    }

    const basket = group(pivot, [0.37, 0.014, 0.36]);
    cylinder(basket, 0.08, 0.07, Clay.matte(0xc9a06a), [0, 0.04, 0]);
    cylinder(basket, 0.082, 0.058, Clay.matte(0x8f6a43), [0, 0.042, 0]);
    sphere(basket, 0.03, Clay.matte(Tone.blanket), [-0.02, 0.09, 0.0]);
    sphere(basket, 0.028, Clay.matte(0xf2d3a0), [0.025, 0.088, 0.015]);
    sphere(basket, 0.026, Clay.matte(0x9db08a), [0.0, 0.092, -0.03]);

    const stool = group(pivot, [-0.1, 0.014, -0.42]);
    box(stool, 0.11, 0.16, 0.11, 0.01, Clay.matte(Tone.wood), [0, 0.08, 0]);
    cylinder(stool, 0.012, 0.03, Clay.matte(Tone.woodDark), [0, 0.166, 0]);
    cylinder(stool, 0.07, 0.006, Clay.matte(Tone.woodDark), [0, 0.2, 0]);
    cylinder(stool, 0.055, 0.042, Clay.glow(0xffe2ae, 2.2), [0, 0.255, 0]);
    pointLight(stool, [-0.05, 0.3, 0.08], 0xffc27a, 1500, 0.9);

    box(pivot, 0.12, 0.024, 0.09, 0.005, Clay.matte(0x7c9a7e), [0.2, 0.026, 0.4], {
      rotation: quat.y(0.3),
    });
    box(pivot, 0.1, 0.022, 0.08, 0.005, Clay.matte(0xe3b45c), [0.2, 0.049, 0.4], {
      rotation: quat.y(0.1),
    });
  }

  buildLighting() {
    const sun = new THREE.DirectionalLight(Lighting.sun.color, Lighting.sun.intensity);
    sun.position.set(1.4, 2.2, 0.9);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    Object.assign(sun.shadow.camera, {
      left: -0.9,
      right: 0.9,
      top: 0.9,
      bottom: -0.9,
      near: 0.5,
      far: 5,
    });
    sun.shadow.bias = -0.0005;
    sun.shadow.normalBias = 0.01;
    this.root.add(sun);

    pointLight(this.pivot, [-0.3, 0.47, 0.02], Lighting.window, 4500, 1.3);
  }
}

/** Warm two-tone environment for image-based light, like the app's generated gradient. */
export function gradientEnvironment(renderer, { top, bottom } = Lighting.environment) {
  const canvas = document.createElement("canvas");
  canvas.width = 64;
  canvas.height = 32;
  const ctx = canvas.getContext("2d");
  const gradient = ctx.createLinearGradient(0, 0, 0, 32);
  gradient.addColorStop(0, top);
  gradient.addColorStop(1, bottom);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 64, 32);
  const texture = new THREE.CanvasTexture(canvas);
  texture.mapping = THREE.EquirectangularReflectionMapping;
  texture.colorSpace = THREE.SRGBColorSpace;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromEquirectangular(texture).texture;
  pmrem.dispose();
  return env;
}

export { Lighting };
