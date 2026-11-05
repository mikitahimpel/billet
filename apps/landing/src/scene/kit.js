// Ports of Nooki/Scene/Kit.swift: clay materials and primitive builders with RealityKit's parameter order.
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";

export const Clay = {
  matte(hex, roughness = 0.82) {
    return new THREE.MeshStandardMaterial({ color: hex, roughness, metalness: 0 });
  },
  glow(hex, intensity) {
    const m = Clay.matte(hex);
    m.emissive = new THREE.Color(hex);
    m.emissiveIntensity = intensity;
    return m;
  },
};

export const quat = {
  x: (a) => new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), a),
  y: (a) => new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), a),
  z: (a) => new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), a),
};

function place(parent, mesh, at, { scale = [1, 1, 1], rotation } = {}) {
  mesh.position.set(...at);
  mesh.scale.set(...scale);
  if (rotation) mesh.quaternion.copy(rotation);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  parent.add(mesh);
  return mesh;
}

export function box(parent, w, h, d, r, material, at, options) {
  const radius = Math.max(Math.min(r, Math.min(w, h, d) / 2 - 0.0005), 0);
  return place(
    parent,
    new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 3, radius), material),
    at,
    options,
  );
}

export function sphere(parent, radius, material, at, options) {
  return place(
    parent,
    new THREE.Mesh(new THREE.SphereGeometry(radius, 32, 16), material),
    at,
    options,
  );
}

export function cylinder(parent, height, radius, material, at, options) {
  return place(
    parent,
    new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, height, 48), material),
    at,
    options,
  );
}

export function group(parent, at = [0, 0, 0], rotation) {
  const g = new THREE.Group();
  g.position.set(...at);
  if (rotation) g.quaternion.copy(rotation);
  parent.add(g);
  return g;
}
