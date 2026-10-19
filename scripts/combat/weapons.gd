extends RefCounted
## The power weapons: their stats and their compact models.
##
## Every weapon fires on its own at enemies in range (see arsenal.gd); the
## player only drives. Models are built at mount size (about half a metre
## long), face -Z, and expose a "Muzzle" node. Each level (from picking up
## the same weapon again) adds LEVEL_DMG damage and fires LEVEL_RATE faster.
##
## kind:
##   bolt     energy projectile with a splash (ray gun)
##   hitscan  instant hit with a tracer (sniper, deagle)
##   pellets  a spread of instant hits, short range (scatter cannon)
##   missiles a salvo of homing missiles at several targets (swarm pod)
##   rocket   one big slow rocket, huge splash (thunderhead)
##   beam     continuous beam, damage per second (plasma lance)
##   chain    lightning that jumps between enemies (tesla coil)
##   saw      a saw blade that ricochets from enemy to enemy (saw ripper)
##   frost    icy shard burst that slows what it hits (cryo spiker)

const LEVEL_DMG := 0.3
const LEVEL_RATE := 0.9
const MAX_LEVEL := 5
const TIER_COLORS := [Color(0.75, 0.85, 0.8), Color(0.35, 0.75, 1.0), Color(0.75, 0.4, 1.0), Color(1.0, 0.75, 0.25)]

const DEFS := {
	"raygun": {"name": "RAY GUN", "tier": 1, "kind": "bolt", "range": 55.0, "interval": 0.55, "dmg": 30.0, "splash": 3.5,
		"color": Color(0.3, 1.0, 0.35)},
	"deagle": {"name": "GOLDEN DEAGLE", "tier": 2, "kind": "hitscan", "range": 50.0, "interval": 0.42, "dmg": 48.0,
		"color": Color(1.0, 0.82, 0.3)},
	"scatter": {"name": "SCATTERBLAST", "tier": 1, "kind": "pellets", "range": 22.0, "interval": 0.85, "dmg": 13.0, "pellets": 8,
		"color": Color(1.0, 0.6, 0.3)},
	"saw": {"name": "SAW RIPPER", "tier": 2, "kind": "saw", "range": 45.0, "interval": 1.7, "dmg": 42.0, "bounces": 4,
		"color": Color(0.85, 0.9, 0.95)},
	"frost": {"name": "CRYO SPIKER", "tier": 2, "kind": "frost", "range": 40.0, "interval": 1.1, "dmg": 26.0, "splash": 4.0,
		"color": Color(0.55, 0.9, 1.0)},
	"sniper": {"name": "LONGSHOT", "tier": 3, "kind": "hitscan", "range": 130.0, "interval": 1.6, "dmg": 170.0, "toughest": true,
		"color": Color(0.9, 0.95, 1.0)},
	"swarm": {"name": "SWARM POD", "tier": 3, "kind": "missiles", "range": 75.0, "interval": 2.6, "dmg": 30.0, "count": 6, "splash": 2.5,
		"color": Color(1.0, 0.55, 0.2)},
	"plasma": {"name": "PLASMA LANCE", "tier": 3, "kind": "beam", "range": 38.0, "interval": 0.0, "dmg": 80.0,
		"color": Color(0.55, 0.25, 1.0)},
	"rocket": {"name": "THUNDERHEAD", "tier": 4, "kind": "rocket", "range": 90.0, "interval": 3.2, "dmg": 160.0, "splash": 7.0,
		"color": Color(1.0, 0.45, 0.15)},
	"tesla": {"name": "TESLA COIL", "tier": 4, "kind": "chain", "range": 35.0, "interval": 1.3, "dmg": 75.0, "chains": 4, "chain_r": 13.0,
		"color": Color(0.5, 0.85, 1.0)},
}


static func ids_of_tier(lo: int, hi: int) -> Array:
	var out := []
	for id in DEFS:
		if DEFS[id].tier >= lo and DEFS[id].tier <= hi:
			out.append(id)
	return out


static func stat(id: String, key: String, level: int) -> float:
	var v: float = DEFS[id][key]
	if key == "dmg":
		return v * (1.0 + LEVEL_DMG * (level - 1))
	if key == "interval":
		return v * pow(LEVEL_RATE, level - 1)
	return v


# ------------------------------------------------------------------ models

static var _mats := {}


static func _m(key: String, c := Color.WHITE) -> StandardMaterial3D:
	var k := key + str(c)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	match key:
		"gunmetal":
			m.albedo_color = Color(0.16, 0.17, 0.19)
			m.metallic = 0.85
			m.roughness = 0.3
		"steel":
			m.albedo_color = Color(0.62, 0.64, 0.68)
			m.metallic = 0.95
			m.roughness = 0.22
		"gold":
			m.albedo_color = Color(1.0, 0.76, 0.3)
			m.metallic = 1.0
			m.roughness = 0.18
		"red":
			m.albedo_color = Color(0.7, 0.1, 0.08)
			m.metallic = 0.5
			m.roughness = 0.35
		"cream":
			m.albedo_color = Color(0.9, 0.85, 0.7)
			m.roughness = 0.5
		"olive":
			m.albedo_color = Color(0.3, 0.33, 0.24)
			m.metallic = 0.5
			m.roughness = 0.5
		"copper":
			m.albedo_color = Color(0.8, 0.45, 0.25)
			m.metallic = 0.95
			m.roughness = 0.3
		"glow":
			m.albedo_color = c * 0.3
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 3.0
	_mats[k] = m
	return m


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _cyl(r1: float, r2: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r2
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _tor(a: float, b: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = a
	t.outer_radius = b
	t.rings = 18
	t.ring_segments = 8
	return t


const ALONG_Z := Vector3(PI * 0.5, 0, 0)       # cylinders lie along the barrel


## Builds the model for `id`. Faces -Z, sits on y = 0, has a "Muzzle" node.
static func model(id: String) -> Node3D:
	var g := Node3D.new()
	var c: Color = DEFS[id].color
	var muzzle_z := -0.3
	match id:
		"raygun":
			_p(g, _cyl(0.06, 0.06, 0.28), _m("red"), Vector3(0, 0.06, 0.02), ALONG_Z)
			_p(g, _cyl(0.028, 0.034, 0.24), _m("steel"), Vector3(0, 0.06, -0.2), ALONG_Z)
			for z in [-0.13, -0.2, -0.27]:
				_p(g, _tor(0.035, 0.055), _m("glow", c), Vector3(0, 0.06, z), ALONG_Z)
			_p(g, _box(Vector3(0.01, 0.07, 0.14)), _m("cream"), Vector3(0, 0.13, 0.03))
			muzzle_z = -0.33
		"deagle":
			_p(g, _box(Vector3(0.06, 0.07, 0.34)), _m("gold"), Vector3(0, 0.07, -0.06))
			_p(g, _box(Vector3(0.05, 0.05, 0.12)), _m("gold"), Vector3(0, 0.03, 0.08), Vector3(0.4, 0, 0))
			_p(g, _box(Vector3(0.062, 0.012, 0.3)), _m("gunmetal"), Vector3(0, 0.11, -0.06))
			muzzle_z = -0.24
		"scatter":
			for x in [-0.035, 0.035]:
				_p(g, _cyl(0.035, 0.035, 0.3), _m("gunmetal"), Vector3(x, 0.06, -0.08), ALONG_Z)
			_p(g, _box(Vector3(0.14, 0.08, 0.16)), _m("copper"), Vector3(0, 0.06, 0.1))
			_p(g, _tor(0.075, 0.09), _m("glow", c), Vector3(0, 0.06, -0.2), ALONG_Z)
			muzzle_z = -0.24
		"saw":
			_p(g, _box(Vector3(0.12, 0.08, 0.26)), _m("olive"), Vector3(0, 0.06, 0.02))
			var blade := _p(g, _cyl(0.1, 0.1, 0.012, 16), _m("steel"), Vector3(0, 0.12, -0.12))
			blade.name = "Spin"
			_p(blade, _cyl(0.03, 0.03, 0.02, 8), _m("glow", c), Vector3.ZERO)
			muzzle_z = -0.2
		"frost":
			_p(g, _cyl(0.05, 0.065, 0.26), _m("steel"), Vector3(0, 0.06, -0.03), ALONG_Z)
			for k in 3:
				var a := k * TAU / 3.0
				_p(g, _cyl(0.0, 0.02, 0.16), _m("glow", c), Vector3(cos(a) * 0.05, 0.06 + sin(a) * 0.05, -0.2), ALONG_Z + Vector3(PI, 0, 0))
			muzzle_z = -0.28
		"sniper":
			_p(g, _cyl(0.022, 0.026, 0.62), _m("gunmetal"), Vector3(0, 0.06, -0.18), ALONG_Z)
			_p(g, _box(Vector3(0.06, 0.07, 0.2)), _m("gunmetal"), Vector3(0, 0.06, 0.1))
			_p(g, _cyl(0.025, 0.025, 0.16), _m("steel"), Vector3(0, 0.12, 0.02), ALONG_Z)
			_p(g, _sph(0.022), _m("glow", Color(1.0, 0.2, 0.15)), Vector3(0, 0.12, -0.065))
			muzzle_z = -0.5
		"swarm":
			_p(g, _box(Vector3(0.2, 0.14, 0.24)), _m("olive"), Vector3(0, 0.08, 0.0))
			for row in 2:
				for col in 3:
					_p(g, _cyl(0.025, 0.025, 0.02, 8), _m("glow", c), Vector3(-0.06 + col * 0.06, 0.05 + row * 0.06, -0.121), ALONG_Z)
			muzzle_z = -0.13
		"plasma":
			_p(g, _cyl(0.05, 0.07, 0.3), _m("gunmetal"), Vector3(0, 0.07, -0.02), ALONG_Z)
			for z in [-0.06, -0.14]:
				_p(g, _tor(0.055, 0.075), _m("glow", c), Vector3(0, 0.07, z), ALONG_Z)
			_p(g, _sph(0.045), _m("glow", c.lightened(0.3)), Vector3(0, 0.07, -0.2))
			muzzle_z = -0.24
		"rocket":
			_p(g, _cyl(0.075, 0.075, 0.46), _m("olive"), Vector3(0, 0.09, -0.04), ALONG_Z)
			_p(g, _cyl(0.085, 0.075, 0.06), _m("gunmetal"), Vector3(0, 0.09, -0.28), ALONG_Z)
			_p(g, _box(Vector3(0.04, 0.06, 0.1)), _m("gunmetal"), Vector3(0, 0.03, 0.06))
			_p(g, _tor(0.075, 0.09), _m("glow", c), Vector3(0, 0.09, 0.17), ALONG_Z)
			muzzle_z = -0.32
		"tesla":
			_p(g, _cyl(0.07, 0.09, 0.08), _m("gunmetal"), Vector3(0, 0.04, 0.0))
			_p(g, _cyl(0.025, 0.04, 0.2), _m("copper"), Vector3(0, 0.17, 0.0))
			for y in [0.11, 0.16, 0.21]:
				_p(g, _tor(0.04, 0.06), _m("copper"), Vector3(0, y, 0.0))
			_p(g, _sph(0.05), _m("glow", c), Vector3(0, 0.3, 0.0))
			muzzle_z = 0.0
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.3 if id == "tesla" else 0.06, muzzle_z)
	g.add_child(muzzle)
	return g
