"""Makes the shopkeepers who stand behind the shop counter, from code alone.

Run: Blender -b --python make_shopkeepers.py -- [raccoon fox tabby] [--render <folder>]
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
under it. Shapes are low-poly with flat faces and one plain colour each, like the room's furniture.
Blender's front view looks at the face: the keeper faces -y, which the USD export turns into +z.
"""

from __future__ import annotations

import math
import os
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


class Kit:
    """Makes joints and flat-shaded parts in one keeper, with one material per colour."""

    def __init__(self, name: str):
        self.name = name
        self.materials: dict[int, bpy.types.Material] = {}

    def material(self, hex_colour: int) -> bpy.types.Material:
        if hex_colour in self.materials:
            return self.materials[hex_colour]
        material = bpy.data.materials.new(f"{self.name}_{hex_colour:06X}")
        material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = linear(hex_colour)
        shader.inputs["Roughness"].default_value = 0.85
        material.diffuse_color = linear(hex_colour)
        self.materials[hex_colour] = material
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
    ) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(f"{name}_mesh")
        bm = bmesh.new()
        if shape == "ball":
            bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=0.5)
        elif shape == "box":
            bmesh.ops.create_cube(bm, size=1.0)
        elif shape == "cone":
            bmesh.ops.create_cone(
                bm, cap_ends=True, cap_tris=False, segments=segments, radius1=0.5,
                radius2=0.5 * top, depth=1.0)
        elif shape == "ring":
            ring(bm, segments=max(segments, 10))
        else:
            raise ValueError(shape)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        bm.to_mesh(mesh)
        bm.free()
        for polygon in mesh.polygons:
            polygon.use_smooth = False
        mesh.materials.append(self.material(colour))
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


KEEPERS = {"raccoon": raccoon, "tabby": tabby, "fox": fox}


def build(name: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    KEEPERS[name](Kit(name))


def export(name: str) -> str:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.abspath(os.path.join(OUT, f"Keeper_{name}.usdz"))
    bpy.ops.wm.usd_export(
        filepath=path, selected_objects_only=False, export_animation=False, export_materials=True,
        export_normals=True, export_uvmaps=False, generate_preview_surface=True,
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
