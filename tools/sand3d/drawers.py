"""A chest of three drawers whose bottom one slides out, deep enough for the cat to curl up in.

Millimetres, Z up, front towards -Y. The two upper drawers are fronts only; the bottom drawer is a real box on a
prismatic joint `bottom_drawer` (0 shut, `reach` open, along -Y). In the GLB the joint rides in the node extras; in
the USDZ the drawer is its own node, named `bottom_drawer`, for the app to slide.
"""

import sand3d as s3d

import billet_style as st


def chest_of_drawers(width=640, depth=420, height=720, color=st.WOOD, front=st.OAT, reach=300, open=0):
    carcass = cabinet(width, depth, height)
    rows = drawer_rows(height)
    fronts = [s3d.at(drawer_front(width - 70, h - 20), y=-depth / 2, z=z + 10) for z, h in rows[1:]]
    z0, h0 = rows[0]
    drawer = s3d.at(cat_drawer(width - 70, depth - 50, h0 - 20), y=-37, z=z0 + 10)
    st.wood(carcass, color)
    st.clay([drawer, *fronts], front)
    knobs = [st.wood(s3d.at(s3d.sphere("knob", 34), y=-depth / 2 - 28, z=z + h / 2 - 7), st.WOOD_DARK)
             for z, h in rows[1:]]
    bottom_knob = st.wood(s3d.at(s3d.sphere("bottom_knob", 34), y=-depth / 2 - 28, z=z0 + h0 / 2 - 7),
                          st.WOOD_DARK)
    drawer = s3d.group("bottom_drawer", drawer, bottom_knob)
    s3d.joint("bottom_drawer", drawer, s3d.bbox(carcass, "-Y"), kind="prismatic", axis="-Y", range=(0, reach))
    chest = s3d.assembly("chest_of_drawers", carcass, drawer, *fronts, *knobs)
    if open:
        s3d.pose(drawer, open)
    return chest


def drawer_rows(height, plinth=60, top=40, split=(0.42, 0.29, 0.29)):
    """(bottom, height) of each drawer's opening, the deepest first."""
    room = height - plinth - top
    rows, z = [], plinth
    for share in split:
        rows.append((z, room * share))
        z += room * share
    return rows


def cabinet(width, depth, height, wall=30):
    body = s3d.box("cabinet", width, depth, height)
    hollow = s3d.at(s3d.box("opening", width - 2 * wall, depth, height - 60 - 40), y=-wall, z=60)
    s3d.cut(body, hollow)
    return st.soft(body, 20)


def drawer_front(w, h, t=24):
    return st.soft(s3d.box("front", w, t, h), 11)


def cat_drawer(w, d, h, t=18):
    tray = s3d.shell(s3d.box("drawer", w, d, h), t, open="top")
    return st.soft(tray, 6)
