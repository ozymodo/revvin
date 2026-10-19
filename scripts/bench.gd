extends Node
## Frame-rate benchmark (main.gd adds this when run with --bench):
##   godot --path . --resolution 1920x1080 -- --bench [options]
##     --preset=0..3        graphics preset (default High)
##     --mobile             the phone/tablet defaults (Settings.MOBILE_DEFAULTS)
##     --handheld           the Steam Deck defaults (Settings.HANDHELD_DEFAULTS)
##     --scale=0.77 --upscaler=0..2   render scale and upscaler
##     --static             dynamic detail off (fixed level of detail)
##     --shots=/some/dir    a screenshot per segment
## Free play with everything spawned, V-Sync and the frame cap off (the
## dynamic detail still aims at the target the settings would give). A
## camera visits fixed viewpoints round the world, sweeping a full turn at
## each, then the SKYWAY autopilot drives under the chase camera. Prints
## frame time, GPU time, draw calls, triangles and the detail level per
## segment.

const WARMUP := 1.0
const MEASURE := 4.0
const DRIVE := 20.0

## [name, eye, look-at (Vector3.INF: sweep a full turn)]
const VIEWS := [
	["street", Vector3(0, 2.5, 330), Vector3.INF],
	["crossing", Vector3(150, 3, 150), Vector3.INF],
	["park", Vector3(-150, 6, 80), Vector3.INF],
	["rooftop", Vector3(-80, 70, 260), Vector3.INF],
	["overview", Vector3(0, 240, 470), Vector3(0, 0, 0)],
]

var main: Node
var _cam: Camera3D
var _seg := -1
var _t := 0.0
var _frames: PackedFloat32Array
var _gpu := 0.0
var _cpu := 0.0
var _draws := 0.0
var _prims := 0.0
var _detail := 0.0
var _n := 0
var _rows := []
var _shots := ""
var _shot_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for defaults in [["--handheld", Settings.HANDHELD_DEFAULTS], ["--mobile", Settings.MOBILE_DEFAULTS]]:
		if defaults[0] in args:
			Settings.values.merge(defaults[1], true)
			Settings.set_value("preset", Settings.values.preset)
	for a in args:
		if a.begins_with("--preset="):
			Settings.set_value("preset", int(a.trim_prefix("--preset=")))
		elif a.begins_with("--scale="):
			Settings.set_value("render_scale", float(a.trim_prefix("--scale=")))
		elif a.begins_with("--upscaler="):
			Settings.set_value("upscaler", int(a.trim_prefix("--upscaler=")))
		elif a.begins_with("--shots="):
			_shots = a.trim_prefix("--shots=")
	if "--static" in args:
		Settings.set_value("dynamic_lod", false)
	Settings.apply_graphics()
	# Uncapped, so the numbers show headroom; the governor still aims where
	# it would on the device.
	var target := Settings.target_fps()
	Settings.values.max_fps = 0
	Settings.values.vsync = 0
	Settings.apply_display()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Lod.target_fps = target
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_cam = Camera3D.new()
	_cam.fov = Settings.get_value("fov")
	_cam.far = 2000.0
	add_child(_cam)
	print("bench: %s  %s  preset %s  render scale %.2f  lod %s  dynamic %s (target %.0f fps)" % [RenderingServer.get_video_adapter_name(),
		get_viewport().get_visible_rect().size, Settings.PRESETS[int(Settings.values.preset)],
		Settings.values.render_scale, Settings.LOD[int(Settings.values.lod)], Settings.values.dynamic_lod, Lod.target_fps])
	_next()


func _next() -> void:
	_seg += 1
	_t = 0.0
	_frames = PackedFloat32Array()
	_gpu = 0.0
	_cpu = 0.0
	_draws = 0.0
	_prims = 0.0
	_detail = 0.0
	_n = 0
	_shot_done = false
	if _seg < VIEWS.size():
		_cam.current = true
	elif _seg == VIEWS.size():
		main.cam.current = true
		main.car.global_transform = main.course.start_xform()
		main.cam.snap()
	else:
		_report()


func _process(delta: float) -> void:
	if _seg > VIEWS.size():
		return
	_t += delta
	var span := MEASURE if _seg < VIEWS.size() else DRIVE
	var seg_name: String = VIEWS[_seg][0] if _seg < VIEWS.size() else "drive"
	if _seg < VIEWS.size():
		var v: Array = VIEWS[_seg]
		_cam.global_position = v[1]
		if v[2] == Vector3.INF:
			var yaw := TAU * clampf(_t / (WARMUP + span), 0.0, 1.0)
			_cam.global_basis = Basis.from_euler(Vector3(-0.12 if v[1].y < 20.0 else -0.35, yaw, 0))
		else:
			_cam.look_at(v[2])
	if _shots != "" and not _shot_done and _t > WARMUP + 0.5:
		_shot_done = true
		get_viewport().get_texture().get_image().save_png(_shots.path_join(seg_name + ".png"))
	if _t > WARMUP:
		var rid := get_viewport().get_viewport_rid()
		_frames.append(delta * 1000.0)
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		_detail += Lod.detail
		_n += 1
	if _t > WARMUP + span:
		var sorted := _frames.duplicate()
		sorted.sort()
		var avg := 0.0
		for f in _frames:
			avg += f
		avg /= maxi(_n, 1)
		var p99: float = sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if sorted.size() > 0 else 0.0
		_rows.append([seg_name, 1000.0 / avg, avg, p99, _gpu / _n, _cpu / _n, _draws / _n, _prims / _n, _detail / _n])
		_next()


func _physics_process(_delta: float) -> void:
	if _seg != VIEWS.size():
		return
	var plan: Dictionary = main._autopilot()
	for a in ["throttle", "brake", "steer_left", "steer_right"]:
		if plan.get(a, 0.0) > 0.0:
			Input.action_press(a, plan[a])
		else:
			Input.action_release(a)


func _report() -> void:
	print("%-9s %7s %8s %8s %8s %8s %7s %9s %7s" % ["segment", "fps", "frame", "p99", "gpu", "render", "draws", "tris", "detail"])
	var worst := INF
	var sum := 0.0
	for r in _rows:
		print("%-9s %7.1f %6.2fms %6.2fms %6.2fms %6.2fms %7.0f %8.0fk %6.0f%%" % [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7] / 1000.0, r[8] * 100.0])
		worst = minf(worst, r[1])
		sum += r[1]
	print("BENCH avg %.1f fps  worst segment %.1f fps" % [sum / _rows.size(), worst])
	get_tree().quit()
