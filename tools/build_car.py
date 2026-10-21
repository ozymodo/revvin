# Generates the Max Revvin model and exports it for Godot.
#
#   blender --background --python tools/build_car.py -- assets/car.glb
#
# Layout follows the top-down schematic. Positions below are written in
# Godot space (x right, y up, -z forward) and converted with P().
# Node names matter: the game finds Wheel_*, Fan_*, Jet_*, Thruster_*,
# Motor_*, Tank_*, Seat_Passenger, Shell and Collider by name.
#
# Pivot conventions the game relies on:
#   Wheel_*    origin at hub, spins about local X
#   Fan_*      origin at centre, spins about local Y (Godot)
#   Jet_*, Thruster_*  origin at gimbal pivot, exhaust along local -Y (Godot)

import bpy, bmesh, math, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "car.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)


def P(x, y, z):
    """Godot-space position -> Blender-space position."""
    return Vector((x, -z, y))


def srgb(hex_str):
    h = hex_str.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255.0) ** 2.2 for i in (0, 2, 4))


def material(name, color, metallic=0.0, rough=0.5, emission=None, strength=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(color), 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*srgb(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
    return m


M = {
    "body": material("Body", "#2b2d34", 0.65, 0.42),
    "carbon": material("Carbon", "#111216", 0.3, 0.6),
    "cyan": material("NeonCyan", "#19f0ff", emission="#19f0ff", strength=8.0),
    "magenta": material("NeonMagenta", "#ff2bd6", emission="#ff2bd6", strength=8.0),
    "hazard": material("Hazard", "#ffd400", 0.2, 0.5, emission="#ffb000", strength=0.6),
    "floor": material("Floor", "#232325", 0.2, 0.8),
    "glass": material("Glass", "#0b2a33", 0.7, 0.05, alpha=0.5),
    "motor": material("Motor", "#3e3580", 0.3, 0.4, emission="#6b5cff", strength=0.0),
    "tank": material("Tank", "#1f3f78", 0.25, 0.3),
    "fan": material("Fan", "#2a5a4a", 0.3, 0.4),
    "thruster": material("Thruster", "#e09a3a", 0.7, 0.3),
    "jet": material("Jet", "#8a3a26", 0.6, 0.35),
    "tire": material("Tire", "#151515", 0.0, 0.9),
    "rim": material("Rim", "#3a3d45", 0.9, 0.3),
    "seat": material("Seat", "#2b2b2e", 0.0, 0.7),
    "helmet": material("Helmet", "#16171b", 0.4, 0.3),
}


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def mesh_obj(name, bm, mat, location=Vector((0, 0, 0))):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = link(bpy.data.objects.new(name, me))
    obj.location = location
    obj.data.materials.append(mat)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


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
    mod.harden_normals = False
    return mod


def apply_modifiers(obj):
    activate(obj)
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def rounded_outline(width, length, r_front, r_rear, n=10):
    """CCW outline in Blender XY. +Y is the front of the car."""
    hw, hl = width / 2, length / 2
    pts = []
    corners = [
        ((hw - r_front, hl - r_front), r_front, 0),
        ((-hw + r_front, hl - r_front), r_front, 90),
        ((-hw + r_rear, -hl + r_rear), r_rear, 180),
        ((hw - r_rear, -hl + r_rear), r_rear, 270),
    ]
    for (cx, cy), r, a0 in corners:
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
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, mat)


def rounded_box(name, size, loc, mat, radius=0.04):
    """size and loc are in Godot space (x, y, z)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=P(*loc))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    bevel(obj, radius, 3)
    apply_modifiers(obj)
    smooth(obj)
    return obj


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def set_origin(obj, point):
    """Move the object's origin to a Blender-space point without moving the mesh."""
    activate(obj)
    bpy.context.scene.cursor.location = point
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)


# ---------------------------------------------------------------- body
LENGTH, WIDTH = 4.8, 1.87

chassis = prism("Chassis", rounded_outline(WIDTH - 0.04, LENGTH - 0.04, 0.5, 0.45), 0.05, 0.15, M["floor"])
bevel(chassis, 0.03, 2)
apply_modifiers(chassis)

def loft(name, stations, mat):
    """Faceted body from cross-sections. Each station is (z, half_profile)
    in Godot space; half_profile runs from bottom centre round the right
    side to top centre and is mirrored for the left. Left flat-shaded."""
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


def section(hw, ys, yt, spine, c, yb=0.15):
    """Hexagonal-ish half cross-section: flat floor, vertical flank,
    chamfered shoulder, raised centre spine."""
    return [(0, yb), (hw - 0.07, yb), (hw, yb + 0.09), (hw, ys), (hw - c, yt),
            (hw * 0.3, yt + spine * 0.7), (0, yt + spine)]


# Wedge nose, wasp waist at the axles, high squared-off tail.
STATIONS = [
    (-2.42, section(0.60, 0.25, 0.29, 0.00, 0.10, 0.18)),
    (-2.22, section(0.84, 0.30, 0.37, 0.01, 0.14)),
    (-1.85, section(0.90, 0.36, 0.47, 0.03, 0.20)),
    (-1.57, section(0.84, 0.38, 0.52, 0.04, 0.20)),
    (-0.95, section(0.935, 0.42, 0.58, 0.05, 0.25)),
    (0.40, section(0.935, 0.45, 0.62, 0.06, 0.27)),
    (1.50, section(0.86, 0.47, 0.64, 0.05, 0.24)),
    (2.10, section(0.92, 0.48, 0.63, 0.03, 0.22)),
    (2.43, section(0.82, 0.46, 0.58, 0.00, 0.20)),
]
shell = loft("Shell", STATIONS, M["body"])

# Gem-cut canopy: a low-poly ellipsoid, flat shaded so every facet catches light.
bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1, location=P(0, 0.6, -0.45))
canopy = bpy.context.active_object
canopy.name = "Canopy"
canopy.scale = (0.72, 1.15, 0.42)
bpy.ops.object.transform_apply(scale=True)
canopy.data.materials.append(M["glass"])


def strip(name, size, loc, mat, rot=(0, 0, 0)):
    """Thin box; size/loc in Godot space, rot in Blender euler."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=P(*loc), rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    o.data.materials.append(mat)
    return o


# Segmented LED nose bar and the cut-in "brow" above it.
for i in range(8):
    x = -0.49 + i * 0.14
    strip("HeadLight_%d" % i, (0.1, 0.035, 0.03), (x, 0.31, -2.36 + abs(x) * 0.18), M["cyan"])
strip("Brow", (1.2, 0.03, 0.12), (0, 0.36, -2.24), M["carbon"])

# Tail: full-width magenta bar plus two vertical slits.
strip("TailLight", (1.36, 0.045, 0.03), (0, 0.52, 2.44), M["magenta"])
for x in (-0.7, 0.7):
    strip("TailSlit", (0.03, 0.2, 0.03), (x, 0.38, 2.43), M["magenta"])
strip("Diffuser", (1.5, 0.08, 0.3), (0, 0.19, 2.3), M["carbon"])

# Flank neon at the shoulder line and a spine light down the rear deck.
for side in (-1, 1):
    strip("FlankNeon", (0.02, 0.025, 2.1), (side * 0.94, 0.41, -0.05), M["cyan"])
    strip("Underglow", (0.03, 0.02, 3.4), (side * 0.8, 0.055, 0.0), M["magenta"])
    # Angular intakes ahead of the rear wheels.
    strip("Intake", (0.04, 0.16, 0.42), (side * 0.9, 0.31, 0.95), M["carbon"], rot=(0, 0, side * 0.12))
strip("SpineNeon", (0.03, 0.02, 1.5), (0, 0.69, 1.35), M["cyan"])
strip("Hazard", (0.22, 0.012, 0.32), (0.42, 0.52, -1.75), M["hazard"])

# Rear wing on two raked struts, with a lit trailing edge.
for x in (-0.5, 0.5):
    strip("WingStrut", (0.05, 0.42, 0.18), (x, 0.82, 2.08), M["carbon"], rot=(-0.35, 0, 0))
strip("Wing", (1.8, 0.04, 0.42), (0, 1.04, 2.16), M["body"], rot=(0.12, 0, 0))
strip("WingNeon", (1.8, 0.02, 0.02), (0, 1.02, 2.38), M["cyan"])
for x in (-0.9, 0.9):
    strip("WingEndplate", (0.03, 0.22, 0.5), (x, 1.0, 2.16), M["carbon"])

# Angular arch fenders over each wheel, carried on an arm from the flank.
for x, z in ((-1.05, -1.57), (1.05, -1.57), (-1.05, 1.50), (1.05, 1.50)):
    side = 1 if x > 0 else -1
    strip("Fender", (0.34, 0.035, 0.5), (x, 0.7, z), M["body"])
    for dz in (-1, 1):   # front and rear facets angle down like a gable
        strip("Fender", (0.34, 0.035, 0.32), (x, 0.62, z + dz * 0.38), M["body"], rot=(dz * 0.55, 0, 0))
    strip("FenderArm", (0.2, 0.06, 0.16), (x - side * 0.2, 0.62, z), M["carbon"], rot=(0, side * 0.5, 0))
    strip("FenderNeon", (0.02, 0.02, 0.46), (x + side * 0.17, 0.69, z), M["cyan"])

# Hidden collision hull: covers the body and the wheels' width, not the canopy.
collider = prism("Collider", rounded_outline(2.2, LENGTH, 0.55, 0.5), 0.05, 0.8, M["floor"], top_scale=0.95)

# ---------------------------------------------------------------- cockpit
def seat(name, x):
    base = rounded_box(name + "_base", (0.42, 0.12, 0.55), (x, 0.24, -0.38), M["seat"], 0.04)
    back = rounded_box(name + "_back", (0.42, 0.55, 0.12), (x, 0.5, -0.1), M["seat"], 0.04)
    return join([base, back], name)

seat("Seat_Driver", -0.36)
seat("Seat_Passenger", 0.36)

bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.14, location=P(-0.36, 0.86, -0.32))
helmet = bpy.context.active_object
helmet.name = "Helmet"
helmet.data.materials.append(M["helmet"])
bpy.ops.object.shade_smooth()
strip("Visor", (0.2, 0.05, 0.05), (-0.36, 0.87, -0.45), M["cyan"])

# ---------------------------------------------------------------- powertrain
rounded_box("Motor_F", (0.6, 0.22, 0.35), (0, 0.28, -1.75), M["motor"], 0.05)
rounded_box("Motor_RL", (0.48, 0.3, 0.35), (-0.29, 0.32, 1.49), M["motor"], 0.05)
rounded_box("Motor_RR", (0.48, 0.3, 0.35), (0.29, 0.32, 1.49), M["motor"], 0.05)


def tank(name, radius, length, loc, along_x):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=length, location=P(*loc))
    obj = bpy.context.active_object
    obj.name = name
    if along_x:
        obj.rotation_euler = (0, math.pi / 2, 0)
    else:
        obj.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    obj.data.materials.append(M["tank"])
    bevel(obj, radius * 0.9, 6, 60)
    apply_modifiers(obj)
    smooth(obj, 50)
    return obj

# 400 L (Rocket trim) sits where the passenger would; 200 L runs across the car.
tank("Tank_Rocket", 0.28, 1.29, (0.36, 0.42, -0.42), along_x=False)
tank("Tank_Thrust", 0.17, 1.29, (0, 0.33, 0.57), along_x=True)


def fan(name, x):
    loc = P(x, 0.035, 1.05)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.24, depth=0.03, location=loc)
    ring = bpy.context.active_object
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.06, depth=0.05, location=loc)
    hub = bpy.context.active_object
    parts = [ring, hub]
    for o in parts:
        o.data.materials.append(M["fan"])
    for i in range(5):
        a = i * 2 * math.pi / 5
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc + Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, -0.02)))
        b = bpy.context.active_object
        b.scale = (0.17, 0.05, 0.012)
        b.rotation_euler = (0.35, 0, a)
        b.data.materials.append(M["rim"])
        parts.append(b)
    obj = join(parts, name)
    set_origin(obj, loc)
    return obj

fan("Fan_L", -0.43)
fan("Fan_R", 0.43)

# ---------------------------------------------------------------- wheels
WHEEL_R, WHEEL_W = 0.34, 0.26
WHEELS = {"FL": (-1.05, -1.57), "FR": (1.05, -1.57), "RL": (-1.05, 1.50), "RR": (1.05, 1.50)}


def wheel(name, x, z):
    loc = P(x, 0.14, z)
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=WHEEL_R, depth=WHEEL_W, location=loc, rotation=(0, math.pi / 2, 0))
    tire = bpy.context.active_object
    tire.data.materials.append(M["tire"])
    bevel(tire, 0.06, 3, 60)
    apply_modifiers(tire)
    side = 1 if x > 0 else -1
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.22, depth=0.02,
                                        location=loc + Vector((side * WHEEL_W / 2, 0, 0)), rotation=(0, math.pi / 2, 0))
    rim = bpy.context.active_object
    rim.data.materials.append(M["rim"])
    parts = [tire, rim]
    # Spokes make the spin readable.
    for i in range(5):
        a = i * 2 * math.pi / 5
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc + Vector((side * (WHEEL_W / 2 + 0.012), math.cos(a) * 0.1, math.sin(a) * 0.1)))
        s = bpy.context.active_object
        s.scale = (0.01, 0.045, 0.2)
        s.rotation_euler = (a - math.pi / 2, 0, 0)
        s.data.materials.append(M["tire"])
        parts.append(s)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.25, minor_radius=0.012, major_segments=40, minor_segments=6,
                                     location=loc + Vector((side * (WHEEL_W / 2 + 0.01), 0, 0)), rotation=(0, math.pi / 2, 0))
    ring = bpy.context.active_object
    ring.data.materials.append(M["cyan"])
    parts.append(ring)
    obj = join(parts, name)
    # Bake the tyre's 90 degree rotation into the mesh: the game overwrites
    # the node rotation every frame (steer + spin about local X).
    activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    set_origin(obj, loc)
    smooth(obj, 40)
    return obj

for key, (x, z) in WHEELS.items():
    wheel("Wheel_" + key, x, z)

# ---------------------------------------------------------------- nozzles
def nozzle(name, loc, mat, r_exit, r_throat, depth, rest_rot, glow=None):
    """Bell nozzle hanging along Blender -Z from its pivot at loc."""
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=r_exit, radius2=r_throat, depth=depth,
                                    location=(0, 0, -depth / 2), end_fill_type="NOTHING")
    bell = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=r_throat * 1.25, location=(0, 0, 0))
    ball = bpy.context.active_object
    for o in (bell, ball):
        o.data.materials.append(mat)
    parts = [bell, ball]
    obj = join(parts, name)
    set_origin(obj, Vector((0, 0, 0)))
    solid = obj.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    apply_modifiers(obj)
    if glow:
        bpy.ops.mesh.primitive_torus_add(major_radius=r_exit + 0.006, minor_radius=0.008, major_segments=24,
                                         minor_segments=6, location=(0, 0, -depth))
        ring = bpy.context.active_object
        ring.data.materials.append(glow)
        obj = join([obj, ring], name)
        set_origin(obj, Vector((0, 0, 0)))
    bpy.ops.object.shade_smooth()
    obj.location = loc
    obj.rotation_euler = rest_rot
    return obj

# Six perimeter jets (Rocket trim): front corners, then two pairs on the sides.
JETS = {
    "Jet_FL": (-0.67, 0.28, -2.21), "Jet_FR": (0.67, 0.28, -2.21),
    "Jet_ML": (-0.97, 0.30, -0.27), "Jet_MR": (0.97, 0.30, -0.27),
    "Jet_RL": (-0.97, 0.30, 0.56), "Jet_RR": (0.97, 0.30, 0.56),
}
for name, pos in JETS.items():
    nozzle(name, P(*pos), M["jet"], 0.085, 0.045, 0.15, (0, 0, 0), glow=M["cyan"])

# Four rear thrusters, exhaust pointing backwards (Godot +Z).
for i, x in enumerate((-0.54, -0.20, 0.20, 0.54)):
    nozzle("Thruster_%d" % i, P(x, 0.36, 2.34), M["thruster"], 0.09, 0.055, 0.22, (-math.pi / 2, 0, 0), glow=M["magenta"])

# ---------------------------------------------------------------- export
bpy.ops.object.select_all(action="SELECT")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_yup=True, use_selection=False)
# Editable source lives outside Godot's import path (source/ has a .gdignore).
blend_dir = os.path.join(os.path.dirname(OUT), "..", "source")
os.makedirs(blend_dir, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(os.path.join(blend_dir, "car.blend")))
print("EXPORTED", OUT)
