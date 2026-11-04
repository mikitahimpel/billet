"""Shared helpers for the plush pet models (Tools/make_cat.py, Tools/make_hamster.py).

Both pets are a single body mesh with a "Coat" vertex color. These helpers turn that into a
game-ready plush look that RealityKit can show with plain textured PBR:

- fur strands that follow the direction the coat grows ("Flow" vertex attribute),
- ambient occlusion baked into the color, so creases, ear roots and the spots under paws
  stay soft and shaded under any light,
- glossy eyes with a painted iris and pupil.
"""

import math
import os

import bpy
import numpy as np
from mathutils import Vector


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fuzz(p, scale):
    """Positive-only cell noise in [0, 1] that reads as small clumps of fur."""
    from mathutils import noise
    n = noise.noise(p * scale) * 0.7 + noise.noise(p * scale * 2.3) * 0.3
    return max(n, 0.0) ** 1.4


def set_flow(mesh, flow_fn):
    """Stores the fur growth direction, flattened onto the surface, per vertex."""
    attr = mesh.attributes.new("Flow", "FLOAT_VECTOR", "POINT")
    for v, a in zip(mesh.vertices, attr.data):
        f = flow_fn(v.co)
        n = v.normal
        f = f - n * f.dot(n)
        a.vector = f.normalized() if f.length > 1e-6 else Vector((0.0, 0.0, -1.0))


def _vector_math(nodes, op):
    node = nodes.new("ShaderNodeVectorMath")
    node.operation = op
    return node


def bake_plush_coat(obj, tex_dir, prefix, size=1024, strand_scale=380.0, strand_length=6.0,
                    bump_strength=0.5, ao_strength=0.6, ao_distance=0.02, strand_contrast=0.28):
    """Bakes the fur look of `obj` into color (with AO) and normal textures.

    Expects a "Coat" color attribute and a "Flow" vector attribute on the mesh. Every other
    object in the scene casts occlusion onto the body, so call this after the ears, paws and
    face details are in place. Returns the baked material, already assigned to `obj`.
    """
    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("BakeWorld")
    scene.world.light_settings.distance = ao_distance

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")

    fur = bpy.data.materials.new(f"{prefix}FurSource")
    fur.use_nodes = True
    nodes, links = fur.node_tree.nodes, fur.node_tree.links
    bsdf = nodes["Principled BSDF"]
    coat = nodes.new("ShaderNodeVertexColor")
    coat.layer_name = "Coat"
    flow = nodes.new("ShaderNodeAttribute")
    flow.attribute_name = "Flow"
    coords = nodes.new("ShaderNodeTexCoord")

    # Squash position along the growth direction so noise turns into long strands.
    along = _vector_math(nodes, "DOT_PRODUCT")
    links.new(coords.outputs["Object"], along.inputs[0])
    links.new(flow.outputs["Vector"], along.inputs[1])
    proj = _vector_math(nodes, "SCALE")
    links.new(flow.outputs["Vector"], proj.inputs[0])
    links.new(along.outputs["Value"], proj.inputs["Scale"])
    keep = _vector_math(nodes, "SCALE")
    keep.inputs["Scale"].default_value = 1.0 - 1.0 / strand_length
    links.new(proj.outputs["Vector"], keep.inputs[0])
    stretched = _vector_math(nodes, "SUBTRACT")
    links.new(coords.outputs["Object"], stretched.inputs[0])
    links.new(keep.outputs["Vector"], stretched.inputs[1])
    scaled = _vector_math(nodes, "SCALE")
    scaled.inputs["Scale"].default_value = strand_scale
    links.new(stretched.outputs["Vector"], scaled.inputs[0])

    strands = nodes.new("ShaderNodeTexNoise")
    strands.inputs["Scale"].default_value = 1.0
    strands.inputs["Detail"].default_value = 6.0
    strands.inputs["Roughness"].default_value = 0.62
    links.new(scaled.outputs["Vector"], strands.inputs["Vector"])
    clumps = nodes.new("ShaderNodeTexNoise")   # larger tufts that break up the strand field
    clumps.inputs["Scale"].default_value = 0.22
    clumps.inputs["Detail"].default_value = 2.0
    links.new(scaled.outputs["Vector"], clumps.inputs["Vector"])

    height = nodes.new("ShaderNodeMath")
    height.operation = "MULTIPLY_ADD"
    links.new(clumps.outputs["Fac"], height.inputs[0])
    height.inputs[1].default_value = 0.6
    links.new(strands.outputs["Fac"], height.inputs[2])

    shade = nodes.new("ShaderNodeMapRange")
    shade.inputs["From Min"].default_value = 0.45
    shade.inputs["From Max"].default_value = 1.15
    shade.inputs["To Min"].default_value = 1.08 - strand_contrast   # darker roots between strands
    shade.inputs["To Max"].default_value = 1.08                     # sunlit tips
    links.new(height.outputs["Value"], shade.inputs["Value"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    links.new(coat.outputs["Color"], mix.inputs[6])
    links.new(shade.outputs["Result"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = bump_strength
    bump.inputs["Distance"].default_value = 0.0008
    links.new(height.outputs["Value"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(fur)

    def bake(kind, colorspace, samples, **kwargs):
        img = bpy.data.images.new(f"{prefix}_{kind}", size, size)
        img.colorspace_settings.name = colorspace
        node = nodes.new("ShaderNodeTexImage")
        node.image = img
        nodes.active = node
        scene.cycles.samples = samples
        bpy.ops.object.bake(margin=8, use_clear=True, **kwargs)
        nodes.remove(node)
        return img

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    color = bake("color", "sRGB", 1, type="DIFFUSE", pass_filter={"COLOR"})
    normal = bake("normal", "Non-Color", 1, type="NORMAL", normal_space="TANGENT")
    ao = bake("ao", "Non-Color", 96, type="AO")

    # Fold the occlusion into the color: RealityKit then shows soft contact shading for free.
    px = np.empty(size * size * 4, dtype=np.float32)
    color.pixels.foreach_get(px)
    occ = np.empty_like(px)
    ao.pixels.foreach_get(occ)
    shade_ao = 1.0 - ao_strength * (1.0 - occ[0::4])
    for c in range(3):
        px[c::4] *= shade_ao
    color.pixels.foreach_set(px)

    for img, kind in ((color, "color"), (normal, "normal")):
        img.filepath_raw = os.path.join(tex_dir, f"{prefix.lower()}_{kind}.png")
        img.file_format = "PNG"
        img.save()

    baked = bpy.data.materials.new(f"{prefix}Fur")
    baked.use_nodes = True
    bn, bl = baked.node_tree.nodes, baked.node_tree.links
    bb = bn["Principled BSDF"]
    bb.inputs["Roughness"].default_value = 0.88
    color_node = bn.new("ShaderNodeTexImage")
    color_node.image = color
    normal_node = bn.new("ShaderNodeTexImage")
    normal_node.image = normal
    normal_map = bn.new("ShaderNodeNormalMap")
    bl.new(color_node.outputs["Color"], bb.inputs["Base Color"])
    bl.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    bl.new(normal_map.outputs["Normal"], bb.inputs["Normal"])
    obj.data.materials.clear()
    obj.data.materials.append(baked)
    return baked


def eye_material(name, tex_dir, iris_hex, size=256):
    """Glossy eye with a painted iris and pupil, mapped by planar_eye_uv() (+Y = forward)."""
    iris = [((iris_hex >> s) & 0xFF) / 255 for s in (16, 8, 0)]
    img = bpy.data.images.new(name, size, size, alpha=False)
    px = np.zeros((size, size, 4), dtype=np.float32)
    y, x = np.mgrid[0:size, 0:size]
    u = (x + 0.5) / size * 2 - 1
    v = (y + 0.5) / size * 2 - 1
    r = np.sqrt(u * u + v * v)
    # iris brightens toward the bottom where light enters, with a dark limbal ring
    glow = np.clip(0.55 - v * 0.55, 0, 1) * np.clip((r - 0.30) / 0.25, 0, 1)
    ring = np.clip((r - 0.78) / 0.12, 0, 1)
    pupil = np.clip((0.40 - r) / 0.05, 0, 1)
    for c in range(3):
        val = iris[c] * (0.55 + 0.9 * glow) * (1 - ring * 0.8)
        val = val * (1 - pupil) + 0.012 * pupil
        px[..., c] = np.clip(val, 0, 1)
    px[..., 3] = 1
    # 8-bit generated images store plain sRGB bytes.
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(tex_dir, f"{name.lower()}.png")
    img.file_format = "PNG"
    img.save()

    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.04
    bsdf.inputs["Specular IOR Level"].default_value = 0.8
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def planar_eye_uv(obj, radius):
    """Projects UVs straight along local +Y so the iris texture faces outward."""
    mesh = obj.data
    uv = mesh.uv_layers[0] if mesh.uv_layers else mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / radius * 0.5 + 0.5, co.z / radius * 0.5 + 0.5)


def join_furred(body, parts, coat_fn, flow_fn):
    """Merges small furry parts (arms, ear backs, tail) into the body so they share its baked
    fur and occlusion. coat_fn / flow_fn take (part, world position) and return a color /
    growth direction."""
    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = part
        part.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mesh = part.data
        coat = mesh.color_attributes.new("Coat", "FLOAT_COLOR", "POINT")
        for v, c in zip(mesh.vertices, coat.data):
            col = coat_fn(part, v.co)
            c.color = (col.x, col.y, col.z, 1)
        set_flow(mesh, lambda p, part=part: flow_fn(part, p))
        mesh.materials.clear()
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()


def gradient_material(name, tex_dir, center_hex, edge_hex, roughness=0.6, size=128):
    """Radial gradient (deep at the center, light at the rim), mapped by planar_eye_uv()."""
    a = np.array([((center_hex >> s) & 0xFF) / 255 for s in (16, 8, 0)], dtype=np.float32)
    b = np.array([((edge_hex >> s) & 0xFF) / 255 for s in (16, 8, 0)], dtype=np.float32)
    y, x = np.mgrid[0:size, 0:size]
    r = np.sqrt(((x + 0.5) / size * 2 - 1) ** 2 + ((y + 0.5) / size * 2 - 1) ** 2)
    t = np.clip(r, 0, 1)[..., None] ** 1.6
    px = np.ones((size, size, 4), dtype=np.float32)
    px[..., :3] = a * (1 - t) + b * t
    img = bpy.data.images.new(name, size, size, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(tex_dir, f"{name.lower()}.png")
    img.file_format = "PNG"
    img.save()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m
