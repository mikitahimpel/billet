// What every room shares: the turning pivot, the wall group, Mochi with her rig and pet bounce, and the dust motes.
import * as THREE from "three";
import { SplatMesh } from "@sparkjsdev/spark";
import { quat, group } from "./kit.js";
import { CatWalker } from "./cat-walker.js";
import { CatShadow } from "./cat-shadow.js";
import catUrl from "./assets/cat-standing.spz?url";
import seatUrl from "./assets/cat-sit.spz?url";

// cat-standing.spz is modeled 0.26 m tall on all fours (the rig is measured in that space); in a room Mochi sits
// about as tall as a nightstand.
const catScale = 0.5 * (0.162 / 0.152);

// RealityKit's lumens don't carry over to three.js; this factor was tuned by eye.
export const lumensToCandela = 0.00027;

export function pointLight(parent, at, color, lumens, radius) {
  const light = new THREE.PointLight(color, lumens * lumensToCandela, radius, 2);
  light.position.set(...at);
  parent.add(light);
  return light;
}

// Splats are unlit, so their baked fur is tinted by the light falling on them: this far toward its hue (1 would
// multiply by it outright), and darkened with it down to `minBrightness` against the Room's daytime light.
const tintStrength = 0.85;
const minBrightness = 0.45;
const referenceLight = 3.4;

export class CatRoom {
  constructor() {
    this.root = new THREE.Group();
    this.pivot = group(this.root);
    // Everything mounted on the two walls, so the walls can be hidden to look in from behind.
    this.walls = group(this.pivot);
    /** Splat meshes that take on the room's light, see tintSplats. */
    this.tinted = [];
    this.time = 0;
    this.yaw = 0;
    this.targetYaw = 0;
    this.purrStart = -10;
  }

  // MARK: - Interaction

  setYaw(value) {
    this.targetYaw = Math.min(Math.max(value, -0.75), 0.75);
  }

  isCat(object) {
    for (let n = object; n; n = n.parent) if (n === this.catGroup) return true;
    return false;
  }

  purr() {
    this.purrStart = this.time;
    this.cat.pet();
  }

  /** Makes Mochi look toward a world-space point, or stop following when null. */
  lookAt(worldPoint) {
    this.cat.lookAt(worldPoint && this.catModel.worldToLocal(worldPoint.clone()));
  }

  /** Tells Mochi where the camera is, a world-space point. */
  watch(worldPoint) {
    this.cat.watch(this.catModel.worldToLocal(worldPoint.clone()));
  }

  /** World-space height of Mochi's eyes, for aiming the pointer ray. */
  eyeHeight() {
    return this.catModel.localToWorld(this.cat.eyes()).y;
  }

  /** A point just above her head. */
  catAnchor() {
    return this.catModel.localToWorld(this.cat.eyes().add(new THREE.Vector3(0, 0.11, 0)));
  }

  /** Advances the clock, the room's idle sway and Mochi's pet bounce and rig. */
  tickRoom(dt) {
    this.time += dt;
    const t = this.time;

    this.yaw += (this.targetYaw - this.yaw) * Math.min(1, dt * 8);
    this.pivot.quaternion.copy(quat.y(this.yaw + 0.035 * Math.sin(t * 0.35)));

    const p = t - this.purrStart;
    const bounce = p < 0.7 ? Math.sin((p / 0.7) * Math.PI * 3) * (1 - p / 0.7) * 0.12 : 0;
    this.catBody.scale.set(1 + 0.4 * bounce, 1 - bounce, 1 + 0.4 * bounce);
    this.cat.update(dt);
    this.catShadow.update();
  }

  /**
   * Mochi on her skeleton, sitting at `at` facing `yaw`; with a route she walks between its two ends instead (see
   * CatWalker), `yaw` then being her yaws at its start and end.
   */
  buildCat(at, yaw, route = null) {
    this.catGroup = group(this.pivot, at);
    this.catBody = group(this.catGroup);
    this.catModel = group(this.catBody);
    this.catModel.scale.setScalar(catScale);
    const splat = new SplatMesh({ url: catUrl });
    const seat = new SplatMesh({ url: seatUrl });
    this.catModel.add(splat, seat);
    this.tinted.push(splat, seat);
    this.cat = new CatWalker(
      { group: this.catGroup, splat, seat, scale: catScale },
      [yaw].flat(),
      route,
    );

    // Invisible hit box, same as the app's CollisionComponent.
    const hit = new THREE.Mesh(
      new THREE.BoxGeometry(0.5, 0.4, 0.5),
      new THREE.MeshBasicMaterial({ visible: false }),
    );
    hit.position.set(0, 0.11, 0);
    this.catModel.add(hit);
    this.catHitBox = hit;
    this.catShadow = new CatShadow({
      pivot: this.pivot,
      cat: this.catGroup,
      model: this.catModel,
      rig: this.cat.rig,
      scale: catScale,
    });
  }

  /**
   * Sets each tinted splat's recolor to the light at it: the room's lights summed the way three.js shades a matte
   * surface, plus the image-based light (`environment` color times `environmentIntensity`). Call once per frame.
   */
  tintSplats(environment, environmentIntensity) {
    this.lights ??= collectLights(this.root);
    const light = tintLight,
      at = tintPoint;
    for (const mesh of this.tinted) {
      mesh.getWorldPosition(at);
      at.y += 0.05;
      lightAt(this.lights, at, light).add(
        scaled.copy(environment).multiplyScalar(Math.PI * environmentIntensity),
      );
      const level = luminance(light);
      const brightness = THREE.MathUtils.clamp(Math.sqrt(level / referenceLight), minBrightness, 1);
      mesh.recolor
        .setRGB(1, 1, 1)
        .lerp(light.multiplyScalar(1 / Math.max(level, 1e-4)), tintStrength)
        .multiplyScalar(brightness)
        .convertLinearToSRGB();
    }
  }

  /** Warm dust motes rising through a 1.3 x 0.9 x 1.3 box, like the app's particle emitter. */
  buildMotes(color = 0xffd58a) {
    const count = 70;
    this.moteData = Array.from({ length: count }, () => ({
      age: Math.random() * 5,
      pos: randomMote(),
    }));
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(new Float32Array(count * 3), 3),
    );
    geometry.setAttribute("alpha", new THREE.Float32BufferAttribute(new Float32Array(count), 1));
    const material = new THREE.ShaderMaterial({
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      uniforms: { color: { value: new THREE.Color(color) }, size: { value: 0.007 } },
      vertexShader: `
        attribute float alpha; varying float vAlpha; uniform float size;
        void main() {
          vAlpha = alpha;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = size * projectionMatrix[1][1] * 600.0 / -mv.z;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: `
        varying float vAlpha; uniform vec3 color;
        void main() {
          float d = length(gl_PointCoord - 0.5);
          gl_FragColor = vec4(color, vAlpha * smoothstep(0.5, 0.0, d));
        }`,
    });
    this.motes = new THREE.Points(geometry, material);
    this.motes.position.set(0, 0.45, 0);
    this.pivot.add(this.motes);
  }

  tickMotes(dt) {
    const position = this.motes.geometry.attributes.position;
    const alpha = this.motes.geometry.attributes.alpha;
    this.moteData.forEach((m, i) => {
      m.age += dt;
      if (m.age > 5) Object.assign(m, { age: 0, pos: randomMote() });
      m.pos[1] += dt * (0.01 + 0.004 * m.age);
      position.setXYZ(i, ...m.pos);
      alpha.setX(i, Math.sin((m.age / 5) * Math.PI));
    });
    position.needsUpdate = true;
    alpha.needsUpdate = true;
  }
}

function collectLights(root) {
  const lights = [];
  root.traverse((o) => {
    if (o.isDirectionalLight || o.isPointLight) lights.push(o);
  });
  return lights;
}

const lightPosition = new THREE.Vector3();
const scaled = new THREE.Color();
const tintLight = new THREE.Color();
const tintPoint = new THREE.Vector3();

/** Irradiance at `point` from directional and point lights, averaged over a sphere's normals (half face any light). */
function lightAt(lights, point, out) {
  out.setRGB(0, 0, 0);
  for (const light of lights) {
    if (!light.visible || !light.parent?.visible) continue;
    let falloff = 0.5;
    if (light.isPointLight) {
      // three.js's getDistanceAttenuation.
      const d = light.getWorldPosition(lightPosition).distanceTo(point);
      falloff *= 1 / Math.max(d ** light.decay, 0.01);
      if (light.distance > 0)
        falloff *= THREE.MathUtils.clamp(1 - (d / light.distance) ** 4, 0, 1) ** 2;
    }
    out.add(scaled.copy(light.color).multiplyScalar(light.intensity * falloff));
  }
  return out;
}

function luminance(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

function randomMote() {
  return [(Math.random() - 0.5) * 1.3, (Math.random() - 0.5) * 0.9, (Math.random() - 0.5) * 1.3];
}
