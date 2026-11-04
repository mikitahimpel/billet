"""Renders the 3D night street as the room's camera sees it through Window Seat's window, from
street.bin and its two textures, for checking the layout without the app.

    Blender -b --factory-startup -t 4 -P preview_street_view.py -- <out dir> <png> [yaw pitch zoom]

The wall is a black plate with the window cut out; the sky is a flat night gradient.
"""

import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
OUT, PNG = Path(argv[0]), argv[1]
YAW, PITCH, ZOOM = (float(argv[2]), float(argv[3]), float(argv[4])) if len(argv) > 4 else (0.34, 0.42, 1.0)
INFO = json.loads((OUT / "cards.json").read_text())

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 393 * 2, 852 * 2
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.012, 0.035, 1)


def scene_to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def read_bin(path):
    data = path.read_bytes()
    assert data[:4] == b"BSV1"
    (count,) = struct.unpack_from("<I", data, 4)
    at, meshes = 8, {}
    for _ in range(count):
        n = data[at]
        name = data[at + 1 : at + 1 + n].decode()
        at += 1 + n
        nv, ni = struct.unpack_from("<II", data, at)
        at += 8
        verts = [struct.unpack_from("<5f", data, at + 20 * k) for k in range(nv)]
        at += 20 * nv
        idx = struct.unpack_from(f"<{ni}H", data, at)
        at += 2 * ni
        meshes[name] = (verts, idx)
    return meshes


def textured(name, path, alpha):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(path))
    tex.interpolation = "Smart"
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    if alpha:
        mix = nt.nodes.new("ShaderNodeMixShader")
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
        nt.links.new(clear.outputs[0], mix.inputs[1])
        nt.links.new(emit.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        mat.surface_render_method = "BLENDED"
    else:
        nt.links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


f = INFO["frame"]
right, up, outward = Vector(f["right"]), Vector(f["up"]), Vector(f["out"])
# RealityKit local frame: x right, y up, z towards the home camera (minus out).
basis = Matrix((right, up, -outward)).transposed()
local_to_scene = Matrix.Translation(Vector(f["origin"])) @ basis.to_4x4()
scene_to_bl = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

atlas = textured("atlas", OUT / "street-atlas.png", False)
cards = textured("cards", OUT / "street-cards.png", True)
for name, (verts, idx) in read_bin(OUT / "street.bin").items():
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([v[:3] for v in verts], [], [idx[k : k + 3] for k in range(0, len(idx), 3)])
    uv = mesh.uv_layers.new()
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            u, v = verts[mesh.loops[li].vertex_index][3:5]
            uv.data[li].uv = (u, 1 - v)
    mesh.materials.append(cards if name == "cards" else atlas)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.matrix_world = scene_to_bl @ local_to_scene
    if name == "car":
        lane = INFO["road"]["lanes"][0]
        obj.matrix_world = scene_to_bl @ local_to_scene @ Matrix.Translation((10, 0, -lane))

# The wall: a black plate with the window cut out, at the wall's outer face.
w = dict(x0=0.6, x1=7.0, z0=1.3, z1=5.0, wall=0.35)
bm_verts = [(-60, -40), (70, -40), (70, 60), (-60, 60), (w["x0"], w["z0"]), (w["x1"], w["z0"]), (w["x1"], w["z1"]), (w["x0"], w["z1"])]
wall = bpy.data.meshes.new("wall")
wv = [scene_to_blender((x, z, -w["wall"] + 0.02)) for x, z in bm_verts]
wall.from_pydata(wv, [], [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
wm = bpy.data.materials.new("wall")
wm.use_nodes = True
wm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.015, 0.012, 1)
wall.materials.append(wm)
wobj = bpy.data.objects.new("wall", wall)
scene.collection.objects.link(wobj)

target = Vector((4.3, 1.9, 2.4))
flat = math.cos(PITCH)
eye = target + 19.5 * ZOOM * Vector((flat * math.sin(YAW), math.sin(PITCH), flat * math.cos(YAW)))
cam_data = bpy.data.cameras.new("cam")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(40)
cam_data.clip_start, cam_data.clip_end = 0.5, 300
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = scene_to_blender(eye)
direction = scene_to_blender(target) - cam.location
cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.filepath = PNG
bpy.ops.render.render(write_still=True)
