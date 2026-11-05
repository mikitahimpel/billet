// Splats neither cast nor receive three.js shadows, so Mochi gets a contact shadow of her own: a soft oval under her
// body and a spot under each paw that touches down, laid on whatever is below her and fading as she leaves it.
// Five textured quads and five downward rays a frame, simple enough to port to RealityKit as is.
import * as THREE from "three";

const smoothstep = THREE.MathUtils.smoothstep;
// Model units: the rig's paw centers sit this far above the surface they stand on.
const pawRadius = 0.012;
// Model units: the body oval and a paw spot.
const body = { width: 0.17, length: 0.32 };
const pawSize = 0.06;
// Room units of height over which the body shadow shrinks and fades away.
const reach = 0.25;

export class CatShadow {
  /** `cat` is the group she moves in, `model` the scaled group her rig's paw targets live in, both under `pivot`. */
  constructor({ pivot, cat, model, rig, scale }) {
    Object.assign(this, { pivot, cat, model, rig, scale });
    const map = softSpot();
    const quad = new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2);
    const make = () => {
      // Black at partial opacity darkens what is below by that much, like a multiply, under any light.
      const material = new THREE.MeshBasicMaterial({
        map,
        transparent: true,
        depthWrite: false,
        fog: false,
        polygonOffset: true,
        polygonOffsetFactor: -1,
        polygonOffsetUnits: -4,
      });
      const mesh = new THREE.Mesh(quad, material);
      mesh.matrixAutoUpdate = false;
      // Before Spark's splats, which don't write depth and would otherwise be drawn over.
      mesh.renderOrder = -1;
      pivot.add(mesh);
      return mesh;
    };
    this.body = make();
    this.paws = Object.keys(rig.pose.feet).map(make);
    this.raycaster = new THREE.Raycaster();
    this.toPivot = new THREE.Matrix4();
    this.fromWorld = new THREE.Matrix4();
  }

  /** The room's solid meshes, gathered once the room is built. */
  collect() {
    const skip = new Set([this.body, ...this.paws]);
    this.cat.traverse((o) => skip.add(o));
    const surfaces = [];
    this.pivot.traverse((o) => {
      if (o.isMesh && !skip.has(o) && [o.material].flat().some((m) => m.visible && !m.transparent))
        surfaces.push(o);
    });
    return surfaces;
  }

  update() {
    this.surfaces ??= this.collect();
    // Her pose is fresh this frame but the room's world matrices are last frame's, so work in the pivot's space.
    this.toPivot.identity();
    for (let n = this.model; n !== this.pivot; n = n.parent) {
      n.updateMatrix();
      this.toPivot.premultiply(n.matrix);
    }
    this.fromWorld.copy(this.pivot.matrixWorld).invert();
    const forward = new THREE.Vector3(0, 0, -1).transformDirection(this.toPivot);

    const center = new THREE.Vector3();
    Object.values(this.rig.pose.feet).forEach((foot, i) => {
      const paw = foot.clone().applyMatrix4(this.toPivot);
      center.add(paw);
      const hit = this.ground(paw, 0.03);
      const height = hit ? paw.y - pawRadius * this.scale - hit.point.y : Infinity;
      const size = pawSize * this.scale;
      // A paw well below the surface found has stepped off its edge.
      place(
        this.paws[i],
        hit,
        forward,
        size,
        size,
        0.45 * (1 - smoothstep(Math.abs(height), 0.004, 0.02)),
      );
    });
    center.divideScalar(this.paws.length);

    const hit = this.ground(center, 0.05);
    const air = hit ? smoothstep(this.cat.position.y - hit.point.y, 0, reach) : 1;
    const size = this.scale * (1 - 0.4 * air);
    place(this.body, hit, forward, body.width * size, body.length * size, 0.5 * (1 - air));
  }

  /** The first visible surface straight below a pivot-space point raised by `above`, in pivot space. */
  ground(at, above) {
    const world = this.pivot.matrixWorld;
    const origin = at
      .clone()
      .setY(at.y + above)
      .applyMatrix4(world);
    this.raycaster.set(origin, new THREE.Vector3(0, -1, 0).transformDirection(world));
    const hit = this.raycaster
      .intersectObjects(this.surfaces, false)
      .find((h) => visible(h.object));
    if (!hit) return null;
    const normal = hit.face.normal
      .clone()
      .transformDirection(hit.object.matrixWorld)
      .transformDirection(this.fromWorld);
    if (normal.y < 0) normal.negate();
    return { point: hit.point.applyMatrix4(this.fromWorld), normal };
  }
}

/** Lays a quad flat on the hit surface, `length` along her heading. */
function place(mesh, hit, forward, width, length, opacity) {
  mesh.visible = Boolean(hit) && opacity > 0.01;
  if (!mesh.visible) return;
  mesh.material.opacity = opacity;
  const n = hit.normal;
  const z = forward.clone().addScaledVector(n, -forward.dot(n)).normalize();
  const x = new THREE.Vector3().crossVectors(n, z);
  mesh.matrix.makeBasis(x.multiplyScalar(width), n, z.multiplyScalar(length));
  mesh.matrix.setPosition(hit.point.addScaledVector(n, 0.0005));
}

function visible(object) {
  for (let o = object; o; o = o.parent) if (!o.visible) return false;
  return true;
}

/** A black spot with a soft, roughly Gaussian edge. */
function softSpot() {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 64;
  const g = canvas.getContext("2d");
  const gradient = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  [
    [0, 1],
    [0.3, 0.8],
    [0.6, 0.35],
    [0.85, 0.08],
    [1, 0],
  ].forEach(([at, a]) => gradient.addColorStop(at, `rgba(0,0,0,${a})`));
  g.fillStyle = gradient;
  g.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(canvas);
}
