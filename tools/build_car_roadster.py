# Builds the "Phantom": a gloss-black grand-tourer with the long-nose,
# teardrop-cabin, ducktail silhouette of a modern electric roadster, picked
# out with thin high-tech green light lines. Same physical layout and node
# names as the Neon car (build_car.py), so the game's physics apply as-is.
#
#   blender --background --python tools/build_car_roadster.py -- assets/car_roadster.glb
#
# The body is one smooth loft: cross-sections are generated from the
# centre-line, shoulder and plan-width curves below, with wheel arches cut
# into the lower flanks and the greenhouse faces given the glass material.

import bpy, bmesh, math, os, sys
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from carkit import *   # noqa: E402,F403

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "assets/car_roadster.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)

GREEN = "#2bff7a"
M = {
    "paint": material("BlackPaint", "#0a0b0c", 0.25, 0.3),
    "glass": material("SmokedGlass", "#10201c", 0.95, 0.03),
    "trim": material("SatinBlack", "#151719", 0.3, 0.55),
    "carbon": material("Carbon", "#1a1c1f", 0.25, 0.35),
    "floor": material("Floor", "#121315", 0.3, 0.8),
    "green": material("GreenLine", "#7dffb0", emission=GREEN, strength=7.0),
    "head": material("HeadLamp", "#e8fff2", emission="#c8ffe0", strength=8.0),
    "tail": material("TailLamp", "#ff2a2a", emission="#ff1a1a", strength=6.0),
    "under": material("UnderGlow", GREEN, emission=GREEN, strength=6.0),
    "tire": material("Tire", "#121212", 0.0, 0.9),
    "rim": material("Rim", "#1b1d20", 0.85, 0.3),
    "seat": material("Seat", "#17191b", 0.1, 0.6),
    "motor": material("Motor", "#1d2321", 0.5, 0.4),
    "tank": material("TankCarbon", "#1a1d1c", 0.4, 0.3),
    "fan": material("FanMetal", "#2a2d30", 0.7, 0.4),
    "jet": material("JetMetal", "#2b2f33", 0.85, 0.3),
}

LENGTH = 4.8
Z_NOSE, Z_TAIL = -2.38, 2.32
WHEELS = {"FL": (-1.05, -1.57), "FR": (1.05, -1.57), "RL": (-1.05, 1.50), "RR": (1.05, 1.50)}
WHEEL_R, WHEEL_W, HUB_Y = 0.34, 0.3, 0.14
ARCH_R = 0.45


def catmull(keys, z):
    """Catmull-Rom through (z, value) keys, clamped at the ends."""
    if z <= keys[0][0]:
        return keys[0][1]
    if z >= keys[-1][0]:
        return keys[-1][1]
    for i in range(len(keys) - 1):
        z0, z1 = keys[i][0], keys[i + 1][0]
        if z0 <= z <= z1:
            p0 = keys[max(i - 1, 0)][1]
            p1, p2 = keys[i][1], keys[i + 1][1]
            p3 = keys[min(i + 2, len(keys) - 1)][1]
            t = (z - z0) / (z1 - z0)
            return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


# Plan half-width: pronounced front fenders, a waist at the doors, wide rear haunches.
HALF_W = [(-2.38, 0.70), (-2.25, 0.93), (-1.9, 1.10), (-1.57, 1.17), (-1.1, 1.10), (-0.4, 1.02),
          (0.4, 1.04), (1.0, 1.15), (1.5, 1.21), (1.95, 1.17), (2.22, 1.06), (2.32, 0.98)]
# Shoulder (top of the flank): peaks over the wheels, low at the nose.
SHOULDER = [(-2.38, 0.30), (-2.2, 0.42), (-1.9, 0.56), (-1.57, 0.65), (-1.1, 0.62), (-0.4, 0.60),
            (0.4, 0.63), (1.0, 0.68), (1.5, 0.71), (1.95, 0.70), (2.2, 0.68), (2.32, 0.60)]
# Centre-line of the hood and rear deck, without the cabin.
DECK = [(-2.38, 0.29), (-2.2, 0.39), (-1.8, 0.48), (-1.2, 0.56), (0.0, 0.62), (1.0, 0.65),
        (1.8, 0.66), (2.12, 0.68), (2.26, 0.71), (2.32, 0.62)]
# Roof line: a very raked windscreen into a long teardrop that fades into the deck.
ROOF = [(-1.3, 0.56), (-0.9, 0.74), (-0.45, 0.93), (-0.1, 1.01), (0.35, 0.99), (0.85, 0.89),
        (1.3, 0.76), (1.75, 0.66)]
# Greenhouse half-width at its base and its top: a teardrop in plan too.
CAB_BASE = [(-1.3, 0.72), (-0.5, 0.74), (0.4, 0.68), (1.0, 0.56), (1.75, 0.3)]
CAB_TOP = [(-1.3, 0.55), (-0.5, 0.55), (0.4, 0.5), (1.0, 0.38), (1.75, 0.15)]
CAB_Z0, CAB_Z1 = ROOF[0][0], ROOF[-1][0]


def roof(z):
    if z <= CAB_Z0 or z >= CAB_Z1:
        return 0.0
    return catmull(ROOF, z)


def arch(z, hw):
    """Height of the wheel-arch opening at this z (0.15 = no arch)."""
    y = 0.15
    for _, wz in WHEELS.values():
        d = z - wz
        if abs(d) < ARCH_R:
            y = max(y, HUB_Y + math.sqrt(ARCH_R ** 2 - d * d))
    return y


def end_round(z):
    """Round the plan view off at the nose and tail."""
    u = min(max((z - Z_NOSE) / 0.5, 0.0), 1.0)
    v = min(max((Z_TAIL - z) / 0.22, 0.0), 1.0)
    return (0.6 + 0.4 * math.sqrt(1 - (1 - u) ** 2)) * (0.8 + 0.2 * math.sqrt(1 - (1 - v) ** 2))


def section(z):
    """Half cross-section, bottom centre round the right side to the top centre."""
    hw = catmull(HALF_W, z) * end_round(z)
    sh = catmull(SHOULDER, z)
    dk = min(catmull(DECK, z), sh - 0.02)
    rf = max(roof(z), dk + 0.015)
    cab = min(max((rf - dk) / 0.25, 0.0), 1.0)          # 0 = no cabin, 1 = full greenhouse
    ya = arch(z, hw)
    # Floor lifts into a chin at the nose and a diffuser kick at the tail.
    yb = 0.15 + 0.12 * max(0.0, 1 - (z - Z_NOSE) / 0.35) ** 2 + 0.2 * max(0.0, 1 - (Z_TAIL - z) / 0.45) ** 2
    inner = min(0.84, hw - 0.12)
    cw_b = min(catmull(CAB_BASE, z), hw - 0.3) * cab + (hw - 0.3) * (1 - cab)
    cw_t = catmull(CAB_TOP, z) * cab + (hw - 0.3) * 0.5 * (1 - cab)
    flank = (hw + 0.01, (max(ya, 0.2) + sh) * 0.5)       # slight bulge mid-flank
    return [
        (0.0, yb), (inner, yb), (inner + 0.02, max(ya, yb)),     # floor, then up into the arch
        (hw - 0.05, max(ya + 0.02, yb + 0.02)), (hw, max(ya + 0.07 if ya > 0.16 else 0.24, yb + 0.07)), flank,
        (hw - 0.02, sh - 0.07), (hw - 0.09, sh), (hw - 0.2, sh - 0.01),
        ((hw - 0.2 + cw_b) * 0.5, (sh + dk) * 0.5),
        (cw_b, dk + 0.01),                              # base of the glass (10)
        ((cw_b + cw_t) * 0.5 + 0.03, dk + (rf - dk) * 0.62),
        (cw_t, rf - 0.035), (cw_t * 0.5, rf - 0.008), (0.0, rf),
    ]


GLASS_FROM = 10


def body_loft():
    zs = []
    z = Z_NOSE
    while z < Z_TAIL - 1e-6:
        zs.append(z)
        near_end = z < Z_NOSE + 0.3 or z > Z_TAIL - 0.3
        z += 0.04 if near_end else 0.08
    zs.append(Z_TAIL)
    bm = bmesh.new()
    rings, cabs = [], []
    for z in zs:
        half = section(z)
        right = [P(x, y, z) for x, y in half]
        left = [P(-x, y, z) for x, y in reversed(half[1:-1])]
        rings.append([bm.verts.new(v) for v in right + left])
        cabs.append(roof(z) - min(catmull(DECK, z), catmull(SHOULDER, z) - 0.02))
    n = len(rings[0])
    h = len(section(0.0))
    glass_idx = set(range(GLASS_FROM, h - 1)) | set(range(h - 1, h - 1 + (h - 1 - GLASS_FROM)))
    for k, (r0, r1) in enumerate(zip(rings, rings[1:])):
        is_cab = cabs[k] > 0.1 and cabs[k + 1] > 0.1
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
            f.material_index = 1 if is_cab and i in glass_idx else 0
            f.smooth = True
    for r in (rings[0], list(reversed(rings[-1]))):
        f = bm.faces.new(r)
        f.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_obj("Shell", bm, M["paint"])
    obj.data.materials.append(M["glass"])
    smooth(obj, 38)
    return obj, zs


shell, ZS = body_loft()


def surface_point(z, idx, out=0.006):
    """A point on the right half of the body section, nudged outward."""
    half = section(z)
    x, y = half[idx]
    return (x + out, y + out * 0.5, z)


def line_along(points, r, mat, side_mirror=True):
    parts = pipe(points, r, mat, 6)
    if side_mirror:
        parts += pipe([(-x, y, z) for x, y, z in points], r, mat, 6)
    return parts


# ---------------------------------------------------------------- green light lines
accents = []
# Daylight line round the base of the glass, nose of the windscreen to the tail of the teardrop.
dlo = [surface_point(z, GLASS_FROM, 0.012) for z in [CAB_Z0 + 0.2 + i * 0.1 for i in range(int((CAB_Z1 - CAB_Z0 - 0.45) / 0.1))]]
accents += line_along(dlo, 0.008, M["green"])
# Sill blade between the arches.
sill = [(catmull(HALF_W, z) * end_round(z) + 0.004, 0.25, z) for z in [-1.05 + i * 0.1 for i in range(21)]]
accents += line_along(sill, 0.01, M["green"])
# Arch rims: a thin green edge following each arch opening.
for wx, wz in WHEELS.values():
    if wx < 0:
        continue
    pts = []
    for i in range(15):
        a = math.radians(-70 + i * 10)
        z = wz + math.sin(a) * (ARCH_R + 0.005)
        y = HUB_Y + math.cos(a) * (ARCH_R + 0.005)
        hw = catmull(HALF_W, z) * end_round(z)
        pts.append((hw - 0.03, y, z))
    accents += line_along(pts, 0.009, M["green"])
join(accents, "GreenLines")

# Slim wrap-around headlamps: a white lamp with a green brow, swept back along the fender.
for s in (-1, 1):
    lamp = []
    brow = []
    for i in range(9):
        z = -2.3 + i * 0.055
        half = section(z)
        x, y = half[7]
        lamp.append((s * (x + 0.004), y - 0.03, z))
        brow.append((s * (x - 0.02), y + 0.004, z + 0.01))
    join(pipe(lamp, 0.022, M["head"], 8), "HeadLamp")
    join(pipe(brow, 0.008, M["green"], 6), "HeadBrow")
# Nose: a thin green blade under the lip, and a sensor slot.
box("NoseBlade", (0.9, 0.012, 0.02), (0, 0.29, Z_NOSE + 0.004), M["green"])

# Tail: a full-width green bar under the ducktail lip, red lamps at its ends.
tail_z = Z_TAIL + 0.004
box("TailBar", (1.4, 0.018, 0.02), (0, 0.63, tail_z - 0.01), M["green"])
for s in (-1, 1):
    box("TailLamp", (0.26, 0.035, 0.03), (s * 0.6, 0.595, tail_z - 0.02), M["tail"], rot=(0, 0, -s * 0.1))
box("Diffuser", (1.5, 0.03, 0.4), (0, 0.17, 2.12), M["carbon"], rot=(-0.25, 0, 0))
for x in (-0.6, -0.3, 0.0, 0.3, 0.6):
    box("DiffuserFin", (0.02, 0.1, 0.36), (x, 0.2, 2.14), M["carbon"])
for s in (-1, 1):
    box("Underglow", (0.03, 0.02, 2.4), (s * 0.78, 0.07, 0.0), M["under"])

# Door seam and flush handle slot (paint-on-paint, just catches the light).
for s in (-1, 1):
    box("DoorSeam", (0.004, 0.32, 0.006), (s * (catmull(HALF_W, 0.55) + 0.002), 0.45, 0.55), M["trim"])
    box("HandleSlot", (0.006, 0.02, 0.16), (s * (catmull(HALF_W, 0.25) + 0.006), 0.56, 0.25), M["green"])

# Mirrors: small blades on stalks at the base of the windscreen.
for s in (-1, 1):
    z = -0.75
    half = section(z)
    base = (s * (half[GLASS_FROM][0] + 0.02), half[GLASS_FROM][1] + 0.02, z)
    head = (s * (half[GLASS_FROM][0] + 0.2), half[GLASS_FROM][1] + 0.1, z + 0.03)
    stalk = cyl(base, head, 0.015, 0.012, M["paint"], 6)
    cap = sphere(head, 0.07, M["paint"], scale=(1.2, 0.6, 0.6), segments=12, rings=6)
    glow = box("MirrorLine", (0.14, 0.006, 0.006), (head[0], head[1] - 0.035, head[2] - 0.035), M["green"])
    join([stalk, cap, glow], "Mirror")

# Hidden collision hull (same as the other bodies).
prism("Collider", rounded_outline(2.2, LENGTH, 0.55, 0.5), 0.05, 0.8, M["floor"], top_scale=0.95)

# ---------------------------------------------------------------- cockpit (only seen in x-ray)
for name, x in (("Seat_Driver", -0.36), ("Seat_Passenger", 0.36)):
    base = rounded_box(name + "_b", (0.42, 0.12, 0.55), (x, 0.24, -0.38), M["seat"], 0.05)
    back = rounded_box(name + "_k", (0.42, 0.5, 0.12), (x, 0.48, -0.1), M["seat"], 0.05)
    join([base, back], name)

# ---------------------------------------------------------------- powertrain (same layout as Neon)
rounded_box("Motor_F", (0.6, 0.22, 0.35), (0, 0.28, -1.75), M["motor"], 0.05)
rounded_box("Motor_RL", (0.48, 0.3, 0.35), (-0.29, 0.32, 1.49), M["motor"], 0.05)
rounded_box("Motor_RR", (0.48, 0.3, 0.35), (0.29, 0.32, 1.49), M["motor"], 0.05)
tank("Tank_Rocket", 0.28, 1.29, (0.36, 0.42, -0.42), False, M["tank"])
tank("Tank_Thrust", 0.17, 1.29, (0, 0.33, 0.57), True, M["tank"])
fan("Fan_L", -0.43, M["fan"], M["jet"])
fan("Fan_R", 0.43, M["fan"], M["jet"])

# ---------------------------------------------------------------- wheels: low-profile tyres, turbine-blade rims
for key, (x, z) in WHEELS.items():
    loc = P(x, HUB_Y, z)
    side = 1 if x > 0 else -1
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=WHEEL_R, depth=WHEEL_W, location=loc, rotation=(0, math.pi / 2, 0))
    tire = assign(active(), M["tire"])
    bevel(tire, 0.05, 3, 60)
    apply_modifiers(tire)
    face = loc + Vector((side * (WHEEL_W / 2 + 0.002), 0, 0))
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=0.26, depth=0.02, location=face, rotation=(0, math.pi / 2, 0))
    parts = [tire, assign(active(), M["rim"])]
    for i in range(10):                       # curved turbine blades
        a = i / 10 * math.tau
        bpy.ops.mesh.primitive_cube_add(size=1, location=face + Vector((side * 0.012, math.cos(a) * 0.14, math.sin(a) * 0.14)))
        b = active()
        b.scale = (0.012, 0.035, 0.2)
        b.rotation_euler = (a - math.pi / 2 + 0.45, 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        parts.append(assign(b, M["carbon"]))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.262, minor_radius=0.009, major_segments=40, minor_segments=6,
                                     location=face + Vector((side * 0.012, 0, 0)), rotation=(0, math.pi / 2, 0))
    parts.append(assign(active(), M["green"]))
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.045, depth=0.03, location=face + Vector((side * 0.015, 0, 0)),
                                        rotation=(0, math.pi / 2, 0))
    parts.append(assign(active(), M["green"]))
    w = join(parts, "Wheel_" + key)
    bake_rotation(w)
    set_origin(w, loc)
    smooth(w, 40)

# ---------------------------------------------------------------- nozzles (same pivots as Neon)
JETS = {
    "Jet_FL": (-0.67, 0.28, -2.21), "Jet_FR": (0.67, 0.28, -2.21),
    "Jet_ML": (-0.97, 0.30, -0.27), "Jet_MR": (0.97, 0.30, -0.27),
    "Jet_RL": (-0.97, 0.30, 0.56), "Jet_RR": (0.97, 0.30, 0.56),
}
for name, pos in JETS.items():
    nozzle(name, P(*pos), M["jet"], 0.085, 0.045, 0.15, (0, 0, 0), glow=M["green"])
for i, x in enumerate((-0.54, -0.20, 0.20, 0.54)):
    nozzle("Thruster_%d" % i, P(x, 0.36, 2.34), M["jet"], 0.09, 0.055, 0.22, (-math.pi / 2, 0, 0), glow=M["green"])

os.makedirs(os.path.dirname(OUT), exist_ok=True)
blend_dir = os.path.join(os.path.dirname(OUT), "..", "source")
os.makedirs(blend_dir, exist_ok=True)
export(OUT, os.path.abspath(os.path.join(blend_dir, "car_roadster.blend")))
