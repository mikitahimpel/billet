"""Writes apps/ios/Shared/Places/WorldMap.txt from Natural Earth's 1:50m countries (public domain).

    curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
    python3 -I scripts/places/world-map.py ne_50m_admin_0_countries.geojson apps/ios/Shared/Places/WorldMap.txt

Each line is an ISO 3166-1 alpha-2 code (`XX` for land without one), a space, then the country's
rings split by `|`, each ring as `x,y` points split by spaces. Points are in half degrees on an
equirectangular map from 180°W, 84°N: x runs 0...720, y 0...280 (56°S). Antarctica is left out.
"""

import json
import math
import sys

SCALE = 2  # points per degree
TOP, BOTTOM = 84.0, -56.0
TOLERANCE = 0.3  # degrees, for Douglas-Peucker
MIN_AREA = 0.6  # square degrees; smaller islands go, unless they are the country's largest ring


def simplify(points, tolerance):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (ax, ay), (bx, by) = points[first], points[last]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1e-9
        index, distance = None, tolerance
        for i in range(first + 1, last):
            px, py = points[i]
            d = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if d > distance:
                index, distance = i, d
        if index is not None:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]


def simplify_ring(ring, tolerance):
    """A closed ring starts and ends on one point, so it is split at the point farthest from it."""
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(ring) < 3:
        return ring
    x0, y0 = ring[0]
    far = max(range(len(ring)), key=lambda i: (ring[i][0] - x0) ** 2 + (ring[i][1] - y0) ** 2)
    return simplify(ring[: far + 1], tolerance)[:-1] + simplify(ring[far:] + ring[:1], tolerance)[:-1]


def area(ring):
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]))) / 2


def project(lon, lat):
    lat = max(BOTTOM, min(TOP, lat))
    return round((lon + 180) * SCALE), round((TOP - lat) * SCALE)


def main(source, target):
    features = json.load(open(source))["features"]
    lines = {}
    for feature in features:
        props = feature["properties"]
        code = props["ISO_A2_EH"]
        if code == "AQ":
            continue
        if len(code) != 2 or not code.isalpha():
            code = "XX"
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        rings = [polygon[0] for polygon in polygons]
        largest = max(rings, key=lambda ring: area([tuple(p) for p in ring]))
        out = []
        for raw in rings:
            ring = [tuple(p) for p in raw]
            if raw is not largest and area(ring) < MIN_AREA:
                continue
            points = []
            for p in simplify_ring(ring, TOLERANCE):
                q = project(*p)
                if not points or points[-1] != q:
                    points.append(q)
            if len(points) < 3:
                # A tiny country still shows: a small diamond around its middle.
                cx = sum(p[0] for p in ring) / len(ring)
                cy = sum(p[1] for p in ring) / len(ring)
                x, y = project(cx, cy)
                points = [(x, y - 1), (x + 1, y), (x, y + 1), (x - 1, y)]
            out.append(" ".join(f"{x},{y}" for x, y in points))
        lines.setdefault(code, []).extend(out)
    with open(target, "w") as file:
        for code in sorted(lines):
            file.write(f"{code} {'|'.join(lines[code])}\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
