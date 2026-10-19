extends GPUParticles3D
## Bioluminescent spores and fireflies drifting around the player.

var target: Node3D


func _ready() -> void:
	amount = 700
	lifetime = 9.0
	preprocess = 9.0
	local_coords = false
	visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 50, 160))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(70, 8, 70)
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.1
	m.initial_velocity_max = 0.6
	m.gravity = Vector3(0, 0.05, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 6.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	grad.colors = PackedColorArray([Color(0.3, 1.0, 0.4, 0.0), Color(0.3, 1.0, 0.4, 1.0), Color(0.3, 0.6, 1.0, 1.0), Color(0.3, 0.6, 1.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	m.scale_min = 0.5
	m.scale_max = 1.2
	process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(2.5, 2.5, 2.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = g
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = dot
	quad.material = mat
	draw_pass_1 = quad


func _process(_delta: float) -> void:
	if target:
		global_position = target.global_position + Vector3.UP * 4.0
