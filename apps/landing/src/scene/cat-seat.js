// Mochi sitting: cat-sit.spz is the same cat generated sitting, on a skeleton of its own for head, ears and tail. She
// rests on it and swaps to the standing splat in one frame, while the standing skeleton crouches in the seated
// silhouette.
import { CatRig, Pose } from "./cat-rig.js";
import rig from "./assets/cat-sit.rig.json";
import skinUrl from "./assets/cat-sit.skin?url";

export class CatSeat {
  /** `splat` is the seated cat, `standing` the standing one in the same model space. */
  constructor(splat, standing) {
    this.splat = splat;
    this.standing = standing;
    splat.position.set(...rig.mount);
    this.rig = new CatRig(splat, rig, skinUrl);
    // Where her spine bends sitting, in the standing cat's model space.
    this.spine = this.rig.spineMid.clone().add(splat.position);
    this.fade(1);
  }

  get seated() {
    return this.amount > 0.5;
  }

  /**
   * 1 shows the seated cat, 0 the standing one, cutting from one to the other halfway: their collars, bells and paws
   * sit a little apart, so any frame showing both, blended or dithered, shows two of each.
   */
  fade(amount) {
    this.amount = amount;
    this.splat.visible = this.seated;
    this.standing.visible = !this.seated;
  }

  /**
   * Poses the seated skeleton: head and ears as the standing one holds them, so the two heads stay on each other
   * through a swap, `headPitch` being the standing head's own nod without its posture; the tail sweeps along the
   * floor with the resting behavior. The model-space moves of chest and hips carry over too, shifted into the seated
   * splat's space.
   */
  update(standing, headPitch, behavior) {
    const b = behavior.state;
    const p = this.rig.pose;
    p.headYaw = standing.headYaw;
    p.headPitch = headPitch;
    p.headRoll = standing.headRoll;
    p.headShift.copy(standing.headShift);
    p.earLeft = standing.earLeft;
    p.earRight = standing.earRight;
    const mount = this.splat.position;
    const local = (move) =>
      new Pose(
        move.q.clone(),
        move.t.clone().add(mount.clone().applyQuaternion(move.q)).sub(mount),
      );
    p.chestMove = local(standing.chestMove);
    p.hipsMove = local(standing.hipsMove);
    for (const key of ["earsBack", "earTurnLeft", "earTurnRight", "lidLeft", "lidRight"])
      p[key] = standing[key];
    const last = p.tail.length - 1;
    p.tail.forEach((joint, i) => {
      joint.sway = 1.5 * b[`tailSway${i}`];
      joint.lift = i === last ? 0.6 * b[`tailLift${i}`] : 0;
    });
    this.rig.update();
  }
}
