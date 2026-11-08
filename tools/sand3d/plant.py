"""A potted plant: a clay pot with a rolled rim and soil, and one of three kinds of foliage.

Millimetres, Z up, front towards -Y. `kind` is monstera (split leaves on stems), snake (upright blades) or
bush (a clump of round leaves); `pot` is tapered or belly; `seed` turns the leaves so two plants of one kind
differ.
"""

import math
import random

import sand3d as s3d

import billet_style as st


def potted_plant(kind="monstera", pot="tapered", pot_color=st.TERRACOTTA, leaf=st.LEAF, leaf_dark=st.LEAF_DARK,
                 seed=1, pot_h=300):
    vessel = planter(pot, pot_h)
    soil = s3d.at(s3d.cylinder("soil", 360, 20), z=pot_h - 30)
    st.clay(vessel, pot_color)
    st.clay(soil, st.INK, roughness=st.CHALK)
    grow = {"monstera": monstera_leaves, "snake": snake_blades, "bush": bush_clump}[kind]
    foliage = grow(random.Random(seed), pot_h - 15, leaf, leaf_dark)
    return s3d.assembly("potted_plant", vessel, soil, *foliage)


def planter(style, h, top_d=420, foot_d=330, wall=20):
    if style == "belly":
        outline = s3d.spline([(165, 0), (215, h * 0.45), (190, h * 0.9), (205, h)])
        body = s3d.revolve("pot", s3d.poly([(0, 0), (165, 0), outline, (0, h)]))
    else:
        body = s3d.cone("pot", foot_d, h, d2=top_d)
    rim = s3d.at(s3d.torus("rim", top_d + 10, 50), z=h - 25)
    return st.soft(s3d.join(body, rim), 10)


def monstera_leaves(rng, base, light, dark, n=6):
    parts = []
    for i in range(n):
        turn = i * 360 / n + rng.uniform(-15, 15)
        rise = rng.uniform(380, 560)
        out = rng.uniform(170, 240)
        a = math.radians(turn)
        tip = (out * math.cos(a), out * math.sin(a), base + rise)
        stem = s3d.wire("stem", [(0, 0, base), (tip[0] * 0.35, tip[1] * 0.35, base + rise * 0.6), tip], 16)
        st.clay(stem, dark)
        length = rng.uniform(330, 400)
        blade = split_leaf(length)
        blade = s3d.at(blade, x=tip[0] + 0.4 * length * math.cos(a), y=tip[1] + 0.4 * length * math.sin(a), z=tip[2],
                       ry=-rng.uniform(25, 45), rz=turn)
        st.clay(blade, light if i % 2 == 0 else dark)
        parts += [stem, blade]
    return parts


def split_leaf(length, t=24):
    """A heart-wide leaf lying in XY, its tip towards +X, with the monstera's slits cut in from both edges."""
    leaf = s3d.extrude("leaf", s3d.ellipse(length, length * 0.72), t, both=True)
    for side in (-1, 1):
        for k in (-0.22, 0.05, 0.3):
            slit = s3d.at(s3d.extrude("slit", s3d.slot(length * 0.3, 14), t * 3, both=True),
                          x=k * length, y=side * length * 0.3, rz=side * 70)
            s3d.cut(leaf, slit)
    return st.soft(leaf, 9)


def snake_blades(rng, base, light, dark, n=9):
    parts = []
    for i in range(n):
        turn = i * 360 / n + rng.uniform(-20, 20)
        h = rng.uniform(420, 640)
        blade = s3d.extrude("blade", s3d.ellipse(70, 22), h, taper=0.7)
        blade = s3d.at(st.soft(blade, 6), x=40 * math.cos(math.radians(turn)), y=40 * math.sin(math.radians(turn)),
                       z=base, rx=rng.uniform(4, 14), rz=turn + 90)
        st.clay(blade, light if i % 2 == 0 else dark)
        parts.append(blade)
    return parts


def bush_clump(rng, base, light, dark, n=14):
    parts = []
    for i in range(n):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 140)
        ball = s3d.at(s3d.sphere("puff", rng.uniform(150, 230)), x=r * math.cos(a), y=r * math.sin(a),
                      z=base + rng.uniform(0, 260) - r * 0.4)
        st.clay(ball, light if i % 2 == 0 else dark)
        parts.append(ball)
    return parts
