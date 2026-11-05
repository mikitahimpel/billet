// How a cat's body moves, independent of any one splat: a two-bone leg solver, a walking gait and a springy tail.
// Model space: front toward -Z, up +Y, paws on y = 0.
import * as THREE from "three";

/** Angle of a vector in the side (y, z) plane, measured the way a rotation about +X turns it. */
const sideAngle = (y, z) => Math.atan2(z, y);
/** Angle of a vector in the front (x, y) plane, measured the way a rotation about +Z turns a leg hanging down. */
const frontAngle = (x, y) => Math.atan2(x, -y);
const up = new THREE.Vector3(0, 1, 0);
const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * Bends a leg so its paw reaches `foot`. `hip`, `knee` and `paw` are the rest joints in the leg's parent frame,
 * `foot` the target in that frame. The leg swings out about +Z at the hip to the target's side, then bends in its rest
 * plane, folding the way it does at rest (back for a cat's elbow, forward for the knee). Returns the upper bone's turn
 * about the hip and the lower bone's turn about the knee relative to the upper, both about +X, and the swing out.
 */
export function solveLeg(hip, knee, paw, target) {
  const splay = wrap(
    frontAngle(target.x - hip.x, target.y - hip.y) - frontAngle(paw.x - hip.x, paw.y - hip.y),
  );
  const foot = target
    .clone()
    .sub(hip)
    .applyAxisAngle(new THREE.Vector3(0, 0, 1), -splay)
    .add(hip);
  const upper = Math.hypot(knee.y - hip.y, knee.z - hip.z);
  const lower = Math.hypot(paw.y - knee.y, paw.z - knee.z);
  const dy = foot.y - hip.y;
  const dz = foot.z - hip.z;
  const reach = THREE.MathUtils.clamp(
    Math.hypot(dy, dz),
    Math.abs(upper - lower) + 1e-4,
    upper + lower - 1e-4,
  );
  const opening = Math.acos(
    THREE.MathUtils.clamp(
      (upper * upper + reach * reach - lower * lower) / (2 * upper * reach),
      -1,
      1,
    ),
  );
  const restUpper = sideAngle(knee.y - hip.y, knee.z - hip.z);
  const bend = Math.sign(Math.sin(restUpper - sideAngle(paw.y - hip.y, paw.z - hip.z))) || 1;
  const upperAngle = sideAngle(dy, dz) + bend * opening;
  const kneeY = hip.y + upper * Math.cos(upperAngle);
  const kneeZ = hip.z + upper * Math.sin(upperAngle);
  const lowerAngle = sideAngle(foot.y - kneeY, foot.z - kneeZ);
  const restLower = sideAngle(paw.y - knee.y, paw.z - knee.z);
  // Wrapped, since legs point straight down where the angle crosses ±π.
  const turnUpper = wrap(upperAngle - restUpper);
  return [turnUpper, wrap(lowerAngle - restLower - turnUpper), splay];
}

// A walk: each paw on the ground for 60% of the cycle, set down in the order left hind, left fore, right hind,
// right fore, a quarter cycle apart.
const duty = 0.6;
export const legOrder = ["leftHind", "leftFore", "rightHind", "rightFore"];
const phaseOffset = { leftHind: 0, leftFore: 0.25, rightHind: 0.5, rightFore: 0.75 };

/**
 * Where the body stands in the room: `at` its origin and `yaw` about +Y, `scale` room units per model unit, and
 * `velocity` (room units/s) and `yawRate` (rad/s) to tell where it will be a moment later.
 */
const toRoom = (frame, p, out = new THREE.Vector3()) =>
  out.copy(p).multiplyScalar(frame.scale).applyAxisAngle(up, frame.yaw).add(frame.at);
const toModel = (frame, p, out = new THREE.Vector3()) =>
  out.copy(p).sub(frame.at).applyAxisAngle(up, -frame.yaw).divideScalar(frame.scale);
const ahead = (frame, seconds) => ({
  ...frame,
  at: frame.at.clone().addScaledVector(frame.velocity, seconds),
  yaw: frame.yaw + frame.yawRate * seconds,
});

/**
 * A walk that keeps each paw where it was set down: a paw in stance holds its spot in the room whatever the body does,
 * and a swing carries it to where its stance spot will be halfway through its next stance. Walking, that spot is
 * halfway from the rest paw to under the hip, so the stride stays within the leg's reach. The cycle runs slower at a
 * slow walk and stops once every paw has stepped back to its rest spot.
 */
export class Gait {
  /**
   * `legs` maps each leg to its `hip` and rest `paw` in model space; `speed` (model units/s) is where the cycle takes
   * `period`.
   */
  constructor(legs, { period = 0.55, speed = 0.26, lift = 0.022 } = {}) {
    this.basePeriod = this.period = period;
    this.speed = speed;
    this.lift = lift;
    this.phase = 0;
    this.amount = 0; // 0 standing, 1 walking; eased so the body's rocking starts and stops softly
    this.legs = Object.fromEntries(
      Object.entries(legs).map(([name, { hip, paw }]) => [
        name,
        {
          rest: paw.clone(),
          stride: paw.clone().setZ((paw.z + hip.z) / 2),
          anchor: null,
          from: new THREE.Vector3(),
          swinging: false,
          done: true,
        },
      ]),
    );
  }

  /**
   * Advances the cycle and the paws. `stepping` keeps the paws moving even without ground speed (turning on the spot);
   * without `planted` the paws ride with the body (in the air) and are set down again where they are.
   */
  update(dt, frame, stepping, planted = true) {
    const pace = Math.max(frame.velocity.length() / frame.scale, Math.abs(frame.yawRate) * 0.12);
    const moving = planted && (stepping || pace > 1e-3);
    const legs = Object.values(this.legs);
    for (const leg of legs) {
      if (!planted || !leg.anchor) {
        leg.anchor = toRoom(frame, leg.rest, leg.anchor ?? undefined);
        leg.swinging = false;
        leg.done = true;
      } else if (moving) {
        leg.done = false;
      } else if (!leg.swinging && !leg.done) {
        // Coming to a stop: a paw already under the body stays; the others take one more step.
        leg.done = toModel(frame, leg.anchor).distanceTo(leg.rest) < 0.004;
      }
    }
    const active = legs.some((leg) => !leg.done);
    this.amount += ((moving ? 1 : 0) - this.amount) * (1 - Math.exp(-dt * 6));
    this.period =
      this.basePeriod * THREE.MathUtils.clamp(Math.sqrt(this.speed / Math.max(pace, 1e-3)), 1, 1.6);
    if (active) this.phase = (this.phase + dt / this.period) % 1;

    for (const [name, leg] of Object.entries(this.legs)) {
      if (leg.done) continue;
      const u = (this.phase + phaseOffset[name]) % 1;
      if (u >= duty && !leg.swinging) {
        leg.swinging = true;
        leg.from.copy(leg.anchor);
      } else if (u < duty && leg.swinging) {
        leg.swinging = false;
        leg.anchor.copy(this.touchdown(frame, leg, 1, moving));
        if (!moving) leg.done = true;
      }
    }
    this.frame = frame;
    this.moving = moving;
  }

  /** Where a swinging paw lands, `w` of the way through its swing; once stopping, back at its rest spot. */
  touchdown(frame, leg, w, moving = this.moving) {
    const swing = (1 - duty) * this.period;
    return toRoom(
      ahead(frame, (1 - w) * swing + (duty * this.period) / 2),
      moving ? leg.stride : leg.rest,
    );
  }

  /** Paw position in model space. */
  foot(name, out = new THREE.Vector3()) {
    const leg = this.legs[name];
    if (!leg.swinging) return toModel(this.frame, leg.anchor, out);
    const u = (this.phase + phaseOffset[name]) % 1;
    const w = (u - duty) / (1 - duty);
    const target = this.touchdown(this.frame, leg, w);
    const step = leg.from.distanceTo(target) / this.frame.scale;
    toModel(this.frame, leg.from.clone().lerp(target, w * w * (3 - 2 * w)), out);
    // A short settling step barely clears the floor.
    out.y += this.lift * Math.min(1, 0.3 + step / 0.03) * Math.sin(w * Math.PI);
    return out;
  }

  /**
   * The body walks a little low and dips as each paw takes its weight, twice per side per cycle, rocks nose down as the
   * weight passes to the fore paws, and rolls toward the planted side.
   */
  body() {
    const a = this.phase * Math.PI * 2;
    const m = this.amount;
    const y = -m * (0.012 + 0.004 * (1 - Math.cos(2 * a)) * 0.5);
    return { y, pitch: 0.012 * m * Math.sin(2 * a), roll: 0.025 * m * Math.sin(a) };
  }
}

/**
 * The tail as a chain of damped springs on top of whatever the motion poses: the body's accelerations push each joint
 * off its posed angle, and each is pulled back toward its parent's swing, so the tip lags most and overshoots last.
 * `bones` are the joints' rest directions in model space.
 */
export class TailSpring {
  constructor(bones, { frequency = [11, 8, 6], damping = 0.3, gain = 3, limit = 0.7 } = {}) {
    this.joints = bones.map((dir, i) => ({
      dir: dir.clone().normalize(),
      k: frequency[i] ** 2,
      c: 2 * damping * frequency[i],
      lean: 0,
      leanSpeed: 0,
      lift: 0,
      liftSpeed: 0,
    }));
    this.gain = gain;
    this.limit = limit;
  }

  /** `force` is the inertial push on the tail per unit mass, model units/s² in the body's frame: minus its acceleration. */
  update(dt, force) {
    const steps = Math.ceil(dt * 240);
    const h = dt / steps;
    const rest = { lean: 0, leanSpeed: 0, lift: 0, liftSpeed: 0 };
    for (let n = 0; n < steps; n++) {
      let parent = rest;
      for (const j of this.joints) {
        // Torques of the push on the bone, about +Z for leaning and about -X for lifting.
        const leanTorque = j.dir.x * force.y - j.dir.y * force.x;
        const liftTorque = j.dir.z * force.y - j.dir.y * force.z;
        const lean = j.k * (j.lean - parent.lean) + j.c * (j.leanSpeed - parent.leanSpeed);
        const lift = j.k * (j.lift - parent.lift) + j.c * (j.liftSpeed - parent.liftSpeed);
        j.leanSpeed += h * (this.gain * leanTorque - lean);
        j.liftSpeed += h * (this.gain * liftTorque - lift);
        j.lean = THREE.MathUtils.clamp(j.lean + h * j.leanSpeed, -this.limit, this.limit);
        j.lift = THREE.MathUtils.clamp(j.lift + h * j.liftSpeed, -this.limit, this.limit);
        parent = j;
      }
    }
  }
}
