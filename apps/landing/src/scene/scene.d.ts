import type * as THREE from "three";

export class DioramaScene {
  root: THREE.Group;
  pivot: THREE.Group;
  walls: THREE.Group;
  targetYaw: number;
  catHitBox: THREE.Object3D;
  tick(dt: number): void;
  watch(point: THREE.Vector3): void;
  tintSplats(environment: THREE.Color, intensity: number): void;
  setYaw(value: number): void;
  purr(): void;
  lookAt(point: THREE.Vector3 | null): void;
  eyeHeight(): number;
  catAnchor(): THREE.Vector3;
}

export const Lighting: {
  exposure: number;
  environment: { top: string; bottom: string; intensity: number };
};

export function gradientEnvironment(renderer: THREE.WebGLRenderer): THREE.Texture;
