// Mochi on her skeleton: rests at one of two spots and walks or jumps a route between them.
import * as THREE from "three";
import { CatRig, CatBehavior, Pose, noise } from "./cat-rig.js";
import { CatSeat } from "./cat-seat.js";
import rig from "./assets/cat-standing.rig.json";
import skinUrl from "./assets/cat-standing.skin?url";
import { Gait, TailSpring, legOrder } from "./cat-gait.js";

const up = new THREE.Vector3(0, 1, 0);
const facing = (dx, dz) => Math.atan2(-dx, -dz);
const lerp = THREE.MathUtils.lerp;
const ease = (t) => t * t * (3 - 2 * t);
const shortest = (a, b) => a + Math.atan2(Math.sin(b - a), Math.cos(b - a));
const random = (min, max) => min + Math.random() * (max - min);
const spin = (pivot, x, y, z) =>
  Pose.about(pivot, new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, "YXZ")));

// Room units per second.
const walkSpeed = 0.14;
// Seconds she takes to reach that speed from standing, and to stop from it: about one stride.
const rampTime = 0.6;
// Seconds the head takes to follow the body's bob, pitch and roll while walking.
const headLag = 0.3;

/** Postures as rig values; feet are [up, back] offsets from the rest paws in model units,
 * `tail` lifts each tail joint (negative lowers it). */
const still = [0, 0, 0];
const postures = {
  stand: {
    lift: 0,
    back: 0,
    pitch: 0,
    bend: 0,
    headPitch: 0,
    seat: 0,
    fore: [0, 0],
    hind: [0, 0],
    tail: still,
  },
  // The seated splat's silhouette, with the head exactly where cat-sit.ply has it, for the swap
  // between the two (see CatSeat).
  sit: {
    lift: -0.005,
    back: -0.005,
    pitch: 0.5,
    bend: -0.7,
    headPitch: 0,
    seat: 1,
    fore: [0, 0],
    hind: [0, -0.035],
    tail: [-1.1, -0.4, -0.2],
  },
  crouch: {
    lift: -0.03,
    back: 0,
    pitch: 0,
    bend: 0.05,
    headPitch: 0,
    seat: 0,
    fore: [0, 0],
    hind: [0, 0],
    tail: still,
  },
  loaf: {
    lift: -0.065,
    back: 0,
    pitch: 0,
    bend: 0.05,
    headPitch: 0.05,
    seat: 0,
    fore: [0, 0.035],
    hind: [0, -0.03],
    tail: [-0.9, -0.3, -0.1],
  },
};
const blendKeys = ["lift", "back", "pitch", "bend", "headPitch", "seat"];
// Model units the chest and the hips move at a full breath in.
const breathChest = new THREE.Vector3(0, 0.0014, -0.0005);
const breathHips = new THREE.Vector3(0, 0.0003, 0);

/** About 0.4 breaths a second, slower when drowsy, quicker after exertion; `value` is how far in
 * she has breathed, about 0 to 1. */
class Breath {
  constructor() {
    this.phase = Math.random();
    this.value = 0;
    this.next();
  }

  next() {
    this.length = random(0.85, 1.2);
    this.depth = random(0.75, 1.15);
  }

  /** `drowse` and `effort` run from 0 to 1. */
  update(dt, drowse, effort) {
    this.phase += (dt * 0.4 * (1 - 0.35 * drowse) * (1 + 0.7 * effort)) / this.length;
    if (this.phase >= 1) {
      this.phase %= 1;
      this.next();
    }
    // In over the first 40% of a breath, out over the next 45%, then a pause.
    const u = this.phase;
    const shape = u < 0.4 ? ease(u / 0.4) : u < 0.85 ? 1 - ease((u - 0.4) / 0.45) : 0;
    this.value = shape * this.depth * (1 + 0.5 * drowse) * (1 + 0.4 * effort);
  }
}

export class CatWalker {
  /** `scale` turns model units into room units. Without a route she sits facing `rests[0]`; a
   * route [{ at: [x, y, z], move: 'walk' | 'jump' }] runs between two spots with resting yaws
   * `rests`, `move` being how she reaches that point. */
  constructor({ group, splat, seat, scale }, rests, route = null, startAtEnd = true) {
    this.group = group;
    this.scale = scale;
    this.rig = new CatRig(splat, rig, skinUrl);
    this.seat = new CatSeat(seat, splat);
    this.behavior = new CatBehavior(this.rig);
    this.gait = new Gait(this.rig.legs, { speed: walkSpeed / scale });
    this.route = route?.map((p) => ({ ...p, at: new THREE.Vector3(...p.at) }));
    this.rests = rests;
    this.atEnd = startAtEnd;
    this.yaw = route && startAtEnd ? rests[1] : rests[0];
    if (route) this.group.position.copy(this.route[startAtEnd ? this.route.length - 1 : 0].at);
    this.steps = [];
    this.wait = 6 + Math.random() * 6;
    this.time = 0;
    this.posture = { ...postures.sit };
    this.resting = 1;
    this.lookPitch = 0;
    this.gaze = 0;
    this.stepping = false;
    this.free = false;
    this.wiggle = 0;
    this.tread = [0, 0];
    this.frame = {
      at: group.position,
      yaw: this.yaw,
      scale,
      velocity: new THREE.Vector3(),
      yawRate: 0,
    };
    this.last = { at: group.position.clone(), yaw: this.yaw };
    this.steady = { y: 0, pitch: 0, roll: 0 };
    const bone = (b) => new THREE.Vector3(...b.tail).sub(new THREE.Vector3(...b.head));
    this.tail = new TailSpring(this.rig.tailBones.map((i) => bone(rig.bones[i])));
    this.tailBase = this.rig.joint(rig.bones[this.rig.tailBones[0]].name);
    this.tailTrack = [];
    this.tailPush = new THREE.Vector3();
    this.breath = new Breath();
    this.effort = 0;
    this.spine = this.seat.spine;
    this.floor = this.spine.clone().setY(0);
    this.lying = false;
  }

  get moving() {
    return this.steps.length > 0;
  }

  /** Model-space point between her eyes; the two skeletons hold their heads on each other. */
  eyes() {
    return this.rig.eyes();
  }

  lookAt(point) {
    this.behavior.lookAt(point);
  }

  /** Model-space point she sees whoever watches her from. */
  watch(point) {
    this.behavior.watch(point);
  }

  pet() {
    this.behavior.pet();
  }

  update(dt) {
    this.time += dt;
    if (!this.moving && this.route) {
      this.wait -= dt;
      if (this.wait <= 0) this.plan();
    }
    const drowse = this.behavior.drowse;
    if (!this.moving && !this.lying && drowse > 0.7 && this.behavior.mood.energy < 0.3)
      this.lieDown();
    else if (!this.moving && this.lying && this.behavior.mood.energy > 0.5) this.getUp();
    this.behavior.napping = this.lying;
    this.stepping = false;
    this.free = false;
    this.gaze = 0;
    const step = this.steps[0];
    if (step) {
      step.time += dt;
      const u = Math.min(step.time / step.duration, 1);
      step.run(u, dt);
      if (u >= 1) this.steps.shift();
      if (!this.moving) {
        this.atEnd = !this.atEnd;
        this.wait = (10 + Math.random() * 12) * lerp(1.6, 0.6, this.behavior.mood.energy);
      }
    }
    // Resting, she gets her breath back over half a minute or so.
    const winding = this.free ? 0.6 : this.stepping ? 0.1 : 0;
    this.effort = winding
      ? Math.min(1, this.effort + winding * dt)
      : this.effort * Math.exp(-dt / 12);
    this.group.quaternion.setFromAxisAngle(up, this.yaw);
    const frame = this.frame;
    if (dt > 0) {
      frame.velocity.subVectors(this.group.position, this.last.at).divideScalar(dt);
      frame.yawRate = (this.yaw - this.last.yaw) / dt;
    }
    frame.yaw = this.yaw;
    this.last.at.copy(this.group.position);
    this.last.yaw = this.yaw;
    this.behavior.update(dt);
    this.resting += ((this.moving ? 0 : 1) - this.resting) * (1 - Math.exp(-dt * 4));
    this.pose(dt);
    this.seat.update(
      this.rig.pose,
      this.rig.pose.headPitch - this.posture.headPitch,
      this.behavior,
    );
  }

  /** Writes the posture, gait, and the resting behavior as far as she is at rest, into the rig. */
  pose(dt) {
    this.gait.update(dt, this.frame, this.stepping, !this.free);
    const g = this.gait.body();
    const p = this.rig.pose;
    const s = this.posture;
    p.lift = s.lift + g.y;
    p.back = s.back;
    p.pitch = s.pitch + g.pitch;
    p.roll = g.roll;
    p.bend = s.bend;
    p.wiggle = this.wiggle;
    p.headSeat = s.seat;
    const b = this.behavior.state;
    const r = this.resting;
    // Walking she watches the floor ahead.
    this.lookPitch += (this.gaze - this.lookPitch) * (1 - Math.exp(-dt * 4));
    p.headPitch = s.headPitch + lerp(this.lookPitch, b.pitch, r);
    p.headYaw = lerp(0.12 * noise(this.time * 0.5, 8), b.yaw, r);
    p.headRoll = b.roll * r;
    this.steadyHead(dt, g);
    this.settle(dt, r);
    p.earLeft = b.earLeft * r;
    p.earRight = b.earRight * r;
    p.earsBack = b.earsBack * r;
    // On the move the ears point ahead; the eyes blink whatever she does, but droop only at rest.
    p.earTurnLeft = lerp(-0.1, b.earTurnLeft, r);
    p.earTurnRight = lerp(-0.1, b.earTurnRight, r);
    p.lidLeft = Math.max(b.blink, b.lidLeft * r);
    p.lidRight = Math.max(b.blink, b.lidRight * r);
    for (const name of legOrder) {
      const [y, z] = name.endsWith("Fore") ? s.fore : s.hind;
      this.gait.foot(name, p.feet[name]);
      p.feet[name].y +=
        y + (name === "leftHind" ? this.tread[0] : name === "rightHind" ? this.tread[1] : 0);
      p.feet[name].z += z;
    }
    // On the move the tail rides high and waves; the spring adds the body's turns and landings.
    this.tail.update(dt, this.tailPush);
    p.tail.forEach((joint, i) => {
      const spring = this.tail.joints[i];
      joint.sway = lerp(
        (0.06 + 0.05 * i) * Math.sin(this.time * 1.6 - i * 0.8),
        b[`tailSway${i}`],
        r,
      );
      joint.lift = s.tail[i] + 0.1 * this.gait.amount + b[`tailLift${i}`] * r + spring.lift;
      joint.lean = spring.lean;
    });
    this.rig.update();
    this.tailPush = this.tailForce(dt);
  }

  /** Minus the acceleration of the tail's root over the last frames, in model units and axes. */
  tailForce(dt) {
    const track = this.tailTrack;
    const local = this.rig.hipsPose
      .apply(this.tailBase)
      .multiplyScalar(this.scale)
      .applyAxisAngle(up, this.yaw);
    track.push({ at: local.add(this.group.position), dt });
    if (track.length > 3) track.shift();
    const force = new THREE.Vector3();
    if (track.length < 3 || dt <= 0) return force;
    const [a, b, c] = track;
    const v1 = b.at.clone().sub(a.at).divideScalar(b.dt);
    const v2 = c.at.clone().sub(b.at).divideScalar(c.dt);
    force
      .subVectors(v1, v2)
      .divideScalar((b.dt + c.dt) / 2)
      .applyAxisAngle(up, -this.yaw)
      .divideScalar(this.scale);
    // A cut in the motion (a teleport, a long hitch) is not a push.
    return force.length() > 80 ? force.set(0, 0, 0) : force;
  }

  /** Laid over the body in model space about the seated spine; the seated skeleton takes the
   * same moves, so the two heads stay on each other (see CatSeat). */
  settle(dt, r) {
    const p = this.rig.pose;
    const b = this.behavior.state;
    this.breath.update(dt, this.behavior.drowse * r, this.effort);
    const chestYaw = b.chestYaw * r;
    // The head keeps looking where it did, the chest having turned under it.
    p.headYaw -= chestYaw;
    const lean = spin(this.floor, -b.forward * r, 0, b.lean * r);
    p.chestMove = lean.under(spin(this.spine, 0, chestYaw, 0));
    p.chestMove.t.addScaledVector(breathChest, this.breath.value);
    p.hipsMove = lean.under(spin(this.spine, 0, 0.3 * chestYaw, 0));
    p.hipsMove.t.addScaledVector(breathHips, this.breath.value);
  }

  /** The head rides the gait's bob, pitch and roll only as a slow average, countering them on
   * the neck so it stays level, a little behind the body. */
  steadyHead(dt, g) {
    const p = this.rig.pose;
    const k = 1 - Math.exp(-dt / headLag);
    const e = {};
    for (const key of ["y", "pitch", "roll"]) {
      this.steady[key] += (g[key] - this.steady[key]) * k;
      e[key] = this.steady[key] - g[key];
    }
    // The neck moves with the body turning about the spine's middle, to first order.
    const d = this.rig.neck.clone().sub(this.rig.spineMid);
    p.headPitch += e.pitch;
    p.headRoll += e.roll;
    p.headShift.set(-e.roll * d.y, e.y - e.pitch * d.z, e.pitch * d.y);
  }

  add(duration, run) {
    this.steps.push({ duration, run, time: 0 });
  }

  /** Lays out the trip to the other resting spot. */
  plan() {
    const points = this.atEnd ? [...this.route].reverse() : this.route;
    this.planYaw = this.yaw;
    this.behavior.stir(0.2);
    this.standUp();
    if (Math.random() < 0.6) this.stretch();
    for (let i = 1; i < points.length; i++) {
      const from = points[i - 1].at;
      const to = points[i].at;
      // Going back, each leg is crossed the way it was reached going forth.
      const move = this.atEnd ? points[i - 1].move : points[i].move;
      this.turn(facing(to.x - from.x, to.z - from.z));
      if (move === "jump") this.jump(from, to);
      else this.walk(from, to);
    }
    this.turn(this.atEnd ? this.rests[0] : this.rests[1]);
    this.sitDown();
  }

  blend(from, to, t) {
    for (const key of blendKeys) this.posture[key] = lerp(from[key], to[key], t);
    for (const key of ["fore", "hind"])
      this.posture[key] = [0, 1].map((i) => lerp(from[key][i], to[key][i], t));
    this.posture.tail = from.tail.map((v, i) => lerp(v, to.tail[i], t));
  }

  /** From the seated splat to the standing one crouched in its silhouette, then up; or up from a loaf. */
  standUp() {
    if (this.lying) {
      this.lying = false;
      this.add(0.9, (u) => this.blend(postures.loaf, postures.stand, ease(u)));
      return;
    }
    this.add(0.05, (u) => this.seat.fade(1 - u));
    this.add(0.7, (u) => this.blend(postures.sit, postures.stand, ease(u)));
  }

  /** A front stretch before setting off, held with a little shiver. */
  stretch() {
    const bow = {
      ...postures.stand,
      lift: -0.012,
      pitch: -0.25,
      bend: 0.05,
      headPitch: 0.25,
      fore: [0, -0.035],
      tail: [0.35, 0.1, 0],
    };
    const hold = 0.5 + Math.random() * 0.6;
    const length = 0.6 + hold + 0.5;
    this.add(length, (u) => {
      const t = u * length;
      this.keyframes(
        [
          [0, postures.stand],
          [0.6, bow],
          [0.6 + hold, bow],
          [length, postures.stand],
        ],
        t,
      );
      if (t > 0.6 && t < 0.6 + hold) this.posture.lift += 0.0015 * Math.sin(t * 50);
    });
  }

  /** From sitting down into a loaf on the standing splat. */
  lieDown() {
    this.add(0.05, (u) => this.seat.fade(1 - u));
    this.add(1.4, (u) => this.blend(postures.sit, postures.loaf, ease(u)));
    this.add(0.01, () => {
      this.lying = true;
    });
  }

  getUp() {
    this.lying = false;
    this.add(1, (u) => this.blend(postures.loaf, postures.sit, ease(u)));
    this.add(0.05, (u) => this.seat.fade(u));
  }

  sitDown() {
    this.add(0.8, (u) => this.blend(postures.stand, postures.sit, ease(u)));
    this.add(0.05, (u) => this.seat.fade(u));
  }

  /** Turns on the spot with small steps, about 2.5 rad a second. */
  turn(target) {
    const end = shortest(this.planYaw, target);
    const angle = Math.abs(end - this.planYaw);
    this.planYaw = end;
    if (angle < 0.05) return;
    let start;
    this.add(0.15 + angle / 2.5, (u) => {
      start ??= this.yaw;
      this.yaw = lerp(start, shortest(start, target), ease(u));
      this.stepping = true;
    });
  }

  /** Picks up speed over her first stride and loses it over the last, smoothly both ways. */
  walk(from, to) {
    const distance = from.distanceTo(to);
    const speed = Math.min(walkSpeed, distance / rampTime);
    const duration = distance / speed + rampTime;
    // Distance covered `t` seconds into a ramp from standing to full speed.
    const ramp = (t) => speed * rampTime * ((t / rampTime) ** 3 - (t / rampTime) ** 4 / 2);
    this.add(duration, (u) => {
      const t = u * duration;
      let along = ramp(rampTime) + speed * (t - rampTime);
      if (t < rampTime) along = ramp(t);
      else if (t > duration - rampTime) along = distance - ramp(duration - t);
      this.group.position.lerpVectors(from, to, along / distance);
      this.stepping = true;
      this.gaze = -0.15;
    });
  }

  /** Blends the posture along `keys`, [seconds, posture] in order, at `t` seconds. */
  keyframes(keys, t) {
    let i = 1;
    while (i < keys.length - 1 && t > keys[i][0]) i++;
    const [t0, from] = keys[i - 1];
    const [t1, to] = keys[i];
    this.blend(from, to, ease(THREE.MathUtils.clamp((t - t0) / (t1 - t0), 0, 1)));
  }

  /** She gathers, wiggles her rump, goes still, springs off her hind legs, lands fore paws first
   * and lets both sets of legs take the weight before standing up. */
  jump(from, to) {
    const rise = (to.y - from.y) / this.scale;
    const up = rise > 0 ? 1 : 0;
    const reach = from.distanceTo(to) / this.scale;
    const air = 0.28 + 0.6 * Math.sqrt(reach);
    // Room units above the straight line from takeoff to landing.
    const arc = 0.03 + 0.4 * Math.max(0, to.y - from.y);
    const aim = THREE.MathUtils.clamp(
      Math.atan2(rise, Math.hypot(to.x - from.x, to.z - from.z) / this.scale),
      -0.6,
      0.6,
    );
    const key = (over) => ({ ...postures.stand, ...over });
    const lowTail = [-0.3, -0.1, 0.1];

    const wiggle = 0.4 + Math.random() * 0.4;
    const gather = key({
      lift: -0.022,
      back: 0.008,
      pitch: lerp(-0.1, 0.08, up),
      bend: 0.05,
      headPitch: aim * 0.9,
      tail: lowTail,
    });
    const coil = { ...gather, lift: -0.032, back: 0.012 };
    const prepare = 0.35 + wiggle + 0.12;
    this.add(prepare, (u) => {
      const t = u * prepare;
      this.group.position.copy(from);
      this.keyframes(
        [
          [0, postures.stand],
          [0.35, gather],
          [0.35 + wiggle, coil],
        ],
        t,
      );
      // The rump sways side to side, the hind paws treading in turn, then she goes still.
      const w = THREE.MathUtils.clamp((t - 0.35) / wiggle, 0, 1);
      const sway = Math.sin(w * Math.PI) * Math.sin((t - 0.35) * Math.PI * 2 * 4.5);
      this.wiggle = 0.12 * sway;
      this.tread = [0.005 * Math.max(0, sway), 0.005 * Math.max(0, -sway)];
      this.posture.tail = this.posture.tail.map((v, i) => (i === 2 ? v + 0.3 * sway : v));
    });

    const launch = key({
      lift: 0.015,
      back: -0.022,
      pitch: lerp(0.05, 0.4, up),
      bend: -0.1,
      headPitch: aim * 0.5,
      fore: [0.03, -0.035],
      tail: [0.1, 0, 0],
    });
    this.add(0.14, (u) => {
      this.group.position.copy(from);
      this.free = true;
      this.wiggle = 0;
      this.tread = [0, 0];
      this.blend(coil, launch, ease(u));
    });

    const flight = key({
      back: -0.02,
      pitch: lerp(-0.25, 0.2, up),
      bend: -0.12,
      headPitch: aim * 0.3,
      fore: [0.02, -0.04],
      hind: [0.025, 0.035],
      tail: [0.2, 0.1, 0],
    });
    const reachDown = key({
      back: -0.008,
      pitch: lerp(-0.3, -0.02, up),
      bend: 0.05,
      headPitch: lerp(0.15, -0.1, up),
      fore: [0, -0.03],
      hind: [0.035, 0],
      tail: [0.15, 0.1, 0],
    });
    const contact = { ...reachDown, fore: [0, -0.02] };
    this.add(air, (u) => {
      this.free = true;
      this.group.position.lerpVectors(from, to, u);
      this.group.position.y += 4 * arc * u * (1 - u);
      this.keyframes(
        [
          [0, launch],
          [0.3, flight],
          [0.75, reachDown],
          [1, contact],
        ],
        u,
      );
    });

    // The fore legs fold under the landing, then the hind paws come down and fold in turn; the head stays level.
    const forward = key({
      lift: -0.02,
      back: -0.012,
      pitch: -0.18,
      bend: 0.08,
      headPitch: 0.13,
      fore: [0, -0.01],
      hind: [0.03, 0],
      tail: [0.1, 0.05, 0],
    });
    const settle = key({ lift: -0.028, back: -0.004, pitch: -0.03, bend: 0.04, headPitch: 0.02 });
    this.add(0.55, (u) => {
      this.group.position.copy(to);
      this.free = true;
      this.keyframes(
        [
          [0, contact],
          [0.1, forward],
          [0.24, settle],
          [0.55, postures.stand],
        ],
        u * 0.55,
      );
    });
  }
}
