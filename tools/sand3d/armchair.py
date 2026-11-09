"""A cloud armchair: a soft seat block on four legs, a cushion, a back, two rolled arms and a pillow.

Millimetres, Z up, front towards -Y. `fabric` is a colourway from billet_style.FABRICS, `cushion` one of
plump, tufted or flat, `legs` one of peg, tapered or bun.
"""

import sand3d as s3d

import billet_style as st

LEG_HEIGHT = {"peg": 100, "tapered": 140, "bun": 70}


def armchair(fabric="oat", cushion="plump", legs="peg", width=860, depth=740):
    body_color, cushion_color, pillow_color = st.FABRICS[fabric]
    lift = LEG_HEIGHT[legs]
    base = s3d.at(seat_block(width, depth), z=lift)
    back = s3d.at(backrest(width), y=depth / 2 - 110, z=lift + 200)
    arm = s3d.at(arm_roll(depth), x=-(width / 2 - 100), z=lift + 140)
    twin = s3d.transform(s3d.copy(arm), mirror="x")
    seat = s3d.at(seat_cushion(cushion), y=-40, z=lift + 240)
    pillow = s3d.at(back_pillow(), x=120, y=depth / 2 - 260, z=lift + 340, rx=-15)
    feet = [s3d.at(leg(legs), x=sx * (width / 2 - 70), y=sy * (depth / 2 - 90))
            for sx in (-1, 1) for sy in (-1, 1)]
    st.cloth([base, back, arm, twin], body_color)
    st.cloth(seat, cushion_color)
    st.cloth(pillow, pillow_color)
    st.wood(feet, st.WOOD_DARK)
    return s3d.assembly("armchair", base, back, arm, twin, seat, pillow, *feet)


def seat_block(width, depth, h=240):
    return st.soft(s3d.box("seat_block", width, depth, h), st.SOFT)


def backrest(width, d=220, h=560):
    return st.soft(s3d.box("backrest", width, d, h), 100)


def arm_roll(depth, w=200, h=400):
    return st.soft(s3d.box("arm", w, depth, h), 90)


def seat_cushion(style, w=620, d=600):
    if style == "flat":
        return st.soft(s3d.box("cushion", w, d, 80), 30)
    pad = st.soft(s3d.box("cushion", w, d, 140), st.PLUMP)
    if style == "tufted":
        s3d.dent(pad, [(x, y, 140) for x in (-150, 0, 150) for y in (-140, 140)], r=26, depth=14)
    return pad


def back_pillow(w=330, d=120, h=270):
    return st.soft(s3d.box("pillow", w, d, h), 55)


def leg(style):
    h = LEG_HEIGHT[style]
    if style == "peg":
        return st.soft(s3d.cylinder("leg", 60, h), st.TRIM)
    if style == "tapered":
        return st.soft(s3d.cone("leg", 40, h, d2=62), st.TRIM)
    return st.soft(s3d.cylinder("leg", 100, h), 30)
