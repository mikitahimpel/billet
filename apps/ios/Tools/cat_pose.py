"""Mochi sitting, as the app poses her splat: CatRig.update and Gait's leg IK in numpy, for the baked pictures.

`sit_poses(rig)` gives every bone of MochiStanding.rig.json its model-space motion, (quaternion x y z w, translation),
for CatWalker's `Posture.sit` at rest; `lids` and `ear` close the lids and flick the left ear on top. Keep `SIT`,
`SEAT` and the rig maths in step with CatWalker.swift, CatRig.swift and CatGait.swift.
"""

import numpy as np

# CatWalker.Posture.sit: lift, back, pitch, bend, head seat, head shift, hind paw offset (up, back), tail lifts.
SIT = dict(lift=-0.014, back=-0.04, pitch=0.5, bend=-0.34, seat=1.0, neck=(0.0, 0.02, -0.01), hind=(0.0, -0.14),
           tail=(2.84, -0.05, -0.32))
# CatWalker.seat: where she sits from the splat's origin; pictures frame her about it.
SEAT = np.array([0.01, 0.0, -0.058])
# CatRig.lidSwing and Gait.kneeFloor.
LID_SWING = (0.7, 0.42)
KNEE_FLOOR = 0.026
LEGS = ["leftFore", "rightFore", "leftHind", "rightHind"]


def qmul(a, b):
    return np.array([*(a[3] * b[:3] + b[3] * a[:3] + np.cross(a[:3], b[:3])), a[3] * b[3] - a[:3] @ b[:3]])


def axis(name, angle):
    q = np.zeros(4)
    q["xyz".index(name)] = np.sin(angle / 2)
    q[3] = np.cos(angle / 2)
    return q


def act(q, p):
    u = q[:3]
    return p + 2 * np.cross(u, np.cross(u, p) + q[3] * p)


class Pose:
    def __init__(self, q=None, t=None):
        self.q = np.array([0.0, 0, 0, 1]) if q is None else np.asarray(q, float)
        self.t = np.zeros(3) if t is None else np.asarray(t, float)

    @staticmethod
    def about(pivot, q):
        pivot = np.asarray(pivot, float)
        return Pose(q, pivot - act(q, pivot))

    def under(self, parent):
        return Pose(qmul(parent.q, self.q), act(parent.q, self.t) + parent.t)

    def apply(self, p):
        return act(self.q, p) + self.t

    @property
    def inverse(self):
        q = np.array([-self.q[0], -self.q[1], -self.q[2], self.q[3]])
        return Pose(q, act(q, -self.t))

    def mix(self, other, t):
        a, b = self.q, other.q if self.q @ other.q >= 0 else -other.q
        angle = np.arccos(np.clip(a @ b, -1, 1))
        q = a if angle < 1e-6 else (np.sin((1 - t) * angle) * a + np.sin(t * angle) * b) / np.sin(angle)
        return Pose(q / np.linalg.norm(q), self.t + (other.t - self.t) * t)


def wrap(a):
    return np.arctan2(np.sin(a), np.cos(a))


def solve_leg(hip, knee, paw, target):
    side = lambda y, z: np.arctan2(z, y)
    front = lambda x, y: np.arctan2(x, -y)
    splay = wrap(front(target[0] - hip[0], target[1] - hip[1]) - front(paw[0] - hip[0], paw[1] - hip[1]))
    foot = act(axis("z", -splay), target - hip) + hip
    upper = np.hypot(knee[1] - hip[1], knee[2] - hip[2])
    lower = np.hypot(paw[1] - knee[1], paw[2] - knee[2])
    dy, dz = foot[1] - hip[1], foot[2] - hip[2]
    reach = min(max(np.hypot(dy, dz), abs(upper - lower) + 1e-4), upper + lower - 1e-4)
    opening = np.arccos(np.clip((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1))
    rest_upper = side(knee[1] - hip[1], knee[2] - hip[2])
    bend = -1.0 if np.sin(rest_upper - side(paw[1] - hip[1], paw[2] - hip[2])) < 0 else 1.0
    upper_angle = side(dy, dz) + bend * opening
    knee_y, knee_z = hip[1] + upper * np.cos(upper_angle), hip[2] + upper * np.sin(upper_angle)
    lower_angle = side(foot[1] - knee_y, foot[2] - knee_z)
    turn_upper = wrap(upper_angle - rest_upper)
    return turn_upper, wrap(lower_angle - side(paw[1] - knee[1], paw[2] - knee[2]) - turn_upper), splay


def knee_above_floor(leg, hip, foot):
    down = lambda y, z: np.arctan2(z, -y)
    h, k, p = leg["hip"], leg["knee"], leg["paw"]
    upper, lower = np.hypot(k[1] - h[1], k[2] - h[2]), np.hypot(p[1] - k[1], p[2] - k[2])
    behind = 1.0 if down(k[1] - h[1], k[2] - h[2]) > down(p[1] - h[1], p[2] - h[2]) else -1.0
    dy, dz = foot[1] - hip[1], foot[2] - hip[2]
    reach = min(max(np.hypot(dy, dz), abs(upper - lower) + 1e-4), upper + lower - 1e-4)
    opening = np.arccos(np.clip((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1))
    knee_y = hip[1] - upper * np.cos(down(dy, dz) + behind * opening)
    drop = hip[1] - KNEE_FLOOR
    if knee_y >= KNEE_FLOOR or drop >= upper:
        return foot
    knee_z = hip[2] + behind * np.sqrt(upper * upper - drop * drop)
    rise = foot[1] - KNEE_FLOOR
    return np.array([foot[0], foot[1], knee_z - behind * np.sqrt(max(lower * lower - rise * rise, 0))])


def sit_poses(rig, lids=0.0, ear=0.0):
    bones = rig["bones"]
    names = [b["name"] for b in bones]
    index = {n: i for i, n in enumerate(names)}
    joint = [np.array(b["head"], float) for b in bones]
    spine, neck = joint[index["chest"]], joint[index["head"]]
    poses = [Pose() for _ in bones]

    body = Pose.about(spine, axis("x", SIT["pitch"]))
    body.t = body.t + [0, SIT["lift"], SIT["back"]]
    chest = Pose.about(spine, axis("x", SIT["bend"] / 2)).under(body)
    hips = Pose.about(spine, axis("x", -SIT["bend"] / 2)).under(body)
    head = Pose.about(neck, np.array([0.0, 0, 0, 1])).under(chest.mix(Pose(), SIT["seat"]))
    head.t = head.t + SIT["neck"]
    poses[index["chest"]], poses[index["hips"]], poses[index["head"]] = chest, hips, head
    for name, sign, flick in (("earLeft", 1, ear), ("earRight", -1, 0.0)):
        i = index[name]
        poses[i] = Pose.about(joint[i], axis("z", -sign * flick)).under(head)
    for side in ("Left", "Right"):
        hinge = index[f"lid{side}"]
        poses[hinge] = Pose.about(joint[hinge], axis("x", -LID_SWING[0] * lids)).under(head)
        poses[index[f"lid{side}Low"]] = Pose.about(joint[hinge], axis("x", LID_SWING[1] * lids)).under(head)
    tail = [i for i, n in enumerate(names) if n.startswith("tail")]
    carried = hips
    for k, i in enumerate(tail):
        carried = Pose.about(joint[i], axis("x", -SIT["tail"][min(k, len(SIT["tail"]) - 1)])).under(carried)
        poses[i] = carried
    posed = {index[n] for n in ("hips", "chest", "head", "earLeft", "earRight")} | set(tail)
    posed |= {i for i, n in enumerate(names) if n.startswith("lid")}
    for name in LEGS:
        if name + "Upper" not in index:
            continue
        upper_i, lower_i = index[name + "Upper"], index[name + "Lower"]
        leg = dict(hip=joint[upper_i], knee=joint[lower_i], paw=np.array(bones[lower_i]["tail"], float))
        fore = bones[upper_i].get("parent") == "chest"
        parent = chest if fore else hips
        foot = leg["paw"].copy()
        if not fore:
            foot[1] += SIT["hind"][0]
            foot[2] += SIT["hind"][1]
        foot = knee_above_floor(leg, parent.apply(leg["hip"]), foot)
        a, b, splay = solve_leg(leg["hip"], leg["knee"], leg["paw"], parent.inverse.apply(foot))
        upper = Pose.about(leg["hip"], qmul(axis("z", splay), axis("x", a))).under(parent)
        lower = Pose.about(leg["knee"], axis("x", b)).under(upper)
        poses[upper_i], poses[lower_i] = upper, lower
        posed |= {upper_i, lower_i}
        if name + "Paw" in index:
            poses[index[name + "Paw"]] = Pose(t=lower.apply(leg["paw"]) - leg["paw"])
            posed.add(index[name + "Paw"])
    for i, b in enumerate(bones):
        if i not in posed and b.get("parent"):
            poses[i] = poses[index[b["parent"]]]
    return [(p.q, p.t) for p in poses]


def skin(points, skin_bytes, poses):
    """Dual quaternion skinning as SkinSplats.metal does it: each point's blended rotation (x y z w) and position."""
    index = skin_bytes[:, :4].astype(int)
    weight = skin_bytes[:, 4:].astype(np.float64) / 255
    real = np.array([q for q, _ in poses])
    dual = np.array([0.5 * qmul(np.array([*t, 0.0]), q) for q, t in poses])
    first = real[index[:, 0]]
    r = np.zeros((len(points), 4))
    d = np.zeros((len(points), 4))
    for k in range(4):
        sign = np.where((real[index[:, k]] * first).sum(1) < 0, -1.0, 1.0)
        w = (sign * weight[:, k])[:, None]
        r += w * real[index[:, k]]
        d += w * dual[index[:, k]]
    n = np.linalg.norm(r, axis=1, keepdims=True)
    r, d = r / n, d / n
    u, w = r[:, :3], r[:, 3:]
    # Translation 2 * dual * conjugate(real), its vector part.
    t = 2 * (d[:, 3:] * -u + w * d[:, :3] + np.cross(d[:, :3], -u))
    moved = points + 2 * np.cross(u, np.cross(u, points) + w * points) + t
    return r, moved
