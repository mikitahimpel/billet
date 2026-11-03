"""Makes the shopkeepers who stand behind the shop counter, from code alone.

Run: Blender -b --python make_shopkeepers.py -- [teddy human raccoon fox tabby] [--render <folder>]
Writes assets-source/shopkeepers/Keeper_<name>.usdz. bake_shopkeepers.sh compiles them.

Every keeper is the same set of named joints, so the app moves any of them the same way:

  keeper            the whole figure, standing on z = 0
    body            hips; leans and breathes
      head          the neck; turns to look at you
        eye_L/eye_R one eye each; squashed flat to blink
        ear_L/ear_R
      arm_L/arm_R   the shoulders; arm_R waves
      tail          the base of the tail; sways

A joint is an empty at its pivot and the shapes hang from it, so turning a joint turns everything
under it. Shapes are low-poly with flat faces and one plain colour each, like the room's furniture,
except the teddy's: smooth, in a small fuzzy fabric texture drawn here, with stitched seams.
Blender's front view looks at the face: the keeper faces -y, which the USD export turns into +z.
"""

from __future__ import annotations

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets-source", "shopkeepers")


def linear(hex_colour: int) -> tuple[float, float, float, float]:
    def channel(value: int) -> float:
        c = value / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (
        channel((hex_colour >> 16) & 0xFF),
        channel((hex_colour >> 8) & 0xFF),
        channel(hex_colour & 0xFF),
        1.0,
    )


def fabric_image(name: str, hex_colour: int, seed: int, pixels: int = 128) -> bpy.types.Image:
    """A plush fabric in `hex_colour`: fine fuzz, soft blotches where the pile lies differently,
    and a few darker, worn flecks. It tiles, so it repeats unseen over a part."""
    image = bpy.data.images.new(name, pixels, pixels, alpha=False)
    rnd = random.Random(seed)
    red, green, blue = ((hex_colour >> 16) & 0xFF) / 255, ((hex_colour >> 8) & 0xFF) / 255, (hex_colour & 0xFF) / 255
    tau = 2 * math.pi / pixels
    values: list[float] = []
    for y in range(pixels):
        for x in range(pixels):
            fuzz = rnd.random()
            pile = (math.sin(x * tau * 3 + math.sin(y * tau * 2) * 1.5) * math.sin(y * tau * 4 + 0.7)) * 0.5
            fleck = -0.18 if rnd.random() < 0.012 else 0.0
            shade = 0.86 + 0.12 * fuzz + 0.07 * pile + fleck
            values += [min(red * shade, 1), min(green * shade, 1), min(blue * shade, 1), 1.0]
    image.pixels = values
    image.file_format = "PNG"
    image.pack()
    return image


class Kit:
    """Makes joints and parts in one keeper, with one material per colour and finish."""

    def __init__(self, name: str):
        self.name = name
        self.materials: dict[tuple[int, str], bpy.types.Material] = {}

    def material(self, hex_colour: int, finish: str = "matte") -> bpy.types.Material:
        """A plain colour; `fabric` adds the fuzzy plush texture, `gloss` a shine like a button."""
        key = (hex_colour, finish)
        if key in self.materials:
            return self.materials[key]
        material = bpy.data.materials.new(f"{self.name}_{hex_colour:06X}_{finish}")
        material.use_nodes = True
        nodes = material.node_tree.nodes
        shader = nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = linear(hex_colour)
        shader.inputs["Roughness"].default_value = {"matte": 0.85, "fabric": 1.0, "gloss": 0.3}[finish]
        if finish == "fabric":
            texture = nodes.new("ShaderNodeTexImage")
            texture.image = fabric_image(f"{self.name}_{hex_colour:06X}_fuzz", hex_colour, seed=hex_colour)
            material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        material.diffuse_color = linear(hex_colour)
        self.materials[key] = material
        return material

    def joint(self, name: str, at, parent=None) -> bpy.types.Object:
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_size = 0.05
        bpy.context.scene.collection.objects.link(empty)
        empty.parent = parent
        empty.location = at
        return empty

    def part(
        self,
        name: str,
        shape: str,
        size,
        colour: int,
        parent,
        at=(0, 0, 0),
        turn=(0, 0, 0),
        detail: int = 1,
        top: float = 0.0,
        segments: int = 7,
        finish: str = "matte",
        smooth: bool = False,
    ) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        bm = bmesh.new()
        uvs = finish == "fabric"
        if uvs:
            bm.loops.layers.uv.verify()
        if shape == "ball":
            bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=0.5, calc_uvs=uvs)
        elif shape == "box":
            bmesh.ops.create_cube(bm, size=1.0, calc_uvs=uvs)
        elif shape == "cone":
            bmesh.ops.create_cone(
                bm, cap_ends=True, cap_tris=False, segments=segments, radius1=0.5,
                radius2=0.5 * top, depth=1.0, calc_uvs=uvs)
        elif shape == "ring":
            ring(bm, segments=max(segments, 10))
        else:
            raise ValueError(shape)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        bm.to_mesh(mesh)
        bm.free()
        for polygon in mesh.polygons:
            polygon.use_smooth = smooth
        mesh.materials.append(self.material(colour, finish))
        part = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(part)
        part.parent = parent
        part.location = at
        part.rotation_euler = Euler(turn)
        return part


def ring(bm: bmesh.types.BMesh, segments: int, sides: int = 4, thickness: float = 0.16) -> None:
    """A torus of outer radius 0.5 lying in the x-z plane, facing -y, like a spectacle rim."""
    rows = []
    centre = 0.5 - thickness / 2
    for i in range(segments):
        a = 2 * math.pi * i / segments
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides + math.pi / 4
            r = centre + thickness / 2 * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), thickness / 2 * math.sin(b), r * math.sin(a))))
        rows.append(row)
    for i in range(segments):
        for j in range(sides):
            a, b = rows[i], rows[(i + 1) % segments]
            bm.faces.new((a[j], b[j], b[(j + 1) % sides], a[(j + 1) % sides]))


# --- One figure, three animals --------------------------------------------------------------------


def figure(kit: Kit, look: dict) -> bpy.types.Object:
    """The shared body: a round torso with an apron, a big head, short arms and a tail."""
    keeper = kit.joint("keeper", (0, 0, 0))
    body = kit.joint("body", (0, 0, 0.12), keeper)
    kit.part("torso", "ball", (0.62, 0.5, 0.78), look["fur"], body, at=(0, 0, 0.36), detail=2)
    kit.part("chest", "ball", (0.34, 0.16, 0.34), look["chest"], body, at=(0, -0.19, 0.5), detail=2)
    # The apron or cardigan hugs the lower torso, with a pocket on the front.
    kit.part("apron", "ball", (0.66, 0.54, 0.5), look["cloth"], body, at=(0, -0.01, 0.24), detail=2)
    kit.part("apron_pocket", "box", (0.22, 0.04, 0.09), look["cloth_dark"], body,
             at=(0, -0.27, 0.2), turn=(-0.25, 0, 0))

    head = kit.joint("head", (0, 0, 0.7), body)
    kit.part("skull", "ball", (0.66, 0.56, 0.54), look["fur"], head, at=(0, 0, 0.26), detail=2)
    kit.part("cheek_L", "ball", (0.2, 0.14, 0.15), look["cheek"], head, at=(0.19, -0.17, 0.15), detail=2)
    kit.part("cheek_R", "ball", (0.2, 0.14, 0.15), look["cheek"], head, at=(-0.19, -0.17, 0.15), detail=2)
    kit.part("muzzle", "ball", look["muzzle_size"], look["muzzle"], head,
             at=look["muzzle_at"], detail=2)
    kit.part("nose", "ball", (0.085, 0.06, 0.06), 0x2A2026, head, at=look["nose_at"])
    for side, x in (("L", 0.13), ("R", -0.13)):
        eye = kit.joint(f"eye_{side}", (x, -0.255, 0.3), head)
        kit.part(f"pupil_{side}", "ball", (0.085, 0.05, 0.1), 0x1B1620, eye)
        kit.part(f"shine_{side}", "ball", (0.03, 0.02, 0.03), 0xFFF6E8, eye, at=(-0.015, -0.025, 0.025))
        ear = kit.joint(f"ear_{side}", (x * 1.55, 0.02, 0.48), head)
        lean = -0.35 if side == "L" else 0.35
        kit.part(f"ear_{side}_outer", "cone", look["ear_size"], look["ear"], ear,
                 at=(0, 0, look["ear_size"][2] / 2 - 0.03), turn=(0, lean, 0), top=0.12, segments=5)
        kit.part(f"ear_{side}_inner", "cone",
                 (look["ear_size"][0] * 0.55, 0.03, look["ear_size"][2] * 0.65), look["ear_inner"],
                 ear, at=(0, -0.045, look["ear_size"][2] / 2 - 0.06), turn=(0, lean, 0), top=0.1,
                 segments=5)
        if "ear_tip" in look:
            kit.part(f"ear_{side}_tip", "cone",
                     (look["ear_size"][0] * 0.45, look["ear_size"][1] * 0.6, look["ear_size"][2] * 0.4),
                     look["ear_tip"], ear,
                     at=(math.sin(lean) * look["ear_size"][2] * 0.32, 0,
                         look["ear_size"][2] * 0.74 - 0.03),
                     turn=(0, lean, 0), top=0.1, segments=5)

    for side, x in (("L", 1), ("R", -1)):
        arm = kit.joint(f"arm_{side}", (0.27 * x, -0.02, 0.6), body)
        kit.part(f"sleeve_{side}", "ball", (0.18, 0.18, 0.36), look["arm"], arm, at=(0.03 * x, 0, -0.15))
        kit.part(f"paw_{side}", "ball", (0.15, 0.15, 0.13), look["paw"], arm, at=(0.04 * x, -0.02, -0.33))

    tail = kit.joint("tail", (0, 0.2, 0.12), body)
    look["tail"](kit, tail)
    return keeper


def raccoon(kit: Kit) -> None:
    grey, dark, light = 0x8C8796, 0x3D3844, 0xE9E4DA

    def tail(kit: Kit, joint) -> None:
        # Rings from base to tip, alternating, curling up behind the back.
        for index in range(6):
            t = index / 5
            kit.part(f"tail_{index}", "ball", (0.2 - 0.03 * t, 0.2 - 0.03 * t, 0.17),
                     dark if index % 2 else grey, joint,
                     at=(0.06 * t, 0.12 + 0.07 * index, 0.04 + 0.11 * index * (0.5 + 0.5 * t)),
                     turn=(0.5 + 0.2 * index, 0, 0))

    figure(kit, {
        "fur": grey, "chest": light, "cheek": light, "muzzle": light, "arm": grey, "paw": dark,
        "muzzle_size": (0.26, 0.2, 0.15), "muzzle_at": (0, -0.24, 0.17), "nose_at": (0, -0.34, 0.2),
        "ear": grey, "ear_inner": dark, "ear_size": (0.17, 0.08, 0.17),
        "cloth": 0x4E7A5A, "cloth_dark": 0x3C6047, "tail": tail,
    })
    head = bpy.data.objects["head"]
    # The bandit mask, a pale brow over it, and a dark stripe down the forehead.
    kit.part("mask", "ball", (0.54, 0.16, 0.15), dark, head, at=(0, -0.2, 0.3), detail=1)
    kit.part("brow", "ball", (0.5, 0.12, 0.07), light, head, at=(0, -0.21, 0.4), detail=1)
    kit.part("stripe", "ball", (0.07, 0.1, 0.2), dark, head, at=(0, -0.22, 0.44))
    for side in ("L", "R"):
        # On the dark mask the pupils need a light rim to read.
        kit.part(f"rim_{side}", "ball", (0.12, 0.04, 0.13), 0xCFC8BC, bpy.data.objects[f"eye_{side}"],
                 at=(0, 0.02, 0))


def tabby(kit: Kit) -> None:
    ginger, stripe, cream = 0xD99A5B, 0xA8642E, 0xF4E6D2

    def tail(kit: Kit, joint) -> None:
        for index in range(7):
            kit.part(f"tail_{index}", "ball", (0.11, 0.11, 0.13), stripe if index % 2 else ginger,
                     joint, at=(0.1 * math.sin(index * 0.5), 0.05 + 0.05 * index, 0.05 + 0.1 * index),
                     turn=(0.4, 0, 0))

    figure(kit, {
        "fur": ginger, "chest": cream, "cheek": cream, "muzzle": cream, "arm": 0x8A5A7A,
        "paw": cream, "muzzle_size": (0.22, 0.15, 0.13), "muzzle_at": (0, -0.25, 0.16),
        "nose_at": (0, -0.32, 0.21), "ear": ginger, "ear_inner": 0xF0B0A0,
        "ear_size": (0.2, 0.08, 0.22), "cloth": 0x8A5A7A, "cloth_dark": 0x6E4662, "tail": tail,
    })
    head = bpy.data.objects["head"]
    for index, x in enumerate((-0.09, 0, 0.09)):
        kit.part(f"forehead_{index}", "box", (0.04, 0.05, 0.14 - 0.03 * abs(index - 1)), stripe, head,
                 at=(x, -0.24, 0.45), turn=(0.5, 0, 0))
    body = bpy.data.objects["body"]
    for index in range(3):
        kit.part(f"back_{index}", "box", (0.4, 0.06, 0.05), stripe, body,
                 at=(0, 0.24, 0.3 + 0.13 * index), turn=(0.3, 0, 0))
    # Round reading glasses low on the nose, and grey whisker-brows of an old cat.
    for side, x in (("L", 0.13), ("R", -0.13)):
        kit.part(f"lens_{side}", "ring", (0.17, 0.12, 0.17), 0xD8B25A, head, at=(x, -0.3, 0.29),
                 segments=12)
        kit.part(f"brow_{side}", "box", (0.12, 0.04, 0.035), 0xEDE4D8, head, at=(x, -0.27, 0.4),
                 turn=(0, 0.25 if side == "L" else -0.25, 0))
        kit.part(f"arm_glasses_{side}", "box", (0.02, 0.24, 0.02), 0xD8B25A, head,
                 at=(x * 1.75, -0.18, 0.3))
    kit.part("bridge", "box", (0.08, 0.02, 0.02), 0xD8B25A, head, at=(0, -0.31, 0.31))
    # A cardigan: the arms are already its colour, a row of buttons down the front.
    for index in range(3):
        kit.part(f"button_{index}", "ball", (0.04, 0.02, 0.04), 0xF0D9A8, body,
                 at=(0, -0.27, 0.36 - 0.08 * index))


def fox(kit: Kit) -> None:
    orange, white, black = 0xE07A3C, 0xF6EEE2, 0x2E2630

    def tail(kit: Kit, joint) -> None:
        kit.part("tail_brush", "ball", (0.3, 0.5, 0.3), orange, joint, at=(0.12, 0.2, 0.2),
                 turn=(0.9, 0, 0.4), detail=1)
        kit.part("tail_tip", "ball", (0.2, 0.22, 0.2), white, joint, at=(0.24, 0.32, 0.45),
                 turn=(0.9, 0, 0.4), detail=1)

    figure(kit, {
        "fur": orange, "chest": white, "cheek": white, "muzzle": white, "arm": orange, "paw": black,
        "muzzle_size": (0.2, 0.3, 0.13), "muzzle_at": (0, -0.3, 0.15), "nose_at": (0, -0.45, 0.17),
        "ear": orange, "ear_inner": white, "ear_tip": black, "ear_size": (0.22, 0.09, 0.3),
        "cloth": 0x3E7C86, "cloth_dark": 0x2F6068, "tail": tail,
    })
    body = bpy.data.objects["body"]
    # A knitted scarf.
    kit.part("scarf", "ball", (0.5, 0.42, 0.13), 0xE8C25A, body, at=(0, -0.02, 0.7), detail=1)
    kit.part("scarf_end", "box", (0.1, 0.04, 0.2), 0xE8C25A, body, at=(0.12, -0.24, 0.58),
             turn=(-0.2, 0, 0.2))


# --- Stitches ----------------------------------------------------------------------------------------


def on_front(centre, size, x: float, z: float, lift: float = 0.006) -> Vector:
    """The point at (x, z) on the front (-y) of an ellipsoid of `size` at `centre`, just above it."""
    a, b, c = size[0] / 2, size[1] / 2, size[2] / 2
    u, w = (x - centre[0]) / a, (z - centre[2]) / c
    depth = math.sqrt(max(1 - u * u - w * w, 0.0))
    return Vector((x, centre[1] - (b + lift) * depth - lift * (1 - depth), z))


def stitch(kit: Kit, name: str, parent, points, colour: int, thread: float = 0.012,
           dashed: bool = True) -> None:
    """Thread along `points`: a dash on every other step when `dashed`, else one unbroken line."""
    for index in range(len(points) - 1):
        if dashed and index % 2:
            continue
        start, end = Vector(points[index]), Vector(points[index + 1])
        along = end - start
        if along.length < 1e-5:
            continue
        turn = along.to_track_quat("Z", "Y").to_euler()
        kit.part(f"{name}_{index}", "box", (thread, thread * 0.7, along.length * (0.85 if dashed else 1.05)),
                 colour, parent, at=tuple((start + end) / 2), turn=tuple(turn))


def curve(centre, size, path, steps: int):
    """`steps` points along `path(t)` -> (x, z) for t from 0 to 1, laid on an ellipsoid's front."""
    return [on_front(centre, size, *path(i / steps)) for i in range(steps + 1)]


# --- A plush teddy bear ---------------------------------------------------------------------------


def teddy(kit: Kit) -> None:
    """A well-loved plush bear: honey fuzz, a paler muzzle, belly and paw pads, button eyes sewn on
    with cream thread, a stitched nose and mouth, a seam down the head, a red bow tie and a blue
    patch sewn over a worn spot on the belly, with a loose thread hanging from it."""
    honey, pale, felt, thread, dark = 0xC8925A, 0xEBCFA4, 0xDDB487, 0x5A3A26, 0x2E1D16
    fabric = {"finish": "fabric", "smooth": True, "detail": 3}

    keeper = kit.joint("keeper", (0, 0, 0))
    body = kit.joint("body", (0, 0, 0.12), keeper)
    torso_at, torso = (0, 0, 0.38), (0.74, 0.62, 0.86)
    kit.part("torso", "ball", torso, honey, body, at=torso_at, **fabric)
    belly_at, belly = (0, -0.2, 0.36), (0.48, 0.24, 0.52)
    kit.part("belly", "ball", belly, pale, body, at=belly_at, **fabric)
    # The patch over a worn spot, sewn on with big stitches, a thread left hanging from a corner.
    patch_at = on_front(belly_at, belly, 0.1, 0.44, lift=0.0)
    kit.part("patch", "box", (0.15, 0.025, 0.14), 0x6F8DB0, body, at=tuple(patch_at),
             turn=(0, 0.28, 0.14), **{"finish": "fabric"})
    corners = [(-0.075, -0.07), (0.075, -0.07), (0.075, 0.07), (-0.075, 0.07), (-0.075, -0.07)]
    turn = Euler((0, 0.28, 0.14)).to_matrix()
    edge = []
    for (u, w), (u2, w2) in zip(corners, corners[1:]):
        for step in range(5):
            t = step / 5
            local = Vector((u + (u2 - u) * t, -0.016, w + (w2 - w) * t))
            edge.append(tuple(patch_at + turn @ local))
    edge.append(edge[0])
    stitch(kit, "patch_stitch", body, edge, 0xF2E6C8, thread=0.01)
    loose = patch_at + turn @ Vector((0.075, -0.018, -0.07))
    kit.part("loose_thread", "box", (0.006, 0.006, 0.09), 0xF2E6C8, body,
             at=tuple(loose + Vector((0.012, 0, -0.04))), turn=(0, 0.35, 0))
    # A seam down the middle of the belly.
    stitch(kit, "belly_seam", body, curve(belly_at, belly, lambda t: (-0.03, 0.56 - 0.36 * t), 9), thread)
    # A red bow tie at the neck.
    kit.part("bow_knot", "ball", (0.08, 0.06, 0.07), 0xC8463C, body, at=(0, -0.29, 0.72), **fabric)
    for side in (1, -1):
        kit.part(f"bow_{side}", "cone", (0.12, 0.06, 0.15), 0xC8463C, body,
                 at=(0.075 * side, -0.27, 0.72), turn=(0, -math.pi / 2 * side, 0), top=0.35,
                 segments=8, smooth=True)

    head = kit.joint("head", (0, 0, 0.74), body)
    skull_at, skull = (0, 0, 0.28), (0.72, 0.62, 0.62)
    kit.part("skull", "ball", skull, honey, head, at=skull_at, **fabric)
    # The seam where the two halves of the head were sewn together, over the top and down the front.
    stitch(kit, "head_seam", head,
           curve(skull_at, skull, lambda t: (0, 0.58 - 0.16 * t), 6), thread)
    muzzle_at, muzzle = (0, -0.26, 0.17), (0.32, 0.22, 0.21)
    kit.part("muzzle", "ball", muzzle, pale, head, at=muzzle_at, **fabric)
    # A satin-stitched nose: a dark base under rows of thread.
    nose_at = on_front(muzzle_at, muzzle, 0, 0.215, lift=-0.02)
    kit.part("nose", "ball", (0.11, 0.06, 0.07), dark, head, at=tuple(nose_at), smooth=True, detail=2)
    for row in range(4):
        z = 0.235 - 0.012 * row
        width = 0.045 - 0.008 * row
        stitch(kit, f"nose_row_{row}", head,
               [tuple(nose_at + Vector((x, -0.032, z - 0.215))) for x in (-width, width)], dark,
               thread=0.009, dashed=False)
    # The mouth: a line down from the nose, opening into a little smile.
    stitch(kit, "mouth_down", head, curve(muzzle_at, muzzle, lambda t: (0, 0.18 - 0.05 * t), 2), dark,
           thread=0.011, dashed=False)
    for side in (1, -1):
        stitch(kit, f"mouth_{side}", head,
               curve(muzzle_at, muzzle,
                     lambda t, s=side: (s * 0.07 * t, 0.13 - 0.03 * math.sin(t * math.pi * 0.8)), 4),
               dark, thread=0.011, dashed=False)
    for side, x in (("L", 0.14), ("R", -0.14)):
        eye = kit.joint(f"eye_{side}", (x, -0.27, 0.33), head)
        # A shiny button, sewn on with a cross of cream thread through its four holes.
        kit.part(f"button_{side}", "cone", (0.11, 0.11, 0.03), 0x1E1412, eye,
                 turn=(math.pi / 2, 0, 0), top=1.0, segments=14, finish="gloss", smooth=True)
        kit.part(f"button_rim_{side}", "ring", (0.115, 0.03, 0.115), 0x3A2A22, eye, at=(0, -0.004, 0),
                 segments=14)
        for u in (-1, 1):
            kit.part(f"thread_{side}_{u}", "box", (0.07, 0.008, 0.008), 0xF2E6C8, eye, at=(0, -0.018, 0),
                     turn=(0, u * math.pi / 4, 0))
        kit.part(f"shine_{side}", "ball", (0.022, 0.01, 0.022), 0xFFF6E8, eye, at=(-0.025, -0.017, 0.027))
        ear = kit.joint(f"ear_{side}", (x * 1.85, 0.02, 0.5), head)
        # The right ear is a little bent from years of being carried by it.
        bend = 0.0 if side == "L" else 0.32
        kit.part(f"ear_{side}_outer", "ball", (0.24, 0.11, 0.23), honey, ear, at=(0, 0, 0.06),
                 turn=(bend, 0, 0), **fabric)
        kit.part(f"ear_{side}_inner", "ball", (0.15, 0.06, 0.14), felt, ear, at=(0, -0.04, 0.05),
                 turn=(bend, 0, 0), **fabric)

    for side, x in (("L", 1), ("R", -1)):
        arm = kit.joint(f"arm_{side}", (0.33 * x, -0.02, 0.6), body)
        kit.part(f"arm_{side}_fur", "ball", (0.22, 0.22, 0.44), honey, arm, at=(0.03 * x, 0, -0.17), **fabric)
        kit.part(f"paw_{side}", "ball", (0.17, 0.09, 0.14), felt, arm, at=(0.04 * x, -0.09, -0.31), **fabric)

    tail = kit.joint("tail", (0, 0.3, 0.16), body)
    kit.part("tail_puff", "ball", (0.16, 0.14, 0.15), honey, tail, at=(0, 0.04, 0.05), **fabric)


# --- A shopkeeper -----------------------------------------------------------------------------------


def human(kit: Kit) -> None:
    """A round, friendly shopkeeper: rosy cheeks and a kind smile, hair in a bun, a cream shirt
    with the sleeves rolled up, and a green apron with a pencil in its pocket, tied in a bow behind."""
    skin, cheek, hair, shirt, apron, apron_dark = 0xF1C09A, 0xEE9884, 0x5E3B28, 0xF4E6D0, 0x3F6F5B, 0x2F5546

    keeper = kit.joint("keeper", (0, 0, 0))
    body = kit.joint("body", (0, 0, 0.12), keeper)
    kit.part("torso", "ball", (0.7, 0.58, 0.84), shirt, body, at=(0, 0, 0.36), detail=2)
    kit.part("apron", "ball", (0.74, 0.62, 0.58), apron, body, at=(0, -0.01, 0.22), detail=2)
    kit.part("bib", "box", (0.34, 0.05, 0.3), apron, body, at=(0, -0.265, 0.5), turn=(-0.12, 0, 0))
    for side in (1, -1):
        kit.part(f"strap_{side}", "box", (0.05, 0.5, 0.04), apron, body, at=(0.15 * side, -0.03, 0.66),
                 turn=(0.25, 0, 0))
    kit.part("pocket", "box", (0.2, 0.04, 0.1), apron_dark, body, at=(0, -0.3, 0.47), turn=(-0.12, 0, 0))
    kit.part("pencil", "cone", (0.025, 0.025, 0.14), 0xF2C14E, body, at=(0.06, -0.3, 0.53),
             turn=(0, 0.2, 0), top=1.0, segments=6)
    kit.part("pencil_tip", "cone", (0.025, 0.025, 0.03), 0x3A2A22, body, at=(0.074, -0.3, 0.605),
             turn=(0, 0.2, 0), top=0.0, segments=6)
    kit.part("neck", "ball", (0.2, 0.18, 0.12), skin, body, at=(0, 0, 0.72), detail=2)

    head = kit.joint("head", (0, 0, 0.74), body)
    face_at, face = (0, 0, 0.28), (0.56, 0.52, 0.6)
    kit.part("face", "ball", face, skin, head, at=face_at, detail=3)
    kit.part("hair", "ball", (0.6, 0.56, 0.4), hair, head, at=(0, 0.05, 0.46), detail=3)
    kit.part("fringe", "ball", (0.5, 0.26, 0.12), hair, head, at=(0.03, -0.12, 0.535), turn=(-0.25, 0, 0.08),
             detail=2)
    kit.part("bun", "ball", (0.2, 0.2, 0.18), hair, head, at=(0, 0.1, 0.66), detail=2)
    kit.part("nose", "ball", (0.1, 0.08, 0.09), 0xEAAE8C, head, at=(0, -0.28, 0.26), detail=2)
    for side, x in (("L", 0.17), ("R", -0.17)):
        kit.part(f"cheek_{side}", "ball", (0.12, 0.05, 0.08), cheek, head,
                 at=tuple(on_front(face_at, face, x, 0.2, lift=-0.012)))
        kit.part(f"brow_{side}", "box", (0.1, 0.03, 0.025), hair, head,
                 at=tuple(on_front(face_at, face, x * 0.66, 0.41, lift=0.0)),
                 turn=(0, 0.2 if side == "L" else -0.2, 0))
        eye = kit.joint(f"eye_{side}", tuple(on_front(face_at, face, x * 0.66, 0.33, lift=0.0)), head)
        kit.part(f"pupil_{side}", "ball", (0.07, 0.04, 0.085), 0x2A1E1C, eye)
        kit.part(f"shine_{side}", "ball", (0.024, 0.02, 0.024), 0xFFF6E8, eye, at=(-0.012, -0.02, 0.02))
        ear = kit.joint(f"ear_{side}", (x * 1.62, 0.02, 0.28), head)
        kit.part(f"ear_{side}_lobe", "ball", (0.07, 0.1, 0.13), skin, ear)
    # A kind, closed smile.
    stitch(kit, "smile", head,
           curve(face_at, face, lambda t: (-0.08 + 0.16 * t, 0.17 - 0.035 * math.sin(t * math.pi)), 8),
           0x7A3A2E, thread=0.016, dashed=False)

    for side, x in (("L", 1), ("R", -1)):
        arm = kit.joint(f"arm_{side}", (0.3 * x, -0.02, 0.6), body)
        kit.part(f"sleeve_{side}", "ball", (0.19, 0.19, 0.3), shirt, arm, at=(0.03 * x, 0, -0.1), detail=2)
        kit.part(f"cuff_{side}", "ball", (0.17, 0.17, 0.08), 0xE2D2B8, arm, at=(0.035 * x, -0.005, -0.22),
                 detail=2)
        kit.part(f"forearm_{side}", "ball", (0.13, 0.13, 0.14), skin, arm, at=(0.04 * x, -0.01, -0.28),
                 detail=2)
        kit.part(f"hand_{side}", "ball", (0.14, 0.13, 0.13), skin, arm, at=(0.04 * x, -0.02, -0.35), detail=2)

    # The apron strings tied in a bow at the back, which swings as the keeper moves.
    tail = kit.joint("tail", (0, 0.3, 0.32), body)
    kit.part("bow_knot", "ball", (0.07, 0.06, 0.07), apron, tail, at=(0, 0.02, 0))
    for side in (1, -1):
        kit.part(f"bow_loop_{side}", "ball", (0.14, 0.05, 0.08), apron, tail, at=(0.08 * side, 0.03, 0.01),
                 turn=(0, 0.3 * side, 0))
        kit.part(f"bow_end_{side}", "box", (0.04, 0.02, 0.14), apron_dark, tail,
                 at=(0.04 * side, 0.03, -0.09), turn=(0, 0.25 * side, 0))


KEEPERS = {"teddy": teddy, "human": human, "raccoon": raccoon, "tabby": tabby, "fox": fox}


def build(name: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    KEEPERS[name](Kit(name))


def export(name: str) -> str:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.abspath(os.path.join(OUT, f"Keeper_{name}.usdz"))
    bpy.ops.wm.usd_export(
        filepath=path, selected_objects_only=False, export_animation=False, export_materials=True,
        export_normals=True, export_uvmaps=True, generate_preview_surface=True,
        export_textures_mode="NEW", overwrite_textures=True,
        convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y", root_prim_path="", merge_parent_xform=False,
        triangulate_meshes=True, export_lights=False, export_cameras=False)
    return path


def render(name: str, folder: str) -> None:
    """A quick look from the shop floor, for checking a keeper before it goes in the app."""
    scene = bpy.context.scene
    camera_data = bpy.data.cameras.new("look")
    camera_data.lens = 50
    camera = bpy.data.objects.new("look", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0.7, -2.6, 1.2)
    direction = Vector((0, 0, 0.75)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun_data.color = (1.0, 0.82, 0.6)
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = Euler((0.9, 0.2, 0.6))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = linear(0x3A2A30)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 480
    scene.render.resolution_y = 560
    scene.render.filepath = os.path.join(folder, f"keeper-{name}.png")
    bpy.ops.render.render(write_still=True)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    folder = None
    if "--render" in argv:
        folder = argv[argv.index("--render") + 1]
        argv = [a for a in argv if a not in ("--render", folder)]
    for name in argv or list(KEEPERS):
        build(name)
        print("exported", export(name))
        if folder:
            render(name, folder)


main()
