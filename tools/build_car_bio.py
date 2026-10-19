# Builds the "Symbiote": a rugged high-tech steampunk take on the thrust car,
# driven by a living pilot. Same physical layout and node names as the
# Neon car (build_car.py), so the game's physics and effects apply as-is.
#
#   blender --background --python tools/build_car_bio.py -- assets/car_bio.glb
#
# Extra nodes the game animates if present:
#   Pilot (breathes), Pilot_Eye (looks where you steer), Tendril_* (sway),
#   and any surface using the BioGlow material (pulses like a heartbeat).

import bpy, bmesh, math, os, random, sys
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from carkit import *   # noqa: E402,F403

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "assets/car_bio.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
rnd = random.Random(17)

M = {
    "shell": material("Enamel", "#2a1f63", 0.45, 0.45),            # indigo enamel
    "armor": material("Armor", "#1d4a2c", 0.5, 0.55),              # deep green plate
    "brass": material("Brass", "#b58a3c", 0.95, 0.32),
    "copper": material("Copper", "#b0643a", 0.95, 0.35),
    "iron": material("Iron", "#2e2d2f", 0.7, 0.6),
    "floor": material("Floor", "#1c1b1d", 0.4, 0.8),
    "rubber": material("Rubber", "#141312", 0.0, 0.95),
    "leather": material("Leather", "#4a2e1d", 0.0, 0.7),
    "glass": material("PodGlass", "#1b4a2e", 0.3, 0.05, alpha=0.32),
    "lens": material("LensGlow", "#7dff9a", emission="#3dff6a", strength=6.0),
    "bio": material("BioGlow", "#2bd65a", 0.0, 0.4, emission="#19e05a", strength=3.0),
    "flesh": material("PilotFlesh", "#2f8a45", 0.1, 0.35, emission="#147a35", strength=0.8),
    "eye": material("PilotEye", "#ff7a2a", 0.0, 0.2, emission="#ff4a12", strength=5.0),
    "pupil": material("Pupil", "#050505", 0.0, 0.2),
    "tail": material("TailGlow", "#ff5a1a", emission="#ff4a12", strength=5.0),
    "under": material("UnderGlow", "#19e05a", emission="#19e05a", strength=6.0),
    "motor": material("Motor", "#245e36", 0.4, 0.45),
    "tank": material("TankEnamel", "#1f5a34", 0.3, 0.35),
    "fan": material("FanIron", "#2a2f2b", 0.6, 0.5),
    "gauge": material("GaugeFace", "#e8dfc8", 0.0, 0.4),
}

# ---------------------------------------------------------------- chassis + body
LENGTH, WIDTH = 4.8, 1.87
chassis = prism("Chassis", rounded_outline(WIDTH - 0.04, LENGTH - 0.04, 0.45, 0.4), 0.05, 0.15, M["floor"])


def section(hw, ys, yt):
    """Boxy, slab-sided cross-section with a small chamfer: built, not styled."""
    return [(0, 0.15), (hw - 0.05, 0.15), (hw, 0.22), (hw, ys), (hw - 0.12, yt), (0, yt + 0.02)]


STATIONS = [
    (-2.45, section(0.80, 0.40, 0.48)),
    (-2.25, section(0.92, 0.46, 0.56)),
    (-1.57, section(0.90, 0.50, 0.60)),
    (-0.95, section(0.935, 0.52, 0.62)),
    (0.40, section(0.935, 0.54, 0.64)),
    (1.50, section(0.90, 0.54, 0.65)),
    (2.20, section(0.92, 0.52, 0.63)),
    (2.45, section(0.86, 0.50, 0.60)),
]
loft("Shell", STATIONS, M["shell"])

# Riveted green armour on the flanks and hood.
rivets = []
for s in (-1, 1):
    box("ArmorSide", (0.025, 0.22, 2.3), (s * 0.95, 0.37, -0.05), M["armor"])
    for i in range(20):
        z = -1.15 + i * 0.115
        rivets += [(s * 0.965, 0.27, z), (s * 0.965, 0.47, z)]
    box("BrassTrim", (0.03, 0.035, 4.3), (s * 0.945, 0.535, 0.0), M["brass"])
box("ArmorHood", (1.25, 0.025, 0.95), (0, 0.6, -1.85), M["armor"], rot=(-0.05, 0, 0))
for i in range(9):
    x = -0.58 + i * 0.145
    rivets += [(x, 0.622, -2.3), (x, 0.622, -1.4)]
studs("Rivets", rivets, 0.017, M["brass"])

# Cow-catcher, splitter and round headlamps.
for i in range(7):
    x = -0.6 + i * 0.2
    cyl((x, 0.42, -2.45), (x * 1.1, 0.12, -2.7), 0.02, 0.02, M["brass"], 6)
cyl((-0.72, 0.13, -2.7), (0.72, 0.13, -2.7), 0.03, 0.03, M["iron"], 6)
cyl((-0.66, 0.41, -2.47), (0.66, 0.41, -2.47), 0.025, 0.025, M["brass"], 6)
box("Splitter", (1.75, 0.03, 0.28), (0, 0.13, -2.5), M["iron"])
for x in (-0.55, 0.55):
    cyl((x, 0.47, -2.42), (x, 0.47, -2.5), 0.11, 0.11, M["brass"], 16)
    cyl((x, 0.47, -2.5), (x, 0.47, -2.52), 0.085, 0.085, M["lens"], 16)

# Rear: iron louvred diffuser, round tail lamps.
for i in range(5):
    box("Louvre", (1.5, 0.02, 0.25), (0, 0.16 + i * 0.045, 2.38 + i * 0.02), M["iron"], rot=(0.5, 0, 0))
for x in (-0.72, 0.72):
    cyl((x, 0.47, 2.42), (x, 0.47, 2.5), 0.08, 0.08, M["brass"], 14)
    cyl((x, 0.47, 2.5), (x, 0.47, 2.52), 0.06, 0.06, M["tail"], 14)
for s in (-1, 1):
    box("Underglow", (0.03, 0.02, 3.4), (s * 0.8, 0.055, 0.0), M["under"])

# Copper pressure lines from the tanks back to the thrusters, and a coil on the hood.
for s in (-1, 1):
    pipe([(s * 0.97, 0.5, -0.7), (s * 0.97, 0.5, 1.85), (s * 0.7, 0.44, 2.25), (s * 0.54, 0.38, 2.32)], 0.032, M["copper"])
coil = []
prev = None
for i in range(41):
    t = i / 40
    p = (0.38 + math.cos(t * math.tau * 5) * 0.07, 0.66 + math.sin(t * math.tau * 5) * 0.07, -1.7 + t * 0.6)
    if prev:
        coil.append(cyl(prev, p, 0.014, 0.014, M["copper"], 5))
    prev = p
join(coil, "PressureCoil")

# Compressor intake stacks behind the pod, glowing green inside.
for x in (-0.48, 0.48):
    cyl((x, 0.62, 0.6), (x, 1.12, 0.6), 0.06, 0.055, M["brass"], 12)
    cyl((x, 1.12, 0.6), (x, 1.22, 0.6), 0.055, 0.1, M["brass"], 12)
    cyl((x, 1.2, 0.6), (x, 1.21, 0.6), 0.08, 0.08, M["bio"], 12)
    cyl((x, 0.8, 0.6), (x, 0.86, 0.6), 0.075, 0.075, M["iron"], 12)

# Pressure gauges on the cowl.
for i, x in enumerate((-0.15, 0.05, 0.25)):
    cyl((x, 0.63, -1.02), (x, 0.66, -1.05), 0.07, 0.07, M["brass"], 16)
    cyl((x, 0.66, -1.05), (x, 0.665, -1.055), 0.058, 0.058, M["gauge"], 16)

# Riveted iron mudguards over each wheel, on a bracket from the body.
for x, z in ((-1.05, -1.57), (1.05, -1.57), (-1.05, 1.50), (1.05, 1.50)):
    side = 1 if x > 0 else -1
    for a in (-60, -30, 0, 30, 60):
        r = math.radians(a)
        box("Mudguard", (0.38, 0.03, 0.28), (x, 0.3 + 0.52 * math.cos(r), z + 0.52 * math.sin(r)), M["iron"], rot=(r, 0, 0))
    box("MudguardBrass", (0.02, 0.035, 0.3), (x + side * 0.19, 0.835, z), M["brass"])
    box("Bracket", (0.2, 0.05, 0.12), (x - side * 0.2, 0.78, z), M["iron"])

# Hidden collision hull (same as the Neon car).
prism("Collider", rounded_outline(2.2, LENGTH, 0.55, 0.5), 0.05, 0.8, M["floor"], top_scale=0.95)

# ---------------------------------------------------------------- the pilot pod
bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1, location=P(0, 0.62, -0.45))
canopy = active()
canopy.name = "Canopy"
canopy.scale = (0.72, 1.05, 0.46)
bpy.ops.object.transform_apply(scale=True)
assign(canopy, M["glass"])
bpy.ops.object.shade_smooth()
cyl((-0.74, 0.6, -0.45), (0.74, 0.6, -0.45), 0.03, 0.03, M["brass"], 8)     # pod hoop

# Leather cradles (the passenger one shows on the Thrust trim).
for name, x in (("Seat_Driver", -0.36), ("Seat_Passenger", 0.36)):
    base = rounded_box(name + "_b", (0.42, 0.12, 0.55), (x, 0.24, -0.38), M["leather"], 0.05)
    back = rounded_box(name + "_k", (0.42, 0.5, 0.12), (x, 0.48, -0.1), M["leather"], 0.05)
    join([base, back], name)

# The pilot: a soft, glowing organism, a single eye, and tendrils on the controls.
PILOT = (-0.36, 0.78, -0.35)
pilot = sphere(PILOT, 0.22, M["flesh"], scale=(1.0, 0.9, 1.1), segments=16, rings=10)
bm = bmesh.new()
bm.from_mesh(pilot.data)
for v in bm.verts:
    v.co += v.co.normalized() * (rnd.uniform(-0.02, 0.03))
bm.to_mesh(pilot.data)
bm.free()
spots = [sphere((PILOT[0] + math.cos(a) * 0.17, PILOT[1] + 0.12, PILOT[2] + math.sin(a) * 0.17), 0.025, M["bio"], segments=6, rings=4)
         for a in (0.5, 1.6, 2.8, 4.0, 5.2)]
pilot = join([pilot] + spots, "Pilot")
smooth(pilot, 60)
set_origin(pilot, P(*PILOT))

eye_c = (-0.36, 0.83, -0.54)
eye = sphere(eye_c, 0.075, M["eye"], segments=14, rings=8)
pupil = sphere((eye_c[0], eye_c[1], eye_c[2] - 0.065), 0.03, M["pupil"], scale=(1.0, 1.6, 0.4), segments=8, rings=6)
eye = join([eye, pupil], "Pilot_Eye")
set_origin(eye, P(*eye_c))

# Steering yoke for the tendrils to hold.
bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.015, location=P(-0.36, 0.64, -0.82), rotation=(0, 0, 0))
yoke = assign(active(), M["brass"])
yoke.rotation_euler = (math.radians(70), 0, 0)
bake_rotation(yoke)
cyl((-0.36, 0.64, -0.82), (-0.36, 0.5, -1.0), 0.02, 0.02, M["iron"], 6)

targets = [(-0.48, 0.66, -0.8), (-0.24, 0.66, -0.8), (-0.05, 0.6, -0.95), (-0.36, 0.3, -0.95), (0.05, 0.5, -0.35), (-0.4, 0.55, -0.05)]
for i, t in enumerate(targets):
    pts = []
    for k in range(7):
        f = k / 6
        p = Vector(PILOT).lerp(Vector(t), f)
        p += Vector((rnd.uniform(-1, 1), rnd.uniform(-0.5, 1), rnd.uniform(-1, 1))) * 0.05 * math.sin(f * math.pi)
        pts.append(tuple(p))
    segs = []
    for k in range(6):
        r0 = 0.035 * (1 - k / 7)
        segs.append(cyl(pts[k], pts[k + 1], r0, r0 * 0.85, M["flesh"], 6))
    segs.append(sphere(t, 0.022, M["bio"], segments=6, rings=4))
    tendril = join(segs, "Tendril_%d" % i)
    set_origin(tendril, P(*PILOT))

# Glowing nerve-veins from the pod out to the motors and tanks.
def vein(points):
    out = []
    for a, b in zip(points, points[1:]):
        mid = tuple(Vector(a).lerp(Vector(b), 0.5) + Vector((rnd.uniform(-0.05, 0.05), 0, rnd.uniform(-0.05, 0.05))))
        out += [cyl(a, mid, 0.02, 0.018, M["bio"], 5), cyl(mid, b, 0.018, 0.016, M["bio"], 5)]
    return out
veins = []
veins += vein([(-0.5, 0.64, -0.9), (-0.45, 0.62, -1.3), (-0.2, 0.62, -1.6), (0, 0.6, -1.95), (0.25, 0.6, -2.2)])
veins += vein([(-0.6, 0.62, -0.7), (-0.8, 0.56, -1.0), (-0.92, 0.52, -1.5)])
veins += vein([(0.3, 0.68, 0.1), (0.2, 0.67, 0.6), (0, 0.67, 1.0), (-0.25, 0.66, 1.5), (-0.1, 0.65, 2.1)])
veins += vein([(-0.3, 0.68, 0.1), (-0.6, 0.66, 0.4), (-0.8, 0.6, 1.0), (-0.92, 0.56, 1.4)])
join(veins, "Veins")

# ---------------------------------------------------------------- powertrain (same layout as Neon)
rounded_box("Motor_F", (0.6, 0.22, 0.35), (0, 0.28, -1.75), M["motor"], 0.05)
rounded_box("Motor_RL", (0.48, 0.3, 0.35), (-0.29, 0.32, 1.49), M["motor"], 0.05)
rounded_box("Motor_RR", (0.48, 0.3, 0.35), (0.29, 0.32, 1.49), M["motor"], 0.05)


def banded_tank(name, radius, length, loc, along_x):
    t = tank(name, radius, length, loc, along_x, M["tank"])
    bands = []
    for f in (-0.3, 0.0, 0.3):
        c = Vector(loc) + (Vector((f * length, 0, 0)) if along_x else Vector((0, 0, f * length)))
        bpy.ops.mesh.primitive_torus_add(major_radius=radius + 0.01, minor_radius=0.015, location=P(*c),
                                         rotation=(0, math.pi / 2, 0) if along_x else (math.pi / 2, 0, 0))
        bands.append(assign(active(), M["brass"]))
    out = join([t] + bands, name)
    set_origin(out, P(*loc))
    return out


banded_tank("Tank_Rocket", 0.28, 1.29, (0.36, 0.42, -0.42), along_x=False)
banded_tank("Tank_Thrust", 0.17, 1.29, (0, 0.33, 0.57), along_x=True)
fan("Fan_L", -0.43, M["fan"], M["brass"])
fan("Fan_R", 0.43, M["fan"], M["brass"])

# ---------------------------------------------------------------- wheels: knobbly tyres, brass spoked hubs
WHEEL_R, WHEEL_W = 0.34, 0.3
for key, (x, z) in {"FL": (-1.05, -1.57), "FR": (1.05, -1.57), "RL": (-1.05, 1.50), "RR": (1.05, 1.50)}.items():
    loc = P(x, 0.14, z)
    side = 1 if x > 0 else -1
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=WHEEL_R - 0.03, depth=WHEEL_W, location=loc, rotation=(0, math.pi / 2, 0))
    parts = [assign(active(), M["rubber"])]
    for i in range(20):                       # tread blocks
        a = i / 20 * math.tau
        c = loc + Vector((0, math.cos(a), math.sin(a))) * (WHEEL_R - 0.02)
        bpy.ops.mesh.primitive_cube_add(size=1, location=c, rotation=(a, 0, 0))
        b = active()
        b.scale = (WHEEL_W * (0.9 if i % 2 else 0.6), 0.07, 0.05)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        parts.append(assign(b, M["rubber"]))
    hub = loc + Vector((side * WHEEL_W / 2, 0, 0))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.02, location=hub, rotation=(0, math.pi / 2, 0))
    parts.append(assign(active(), M["brass"]))
    for i in range(6):
        a = i / 6 * math.tau
        bpy.ops.mesh.primitive_cube_add(size=1, location=hub + Vector((side * 0.005, math.cos(a) * 0.1, math.sin(a) * 0.1)))
        s = active()
        s.scale = (0.02, 0.03, 0.2)
        s.rotation_euler = (a - math.pi / 2, 0, 0)
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        parts.append(assign(s, M["brass"]))
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.05, location=hub + Vector((side * 0.01, 0, 0)))
    parts.append(assign(active(), M["bio"]))
    w = join(parts, "Wheel_" + key)
    bake_rotation(w)
    set_origin(w, loc)

# ---------------------------------------------------------------- nozzles
JETS = {
    "Jet_FL": (-0.67, 0.28, -2.21), "Jet_FR": (0.67, 0.28, -2.21),
    "Jet_ML": (-0.97, 0.30, -0.27), "Jet_MR": (0.97, 0.30, -0.27),
    "Jet_RL": (-0.97, 0.30, 0.56), "Jet_RR": (0.97, 0.30, 0.56),
}
for name, pos in JETS.items():
    nozzle(name, P(*pos), M["copper"], 0.085, 0.045, 0.15, (0, 0, 0), glow=M["bio"], extra=M["brass"])
for i, x in enumerate((-0.54, -0.20, 0.20, 0.54)):
    nozzle("Thruster_%d" % i, P(x, 0.36, 2.34), M["brass"], 0.1, 0.055, 0.24, (-math.pi / 2, 0, 0), glow=M["bio"], extra=M["iron"])

os.makedirs(os.path.dirname(OUT), exist_ok=True)
blend_dir = os.path.join(os.path.dirname(OUT), "..", "source")
os.makedirs(blend_dir, exist_ok=True)
export(OUT, os.path.abspath(os.path.join(blend_dir, "car_bio.blend")))
