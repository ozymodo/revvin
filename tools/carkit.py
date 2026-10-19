# Shared Blender helpers for the car build scripts.
# Positions are written in Godot space (x right, y up, -z forward) and
# converted with P(); sizes passed to box helpers are Godot (x, y, z) too.

import bpy, bmesh, math
from mathutils import Vector, Matrix


def P(x, y, z):
    """Godot-space position -> Blender-space position."""
    return Vector((x, -z, y))


def srgb(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


def material(name, color, metallic=0.0, rough=0.5, emission=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emission:
        b.inputs["Emission Color"].default_value = (*srgb(emission), 1.0)
        b.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    return m


def active():
    return bpy.context.active_object


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)
    return obj


def mesh_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def smooth(obj, angle=35):
    activate(obj)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        bpy.ops.object.shade_smooth()


def bevel(obj, width, segments=3, angle=30):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    return mod


def apply_modifiers(obj):
    activate(obj)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = active()
    obj.name = name
    obj.data.name = name
    return obj


def set_origin(obj, point):
    activate(obj)
    bpy.context.scene.cursor.location = point
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)


def bake_rotation(obj):
    activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def rounded_outline(width, length, r_front, r_rear, n=10):
    """CCW outline in Blender XY. +Y is the front of the car."""
    hw, hl = width / 2, length / 2
    pts = []
    for (cx, cy), r, a0 in (((hw - r_front, hl - r_front), r_front, 0), ((-hw + r_front, hl - r_front), r_front, 90),
                            ((-hw + r_rear, -hl + r_rear), r_rear, 180), ((hw - r_rear, -hl + r_rear), r_rear, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def prism(name, outline, z0, z1, mat, top_scale=1.0):
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in outline]
    top = [bm.verts.new((x * top_scale, y * (1 - (1 - top_scale) * 0.35), z1)) for x, y in outline]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, mat)


def loft(name, stations, mat):
    """Flat-shaded body from cross-sections: (z, half_profile) in Godot
    space, half_profile from bottom centre round the right side to top
    centre, mirrored for the left."""
    bm = bmesh.new()
    rings = []
    for z, half in stations:
        right = [P(x, y, z) for x, y in half]
        left = [P(-x, y, z) for x, y in reversed(half[1:-1])]
        rings.append([bm.verts.new(v) for v in right + left])
    n = len(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, mat)


def box(name, size, loc, mat, rot=(0, 0, 0)):
    """Box; size/loc in Godot space, rot in Blender euler."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=P(*loc), rotation=rot)
    o = active()
    o.name = name
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return assign(o, mat)


def rounded_box(name, size, loc, mat, radius=0.04):
    o = box(name, size, loc, mat)
    bevel(o, radius, 3)
    apply_modifiers(o)
    smooth(o)
    return o


def cyl(p0, p1, r0, r1, mat, verts=8):
    """Tapered cylinder between two Godot-space points."""
    a, b = P(*p0), P(*p1)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=d.length, location=(a + b) / 2)
    o = active()
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(rotation=True)
    return assign(o, mat)


def sphere(loc, radius, mat, scale=(1, 1, 1), segments=12, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=P(*loc))
    o = active()
    o.scale = (scale[0], scale[2], scale[1])
    bpy.ops.object.transform_apply(scale=True)
    return assign(o, mat)


def pipe(points, radius, mat, verts=8):
    """Bent pipe through Godot-space points, with ball joints at the bends."""
    parts = []
    for a, b in zip(points, points[1:]):
        parts.append(cyl(a, b, radius, radius, mat, verts))
    for p in points[1:-1]:
        parts.append(sphere(p, radius * 1.15, mat, segments=8, rings=6))
    return parts


def studs(name, positions, radius, mat):
    """Many tiny spheres (rivets, studs) in a single mesh, built fast."""
    bm = bmesh.new()
    for p in positions:
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=radius, matrix=Matrix.Translation(P(*p)))
    return mesh_obj(name, bm, mat)


def tank(name, radius, length, loc, along_x, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=length, location=P(*loc))
    obj = active()
    obj.name = name
    obj.rotation_euler = (0, math.pi / 2, 0) if along_x else (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    assign(obj, mat)
    bevel(obj, radius * 0.9, 6, 60)
    apply_modifiers(obj)
    smooth(obj, 50)
    return obj


def nozzle(name, loc, mat, r_exit, r_throat, depth, rest_rot, glow=None, extra=None):
    """Bell nozzle hanging along Blender -Z from its pivot at loc (Blender
    space). The game swivels it, so the mesh is built around the pivot."""
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r_exit, radius2=r_throat, depth=depth,
                                    location=(0, 0, -depth / 2), end_fill_type="NOTHING")
    bell = assign(active(), mat)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=r_throat * 1.25, location=(0, 0, 0))
    ball = assign(active(), extra or mat)
    obj = join([bell, ball], name)
    set_origin(obj, Vector((0, 0, 0)))
    solid = obj.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    apply_modifiers(obj)
    if glow:
        bpy.ops.mesh.primitive_torus_add(major_radius=r_exit + 0.006, minor_radius=0.009, major_segments=24,
                                         minor_segments=6, location=(0, 0, -depth))
        ring = assign(active(), glow)
        obj = join([obj, ring], name)
        set_origin(obj, Vector((0, 0, 0)))
    bpy.ops.object.shade_smooth()
    obj.location = loc
    obj.rotation_euler = rest_rot
    return obj


def fan(name, x, ring_mat, blade_mat):
    loc = P(x, 0.035, 1.05)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.24, depth=0.03, location=loc)
    parts = [assign(active(), ring_mat)]
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.06, depth=0.05, location=loc)
    parts.append(assign(active(), ring_mat))
    for i in range(5):
        a = i * 2 * math.pi / 5
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, -0.02)))
        b = active()
        b.scale = (0.17, 0.05, 0.012)
        b.rotation_euler = (0.35, 0, a)
        parts.append(assign(b, blade_mat))
    obj = join(parts, name)
    set_origin(obj, loc)
    return obj


def export(out_path, blend_path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_apply=True, export_yup=True, use_selection=False)
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("EXPORTED", out_path)
