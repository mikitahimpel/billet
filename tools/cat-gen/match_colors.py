"""Matches one splat's colors to another's, region by region, so two generations of the same object read as one.

Works in an opponent color space (lightness, red-green, yellow-blue) on the SH DC colors, each splat weighted by how
often it shows on the surface. Lightness is histogram-matched, so the mix of light fur, stripes and white comes out
as light as the reference's. Hue goes by region: both splats' colors are clustered (grey fur, dark stripes, white
chest, pink ears, red collar, ...), k-means on the target first, then on the reference starting from the target's
centers, so cluster i is the same region in both; each target splat takes the reference's mean and spread of hue of
its cluster, blended over its nearest clusters so no seam shows between regions.
Only colors change: splat count, order, positions and shapes stay, so a skin bound to the target stays valid.
"""

import numpy as np

SH_C0 = 0.28209479
# Rows: lightness, red-green, yellow-blue.
OPPONENT = np.array([[1 / 3, 1 / 3, 1 / 3], [1, -1, 0], [0.5, 0.5, -1]])
COLOR = slice(11, 14)


def _visibility(xyz, views=26, size=384):
    """How often each splat center is the front-most one in its pixel, over views from all around and above."""
    rng = np.random.default_rng(1)
    dirs = rng.normal(size=(views, 3))
    dirs[:, 1] = np.abs(dirs[:, 1])
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    p = xyz - (xyz.min(0) + xyz.max(0)) / 2
    scale = (size / 2 - 1) / np.linalg.norm(p, axis=1).max()
    seen = np.zeros(len(p))
    for d in dirs:
        u = np.cross(d, [0, 1, 0] if abs(d[1]) < 0.9 else [1, 0, 0])
        u /= np.linalg.norm(u)
        v = np.cross(d, u)
        pixel = ((p @ u) * scale + size / 2).astype(int) * size + ((p @ v) * scale + size / 2).astype(int)
        order = np.lexsort((p @ d, pixel))
        first = np.r_[True, pixel[order][1:] != pixel[order][:-1]]
        seen[order[first]] += 1
    return seen


def _features(data):
    """Opponent colors and weights: the more often a splat shows on the surface and the more opaque, the more."""
    rgb = 0.5 + SH_C0 * data[:, COLOR].astype(np.float64)
    alpha = 1 / (1 + np.exp(-data[:, 10].astype(np.float64)))
    weight = alpha * _visibility(data[:, :3].astype(np.float64))
    return rgb @ OPPONENT.T, weight / weight.mean()


def _kmeans(x, w, centers, iterations=25):
    for _ in range(iterations):
        label = _nearest(x, centers)
        for k in range(len(centers)):
            mine = label == k
            if w[mine].sum() > 0:
                centers[k] = np.average(x[mine], axis=0, weights=w[mine])
    return centers


def _nearest(x, centers):
    return np.argmin(((x[:, None] - centers[None]) ** 2).sum(-1), 1)


def _stats(x, w, resp):
    total = resp.T @ w + 1e-9
    mean = (resp * w[:, None]).T @ x / total[:, None]
    var = np.stack([(resp[:, k] * w) @ (x - mean[k]) ** 2 / total[k] for k in range(resp.shape[1])])
    return mean, np.sqrt(var) + 1e-4


def _quantiles(x, w, q):
    order = np.argsort(x)
    cdf = np.cumsum(w[order]) - w[order] / 2
    return np.interp(q, cdf / w.sum(), x[order])


def _match_histogram(x, w, y, v):
    q = np.linspace(0, 1, 201)
    return np.interp(x, _quantiles(x, w, q), _quantiles(y, v, q))


def _responsibilities(x, centers, sharpness):
    d = ((x[:, None] - centers[None]) ** 2).sum(-1)
    d -= d.min(1, keepdims=True)
    r = np.exp(-d / sharpness)
    return r / r.sum(1, keepdims=True)


def match_colors(data, reference, clusters=8, seed=0):
    """`data` and `reference` are splats in make_splat's 14-float layout; returns `data` with matched colors."""
    x, w = _features(data)
    y, v = _features(reference)
    rng = np.random.default_rng(seed)
    start = x[rng.choice(len(x), clusters, replace=False, p=w / w.sum())]
    centers = _kmeans(x, w, start)
    ref_centers = _kmeans(y, v, centers.copy())
    # Softness about a tenth of the typical squared gap between neighboring clusters.
    gaps = ((centers[:, None] - centers[None]) ** 2).sum(-1)
    sharpness = 0.1 * np.median(np.sort(gaps, 1)[:, 1])
    resp = _responsibilities(x, centers, sharpness)
    mean, std = _stats(x, w, resp)
    ref_mean, ref_std = _stats(y, v, _responsibilities(y, ref_centers, sharpness))
    gain = np.clip(ref_std / std, 0.67, 1.5)
    matched = np.einsum('nk,nkc->nc', resp, (x[:, None] - mean[None]) * gain[None] + ref_mean[None])
    matched[:, 0] = _match_histogram(x[:, 0], w, y[:, 0], v)

    for k in np.argsort(-mean[:, 0]):
        rgb = (np.linalg.inv(OPPONENT) @ np.stack([mean[k], ref_mean[k]]).T).T
        print(f'  cluster {k}: {resp[:, k].sum() / len(x):5.1%} of splats, rgb {np.round(rgb[0], 3)} -> '
              f'{np.round(rgb[1], 3)}, hue spread x{np.round(gain[k, 1:], 2)}')
    out = data.copy()
    rgb = matched @ np.linalg.inv(OPPONENT).T
    out[:, COLOR] = ((rgb - 0.5) / SH_C0).astype(out.dtype)
    return out
