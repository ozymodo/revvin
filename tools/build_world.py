# Generates the overgrown-city props and wildlife for Mag Revvin.
#
#   blender --background --python tools/build_world.py -- assets/world
#
# One .glb per asset, origin at the base (ground contact), +Y in Blender is
# the asset's front (-Z in Godot). Material names matter to the game:
#   Leaf*      foliage that sways in the wind (replaced by a shader in Godot)
#   *Glow, LeafPanel, DroneEye, LampGlow   emissive tech left running
# Animated parts are separate named objects with their pivot at the joint:
#   deer: Leg_FL/FR/BL/BR (hip), Head (neck);  bird: Wing_L/Wing_R (shoulder)

import bpy, bmesh, math, os, random, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(argv[0] if argv else "assets/world")
os.makedirs(OUT_DIR, exist_ok=True)


# ------------------------------------------------------------------ helpers

def srgb(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


_mats = {}


def mat(name, color, metallic=0.0, rough=0.7, emission=None, strength=0.0, double=False):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*srgb(color), 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emission:
        b.inputs["Emission Color"].default_value = (*srgb(emission), 1)
        b.inputs["Emission Strength"].default_value = strength
    m.use_backface_culling = not double
    _mats[name] = m
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def active():
    return bpy.context.active_object


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)
    return obj


def jitter(obj, amount, seed):
    rnd = random.Random(seed)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for v in bm.verts:
        v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * amount
    bm.to_mesh(obj.data)
    bm.free()


def blob(loc, radius, m, seed, squash=1.0, subdiv=1, amount=0.18):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = active()
    o.scale = (1, 1, squash)
    bpy.ops.object.transform_apply(scale=True)
    jitter(o, radius * amount, seed)
    return assign(o, m)


def cyl(p0, p1, r0, r1, m, verts=8):
    """Tapered cylinder from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=d.length,
                                    location=(p0 + p1) / 2)
    o = active()
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    bpy.ops.object.transform_apply(rotation=True)
    return assign(o, m)


def box(size, loc, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = active()
    o.scale = size
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return assign(o, m)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = active()
    o.name = name
    o.data.name = name
    return o


def origin_at(obj, point):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.cursor.location = point
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)


def vine(start, length, m, seed, sway=0.25, r=0.035):
    """A hanging vine: a few kinked segments plus small leaves."""
    rnd = random.Random(seed)
    parts = []
    p = Vector(start)
    seg = length / 4
    for _ in range(4):
        q = p + Vector((rnd.uniform(-sway, sway), rnd.uniform(-sway, sway), -seg))
        parts.append(cyl(p, q, r, r * 0.8, m, 5))
        bpy.ops.mesh.primitive_plane_add(size=0.22, location=(p + q) / 2 + Vector((0.06, 0, 0)))
        leaf = active()
        leaf.rotation_euler = (rnd.uniform(0, 3), rnd.uniform(0, 3), rnd.uniform(0, 3))
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(assign(leaf, m))
        p = q
    return parts


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    print("EXPORTED", name)


def palette():
    return {
        "bark": mat("Bark", "#3d3026", 0.0, 0.9),
        "leaf": mat("Leaf", "#2e5e2c", 0.0, 0.8, double=True),
        "leaf2": mat("LeafLight", "#4d7f35", 0.0, 0.8, double=True),
        "leafdark": mat("LeafDark", "#1f4223", 0.0, 0.85, double=True),
        "vine": mat("LeafVine", "#36622f", 0.0, 0.8, double=True),
        "moss": mat("Moss", "#4a6b2a", 0.0, 1.0),
        "metal": mat("TechMetal", "#2a2e35", 0.8, 0.45),
        "concrete": mat("Concrete", "#6b6a63", 0.0, 0.95),
        "glow": mat("TechGlow", "#2f7bff", emission="#2f7bff", strength=5.0),
    }


# ------------------------------------------------------------------ trees

def tree_broad():
    reset()
    P = palette()
    parts = [cyl((0, 0, 0), (0.25, 0.1, 5.5), 0.5, 0.25, P["bark"], 7)]
    for i, a in enumerate((0.3, 2.4, 4.3)):
        tip = Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, 6.6))
        parts.append(cyl((0.2, 0.1, 4.6), tip, 0.2, 0.08, P["bark"], 5))
        parts.append(cyl((0, 0, 0.4), (math.cos(a + 1) * 1.2, math.sin(a + 1) * 1.2, -0.05), 0.28, 0.08, P["bark"], 5))
    canopy = [((0, 0, 7.6), 2.6), ((1.8, 0.6, 7.0), 2.0), ((-1.6, 0.9, 7.2), 2.1), ((0.4, -1.8, 7.0), 2.0), ((-0.6, -0.4, 8.8), 1.7)]
    for i, (c, r) in enumerate(canopy):
        parts.append(blob(c, r, P["leaf"] if i % 2 == 0 else P["leaf2"], i + 1, 0.8))
    join(parts, "TreeBroad")
    export("tree_broad")


def tree_tall():
    reset()
    P = palette()
    parts = [cyl((0, 0, 0), (-0.3, 0.2, 12.0), 0.45, 0.2, P["bark"], 7)]
    for i in range(4):
        a = i * math.pi / 2 + 0.4
        parts.append(cyl((0, 0, 0.6), (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.0), 0.3, 0.1, P["bark"], 5))
    tops = [((-0.3, 0.2, 12.2), 3.2), ((1.6, 0.9, 11.6), 2.0), ((-2.0, -0.8, 11.7), 2.1)]
    for i, (c, r) in enumerate(tops):
        parts.append(blob(c, r, P["leafdark"] if i == 0 else P["leaf"], 20 + i, 0.45))
    rnd = random.Random(5)
    for i in range(7):
        a = rnd.uniform(0, math.tau)
        parts += vine((math.cos(a) * 2.6 - 0.3, math.sin(a) * 2.6 + 0.2, 11.2), rnd.uniform(3, 6), P["vine"], 40 + i)
    join(parts, "TreeTall")
    export("tree_tall")


def tree_tech():
    """A dead data pylon that became a tree: metal trunk wrapped in roots,
    crowned with glowing hexagonal leaf-panels still drinking sunlight."""
    reset()
    P = palette()
    panel = mat("LeafPanel", "#164a2a", 0.4, 0.3, emission="#19e05a", strength=2.2, double=True)
    parts = [cyl((0, 0, 0), (0, 0, 7.0), 0.38, 0.3, P["metal"], 6)]
    parts.append(cyl((0, 0, 3.2), (0, 0, 3.45), 0.42, 0.42, P["glow"], 6))
    parts.append(cyl((0, 0, 5.4), (0, 0, 5.55), 0.36, 0.36, P["glow"], 6))
    # Roots spiral up the pylon
    for k in range(3):
        prev = None
        for i in range(14):
            t = i / 13
            a = t * 5.0 + k * 2.1
            r = 0.45 + (1 - t) * 0.9
            p = Vector((math.cos(a) * r, math.sin(a) * r, t * 5.5 - 0.1))
            if prev is not None:
                parts.append(cyl(prev, p, 0.13 * (1.2 - t), 0.11 * (1.2 - t), P["bark"], 5))
            prev = p
    rnd = random.Random(9)
    for i in range(80):
        # Panels on a dome, tilted outward like leaves
        u, v = rnd.uniform(0, math.tau), rnd.uniform(0.15, 1.25)
        d = Vector((math.cos(u) * math.sin(v), math.sin(u) * math.sin(v), math.cos(v)))
        loc = Vector((0, 0, 7.2)) + d * rnd.uniform(1.6, 2.8) * Vector((1.25, 1.25, 0.75))
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=rnd.uniform(0.35, 0.55), depth=0.04, location=loc)
        o = active()
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(assign(o, panel))
        parts.append(cyl(Vector((0, 0, 6.6)), loc, 0.03, 0.02, P["metal"], 4))
    join(parts, "TreeTech")
    export("tree_tech")


def bush():
    reset()
    P = palette()
    flower = mat("FlowerGlow", "#ff6a2a", emission="#ff4a12", strength=3.0)
    parts = []
    for i, (c, r) in enumerate([((0, 0, 0.5), 0.8), ((0.6, 0.3, 0.4), 0.6), ((-0.5, 0.4, 0.45), 0.6), ((0.1, -0.5, 0.4), 0.55)]):
        parts.append(blob(c, r, P["leaf"] if i % 2 else P["leaf2"], 60 + i, 0.75))
    rnd = random.Random(3)
    for i in range(6):
        a = rnd.uniform(0, math.tau)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.07, location=(math.cos(a) * 0.7, math.sin(a) * 0.7, 0.75))
        parts.append(assign(active(), flower))
    join(parts, "Bush")
    export("bush")


def fern():
    reset()
    P = palette()
    parts = []
    rnd = random.Random(11)
    for i in range(9):
        a = i / 9 * math.tau + rnd.uniform(-0.2, 0.2)
        bm = bmesh.new()
        L = rnd.uniform(0.9, 1.4)
        verts = [(0, -0.05, 0), (0, 0.05, 0), (L * 0.5, 0.18, 0.35), (L, 0.02, 0.15), (L * 0.5, -0.18, 0.35)]
        vs = [bm.verts.new(v) for v in verts]
        bm.faces.new((vs[0], vs[4], vs[2], vs[1]))
        bm.faces.new((vs[4], vs[3], vs[2]))
        me = bpy.data.meshes.new("frond")
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new("frond", me)
        bpy.context.collection.objects.link(o)
        o.rotation_euler = (0, 0, a)
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.transform_apply(rotation=True)
        parts.append(assign(o, P["leaf2"] if i % 2 else P["leaf"]))
    join(parts, "Fern")
    export("fern")


def rubble():
    reset()
    P = palette()
    parts = [blob((0, 0, 0.3), 0.8, P["concrete"], 70, 0.5, 1, 0.3),
             blob((1.0, 0.4, 0.2), 0.5, P["concrete"], 71, 0.6, 1, 0.3),
             blob((-0.6, 0.8, 0.15), 0.4, P["concrete"], 72, 0.6, 1, 0.3),
             blob((0.2, 0.1, 0.62), 0.45, P["moss"], 73, 0.3, 1, 0.2)]
    rebar = mat("Rust", "#6b3b22", 0.6, 0.8)
    parts.append(cyl((0.3, 0, 0.3), (0.9, -0.3, 1.4), 0.03, 0.03, rebar, 4))
    parts.append(cyl((-0.2, 0.3, 0.3), (-0.6, 0.1, 1.1), 0.03, 0.03, rebar, 4))
    join(parts, "Rubble")
    export("rubble")


# ------------------------------------------------------------------ tech remnants

def pylon():
    """Arcology energy pylon, still humming: hex column, glowing bands, a
    flared crown, and a root system that has claimed the base."""
    reset()
    P = palette()
    parts = [cyl((0, 0, 0), (0, 0, 26), 1.0, 0.6, P["metal"], 6)]
    for i in range(5):
        z = 4 + i * 4.5
        r = 1.0 - (z / 26) * 0.4 + 0.06
        parts.append(cyl((0, 0, z), (0, 0, z + 0.35), r, r, P["glow"], 6))
    parts.append(cyl((0, 0, 26), (0, 0, 27.2), 0.6, 2.2, P["metal"], 6))
    parts.append(cyl((0, 0, 27.2), (0, 0, 31), 0.08, 0.02, P["metal"], 4))
    parts.append(blob((0, 0, 31.1), 0.25, P["glow"], 1, 1.0, 1, 0.0))
    for i in range(8):
        a = i / 8 * math.tau
        top = Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 6.0 + (i % 3)))
        mid = Vector((math.cos(a) * 1.8, math.sin(a) * 1.8, 1.5))
        foot = Vector((math.cos(a + 0.3) * 3.4, math.sin(a + 0.3) * 3.4, -0.2))
        parts.append(cyl(foot, mid, 0.35, 0.25, P["bark"], 6))
        parts.append(cyl(mid, top, 0.25, 0.08, P["bark"], 6))
    for i in range(4):
        parts.append(blob((math.cos(i * 1.6) * 1.0, math.sin(i * 1.6) * 1.0, 2 + i * 3), 0.7, P["moss"], 80 + i, 0.5, 1, 0.3))
    rnd = random.Random(12)
    for i in range(6):
        a = rnd.uniform(0, math.tau)
        parts += vine((math.cos(a) * 2.0, math.sin(a) * 2.0, 27.0), rnd.uniform(5, 10), P["vine"], 90 + i, 0.4, 0.05)
    join(parts, "Pylon")
    export("pylon")


def lamp():
    reset()
    P = palette()
    head = mat("LampGlow", "#ffb38a", emission="#ff6a2a", strength=6.0)
    parts = [cyl((0, 0, 0), (0, 0, 6.5), 0.12, 0.08, P["metal"], 6),
             cyl((0, 0, 6.5), (1.6, 0, 7.2), 0.07, 0.06, P["metal"], 6),
             box((0.8, 0.3, 0.12), (1.8, 0, 7.15), P["metal"]),
             box((0.7, 0.24, 0.04), (1.8, 0, 7.08), head)]
    prev = None
    for i in range(18):   # vine spiralling up the pole
        t = i / 17
        p = Vector((math.cos(t * 14) * 0.16, math.sin(t * 14) * 0.16, t * 6.3))
        if prev is not None:
            parts.append(cyl(prev, p, 0.04, 0.04, P["vine"], 4))
        prev = p
    parts += vine((1.6, 0.1, 7.1), 2.2, P["vine"], 5, 0.15)
    parts.append(blob((0, 0, 0.2), 0.45, P["leaf"], 3, 0.6))
    join(parts, "Lamp")
    export("lamp")


def wreck():
    """An abandoned hover-car, nose down in the weeds, with a bush growing
    out of the cabin."""
    reset()
    P = palette()
    rust = mat("Rust", "#5a4032", 0.5, 0.75)
    glass = mat("DeadGlass", "#101418", 0.6, 0.2)
    body = box((1.9, 4.4, 0.7), (0, 0, 0.55), rust, rot=(0.04, 0.03, 0))
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:   # taper the nose
        if v.co.y > 1.0:
            v.co.z *= 0.6
            v.co.x *= 0.85
    bm.to_mesh(body.data)
    bm.free()
    parts = [body, box((1.5, 1.8, 0.45), (0, -0.4, 1.1), glass, rot=(0.05, 0.03, 0))]
    for x in (-1.0, 1.0):
        for y in (-1.5, 1.5):
            parts.append(box((0.3, 0.7, 0.18), (x, y, 0.18), P["metal"]))
    parts.append(blob((0.1, -0.4, 1.6), 0.8, P["leaf"], 4, 0.8))
    parts.append(blob((-0.5, 0.6, 1.2), 0.5, P["leaf2"], 5, 0.8))
    parts.append(blob((0.6, 1.4, 0.9), 0.4, P["moss"], 6, 0.4))
    parts.append(box((0.9, 0.05, 0.05), (0, 2.21, 0.5), mat("WreckGlow", "#ff5a1a", emission="#ff5a1a", strength=2.0)))
    join(parts, "Wreck")
    export("wreck")


def drone():
    """Dormant security drone, still hovering on a trickle of power, moss
    on its back and vines trailing underneath."""
    reset()
    P = palette()
    eye = mat("DroneEye", "#ff4a12", emission="#ff3d10", strength=8.0)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.6, location=(0, 0, 0))
    b = active()
    b.scale = (1, 1, 0.55)
    bpy.ops.object.transform_apply(scale=True)
    parts = [assign(b, P["metal"])]
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        tip = Vector((math.cos(a) * 1.1, math.sin(a) * 1.1, 0.05))
        parts.append(cyl((0, 0, 0), tip, 0.06, 0.05, P["metal"], 4))
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.35, depth=0.04, location=tip + Vector((0, 0, 0.08)))
        parts.append(assign(active(), P["metal"]))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=5, radius=0.14, location=(0, 0.52, -0.05))
    parts.append(assign(active(), eye))
    parts.append(blob((0, 0, 0.3), 0.45, P["moss"], 7, 0.35, 1, 0.25))
    for i in range(3):
        parts += vine((0.2 * i - 0.2, 0.1, -0.25), 1.6 + i * 0.4, P["vine"], 30 + i, 0.15, 0.025)
    join(parts, "Drone")
    export("drone")


# ------------------------------------------------------------------ wildlife

def deer():
    reset()
    fur = mat("Fur", "#8a6446", 0.0, 0.9)
    belly = mat("FurLight", "#c9ab88", 0.0, 0.9)
    dark = mat("Hoof", "#2a2420", 0.0, 0.8)
    spots = mat("SpotGlow", "#3dff7a", emission="#19e05a", strength=2.5)
    antler = mat("Antler", "#d8ccb4", 0.0, 0.7)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1, location=(0, 0, 1.05))
    body = active()
    body.scale = (0.3, 0.7, 0.33)
    bpy.ops.object.transform_apply(scale=True)
    assign(body, fur)
    under = blob((0, 0, 0.9), 0.3, belly, 1, 0.5, 1, 0.05)
    neck = cyl((0, 0.5, 1.15), (0, 0.78, 1.6), 0.15, 0.1, fur, 6)
    tail = cyl((0, -0.68, 1.15), (0, -0.82, 1.05), 0.06, 0.02, belly, 4)
    glow = []
    for i in range(5):   # bioluminescent spots along the back
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.04, location=(0.12 * (1 if i % 2 else -1), -0.4 + i * 0.2, 1.33))
        glow.append(assign(active(), spots))
    join([body, under, neck, tail] + glow, "Body")

    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=0.12, radius2=0.05, depth=0.38, location=(0, 0.95, 1.68), rotation=(-1.2, 0, 0))
    head = assign(active(), fur)
    ears = [cyl((s * 0.08, 0.8, 1.75), (s * 0.2, 0.75, 1.9), 0.04, 0.01, fur, 4) for s in (-1, 1)]
    horns = []
    for s in (-1, 1):
        horns.append(cyl((s * 0.05, 0.82, 1.78), (s * 0.18, 0.78, 2.1), 0.025, 0.015, antler, 4))
        horns.append(cyl((s * 0.14, 0.79, 2.0), (s * 0.28, 0.9, 2.12), 0.015, 0.008, antler, 4))
    h = join([head] + ears + horns, "Head")
    origin_at(h, (0, 0.72, 1.55))

    for name, x, y in (("Leg_FL", -0.15, 0.45), ("Leg_FR", 0.15, 0.45), ("Leg_BL", -0.15, -0.45), ("Leg_BR", 0.15, -0.45)):
        upper = cyl((x, y, 1.0), (x, y, 0.45), 0.07, 0.05, fur, 5)
        lower = cyl((x, y, 0.45), (x, y + 0.03, 0.05), 0.04, 0.035, fur, 5)
        hoof = cyl((x, y + 0.03, 0.08), (x, y + 0.04, 0.0), 0.045, 0.045, dark, 5)
        leg = join([upper, lower, hoof], name)
        origin_at(leg, (x, y, 1.0))
    export("deer")


def bird():
    reset()
    dark = mat("Feather", "#1d2226", 0.0, 0.8, double=True)
    tip = mat("FeatherGlow", "#3d7bff", emission="#2f6bff", strength=1.5, double=True)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=5, radius=1, location=(0, 0, 0))
    b = active()
    b.scale = (0.07, 0.2, 0.07)
    bpy.ops.object.transform_apply(scale=True)
    assign(b, dark)
    beak = cyl((0, 0.18, 0), (0, 0.27, -0.01), 0.025, 0.0, mat("Beak", "#c99a3c"), 4)
    join([b, beak], "Body")
    for name, s in (("Wing_L", -1), ("Wing_R", 1)):
        bm = bmesh.new()
        vs = [bm.verts.new(v) for v in ((0, 0.08, 0), (s * 0.42, -0.02, 0), (s * 0.35, -0.12, 0), (0, -0.08, 0))]
        bm.faces.new(vs)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        w = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(w)
        w.data.materials.append(dark)
        bpy.ops.mesh.primitive_plane_add(size=0.06, location=(s * 0.38, -0.07, 0.001))
        t = assign(active(), tip)
        ww = join([w, t], name)
        origin_at(ww, (0, 0, 0))
    export("bird")


for build in (tree_broad, tree_tall, tree_tech, bush, fern, rubble, pylon, lamp, wreck, drone, deer, bird):
    build()
