"""Builds CatStanding.usdz, the mesh fallback for Mochi's splat, from the splat.

Run with nooki-scene's generation Python (numpy, scipy, scikit-image, fast-simplification, xatlas, usd-core, Pillow):
  python Tools/make_mochi_mesh.py [--name MochiStanding] [--blender path/to/blender] [--work dir]

Reads Nooki/Resources/<name>.ply, .rig.json and .skin, writes Nooki/Resources/CatStanding.usdz:
- shape: carved from the splat's median depth (where it turns half opaque) seen from many directions, so thin parts
  like the ears stay thin;
- color: every texel is what the splat shows along the surface normal there, divided by the mesh's own ambient
  occlusion since the splat's colors already carry their shading; the head gets three times the texel density;
- normal map and occlusion: baked by Blender (Tools/bake_maps.py) from the full-resolution surface;
- eyes, collar and bell: clean glossy, ribbon and metal geometry fitted where the splat has them;
- fur: short shells pushed out along the normals plus fins standing on the edges, alpha-tested strands;
- skeleton: UsdSkel joints named after the rig's bones, resting at the bone heads unrotated, weights from the nearest
  splats' skin; the fur round the eyes stays on the head, and a blink is two lids per eye on <lid>Pivot joints of
  their own, which turn as the lid bones do but about a point behind the eye. Everything stays in the splat's model space
  (meters, +Y up, front -Z), so CatMeshRig poses it with the same math as the splat.
"""
import argparse
import json
import os
import shutil
import subprocess
import tempfile

import fast_simplification
import numpy as np
import xatlas
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils, Vt
from scipy import ndimage, sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from skimage import measure

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Nooki", "Resources")

PIXEL = 0.0006            # m, depth map resolution
VOXEL = 0.0008            # m, carving grid
VIEWS = 40
CARVE_VOTES = 3           # views that must see a voxel as empty before it is carved, so one bad pixel can't bore a hole
BODY_TRIS = 20000
HEAD_DENSITY = 3          # head texels per body texel
TEXTURE = 2048
EYE_TEXTURE = 256
SHELLS = [(0.00025 * (i + 1), t) for i, t in enumerate(np.linspace(0.3, 0.85, 6))]   # offset (m), opacity threshold
FIN = (0.0013, 0.45, 0.35)  # height (m), opacity threshold, share of edges
HEAD_BONES = ("head", "earLeft", "earRight", "lidLeft", "lidLeftLow", "lidRight", "lidRightLow")
EYES = {"eyeLeft": ("lidLeft", "lidLeftLow"), "eyeRight": ("lidRight", "lidRightLow")}


def read_splat(path):
    data = open(path, "rb").read()
    a = np.frombuffer(data[data.index(b"end_header\n") + 11:], np.float32).reshape(-1, 14).astype(np.float64)
    q = a[:, 6:10] / np.linalg.norm(a[:, 6:10], axis=1, keepdims=True)
    w, x, y, z = q.T
    rotation = np.stack([
        1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
        2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
        2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)], 1).reshape(-1, 3, 3)
    scale = np.exp(a[:, 3:6])
    return dict(center=a[:, :3], scale=scale, rotation=rotation, opacity=1 / (1 + np.exp(-a[:, 10])),
                color=np.clip(0.5 + 0.28209479 * a[:, 11:14], 0, 1),
                covariance=np.einsum("kij,kj,klj->kil", rotation, scale ** 2, rotation))


def srgb_to_linear(c):
    c = np.asarray(c, np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def compact(v, f):
    used, f = np.unique(f, return_inverse=True)
    return v[used], f.reshape(-1, 3)


# ---------------------------------------------------------------------------------------------------------- shape


def fibonacci_sphere(n):
    i = np.arange(n) + 0.5
    polar = np.arccos(1 - 2 * i / n)
    turn = np.pi * (1 + 5 ** 0.5) * i
    return np.stack([np.cos(turn) * np.sin(polar), np.cos(polar), np.sin(turn) * np.sin(polar)], 1)


def image_axes(d):
    up = np.array([0.0, 1, 0]) if abs(d[1]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(up, d)
    u /= np.linalg.norm(u)
    return u, np.cross(d, u)


def depth_map(mu, covariance, opacity, d, half):
    """Orthographic view along d: per pixel, the depth where the splats composited front to back first reach half
    opacity, inf where they never do."""
    size = int(np.ceil(2 * half / PIXEL))
    u, v = image_axes(d)
    b = np.stack([u, v])
    c2 = np.einsum("ij,kjl,ml->kim", b, covariance, b) + np.eye(2) * (0.3 * PIXEL) ** 2
    det = c2[:, 0, 0] * c2[:, 1, 1] - c2[:, 0, 1] ** 2
    inv = np.stack([c2[:, 1, 1], -c2[:, 0, 1], c2[:, 0, 0]], 1) / det[:, None]
    pu, pv, z = (mu @ u + half) / PIXEL, (mu @ v + half) / PIXEL, mu @ d
    widest = 0.5 * (c2[:, 0, 0] + c2[:, 1, 1]) + np.sqrt(0.25 * (c2[:, 0, 0] - c2[:, 1, 1]) ** 2 + c2[:, 0, 1] ** 2)
    reach = np.clip(np.ceil(3 * np.sqrt(widest) / PIXEL), 1, 12).astype(int)
    pixel, depth, alpha = [], [], []
    for r in np.unique(reach):
        k = np.nonzero(reach == r)[0]
        ox, oy = [a.ravel() for a in np.meshgrid(np.arange(-r, r + 1), np.arange(-r, r + 1))]
        ix = np.floor(pu[k])[:, None].astype(int) + ox
        iy = np.floor(pv[k])[:, None].astype(int) + oy
        dx, dy = (ix + 0.5 - pu[k][:, None]) * PIXEL, (iy + 0.5 - pv[k][:, None]) * PIXEL
        a = opacity[k, None] * np.exp(-0.5 * (inv[k, 0, None] * dx * dx + 2 * inv[k, 1, None] * dx * dy
                                              + inv[k, 2, None] * dy * dy))
        keep = (a > 1 / 255) & (ix >= 0) & (iy >= 0) & (ix < size) & (iy < size)
        pixel.append((iy * size + ix)[keep])
        depth.append(np.broadcast_to(z[k, None], keep.shape)[keep])
        alpha.append(np.minimum(a[keep], 0.99))
    pixel, depth, alpha = map(np.concatenate, (pixel, depth, alpha))
    order = np.lexsort((depth, pixel))
    pixel, depth, alpha = pixel[order], depth[order], alpha[order]
    log_through = np.cumsum(np.log1p(-alpha))
    start = np.r_[True, pixel[1:] != pixel[:-1]]
    before = (log_through - np.log1p(-alpha))[start][np.cumsum(start) - 1]
    reached = log_through - before <= np.log(0.5)
    hit, first = np.unique(pixel[reached], return_index=True)
    out = np.full(size * size, np.inf)
    out[hit] = depth[reached][first]
    return out.reshape(size, size), u, v


def carve(splat):
    """The splat's visible surface: a voxel is outside once CARVE_VOTES views see it in front of their depth."""
    center = 0.5 * (splat["center"].min(0) + splat["center"].max(0))
    mu = splat["center"] - center
    half = np.linalg.norm(mu, axis=1).max() + 0.01
    lo = mu.min(0) - 0.004
    axes = [np.arange(a, b, VOXEL, dtype=np.float32) for a, b in zip(lo, mu.max(0) + 0.004)]
    x, y, z = np.ix_(*axes)
    votes = np.full((CARVE_VOTES,) + tuple(len(a) for a in axes), -np.inf, np.float32)
    for d in fibonacci_sphere(VIEWS):
        depth, u, v = depth_map(mu, splat["covariance"], splat["opacity"], d, half)
        depth = np.where(np.isinf(depth), 1.0, depth).astype(np.float32)
        iu = np.clip(((x * u[0] + y * u[1] + z * u[2] + half) / PIXEL).astype(np.int32), 0, len(depth) - 1)
        iv = np.clip(((x * v[0] + y * v[1] + z * v[2] + half) / PIXEL).astype(np.int32), 0, len(depth) - 1)
        free = depth[iv, iu] - (x * d[0] + y * d[1] + z * d[2])
        for k in range(CARVE_VOTES):   # the largest CARVE_VOTES so far, in order
            votes[k], free = np.maximum(votes[k], free), np.minimum(votes[k], free)
    field = ndimage.gaussian_filter(np.clip(votes[-1], -0.003, 0.003), 1.6)
    v, f, _, _ = measure.marching_cubes(field, 0.0, spacing=(VOXEL,) * 3)
    v = v + lo + center
    edges = sparse.coo_matrix((np.ones(f.size), (f.ravel(), np.roll(f, 1, 1).ravel())), shape=(len(v), len(v)))
    _, labels = connected_components(edges)
    v, f = compact(v, f[labels[f[:, 0]] == np.bincount(labels).argmax()])
    volume = np.einsum("ij,ij->i", v[f[:, 0]], np.cross(v[f[:, 1]], v[f[:, 2]])).sum()
    return taubin(v, f if volume > 0 else f[:, ::-1])


def taubin(v, f, iterations=10):
    """Smooths without shrinking."""
    i, j = f.ravel(), np.roll(f, 1, 1).ravel()
    adjacency = sparse.coo_matrix((np.ones(2 * len(i)), (np.r_[i, j], np.r_[j, i])), shape=(len(v), len(v))).tocsr()
    adjacency.data[:] = 1
    degree = np.asarray(adjacency.sum(1)).ravel()[:, None]
    for _ in range(iterations):
        for step in (0.5, -0.53):
            v = v + step * (adjacency @ v / degree - v)
    return v, f


def face_normals(v, f):
    return np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])


def vertex_normals(v, f):
    face = face_normals(v, f)
    n = np.zeros_like(v)
    for i in range(3):
        np.add.at(n, f[:, i], face)
    length = np.linalg.norm(n, axis=1)
    # A few vertices sit where opposite faces cancel out; any one of their faces is close enough.
    zero = length == 0
    face_of = np.zeros(len(v), int)
    face_of[f.ravel()] = np.repeat(np.arange(len(f)), 3)
    n[zero], length[zero] = face[face_of[zero]], np.linalg.norm(face[face_of[zero]], axis=1)
    return n / length[:, None]


# --------------------------------------------------------------------------------------------------- texturing


def unwrap(v, f, head_faces):
    """UVs per corner (uv, uv_faces) over the same vertices and faces; the head's charts packed HEAD_DENSITY times
    larger by unwrapping it scaled up."""
    atlas = xatlas.Atlas()
    parts = []
    for faces, scale in ((f[head_faces], HEAD_DENSITY ** 0.5), (f[~head_faces], 1.0)):
        used, local = np.unique(faces, return_inverse=True)
        atlas.add_mesh((v[used] * scale).astype(np.float32), local.reshape(-1, 3).astype(np.uint32))
        parts.append(used)
    pack = xatlas.PackOptions()
    pack.resolution, pack.padding, pack.bilinear = TEXTURE, 6, True
    atlas.generate(pack_options=pack)
    faces, uvs, uv_faces = [], [], []
    for i, used in enumerate(parts):
        vmap, local_faces, uv = atlas[i]
        faces.append(used[vmap[local_faces]])
        uv_faces.append(local_faces + sum(len(u) for u in uvs))
        uvs.append(np.asarray(uv, np.float64))
    return np.concatenate(faces), np.concatenate(uvs), np.concatenate(uv_faces)


def rasterize(v, n, f, uv, uv_faces, size):
    """Every texel the UV charts cover: its pixel, surface point and normal."""
    px = uv * size
    pixels, points, normals = [], [], []
    for tri, tri_uv in zip(f, uv_faces):
        t = px[tri_uv]
        lo, hi = np.floor(t.min(0)).astype(int), np.ceil(t.max(0)).astype(int)
        xs, ys = np.meshgrid(np.arange(lo[0], hi[0] + 1), np.arange(lo[1], hi[1] + 1))
        m = np.array([t[0] - t[2], t[1] - t[2]]).T
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        b = np.linalg.solve(m, (np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1) - t[2]).T).T
        b = np.column_stack([b, 1 - b.sum(1)])
        hit = (b >= -1e-4).all(1)
        pixels.append(np.stack([xs.ravel()[hit], ys.ravel()[hit]], 1))
        points.append(b[hit] @ v[tri])
        normals.append(b[hit] @ n[tri])
    normals = np.concatenate(normals)
    return (np.clip(np.concatenate(pixels), 0, size - 1), np.concatenate(points),
            normals / np.linalg.norm(normals, axis=1, keepdims=True))


def splat_color(splat, points, normals, neighbors=64, chunk=50000):
    """What the splat shows along a ray from 4 mm outside each point inward: the nearest splats composited front to
    back, each as opaque as its Gaussian is on the ray."""
    mu, opacity, color = splat["center"], splat["opacity"], splat["color"]
    inverse = np.linalg.inv(splat["covariance"])
    tree = cKDTree(mu)
    rgb = np.zeros((len(points), 3))
    for c in range(0, len(points), chunk):
        p, n = points[c:c + chunk], normals[c:c + chunk]
        _, near = tree.query(p, neighbors)
        rel = mu[near] - (p + n * 0.004)[:, None, :]
        ray = np.broadcast_to(-n[:, None, :], rel.shape)
        a = inverse[near]
        a_ray = np.einsum("nkij,nkj->nki", a, ray)
        ray_a_ray = np.einsum("nki,nki->nk", a_ray, ray)
        ray_a_rel = np.einsum("nki,nki->nk", a_ray, rel)
        closest = np.maximum(np.einsum("nki,nkij,nkj->nk", rel, a, rel) - ray_a_rel ** 2 / ray_a_ray, 0)
        order = np.argsort(ray_a_rel / ray_a_ray, 1)
        alpha = np.take_along_axis(np.minimum(opacity[near] * np.exp(-0.5 * closest), 0.99), order, 1)
        through = np.cumprod(np.concatenate([np.ones((len(p), 1)), 1 - alpha[:, :-1]], 1), 1)
        weight = alpha * through
        shades = color[np.take_along_axis(near, order, 1)]
        rgb[c:c + chunk] = (weight[:, :, None] * shades).sum(1) / np.maximum(weight.sum(1, keepdims=True), 1e-6)
    return rgb


def fill_texture(pixels, values, size):
    """A texture from per-texel values, with each chart's edge spread into the padding so mipmaps stay clean.
    Row 0 is the top (v = 1)."""
    image = np.zeros((size, size, values.shape[1]))
    covered = np.zeros((size, size), bool)
    image[pixels[:, 1], pixels[:, 0]] = values
    covered[pixels[:, 1], pixels[:, 0]] = True
    _, (iy, ix) = ndimage.distance_transform_edt(~covered, return_indices=True)
    return image[iy, ix][::-1], covered[::-1]


def classify(c):
    """Masks of the splat's painted parts by color: red collar, gold bell, pink nose skin, near-black eyes."""
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    hi, lo = c.max(-1), c.min(-1)
    saturation = (hi - lo) / np.maximum(hi, 1e-6)
    return dict(red=(saturation > 0.45) & (r > 0.45) & (r > g * 1.5),
                gold=(saturation > 0.35) & (r > b * 1.6) & (g > b * 1.3) & (r < g * 1.5),
                pink=(saturation > 0.2) & (r > g * 1.15) & ~((saturation > 0.45) & (r > g * 1.5)),
                dark=hi < 0.16)


def strand_alpha(bare):
    """Rank-normalized fine noise, so an opacity threshold is the share of texels without a strand; none over `bare`."""
    noise = ndimage.gaussian_filter(np.random.default_rng(1).random(bare.shape), 0.7)
    rank = np.empty(noise.size)
    rank[noise.ravel().argsort()] = np.linspace(0, 1, noise.size)
    return rank.reshape(bare.shape) * np.clip(ndimage.distance_transform_edt(~bare) / 6, 0, 1)


def quantize(alpha, thresholds):
    """Only which thresholds a texel passes matters: one level per cut compresses far better than noise."""
    cuts = sorted(int(t * 255) for t in thresholds)
    levels = np.array([0] + [c + 1 for c in cuts], np.uint8)
    return levels[np.searchsorted(cuts, (alpha * 255 + 0.5).astype(np.uint8), side="left")]


# ----------------------------------------------------------------------------------------------- parts and rig


def skin_weights(splat, skin, v, joints):
    """Per vertex and joint, blended from the skins of the nearest splats by opacity and distance."""
    k = 24
    distance, near = cKDTree(splat["center"]).query(v, k)
    weight = splat["opacity"][near] * np.exp(-0.5 * (distance / 0.003) ** 2)
    total = np.zeros((len(v), len(joints)))
    rows = np.repeat(np.arange(len(v)), k)
    for i in range(4):
        np.add.at(total, (rows, skin[near, 0, i].ravel()), (weight * skin[near, 1, i] / 255).ravel())
    return total / total.sum(1, keepdims=True)


def top4(weights):
    index = np.argsort(-weights, 1)[:, :4]
    top = np.take_along_axis(weights, index, 1)
    return index, top / top.sum(1, keepdims=True)


def fit_sphere(p):
    a = np.c_[2 * p, np.ones(len(p))]
    x = np.linalg.lstsq(a, (p ** 2).sum(1), rcond=None)[0]
    return x[:3], np.sqrt(x[3] + x[:3] @ x[:3])


def fit_eye(v, n, brightness, hinge):
    """The painted eye near a lid hinge: the sphere its surface lies on, the axis it looks along and the angular
    radius of its opening, the near-black pupil plus the brown iris round it (but not the stripes further out)."""
    facing = (np.linalg.norm(v - hinge, axis=1) < 0.024) & (n[:, 2] < -0.2)
    pupil = facing & (brightness < 0.16)
    middle = v[pupil].mean(0)
    axis = n[pupil].mean(0)
    axis /= np.linalg.norm(axis)
    rel = v - middle
    lateral = np.linalg.norm(rel - np.outer(rel @ axis, axis), axis=1)
    near = facing & (brightness < 0.3) & (lateral < 1.6 * np.percentile(lateral[pupil], 95))
    opening = np.percentile(lateral[near], 95)
    center, radius = fit_sphere(v[near])
    # A painted eye opens well under 60 degrees round its sphere; a tighter sphere is a bad fit to a few pixels.
    if not 1.2 * opening < radius < 0.04 or (middle - center) @ axis < 0:
        radius = 2 * opening
        center = middle - axis * radius
    axis = middle - center
    axis /= np.linalg.norm(axis)
    # The eye bulges past any one sphere; take the one through its outer part, so the cap clears it.
    radius += np.percentile(np.linalg.norm(v[near] - center, axis=1) - radius, 90)
    return dict(center=center, radius=radius, axis=axis, angle=np.arcsin(min(opening / radius, 0.95)))


def eye_region(points, eye, widen=1.0):
    """Points over an eye's opening (scaled by `widen`), as a mask, and how far round from its axis they are."""
    rel = points - eye["center"]
    dist = np.linalg.norm(rel, axis=-1)
    angle = np.arccos(np.clip((rel @ eye["axis"]) / np.maximum(dist, 1e-9), -1, 1))
    return (angle < eye["angle"] * widen) & (np.abs(dist - eye["radius"]) < 0.006), angle


def eye_frame(eye):
    """Side and up across an eye's axis, and how far round from it its cap reaches."""
    side = np.cross([0.0, 1, 0], eye["axis"])
    side /= np.linalg.norm(side)
    return side, np.cross(eye["axis"], side), min(eye["angle"] * 1.6, 1.45)


def eye_point(eye, t):
    """Radius of the cap t radians from the eye's axis: 0.4 mm proud over the opening and a little past it, where the
    body under it is painted over with fur, dipping under the surface beyond."""
    _, _, edge = eye_frame(eye)
    return eye["radius"] + np.interp(t, [0, eye["angle"] * 1.25, edge], [0.0004, 0.0004, -0.0012])


def eye_cap(eye, rings=14, segments=36):
    """A glossy cap over the painted eye."""
    axis = eye["axis"]
    side, up, edge = eye_frame(eye)
    theta = np.linspace(0, edge, rings + 1)[1:]
    phi = np.linspace(0, 2 * np.pi, segments, endpoint=False)
    t, p = [a.ravel() for a in np.meshgrid(theta, phi, indexing="ij")]
    t, p = np.r_[0, t], np.r_[0, p]
    direction = (np.cos(t)[:, None] * axis + np.sin(t)[:, None] * (np.cos(p)[:, None] * side + np.sin(p)[:, None] * up))
    points = eye["center"] + direction * eye_point(eye, t)[:, None]
    uv = 0.5 + 0.5 * np.c_[np.sin(t) * np.cos(p), np.sin(t) * np.sin(p)] / np.sin(edge)
    faces = [[0, 1 + (s + 1) % segments, 1 + s] for s in range(segments)]
    for r in range(rings - 1):
        for s in range(segments):
            a, b = 1 + r * segments + s, 1 + r * segments + (s + 1) % segments
            faces += [[a, b, b + segments], [a, b + segments, a + segments]]
    faces = np.array(faces)
    if (face_normals(points, faces[:1]) @ axis)[0] < 0:
        faces = faces[:, ::-1]
    return points, vertex_normals(points, faces), faces, uv


def inside(points, surface_v, surface_n, margin):
    """Points at least `margin` under a surface given by its vertices and their outward normals."""
    _, near = cKDTree(surface_v).query(points)
    return np.einsum("ij,ij->i", points - surface_v[near], surface_n[near]) < -margin


def eyelids(eye, surface_v, surface_n, rows=12, columns=24):
    """Upper and lower lid for an eye: bands of a sphere round a pivot behind the eye, hidden under the brow and the
    cheek at rest. A blink turns each about the pivot by its lid bone's swing (CatRig's lidSwing, 0.7 down and 0.42 up,
    about model X), which carries them over the eye until they meet. Returns the pivot and per lid (points, normals,
    lid faces, rim faces, uv over the band), or None when no pivot hides both lids."""
    swing_up, swing_down = 0.7, 0.42
    axis = eye["axis"]
    side = np.array([1.0, 0, 0]) - axis * axis[0]
    side /= np.linalg.norm(side)
    t = np.r_[np.linspace(0, eye["angle"], 6), eye["angle"] * 1.25]
    phi = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    across = np.cos(phi)[:, None, None] * side + np.sin(phi)[:, None, None] * np.cross(axis, side)
    cap = (eye["center"] + (np.cos(t)[None, :, None] * axis + np.sin(t)[None, :, None] * across)
           * eye_point(eye, t)[None, :, None]).reshape(-1, 3)

    def rx(a):
        c, s = np.cos(a), np.sin(a)
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

    # The nearest pivot that works, as further back the lids flatten and stop following the socket; at it the lids as
    # far out as still hide at rest, up to where the fur's tips stand, so a shut lid sits level with the face.
    for depth, clearance in ((d, c) for d in np.arange(0.004, 0.03, 0.001) for c in (0.0016, 0.0012, 0.0008)):
        pivot = eye["center"] - axis * depth
        radius = np.linalg.norm(cap - pivot, axis=1).max() + clearance
        rel = cap - pivot
        # Just wider than the opening: past it the lids would stand proud of the face round the socket.
        opening = (rel / np.linalg.norm(rel, axis=1, keepdims=True))[np.tile(np.arange(len(t)) < 6, len(phi))]
        width = np.abs(np.arcsin(opening @ side)).max() + 0.02
        psi = np.linspace(-width, width, columns)

        def band(theta):
            theta = np.atleast_1d(theta)
            base = np.cos(psi)[:, None] * axis + np.sin(psi)[:, None] * side
            d = np.einsum("tij,pj->tpi", np.stack([rx(a) for a in theta]), base)
            return pivot + radius * d.reshape(-1, 3)

        # The lowest the upper lid's edge can rest hidden, then the lower lid's edge to meet it, overlapping a little.
        top = next((a for a in np.arange(0.1, 1.2, 0.01) if inside(band(a), surface_v, surface_n, 0.0008).all()), None)
        if top is None:
            continue
        bottom = top - swing_up - swing_down + 0.04
        if not inside(band(bottom), surface_v, surface_n, 0.0008).all():
            continue
        lids = []
        # Rows bunch up toward the free edge, whose first strip is the dark rim.
        spread = np.linspace(0, 1, rows) ** 1.5
        for theta, edge_row in ((top + 0.8 * spread, 0), ((bottom - 0.6 * spread)[::-1], rows - 1)):
            p = band(theta)
            k = np.arange((rows - 1) * columns).reshape(rows - 1, columns)[:, :-1].ravel()
            f = np.concatenate([np.c_[k, k + 1, k + columns + 1], np.c_[k, k + columns + 1, k + columns]])
            n = (p - pivot) / radius
            if (face_normals(p, f[:1]) @ n[f[0, 0]])[0] < 0:
                f = f[:, ::-1]
            rim = (f // columns == edge_row).any(1)
            uv = np.c_[np.tile(np.linspace(0, 1, columns), rows), np.repeat(np.linspace(0, 1, rows), columns)]
            lids.append((p, n, f[~rim], f[rim], uv))
        print(f"eyelids: {clearance * 1000:.1f} mm over the eye, pivot {depth * 1000:.0f} mm behind, "
              f"upper edge {top:.2f}, lower edge {bottom:.2f} rad")
        return pivot, lids
    return None


def eye_texture(splat, eye):
    """The splat's eye on the cap, painted highlight and all: in soft room light the gloss alone gives no catchlight."""
    side, up, edge = eye_frame(eye)
    grid = (np.indices((EYE_TEXTURE, EYE_TEXTURE)).reshape(2, -1).T[:, ::-1] + 0.5) / EYE_TEXTURE
    across = (grid - 0.5) * 2 * np.sin(edge)
    t = np.arcsin(np.clip(np.linalg.norm(across, axis=1), 0, np.sin(edge)))
    direction = np.cos(t)[:, None] * eye["axis"] + across[:, :1] * side + across[:, 1:] * up
    direction /= np.linalg.norm(direction, axis=1, keepdims=True)
    color = splat_color(splat, eye["center"] + direction * eye_point(eye, t)[:, None], direction)
    return color.reshape(EYE_TEXTURE, EYE_TEXTURE, 3)[::-1]


def fit_collar(v, red):
    """The collar as a ring: center, axis, and per angle its radius and height span on the neck."""
    p = v[red]
    middle = p.mean(0)
    _, _, axes = np.linalg.svd(p - middle)
    axis = axes[2] if axes[2][1] > 0 else -axes[2]
    side = axes[0]
    front = np.cross(axis, side)
    rel = p - middle
    angle = np.arctan2(rel @ front, rel @ side)
    height = rel @ axis
    radius = np.linalg.norm(rel - np.outer(height, axis), axis=1)
    bins = 72
    which = ((angle + np.pi) / (2 * np.pi) * bins).astype(int) % bins
    stats = np.full((bins, 3), np.nan)
    for i in range(bins):
        s = which == i
        if s.sum() >= 3:
            stats[i] = [np.percentile(radius[s], 80), np.percentile(height[s], 20), np.percentile(height[s], 80)]
    known = ~np.isnan(stats[:, 0])
    at = np.arange(bins)
    for c in range(3):
        stats[:, c] = np.interp(at, at[known], stats[known, c], period=bins)
        stats[:, c] = ndimage.uniform_filter1d(stats[:, c], 5, mode="wrap")
    return dict(center=middle, axis=axis, side=side, front=front, profile=stats)


def still_neck(weights, v, collar, head_bones, chest):
    """Weights with the neck under the collar, which rides the chest, moved off the head, fading back in over 1.2 cm
    above it, so a turning head doesn't twist the fur through the collar or turn the red band painted under it."""
    rel = v - collar["center"]
    height = rel @ collar["axis"]
    flat = rel - np.outer(height, collar["axis"])
    angle = np.arctan2(flat @ collar["front"], flat @ collar["side"])
    bins = len(collar["profile"])
    profile = collar["profile"][((angle + np.pi) / (2 * np.pi) * bins).astype(int) % bins]
    above = np.clip((height - profile[:, 2] - 0.003) / 0.012, 0, 1)
    # Only the neck itself: the chin hanging over the collar's front keeps its head weights.
    neck = np.clip((profile[:, 0] + 0.012 - np.linalg.norm(flat, axis=1)) / 0.006, 0, 1)
    moved = weights[:, head_bones] * ((1 - above) * neck)[:, None]
    weights = weights.copy()
    weights[:, head_bones] -= moved
    weights[:, chest] += moved.sum(1)
    return weights


def collar_mesh(collar):
    """A flat ribbon band, every face with its own vertices so its edges stay crisp."""
    profile, bins = collar["profile"], len(collar["profile"])
    angle = (np.arange(bins) + 0.5) / bins * 2 * np.pi - np.pi
    radial = np.cos(angle)[:, None] * collar["side"] + np.sin(angle)[:, None] * collar["front"]
    outer, inner = profile[:, 0] + 0.0018, profile[:, 0] - 0.0025
    low, high = profile[:, 1], profile[:, 2]

    def ring(r, h):
        return collar["center"] + radial * r[:, None] + collar["axis"] * h[:, None]

    points, normals, faces = [], [], []
    for a, b, normal in ((ring(outer, high), ring(outer, low), radial),
                         (ring(outer, low), ring(inner, low), -np.tile(collar["axis"], (bins, 1))),
                         (ring(inner, high), ring(outer, high), np.tile(collar["axis"], (bins, 1)))):
        base = sum(len(p) for p in points)
        points += [a, b]
        normals += [normal, normal]
        for i in range(bins):
            j = (i + 1) % bins
            faces += [[base + i, base + bins + i, base + bins + j], [base + i, base + bins + j, base + j]]
    points, normals, faces = np.concatenate(points), np.concatenate(normals), np.array(faces)
    flip = np.einsum("ij,ij->i", face_normals(points, faces), normals[faces[:, 0]]) < 0
    faces[flip] = faces[flip][:, ::-1]
    return points, normals, faces


def fit_bell(splat, collar):
    gold = classify(splat["color"])["gold"] & (splat["opacity"] > 0.3) & \
        (np.linalg.norm(splat["center"] - collar["center"], axis=1) < 0.06)
    p = splat["center"][gold]
    center = np.median(p, 0)
    radius = np.percentile(np.linalg.norm(p - center, axis=1), 65) + 0.0003
    front = center - collar["center"]
    front[1] = 0
    return dict(center=center, radius=radius, front=front / np.linalg.norm(front))


def bell_frame(bell):
    up = np.array([0.0, 1, 0])
    return np.cross(up, bell["front"]), up, bell["front"]


def bell_uv(bell, points):
    """Seen from the front: the bell's back only touches the chest, so its mirror image there never shows."""
    side, up, _ = bell_frame(bell)
    d = points - bell["center"]
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    return 0.5 + 0.5 * np.c_[d @ side, d @ up]


def bell_texture(splat, bell, size=128):
    """The splat's bell, its shading and highlights included, over the front of the clean one."""
    side, up, front = bell_frame(bell)
    grid = (np.indices((size, size)).reshape(2, -1).T[:, ::-1] + 0.5) / size * 2 - 1
    depth = np.sqrt(np.clip(1 - (grid ** 2).sum(1), 0, 1))
    direction = grid[:, :1] * side + grid[:, 1:] * up + depth[:, None] * front
    direction /= np.linalg.norm(direction, axis=1, keepdims=True)
    color = splat_color(splat, bell["center"] + direction * bell["radius"], direction)
    return color.reshape(size, size, 3)[::-1]


def bell_mesh(bell, rings=24, segments=40):
    """A jingle bell: a sphere with a ridge round its middle, a slot across its bottom and a loop on top. Returns the
    slot's faces separately for their dark material."""
    r = bell["radius"]
    side, up, front = bell_frame(bell)
    polar = np.linspace(0, np.pi, rings + 1)
    turn = np.linspace(0, 2 * np.pi, segments, endpoint=False)
    t, p = [a.ravel() for a in np.meshgrid(polar, turn, indexing="ij")]
    local = np.c_[np.sin(t) * np.cos(p), np.cos(t), np.sin(t) * np.sin(p)]   # side, up, front
    slot = (local[:, 1] < -0.15) & (np.abs(local[:, 0]) < 0.12)
    scale = np.where(slot, 0.72, np.where(np.abs(local[:, 1]) < 0.07, 1.05, 1.0))
    points = bell["center"] + (local * scale[:, None] * r) @ np.stack([side, up, front])
    faces, slot_faces = [], []
    for i in range(rings):
        for j in range(segments):
            a, b = i * segments + j, i * segments + (j + 1) % segments
            for tri in ([a, a + segments, b + segments], [a, b + segments, b]):
                (slot_faces if slot[tri].all() else faces).append(tri)
    # Loop on top: a small torus facing front.
    major, minor = 0.32 * r, 0.09 * r
    top = bell["center"] + up * (r + major * 0.8)
    u, w = [a.ravel() for a in np.meshgrid(np.linspace(0, 2 * np.pi, 16, endpoint=False),
                                           np.linspace(0, 2 * np.pi, 8, endpoint=False), indexing="ij")]
    ring = (major + minor * np.cos(w))[:, None] * (np.cos(u)[:, None] * side + np.sin(u)[:, None] * up)
    base = len(points)
    points = np.concatenate([points, top + ring + (minor * np.sin(w))[:, None] * front])
    for i in range(16):
        for j in range(8):
            a, b = base + i * 8 + j, base + i * 8 + (j + 1) % 8
            c, d = base + ((i + 1) % 16) * 8 + j, base + ((i + 1) % 16) * 8 + (j + 1) % 8
            faces += [[a, c, d], [a, d, b]]
    core = np.concatenate([np.tile(bell["center"], (base, 1)), top + major * (np.cos(u)[:, None] * side
                                                                           + np.sin(u)[:, None] * up)])
    faces, slot_faces = np.array(faces), np.array(slot_faces)
    everything = np.concatenate([faces, slot_faces])
    inward = np.einsum("ij,ij->i", face_normals(points, everything),
                       points[everything[:, 0]] - core[everything[:, 0]]) < 0
    everything[inward] = everything[inward][:, ::-1]
    return points, vertex_normals(points, everything), everything[:len(faces)], everything[len(faces):]


def fins(v, n, f, uv_faces):
    """Strips standing out of a share of the mesh's edges, both faces, carrying the strand texture at their base; seen
    edge-on where the fur faces you, they fill the silhouette where it doesn't."""
    height, _, share = FIN
    a = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    t = np.concatenate([uv_faces[:, [0, 1]], uv_faces[:, [1, 2]], uv_faces[:, [2, 0]]])
    key = np.sort(a, 1)
    _, first, count = np.unique(key, axis=0, return_index=True, return_counts=True)
    pick = first[count == 2]
    pick = pick[np.random.default_rng(2).random(len(pick)) < share]
    a, t = a[pick], t[pick]
    vert = np.concatenate([a[:, 0], a[:, 1], a[:, 0], a[:, 1]])
    lift = np.r_[np.zeros(2 * len(a)), np.full(2 * len(a), height)]
    points = v[vert] + n[vert] * lift[:, None]
    k = np.arange(len(a))
    m = len(a)
    quads = np.stack([k, k + m, k + 3 * m, k + 2 * m], 1)
    faces = np.concatenate([quads[:, [0, 1, 2]], quads[:, [0, 2, 3]], quads[:, [0, 2, 1]], quads[:, [0, 3, 2]]])
    return points, n[vert], faces, np.concatenate([t[:, 0], t[:, 1], t[:, 0], t[:, 1]]), vert


# ------------------------------------------------------------------------------------------------------- output


def write_obj(path, v, f, uv=None, uv_faces=None):
    with open(path, "w") as o:
        o.writelines(f"v {a:.6f} {b:.6f} {c:.6f}\n" for a, b, c in v)
        if uv is None:
            o.writelines(f"f {a + 1} {b + 1} {c + 1}\n" for a, b, c in f)
        else:
            o.writelines(f"vt {a:.6f} {b:.6f}\n" for a, b in uv)
            o.writelines("f " + " ".join(f"{p + 1}/{t + 1}" for p, t in zip(face, tex)) + "\n"
                         for face, tex in zip(f, uv_faces))


def save_image(array, path, **options):
    Image.fromarray((np.clip(array, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path, **options)


def write_usdz(out, work, parts, joint_names, joint_parents, rest_world):
    """parts: (material name, points, normals, faces, uv, uv faces, joint indices, joint weights), one mesh with a
    subset per material name, so RealityKit makes a single skinned ModelEntity of it. rest_world: each joint's 4x4
    model-space transform at rest, which is also its bind transform."""
    stage = Usd.Stage.CreateNew(os.path.join(work, "Cat.usdc"))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1)
    root = UsdSkel.Root.Define(stage, "/Cat")
    stage.SetDefaultPrim(root.GetPrim())

    skel = UsdSkel.Skeleton.Define(stage, "/Cat/Skel")

    def joint_path(i):
        return joint_names[i] if joint_parents[i] is None else joint_path(joint_parents[i]) + "/" + joint_names[i]

    world = [Gf.Matrix4d(np.asarray(m, float).T.tolist()) for m in rest_world]   # Gf is row-vector

    skel.CreateJointsAttr([joint_path(i) for i in range(len(joint_names))])
    skel.CreateJointNamesAttr(joint_names)
    skel.CreateBindTransformsAttr(Vt.Matrix4dArray(world))
    skel.CreateRestTransformsAttr(Vt.Matrix4dArray(
        [world[i] * (world[joint_parents[i]].GetInverse() if joint_parents[i] is not None else Gf.Matrix4d(1))
         for i in range(len(joint_names))]))

    points, normals, faces, uvs, uv_faces, ji, jw, subsets = [], [], [], [], [], [], [], {}
    for name, p, n, f, uv, uvf, index, weight in parts:
        start = sum(len(x) for x in faces)
        subsets.setdefault(name, []).extend(range(start, start + len(f)))
        faces.append(f + sum(len(x) for x in points))
        uv_faces.append(uvf + sum(len(x) for x in uvs))
        points.append(p), normals.append(n), uvs.append(uv), ji.append(index), jw.append(weight)
    points, normals, faces, uvs, uv_faces, ji, jw = map(np.concatenate, (points, normals, faces, uvs, uv_faces, ji, jw))

    mesh = UsdGeom.Mesh.Define(stage, "/Cat/Mochi")
    mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(points.astype(np.float32)))
    mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(faces)))
    mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(faces.ravel().astype(np.int32)))
    mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals.astype(np.float32)))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mesh.CreateExtentAttr([Gf.Vec3f(*map(float, points.min(0))), Gf.Vec3f(*map(float, points.max(0)))])
    st = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.faceVarying)
    st.Set(Vt.Vec2fArray.FromNumpy(uvs.astype(np.float32)))
    st.SetIndices(Vt.IntArray.FromNumpy(uv_faces.ravel().astype(np.int32)))
    binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
    binding.CreateSkeletonRel().SetTargets([skel.GetPath()])
    binding.CreateJointIndicesPrimvar(False, 4).Set(Vt.IntArray.FromNumpy(ji.ravel().astype(np.int32)))
    binding.CreateJointWeightsPrimvar(False, 4).Set(Vt.FloatArray.FromNumpy(jw.ravel().astype(np.float32)))
    binding.CreateGeomBindTransformAttr(Gf.Matrix4d(1))
    UsdSkel.BindingAPI.Apply(root.GetPrim()).CreateSkeletonRel().SetTargets([skel.GetPath()])

    def material(name, color=None, roughness=0.9, metallic=0.0, normal=None, opacity=None, threshold=None):
        base = f"/Cat/Materials/{name}"
        surface = UsdShade.Shader.Define(stage, f"{base}/Surface")
        surface.CreateIdAttr("UsdPreviewSurface")
        reader = UsdShade.Shader.Define(stage, f"{base}/st")
        reader.CreateIdAttr("UsdPrimvarReader_float2")
        reader.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
        st_out = reader.CreateOutput("result", Sdf.ValueTypeNames.Float2)

        def texture(file, space, output, type_name):
            node = UsdShade.Shader.Define(stage, f"{base}/{os.path.splitext(file)[0]}")
            node.CreateIdAttr("UsdUVTexture")
            node.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(Sdf.AssetPath("./" + file))
            node.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set(space)
            node.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(st_out)
            return node, node.CreateOutput(output, type_name)

        def connect(input_name, type_name, value):
            socket = surface.CreateInput(input_name, type_name)
            if isinstance(value, str):
                kind = Sdf.ValueTypeNames.Float3 if type_name != Sdf.ValueTypeNames.Float else Sdf.ValueTypeNames.Float
                space = "sRGB" if input_name == "diffuseColor" else "raw"
                node, out = texture(value, space, "rgb" if kind == Sdf.ValueTypeNames.Float3 else "r", kind)
                if input_name == "normal":
                    node.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 1))
                    node.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, 0))
                socket.ConnectToSource(out)
            else:
                socket.Set(Gf.Vec3f(*map(float, value)) if type_name != Sdf.ValueTypeNames.Float else float(value))

        connect("diffuseColor", Sdf.ValueTypeNames.Color3f, color)
        connect("roughness", Sdf.ValueTypeNames.Float, roughness)
        connect("metallic", Sdf.ValueTypeNames.Float, metallic)
        if normal:
            connect("normal", Sdf.ValueTypeNames.Normal3f, normal)
        if opacity:
            connect("opacity", Sdf.ValueTypeNames.Float, opacity)
            surface.CreateInput("opacityThreshold", Sdf.ValueTypeNames.Float).Set(float(threshold))
        m = UsdShade.Material.Define(stage, base)
        m.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")
        return m

    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim())
    for name, indices in subsets.items():
        base = name.rstrip("0123456789")
        spec = MATERIALS[base]
        if base != name:
            spec = dict(spec, threshold=SHELLS[int(name[len(base):]) - 1][1])
        m = material(name, **spec)
        subset = UsdGeom.Subset.CreateGeomSubset(mesh, name, UsdGeom.Tokens.face,
                                                 Vt.IntArray(indices),
                                                 UsdShade.Tokens.materialBind)
        UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(m)
    stage.GetRootLayer().Save()

    cwd = os.getcwd()
    os.chdir(work)
    try:
        if not UsdUtils.CreateNewARKitUsdzPackage("Cat.usdc", out):
            raise SystemExit("USDZ packaging failed")
    finally:
        os.chdir(cwd)
    print(f"{out}: {os.path.getsize(out) // 1024} KB, {len(points)} points, {len(faces)} triangles")


MATERIALS = {
    "Body": dict(color="MochiColor.jpg", roughness="MochiRoughness.png", normal="MochiNormal.jpg"),
    "Fur": dict(color="MochiColor.jpg", roughness=0.95, opacity="MochiFur.png"),
    "Fins": dict(color="MochiColor.jpg", roughness=0.95, opacity="MochiFur.png", threshold=FIN[1]),
    "Eye": dict(color="MochiEye.png", roughness=0.15),
    "Lid": dict(color="MochiLid.png", roughness=0.95),
    # Half metal: the texture already holds the splat's bell shading, which full metal would tint and flatten.
    "Bell": dict(color="MochiBell.png", roughness=0.3, metallic=0.4),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--blender", default=os.environ.get("BLENDER") or shutil.which("blender") or "blender")
    parser.add_argument("--work", help="keep intermediate files here instead of a temporary folder; a carved "
                        "surface already there is reused")
    parser.add_argument("--name", default="MochiStanding", help="the splat and rig to build from: Mochi or MochiStanding")
    parser.add_argument("--out", help="defaults to CatStanding.usdz for MochiStanding")
    args = parser.parse_args()
    out = args.out or os.path.join(RESOURCES, "Cat" + args.name.removeprefix("Mochi") + ".usdz")
    work = args.work or tempfile.mkdtemp(prefix="mochi_mesh_")
    os.makedirs(work, exist_ok=True)

    splat = read_splat(os.path.join(RESOURCES, f"{args.name}.ply"))
    rig = json.load(open(os.path.join(RESOURCES, f"{args.name}.rig.json")))
    bones = rig["bones"]
    bone = {b["name"]: i for i, b in enumerate(bones)}
    head = {b["name"]: np.array(b["head"]) for b in bones}
    skin = np.frombuffer(open(os.path.join(RESOURCES, f"{args.name}.skin"), "rb").read(), np.uint8).reshape(-1, 2, 4)

    cached = os.path.join(work, "high.npz")
    if os.path.exists(cached):
        high_v, high_f = (np.load(cached)[k] for k in ("v", "f"))
    else:
        high_v, high_f = carve(splat)
        np.savez(cached, v=high_v, f=high_f)
    v, f = fast_simplification.simplify(high_v.astype(np.float32), high_f.astype(np.int32),
                                        target_reduction=1 - BODY_TRIS / len(high_f))
    v, f = compact(v.astype(np.float64), f)
    n = vertex_normals(v, f)
    print(f"surface {len(high_f)} triangles, body {len(f)}")

    # Parts painted into the splat, found by color on the body and rebuilt as clean geometry.
    painted = classify(splat_color(splat, v, n))
    # An eye is only a few body vertices across, so it is fitted on the full surface.
    high_n = vertex_normals(high_v, high_f)
    eyes = {}
    for name, lids in EYES.items():
        near = np.linalg.norm(high_v - head[lids[0]], axis=1) < 0.03
        eyes[name] = fit_eye(high_v[near], high_n[near], splat_color(splat, high_v[near], high_n[near]).max(-1),
                             head[lids[0]])
    rough_collar = v[painted["red"]].mean(0)
    near = np.linalg.norm(high_v - rough_collar, axis=1) < 0.06
    collar = fit_collar(high_v[near], classify(splat_color(splat, high_v[near], high_n[near]))["red"])
    bell = fit_bell(splat, collar)
    # Tuck the body's lumpy bell inside the clean one.
    rel = v - bell["center"]
    dist = np.linalg.norm(rel, axis=1)
    tuck = dist < bell["radius"] * 1.15
    v[tuck] = bell["center"] + rel[tuck] * (np.minimum(dist[tuck], bell["radius"] - 0.0005) / dist[tuck])[:, None]
    n = vertex_normals(v, f)

    # Joints: the rig's bones, unrotated at their heads.
    names = [b["name"] for b in bones]
    parents = [bone.get(b.get("parent")) for b in bones]
    parents[bone["chest"]] = bone["hips"]   # one root joint: chest shares the hips' head and never moves on its own
    rest = []
    for b in bones:
        rest.append(np.eye(4))
        rest[-1][:3, 3] = head[b["name"]]
    weights = skin_weights(splat, skin, v, bones)
    # The splat blinks by swinging the fur above and below each eye over it, splats sliding past each other. Skinned
    # smoothly, the same fur stretches and tears the face, so it stays on the head and lids of their own close over
    # the eyes instead (eyelids).
    for lids in EYES.values():
        for lid in lids:
            weights[:, bone["head"]] += weights[:, bone[lid]]
            weights[:, bone[lid]] = 0
    head_share = weights[:, [bone[b] for b in HEAD_BONES]].sum(1)
    weights = still_neck(weights, v, collar, [bone[b] for b in HEAD_BONES], bone["chest"])
    joints, joint_weights = top4(weights)

    f, uv, uv_faces = unwrap(v, f, head_share[f].mean(1) > 0.5)
    pixels, points, normals = rasterize(v, n, f, uv, uv_faces, TEXTURE)
    color, covered = fill_texture(pixels, splat_color(splat, points, normals), TEXTURE)
    position, _ = fill_texture(pixels, points, TEXTURE)
    masks = classify(color)

    # No fur under the eyeballs, where it would poke through them.
    lids = np.zeros(covered.shape, bool)
    for eye in eyes.values():
        lids |= eye_region(position, eye, 1.05)[0]
    eyes_y, eyes_z = rig["eyes"][1], rig["eyes"][2]
    nose = (masks["pink"] & (position[..., 2] < eyes_z - 0.008) & (position[..., 1] > eyes_y - 0.045)
            & (position[..., 1] < eyes_y))

    write_obj(os.path.join(work, "high.obj"), high_v, high_f)
    write_obj(os.path.join(work, "body.obj"), v, f, uv, uv_faces)
    subprocess.run([args.blender, "-b", "--python-exit-code", "1", "--python", os.path.join(ROOT, "Tools", "bake_maps.py"), "--",
                    os.path.join(work, "high.obj"), os.path.join(work, "body.obj"), os.path.join(work, "normal.png"),
                    os.path.join(work, "ao.png"), str(TEXTURE)], check=True, stdout=subprocess.DEVNULL)
    occlusion = np.asarray(Image.open(os.path.join(work, "ao.png")).convert("L"), np.float64)[..., None] / 255
    save_image(color / (0.45 + 0.55 * occlusion), os.path.join(work, "MochiColor.jpg"), quality=92)
    Image.open(os.path.join(work, "normal.png")).convert("RGB").save(os.path.join(work, "MochiNormal.jpg"), quality=95)
    roughness = np.where(ndimage.binary_dilation(nose, iterations=2), 0.4, 0.9)
    Image.fromarray((roughness * 255).astype(np.uint8)).resize((TEXTURE // 2,) * 2).save(
        os.path.join(work, "MochiRoughness.png"), optimize=True)
    bare = lids | nose | ndimage.binary_dilation(masks["red"] | masks["gold"], iterations=3)
    alpha = strand_alpha(bare)
    Image.fromarray(quantize(alpha, [t for _, t in SHELLS] + [FIN[1]])).save(
        os.path.join(work, "MochiFur.png"), optimize=True)

    def rigid(count, joint):
        return np.tile([joint, 0, 0, 0], (count, 1)), np.tile([1.0, 0, 0, 0], (count, 1))

    no_uv = np.zeros((1, 2))
    parts = [("Body", v, n, f, uv, uv_faces, joints, joint_weights)]
    for i, (offset, _) in enumerate(SHELLS):
        parts.append((f"Fur{i + 1}", v + n * offset, n, f, uv, uv_faces, joints, joint_weights))
    fin_p, fin_n, fin_f, fin_uv, fin_vert = fins(v, n, f, uv_faces)
    parts.append(("Fins", fin_p, fin_n, fin_f, uv, fin_uv[fin_f], joints[fin_vert], joint_weights[fin_vert]))
    eye_pixels = []
    for name, eye in eyes.items():
        p, en, ef, euv = eye_cap(eye)
        eye_pixels.append(eye_texture(splat, eye))
        euv = euv * [0.5, 1] + [0.5 * len(eye_pixels) - 0.5, 0]
        parts.append(("Eye", p, en, ef, euv, ef, *rigid(len(p), bone["head"])))
    save_image(np.concatenate(eye_pixels, 1), os.path.join(work, "MochiEye.png"))
    # Lids on joints of their own, which CatMeshRig turns as the lid bones turn but about the lid's pivot.
    lid_pixels = []
    rng = np.random.default_rng(3)
    for name, eye in eyes.items():
        found = eyelids(eye, high_v, high_n)
        if found is None:
            raise SystemExit(f"no pivot hides both of {name}'s lids")
        pivot, lids = found
        for lid, (p, ln, lf, rim, luv) in zip(EYES[name], lids):
            names.append(lid + "Pivot")
            parents.append(bone["head"])
            rest.append(np.eye(4))
            rest[-1][:3, 3] = pivot
            # The fur in a ring just outside the socket, above or below the eye, its middle tone (a stripe there would
            # paint the lid dark), a little darker toward the edge and grainy like fur; each lid a strip of one atlas.
            _, angle = eye_region(high_v, eye)
            rel = high_v - eye["center"]
            above = rel @ eye_frame(eye)[1] > 0
            ring = ((angle > eye["angle"] + 0.15) & (angle < eye["angle"] + 0.5)
                    & (np.linalg.norm(rel, axis=1) < eye["radius"] + 0.025)
                    & (above if lid == EYES[name][0] else ~above))
            fur = np.median(splat_color(splat, high_v[ring], high_n[ring]), 0)
            edge = np.linspace(0, 1, 48)[:, None, None]
            if lid == EYES[name][0]:   # the upper lid's edge is its strip's bottom row
                edge = edge[::-1]
            grain = ndimage.gaussian_filter(rng.random((48, 64)), (1.5, 0.5))[..., None]
            lid_pixels.append(fur * (0.82 + 0.18 * edge) * (0.92 + 0.16 * grain))
            luv = luv * [0.25, 1] + [0.25 * (len(lid_pixels) - 1), 0]
            parts.append(("Lid", p, ln, lf, luv, lf, *rigid(len(p), len(names) - 1)))
            parts.append(("LidRim", p, ln, rim, no_uv, np.zeros_like(rim), *rigid(len(p), len(names) - 1)))
    save_image(np.concatenate(lid_pixels, 1), os.path.join(work, "MochiLid.png"))
    MATERIALS["LidRim"] = dict(color=(0.03, 0.025, 0.02), roughness=0.7)
    collar_color = srgb_to_linear(np.median(color[masks["red"] & covered], 0))
    MATERIALS["Collar"] = dict(color=collar_color, roughness=0.55)
    cp, cn, cf = collar_mesh(collar)
    parts.append(("Collar", cp, cn, cf, no_uv, np.zeros_like(cf), *rigid(len(cp), bone["chest"])))
    save_image(bell_texture(splat, bell), os.path.join(work, "MochiBell.png"))
    MATERIALS["BellSlot"] = dict(color=(0.04, 0.025, 0.01), roughness=0.6)
    bp, bn, bf, bslot = bell_mesh(bell)
    parts.append(("Bell", bp, bn, bf, bell_uv(bell, bp), bf, *rigid(len(bp), bone["chest"])))
    parts.append(("BellSlot", bp, bn, bslot, no_uv, np.zeros_like(bslot), *rigid(len(bp), bone["chest"])))

    write_usdz(os.path.abspath(out), work, parts, names, parents, rest)


if __name__ == "__main__":
    main()
