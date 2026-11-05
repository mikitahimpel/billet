// Mochi's skeletons: a two-part spine, head with ears, tail and, standing, two bones per leg, skinned by Spark's dual
// quaternions. Bones, eyes and per-splat weights come from the generation pipeline (generate/rigs/<name>.json, bound
// by generate/skin.py), the same files the app reads.
import * as THREE from "three";
import { SplatSkinning } from "@sparkjsdev/spark";
import { solveLeg, legOrder } from "./cat-gait.js";

/** A rigid motion x' = q x + t. */
export class Pose {
  constructor(q = new THREE.Quaternion(), t = new THREE.Vector3()) {
    this.q = q;
    this.t = t;
  }

  /** Rotation by q about a pivot point. */
  static about(pivot, q) {
    return new Pose(q.clone(), pivot.clone().sub(pivot.clone().applyQuaternion(q)));
  }

  /** this after parent: x' = parent(this(x)). */
  under(parent) {
    return new Pose(
      parent.q.clone().multiply(this.q),
      this.t.clone().applyQuaternion(parent.q).add(parent.t),
    );
  }

  inverse() {
    const q = this.q.clone().invert();
    return new Pose(q, this.t.clone().negate().applyQuaternion(q));
  }

  apply(p) {
    return p.clone().applyQuaternion(this.q).add(this.t);
  }

  /** `t` of the way from this to `other`. */
  mix(other, t) {
    return new Pose(this.q.clone().slerp(other.q, t), this.t.clone().lerp(other.t, t));
  }
}

const axisX = new THREE.Vector3(1, 0, 0);
const axisY = new THREE.Vector3(0, 1, 0);
const axisZ = new THREE.Vector3(0, 0, 1);
const turn = (axis, angle) => new THREE.Quaternion().setFromAxisAngle(axis, angle);
// Radians each lid swings from open to shut: the upper rim (6.5 mm above the eye's middle, 12 mm before the hinge)
// and the lower one (7.5 mm below) meet 2 mm under the middle, the upper lid doing most of the work.
const lidSwing = { upper: 0.7, lower: 0.42 };

export class CatRig {
  /** `rig` is a <name>.rig.json sidecar, `skinUrl` the URL of its <name>.skin. */
  constructor(splat, rig, skinUrl) {
    this.splat = splat;
    this.ready = false;
    this.bones = rig.bones;
    this.bone = Object.fromEntries(rig.bones.map((b, i) => [b.name, i]));
    const joint = (name) => new THREE.Vector3(...rig.bones[this.bone[name]].head);
    this.joint = joint;
    // The spine bends at its middle; the head turns on the neck above the collar.
    this.spineMid = joint("chest");
    this.neck = joint("head");
    this.ears = { earLeft: joint("earLeft"), earRight: joint("earRight") };
    this.tailBones = rig.bones
      .filter((b) => b.name.startsWith("tail"))
      .map((b) => this.bone[b.name]);
    // Each leg it has: where it leaves the body, the elbow or knee, and the paw's center on the floor.
    this.legs = Object.fromEntries(
      legOrder
        .filter((name) => `${name}Upper` in this.bone)
        .map((name) => {
          const lower = rig.bones[this.bone[`${name}Lower`]];
          return [
            name,
            {
              hip: joint(`${name}Upper`),
              knee: joint(`${name}Lower`),
              paw: new THREE.Vector3(...lower.tail),
              fore: rig.bones[this.bone[`${name}Upper`]].parent === "chest",
              upper: this.bone[`${name}Upper`],
              lower: this.bone[`${name}Lower`],
            },
          ];
        }),
    );
    this.eyesCenter = new THREE.Vector3(...rig.eyes);
    this.headPose = new Pose();
    this.hipsPose = new Pose();
    // Set by the motion each frame, in model space. `feet` are where the paws should be; a leg that cannot reach
    // stretches toward it.
    this.pose = {
      lift: 0,
      back: 0,
      pitch: 0,
      roll: 0,
      bend: 0,
      wiggle: 0,
      headYaw: 0,
      headPitch: 0,
      headRoll: 0,
      headShift: new THREE.Vector3(),
      headSeat: 0,
      chestMove: new Pose(),
      hipsMove: new Pose(),
      earLeft: 0,
      earRight: 0,
      earsBack: 0,
      earTurnLeft: 0,
      earTurnRight: 0,
      lidLeft: 0,
      lidRight: 0,
      tail: this.tailBones.map(() => ({ sway: 0, lift: 0, lean: 0 })),
      feet: Object.fromEntries(
        Object.entries(this.legs).map(([name, leg]) => [name, leg.paw.clone()]),
      ),
    };
    const skin = fetch(skinUrl).then((r) => r.arrayBuffer());
    Promise.all([splat.initialized, skin]).then(([, data]) => this.bind(new Uint8Array(data)));
  }

  /** `data` holds 4 bone indices and 4 weights out of 255 per splat, in the splat's order. */
  bind(data) {
    const numBones = this.bones.length;
    const skin = new SplatSkinning({ mesh: this.splat, numBones });
    for (let i = 0; i < numBones; i++)
      skin.setRestQuatPos(i, new THREE.Quaternion(), new THREE.Vector3());
    const bones = new THREE.Vector4();
    const amounts = new THREE.Vector4();
    const count = this.splat.packedSplats.numSplats;
    if (data.length !== count * 8)
      console.warn("cat skin does not match its splat", data.length / 8, count);
    this.splat.forEachSplat((index) => {
      const o = index * 8;
      bones.set(data[o], data[o + 1], data[o + 2], data[o + 3]);
      amounts.set(data[o + 4] / 255, data[o + 5] / 255, data[o + 6] / 255, data[o + 7] / 255);
      skin.setSplatBones(index, bones, amounts);
    });
    skin.skinTexture.needsUpdate = true;
    this.splat.skinning = skin;
    this.splat.updateGenerator();
    this.skin = skin;
    this.ready = true;
  }

  /** Model-space point between the eyes as posed last frame. */
  eyes() {
    return this.headPose.apply(this.eyesCenter);
  }

  update() {
    if (!this.ready) return;
    const p = this.pose;
    const { bone: Bone, spineMid, neck, ears, legs } = this;
    // The whole body pitches nose up (+) and rolls about its middle, then rises by `lift` and moves back by `back`;
    // the spine then sags by `bend`, chest and rump both up for positive values, and the rump swings by `wiggle` to her
    // left (+) about the spine's middle. `chestMove` and `hipsMove` are laid over the result in model space. The head
    // turns on the neck, hung `headSeat` of the way from the chest to where the seated skeleton holds it, and then
    // moves by `headShift`, in model space.
    const body = Pose.about(spineMid, turn(axisX, p.pitch).multiply(turn(axisZ, p.roll)));
    body.t.y += p.lift;
    body.t.z += p.back;
    const chest = Pose.about(spineMid, turn(axisX, p.bend / 2))
      .under(body)
      .under(p.chestMove);
    const hips = Pose.about(spineMid, turn(axisY, p.wiggle).multiply(turn(axisX, -p.bend / 2)))
      .under(body)
      .under(p.hipsMove);
    const look = turn(axisY, p.headYaw)
      .multiply(turn(axisX, p.headPitch))
      .multiply(turn(axisZ, p.headRoll));
    const head = Pose.about(neck, look).under(chest.mix(p.chestMove, p.headSeat));
    head.t.add(p.headShift);
    this.headPose = head;
    this.hipsPose = hips;
    const set = (bone, pose) => this.skin.setBoneQuatPos(bone, pose.q, pose.t);
    set(Bone.chest, chest);
    set(Bone.hips, hips);
    set(Bone.head, head);
    // An ear swivels its opening out toward its own side (`earTurn`), folds back with `earsBack` and flicks outward.
    const ear = (side, sign) =>
      Pose.about(
        ears[`ear${side}`],
        turn(axisY, -sign * p[`earTurn${side}`])
          .multiply(turn(axisX, -p.earsBack))
          .multiply(turn(axisZ, -sign * p[`ear${side}`])),
      ).under(head);
    set(Bone.earLeft, ear("Left", 1));
    set(Bone.earRight, ear("Right", -1));
    // The lids are the fur above and below an eye, swung over it about a hinge behind the eye until they meet; 1 shuts
    // them.
    for (const lid of ["lidLeft", "lidRight"]) {
      if (!(lid in Bone)) continue;
      set(
        Bone[lid],
        Pose.about(this.joint(lid), turn(axisX, -lidSwing.upper * p[lid])).under(head),
      );
      set(
        Bone[`${lid}Low`],
        Pose.about(this.joint(lid), turn(axisX, lidSwing.lower * p[lid])).under(head),
      );
    }

    // Each tail joint swings sideways (`sway`, about its up axis), lifts, and leans over to one side (+ toward -X).
    let tail = hips;
    this.tailBones.forEach((bone, i) => {
      const { sway, lift, lean } = p.tail[i];
      const swing = turn(axisY, sway).multiply(turn(axisX, -lift)).multiply(turn(axisZ, lean));
      tail = Pose.about(this.joint(this.bones[bone].name), swing).under(tail);
      set(bone, tail);
    });

    for (const [name, leg] of Object.entries(legs)) {
      const parent = leg.fore ? chest : hips;
      const [a, b, splay] = solveLeg(
        leg.hip,
        leg.knee,
        leg.paw,
        parent.inverse().apply(p.feet[name]),
      );
      const upper = Pose.about(leg.hip, turn(axisZ, splay).multiply(turn(axisX, a))).under(parent);
      set(leg.upper, upper);
      set(leg.lower, Pose.about(leg.knee, turn(axisX, b)).under(upper));
    }
    this.skin.updateBones();
  }

  /** Where a paw rests in the splat's own pose, in model space. */
  rest(name) {
    return this.legs[name].paw.clone();
  }
}

const smoothstep = THREE.MathUtils.smoothstep;
const clamp = THREE.MathUtils.clamp;
const lerp = THREE.MathUtils.lerp;
const random = (min, max) => min + Math.random() * (max - min);
/** A blink `u` seconds in: shut in 70 ms, held 40, open again in 150. */
const blinkShape = (u) => (u < 0.07 ? u / 0.07 : u < 0.11 ? 1 : Math.max(0, 1 - (u - 0.11) / 0.15));
/** 0 → 1 → 0 over `length` seconds from `start`, 0 outside. */
const bump = (t, start, length) =>
  t > start && t < start + length ? Math.sin(((t - start) / length) * Math.PI) : 0;
/** 0 → 1 over the first half second from `start`, held, back to 0 over the last half second of `length`. */
const hold = (t, start, length) =>
  smoothstep(t - start, 0, 0.5) * (1 - smoothstep(t - start, length - 0.5, length));

const hash = (i) => {
  let h = Math.imul(i ^ 0x9e3779b9, 0x85ebca6b);
  h ^= h >>> 13;
  h = Math.imul(h, 0xc2b2ae35);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

/** Smooth gradient noise, about -1 to 1, bending about once per unit of `x`; each `seed` is another curve. */
export function noise(x, seed = 0) {
  const i = Math.floor(x);
  const f = x - i;
  const a = (hash(i + seed * 7919) * 2 - 1) * f;
  const b = (hash(i + 1 + seed * 7919) * 2 - 1) * (f - 1);
  return 2 * lerp(a, b, f * f * f * (f * (f * 6 - 15) + 10));
}

/** Moves `state[key]` toward `goal` as a spring of angular frequency `w` and damping ratio `zeta`, in 120 Hz substeps. */
function spring(state, speed, key, goal, w, zeta, dt) {
  const n = Math.ceil(dt * 120);
  const h = dt / n;
  for (let i = 0; i < n; i++) {
    speed[key] += (w * w * (goal - state[key]) - 2 * zeta * w * speed[key]) * h;
    state[key] += speed[key] * h;
  }
}

const earKeys = ["earLeft", "earRight", "earsBack", "earTurnLeft", "earTurnRight"];

/**
 * What the cat does at rest: looks around on its own, follows the pointer when it is near, checks on whoever watches,
 * twitches its ears, waves its tail, washes its chest now and then, and leans into a pet with ears back and a happy
 * head tilt. It looks the way a cat does, eyes first: the head snaps after them, overshoots a little and holds. Now and
 * then an ear swivels toward a sound she alone hears, she tips her head back in a yawn, and left alone for a while she
 * flicks or curls the tip of her tail. She blinks every few seconds and with each big turn of her head, narrows her
 * eyes while petted, looks up and slow-blinks after a pet, and slow-blinks at someone who lingers. Her ears are
 * springs: they drift on their own, swing their openings to sounds, point at the pointer and lag her head's turns.
 * A mood drives all of it: `energy` drains at rest and makes her drowsy when low, `interest` rises with anything going
 * on and makes her quick and alert, `contentment` grows with pets and softens her eyes and tail. Its values ease toward
 * their targets; whoever poses the rig blends them in.
 */
export class CatBehavior {
  constructor(rig) {
    this.rig = rig;
    this.time = 0;
    this.lookTarget = null;
    this.viewer = null;
    this.lastPointer = -10;
    this.petStart = -10;
    this.nextGlance = 1;
    this.glance = { yaw: 0, pitch: 0, roll: 0 };
    this.nextTwitch = 2;
    this.twitch = null;
    // Where the head is headed (the eyes are already there), and since when.
    this.aim = { yaw: 0, pitch: 0, time: 0, turn: 0 };
    this.speed = Object.fromEntries(["yaw", "pitch", ...earKeys].map((key) => [key, 0]));
    this.nextSound = random(4, 12);
    this.sound = null;
    this.nextYawn = random(25, 60);
    this.yawnStart = -10;
    this.nextFlick = random(6, 14);
    this.flick = null;
    this.pointerSince = -10;
    this.nextBlink = random(1, 4);
    this.blinks = [];
    this.nextSlowBlink = 0;
    this.slowBlink = -10;
    this.nextContentBlink = random(8, 16);
    this.nextShift = random(10, 20);
    this.shift = { lean: 0, forward: 0 };
    this.nextCheck = random(5, 12);
    this.check = null;
    this.nextGroom = random(30, 60);
    this.groom = null;
    this.tailPhase = 0;
    this.mood = { energy: 0.7, interest: 0.3, contentment: 0.5 };
    // Set by whoever moves her: asleep in a loaf, she gets her energy back.
    this.napping = false;
    this.drowse = 0;
    this.state = {
      lean: 0,
      forward: 0,
      chestYaw: 0,
      yaw: 0,
      pitch: 0,
      roll: 0,
      earLeft: 0,
      earRight: 0,
      earsBack: 0,
      earTurnLeft: 0,
      earTurnRight: 0,
      lidLeft: 0,
      lidRight: 0,
      blink: 0,
    };
    rig.tailBones.forEach((_, i) => {
      this.state[`tailSway${i}`] = this.state[`tailLift${i}`] = 0;
    });
    this.target = { ...this.state };
  }

  /** Point in the cat's model space to look at, or null when the pointer left. */
  lookAt(point) {
    this.lookTarget = point;
    if (point && this.time - this.lastPointer > 2) this.pointerSince = this.time;
    if (point) this.lastPointer = this.time;
  }

  /** Where whoever watches her is, in the cat's model space: the camera. */
  watch(point) {
    this.viewer = point;
  }

  pet() {
    this.petStart = this.time;
    this.stir(0.25);
  }

  /** Wakes her up by `amount` of her energy. */
  stir(amount) {
    this.mood.energy = Math.min(1, this.mood.energy + amount);
  }

  /** Yaw and pitch of a model-space point seen from her eyes. */
  toward(point) {
    const d = point.clone().sub(this.rig.eyes());
    return { yaw: Math.atan2(-d.x, -d.z), pitch: Math.atan2(d.y, Math.hypot(d.x, d.z)) };
  }

  update(dt) {
    this.time += dt;
    const t = this.time;
    const target = this.target;
    const mood = this.mood;
    const left = t - Math.max(this.lastPointer, this.petStart);
    const near = this.lookTarget && t - this.lastPointer < 2 ? 1 : 0;

    // Idle glances: every few seconds a new direction, sometimes with a curious head tilt; livelier, she glances
    // more often and wider.
    if (t > this.nextGlance) {
      const reach = 0.6 + 0.6 * mood.energy;
      this.glance = {
        yaw: (Math.random() - 0.5) * 0.9 * reach,
        pitch: (Math.random() - 0.3) * 0.25,
        roll: Math.random() < 0.3 ? (Math.random() - 0.5) * 0.5 : 0,
      };
      this.nextGlance = t + random(2, 5) * lerp(1.8, 0.8, mood.energy) * (1 - 0.4 * mood.interest);
    }
    let { yaw, pitch, roll } = this.glance;

    // A sound off to one side or behind: the ear on that side swivels to it, and now and then she looks.
    if (t > this.nextSound) {
      this.sound = {
        start: t,
        yaw: random(-2.5, 2.5),
        length: random(0.8, 1.8),
        look: Math.random() < 0.3,
      };
      if (this.sound.look) this.stir(0.08);
      this.nextSound = t + random(6, 16);
    }
    const heard = this.sound ? bump(t, this.sound.start, this.sound.length) ** 0.5 : 0;
    if (
      this.sound?.look &&
      t > this.sound.start + 0.25 &&
      t < this.sound.start + this.sound.length + 0.8
    ) {
      yaw = this.sound.yaw;
      pitch = 0;
      roll = 0;
    }

    // Now and then she checks on whoever watches, more often when curious, and slow-blinks at them when content;
    // right after a pet she looks up at them.
    if (t > this.nextCheck) {
      if (this.viewer && Math.random() < 0.3 + 0.5 * mood.interest) {
        this.check = { start: t, length: random(1.2, 2.6) };
        if (mood.contentment > 0.55) this.slowBlink = t + 0.5;
      }
      this.nextCheck = t + random(6, 14);
    }
    const p = t - this.petStart;
    const checking = this.check && t < this.check.start + this.check.length ? 1 : 0;
    if (this.viewer && (checking || (p > 0.4 && p < 3.6))) {
      const at = this.toward(this.viewer);
      if (Math.abs(at.yaw) < 1.2) ({ yaw, pitch, roll } = { ...at, roll: 0 });
    }
    if (near) ({ yaw, pitch, roll } = { ...this.toward(this.lookTarget), roll: 0 });
    // The neck turns only so far before the blend band shears.
    yaw = clamp(yaw, -0.6, 0.6);
    pitch = clamp(pitch, -0.25, 0.3);

    // The eyes are on (yaw, pitch) at once; the head re-aims once they are far enough off it or have rested there,
    // in smaller steps while following the pointer.
    const aim = this.aim;
    const off = Math.hypot(yaw - aim.yaw, pitch - aim.pitch);
    if (off > (near ? 0.06 : 0.12) || (off > 0.03 && t - aim.time > 0.5)) {
      aim.turn = yaw - aim.yaw;
      Object.assign(aim, { yaw, pitch, time: t });
    }

    // Yawn: the head tips back and over with the ears folding, then comes back; tired, she yawns more.
    if (t > this.nextYawn) {
      if (left > 4) this.yawnStart = t;
      this.nextYawn = t + random(40, 90) * lerp(0.6, 1.4, mood.energy);
    }
    const yawn = bump(t, this.yawnStart, 2.4) ** 1.5;

    // Energy drains at rest and comes back with a nap; low, it makes her drowsy, unless something is going on.
    mood.energy = clamp(mood.energy + dt * (this.napping ? 1 / 200 : -1 / 150), 0, 1);
    const drowse = (1 - smoothstep(mood.energy, 0.1, 0.35)) * (1 - heard) * (1 - near);
    this.drowse = drowse;

    // Every 10-20 s she settles her weight a little differently, leaning to a side or forward, and holds it; her chest
    // turns a little after her head.
    if (t > this.nextShift) {
      this.shift = { lean: random(-0.025, 0.025), forward: random(-0.01, 0.02) };
      this.nextShift = t + random(10, 20);
    }
    target.lean = this.shift.lean;
    target.forward = this.shift.forward;
    target.chestYaw = 0.13 * this.state.yaw;

    // Petting: lean into the hand, ears back, tail tip up, for about two seconds.
    const petting =
      p < 2 ? Math.sin((Math.min(p / 0.3, 1) * Math.PI) / 2) * (1 - smoothstep(p, 1.5, 2)) : 0;

    // Grooming: every minute or so, awake and left alone, she washes her chest in short licks, head down and to a
    // side, eyes half shut.
    if (t > this.nextGroom) {
      if (left > 8 && drowse < 0.3)
        this.groom = { start: t, length: random(3, 5.5), side: Math.random() < 0.5 ? -1 : 1 };
      this.nextGroom = t + random(40, 90);
    }
    const groom = this.groom;
    const washing = groom && !near ? hold(t, groom.start, groom.length) : 0;
    const lick = washing * Math.max(0, Math.sin((t - (groom?.start ?? 0)) * Math.PI * 2 * 2.8));
    const side = groom?.side ?? 0;

    const free = (1 - petting) * (1 - yawn) * (1 - washing);
    // Holding still, the head still drifts a hair.
    target.yaw = aim.yaw * free + 0.45 * side * washing + 0.012 * noise(t * 0.7, 1);
    target.pitch =
      aim.pitch * free +
      0.12 * petting +
      0.3 * yawn -
      0.12 * drowse +
      washing * (0.07 * lick - 0.45) +
      0.01 * noise(t * 0.7, 2);
    target.roll =
      roll * free + 0.32 * petting * Math.sin(p * 3) + 0.2 * yawn + 0.2 * side * washing;
    target.earsBack =
      0.5 * petting +
      0.35 * yawn +
      0.25 * heard * smoothstep(Math.abs(this.sound?.yaw ?? 0), 1.2, 2.2) +
      0.15 * washing;

    // Interest jumps with anything going on and fades over several seconds; contentment grows with pets and slowly
    // settles back.
    const lure = Math.max(near, heard, 0.6 * petting, 0.5 * checking);
    mood.interest +=
      (lure - mood.interest) * (1 - Math.exp(-dt * (lure > mood.interest ? 3 : 1 / 8)));
    mood.contentment = clamp(
      mood.contentment + dt * (0.25 * petting + (0.4 - mood.contentment) / 120),
      0,
      1,
    );

    // Ear twitches: one ear, quick flick out and back; more of them when she is curious.
    if (t > this.nextTwitch) {
      this.twitch = {
        start: t,
        ear: Math.random() < 0.5 ? "earLeft" : "earRight",
        both: Math.random() < 0.25,
      };
      this.nextTwitch = t + random(2.5, 6.5) * (1.3 - 0.6 * mood.interest);
    }
    target.earLeft = target.earRight = 0;
    if (this.twitch) {
      const q = (t - this.twitch.start) / 0.35;
      const amount = q < 1 ? Math.sin(q * Math.PI) * 0.45 : 0;
      if (this.twitch.both) target.earLeft = target.earRight = amount;
      else target[this.twitch.ear] = amount;
    }
    // An ear swings ahead of the head toward where it turns (negative yaw is her left), and both lag the turn itself,
    // one flaring as the other folds.
    const lead = Math.abs(aim.turn) > 0.2 ? 0.3 * bump(t, aim.time, 0.45) : 0;
    target[aim.turn < 0 ? "earLeft" : "earRight"] += lead;
    target.earLeft += 0.03 * this.speed.yaw;
    target.earRight -= 0.03 * this.speed.yaw;

    // Ears drift on their own, each its own way; the one on a sound's side swings its opening round to it, the other
    // following for a sound behind her. They point at the pointer, forward when she is curious, and spread out while
    // petted, drowsy or content.
    const behind = smoothstep(Math.abs(this.sound?.yaw ?? 0), 1.2, 2.2);
    for (const [ear, seed] of [
      ["Left", 10],
      ["Right", 11],
    ]) {
      const towards = this.sound && this.sound.yaw < 0 === (ear === "Left");
      target[`earTurn${ear}`] =
        0.14 * noise(t * 0.3, seed) * (1 - near) +
        heard * (towards ? 0.5 + 0.6 * behind : 0.4 * behind) -
        0.2 * near +
        0.45 * petting +
        0.25 * drowse -
        0.15 * mood.interest +
        0.1 * mood.contentment;
    }

    // Eyes: quick blinks, sometimes doubled, fewer when curious; half shut while petted or washing; a slow blink back
    // at someone who has lingered a few seconds, after a pet, and now and then when content; heavy lids when drowsy,
    // soft ones when content, and shut through a yawn.
    if (t > this.nextBlink || (aim.time === t && Math.abs(aim.turn) > 0.35)) {
      this.blinks.push(t);
      if (Math.random() < 0.2) this.blinks.push(t + 0.3);
      this.nextBlink = t + random(2.5, 7) * (1 + 1.5 * drowse) * (1 + 0.5 * mood.interest);
    }
    this.blinks = this.blinks.filter((start) => t - start < 0.3);
    this.state.blink = Math.max(
      0,
      ...this.blinks.map((start) => (t >= start ? blinkShape(t - start) : 0)),
    );
    if (near && t - this.pointerSince > 3 && t > this.nextSlowBlink) {
      this.slowBlink = t;
      this.nextSlowBlink = t + random(6, 12);
    }
    if (p > 2.2 && p - dt <= 2.2) this.slowBlink = t;
    if (t > this.nextContentBlink) {
      if (mood.contentment > 0.6 && !near) this.slowBlink = t;
      this.nextContentBlink = t + random(8, 18);
    }
    const slow = Math.min(
      smoothstep(t - this.slowBlink, 0, 0.5),
      1 - smoothstep(t - this.slowBlink, 1.1, 1.8),
    );
    const lid = Math.max(
      0.55 * petting,
      0.85 * slow,
      0.9 * yawn,
      drowse * (0.6 + 0.1 * noise(t * 0.3, 3)),
      0.5 * washing,
      0.15 * mood.contentment * (1 - mood.interest),
    );
    target.lidLeft = lid;
    target.lidRight = lid * (1 - 0.08 * drowse);

    // Tail: a wave runs from the base to the tip, each joint a little later and wider than the last, its pace and
    // size wandering; calmer when she is content, quicker when curious, the tip twitching then. Now and then the tip
    // lifts, and it stays up while petted. Left alone, she flicks the tip sideways or curls it up for a while.
    this.tailPhase += dt * 0.9 * (1 + 0.35 * noise(t * 0.15, 4)) * (1 + 0.5 * mood.interest);
    const swing = (1.3 - 0.6 * mood.contentment) * (1 + 0.3 * noise(t * 0.2, 5));
    const flick = Math.max(0, noise(t * 0.35, 6)) ** 3;
    [0.04, 0.08, 0.12].forEach((amplitude, i) => {
      const wave = Math.sin(this.tailPhase - i * 0.7) + 0.3 * Math.sin(this.tailPhase * 2.6 - i);
      target[`tailSway${i}`] = amplitude * swing * wave;
    });
    [0, 0.1, 0.25].forEach((share, i) => {
      target[`tailLift${i}`] = share * (flick + 1.2 * petting);
    });
    if (t > this.nextFlick) {
      if (left > 12)
        this.flick = { start: t, curl: Math.random() < 0.35, side: Math.random() < 0.5 ? -1 : 1 };
      this.nextFlick = t + random(9, 20);
    }
    const last = this.rig.tailBones.length - 1;
    target[`tailSway${last}`] += 0.12 * mood.interest * noise(t * 2.5, 7);
    if (this.flick?.curl) target[`tailLift${last}`] += 0.5 * bump(t, this.flick.start, 3);
    else if (this.flick)
      target[`tailSway${last}`] += 0.5 * this.flick.side * bump(t, this.flick.start, 0.35);

    // The head snaps after the eyes as a lightly damped spring, overshooting a little before it holds; the ears are
    // looser springs still. The rest eases, tail lifts quicker, the body's weight slowly.
    for (const key of ["yaw", "pitch"])
      spring(this.state, this.speed, key, target[key], 11, 0.6, dt);
    for (const key of earKeys) spring(this.state, this.speed, key, target[key], 20, 0.35, dt);
    const k = 1 - Math.exp(-dt * 7);
    const fast = 1 - Math.exp(-dt * 20);
    const settle = {
      lean: 1 - Math.exp(-dt * 1.2),
      forward: 1 - Math.exp(-dt * 1.2),
      chestYaw: 1 - Math.exp(-dt * 2),
    };
    for (const key of Object.keys(this.state)) {
      if (key in this.speed || key === "blink") continue;
      const rate = settle[key] ?? (key.startsWith("tailLift") ? fast : k);
      this.state[key] += (target[key] - this.state[key]) * rate;
    }
  }
}
