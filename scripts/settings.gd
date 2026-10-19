extends Node
## Player settings (autoload "Settings"): display, graphics, audio, controls
## and gameplay options, saved to user://settings.cfg and applied live.
## The pause menu (ui/pause_menu.gd) edits `values` through set_value().
##
## Scripted test runs (--test=...) ignore the saved file, so they always
## run on the defaults.

signal changed(key: String)

const PATH := "user://settings.cfg"

const WINDOW_MODES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]
const VSYNC_MODES := ["Off", "On", "Adaptive", "Mailbox (triple buffer)"]
const FPS_CAPS := [0, 30, 60, 75, 120, 144, 165, 240]
const UPSCALERS := ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"]
const AA_MODES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x", "TAA", "MSAA 2x + FXAA"]
const QUALITY := ["Off", "Low", "Medium", "High", "Ultra"]
const LOD := ["Low", "Medium", "High", "Ultra"]
const PRESETS := ["Low", "Medium", "High", "Ultra", "Custom"]
const UNITS := ["km/h", "mph"]
const CAMERAS := ["Chase", "Close", "Far", "Hood"]

const DEFAULTS := {
	# display
	"window_mode": 0, "resolution": "1600x900", "vsync": 1, "max_fps": 0,
	"render_scale": 1.0, "upscaler": 0, "fov": 70.0, "brightness": 1.0,
	# graphics
	"preset": 2, "aa": 2, "shadows": 3, "ssao": true, "glow": true,
	"volumetric_fog": true, "lod": 2,
	# audio (0..1)
	"master_volume": 1.0, "vehicle_volume": 1.0, "air_volume": 0.55,
	"effects_volume": 1.0, "ambience_volume": 1.0, "mute_unfocused": true,
	# controls
	"mouse_sens": 1.0, "invert_mouse_y": false, "invert_air_pitch": false,
	"deadzone": 0.15, "bindings": {},
	# gameplay
	"units": 0, "shake": 1.0, "show_fps": true, "show_hud": true,
	"show_help": true, "camera": 0,
}

## [preset] -> [aa, shadows, ssao, glow, volumetric fog, lod]
const PRESET_VALUES := [
	[1, 1, false, true, false, 0],
	[2, 2, true, true, false, 1],
	[2, 3, true, true, true, 2],
	[3, 4, true, true, true, 3],
]
const GRAPHICS_KEYS := ["aa", "shadows", "ssao", "glow", "volumetric_fog", "lod"]

## Rebindable actions, in menu order: [action, label]. Keyboard/mouse only;
## the controller layout stays fixed.
const REBINDABLE := [
	["throttle", "Accelerate / nose down"], ["brake", "Brake / reverse / nose up"],
	["steer_left", "Steer left"], ["steer_right", "Steer right"],
	["lift", "Jump / fly"], ["boost", "Boost"], ["handbrake", "Powerslide / air roll"],
	["air_roll_left", "Air roll left"], ["air_roll_right", "Air roll right"],
	["flip_forward", "Flip stick forward"], ["flip_back", "Flip stick back"],
	["roll_left", "Flip stick left"], ["roll_right", "Flip stick right"],
	["mag", "MAG (pull to surface)"], ["look_back", "Look back"], ["camera", "Change camera"], ["jet_mode", "Jet mode"],
	["jet_assist", "Jet assist"], ["swap_trim", "Swap trim"], ["swap_car", "Swap car"],
	["fans", "Suction fans"], ["xray", "X-ray"], ["infinite_air", "Infinite air"],
	["reset", "Recover car"], ["respawn", "Respawn at checkpoint"],
	["restart_run", "Restart SKYWAY lap"], ["help", "Toggle help"],
]
## Keyboard pitch in the air follows the drive keys.
const MIRRORS := {"throttle": "kb_nose_down", "brake": "kb_nose_up"}

## Phones and tablets get lighter graphics by default (the player's saved
## choices still win). See also ui/touch_controls.gd.
const MOBILE_DEFAULTS := {
	"preset": 4, "aa": 0, "shadows": 1, "ssao": false, "glow": false,
	"volumetric_fog": false, "lod": 0, "render_scale": 0.6, "max_fps": 2,
	"show_help": false,
}

var values := DEFAULTS.duplicate(true)
var testing := false
## Set by the touch controls once they're in use: no mouse capture, and
## the HUD switches to its compact layout.
var touch_mode := false

## Set by the level / main scene so graphics changes reach them.
var environment: Environment
var sun: DirectionalLight3D

var _default_bindings := {}         # action -> [event, event] (captured from the input map)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			testing = true
	_make_buses()
	if is_mobile():
		values.merge(MOBILE_DEFAULTS, true)
		Engine.max_physics_steps_per_frame = 4    # a slow frame slows the game rather than snowballing
	if not testing:
		_load()
	apply_audio()
	if not testing:
		apply_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and values.mute_unfocused:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, values.master_volume <= 0.001)


## A phone or tablet browser (an iPad may claim to be a Mac; its first
## touch switches the controls on instead).
static func is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	if key == "preset" and int(v) < PRESET_VALUES.size():
		var row: Array = PRESET_VALUES[int(v)]
		for i in GRAPHICS_KEYS.size():
			values[GRAPHICS_KEYS[i]] = row[i]
	elif key in GRAPHICS_KEYS:
		values.preset = _matching_preset()
	_apply(key)
	changed.emit(key)


func reset(keys: Array) -> void:
	for k in keys:
		values[k] = DEFAULTS[k] if not (DEFAULTS[k] is Dictionary) else {}
		_apply(k)
		changed.emit(k)


func _matching_preset() -> int:
	for p in PRESET_VALUES.size():
		var ok := true
		for i in GRAPHICS_KEYS.size():
			if values[GRAPHICS_KEYS[i]] != PRESET_VALUES[p][i]:
				ok = false
		if ok:
			return p
	return PRESETS.size() - 1


func _apply(key: String) -> void:
	if key.ends_with("_volume") or key == "mute_unfocused":
		apply_audio()
	elif key in ["window_mode", "resolution", "vsync", "max_fps", "render_scale", "upscaler"]:
		apply_display()
	elif key in GRAPHICS_KEYS or key in ["preset", "brightness"]:
		apply_graphics()
	elif key in ["deadzone", "invert_air_pitch", "bindings"]:
		apply_controls()


# ------------------------------------------------------------------ saving

func save() -> void:
	if testing:
		return
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("settings", k, values[k])
	cf.save(PATH)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v: Variant = cf.get_value("settings", k)
			if typeof(v) == typeof(DEFAULTS[k]) or (DEFAULTS[k] is float and v is int):
				values[k] = v


# ------------------------------------------------------------------ audio

const BUSES := ["Vehicle", "Effects", "Ambience"]

func _make_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func apply_audio() -> void:
	_bus_volume(0, values.master_volume)
	_bus_volume(AudioServer.get_bus_index("Vehicle"), values.vehicle_volume)
	_bus_volume(AudioServer.get_bus_index("Effects"), values.effects_volume)
	_bus_volume(AudioServer.get_bus_index("Ambience"), values.ambience_volume)


func _bus_volume(i: int, v: float) -> void:
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


## The compressed-air hiss (jets, thrusters, tanks filling) sits inside the
## vehicle and effects mixes, so it gets its own gain on top of the bus.
func air_gain() -> float:
	return values.air_volume


# ------------------------------------------------------------------ display

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web"):
		_apply_render_scale()           # the page owns the window
		return
	match int(values.window_mode):
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var res: PackedStringArray = String(values.resolution).split("x")
			if res.size() == 2:
				var want := Vector2i(int(res[0]), int(res[1]))
				var screen := DisplayServer.screen_get_usable_rect()
				want = want.min(screen.size)
				if DisplayServer.window_get_size() != want:
					DisplayServer.window_set_size(want)
					DisplayServer.window_set_position(screen.position + (screen.size - want) / 2)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][int(values.vsync)])
	_apply_render_scale()


func _apply_render_scale() -> void:
	Engine.max_fps = FPS_CAPS[clampi(int(values.max_fps), 0, FPS_CAPS.size() - 1)]
	var vp := get_viewport()
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
		Viewport.SCALING_3D_MODE_FSR2][int(values.upscaler)]
	vp.scaling_3d_scale = values.render_scale
	if values.upscaler == 2:
		vp.use_taa = false              # FSR 2 does its own temporal AA


## F11: flips between windowed and borderless fullscreen.
func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	set_value("window_mode", 0 if values.window_mode != 0 else 1)
	save()


# ------------------------------------------------------------------ graphics

func apply_graphics() -> void:
	if testing:
		return
	var vp := get_viewport()
	var aa := int(values.aa)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X, Viewport.MSAA_DISABLED, Viewport.MSAA_2X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 or aa == 6 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 5 and values.upscaler != 2
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][int(values.lod)]
	var sh := int(values.shadows)
	if sun:
		sun.shadow_enabled = sh > 0
		sun.directional_shadow_max_distance = [0.0, 120.0, 170.0, 220.0, 340.0][sh]
	if sh > 0:
		RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096, 8192][sh], true)
		RenderingServer.directional_soft_shadow_filter_set_quality([0, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
		vp.positional_shadow_atlas_size = [1024, 1024, 2048, 4096, 8192][sh]
	if environment:
		environment.ssao_enabled = values.ssao
		environment.glow_enabled = values.glow
		environment.volumetric_fog_enabled = values.volumetric_fog
		environment.adjustment_brightness = values.brightness


# ------------------------------------------------------------------ controls

## Called by main once it has built the input map: remembers the default
## keys, then applies the player's own bindings and options.
func init_bindings() -> void:
	for row in REBINDABLE:
		_default_bindings[row[0]] = _kbm_events(row[0])
	apply_controls()


func apply_controls() -> void:
	for a in ["steer_left", "steer_right", "air_nose_down", "air_nose_up", "look_left", "look_right", "look_up", "look_down"]:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, values.deadzone)
	# Controller air pitch: swap the stick directions when inverted.
	for a in ["air_nose_down", "air_nose_up"]:
		if not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadMotion and e.axis == JOY_AXIS_LEFT_Y:
				var down: bool = a == "air_nose_down"
				e.axis_value = (1.0 if values.invert_air_pitch else -1.0) * (1.0 if down else -1.0)
	for row in REBINDABLE:
		var a: String = row[0]
		if not InputMap.has_action(a) or not _default_bindings.has(a):
			continue
		_set_kbm(a, binding(a, 0), binding(a, 1))


## The event in `slot` (0 primary, 1 secondary) for an action, or null.
func binding(action: String, slot: int) -> InputEvent:
	var b: Dictionary = values.bindings
	if b.has(action):
		var codes: Array = b[action]
		return _decode(codes[slot] if slot < codes.size() else "")
	var d: Array = _default_bindings.get(action, [])
	return d[slot] if slot < d.size() else null


func rebind(action: String, slot: int, e: InputEvent) -> void:
	var codes := [_encode(binding(action, 0)), _encode(binding(action, 1))]
	# A key can only do one job: take it off whatever else used it.
	var code := _encode(e)
	if code != "":
		for row in REBINDABLE:
			var other: String = row[0]
			for s in 2:
				if (other != action or s != slot) and _encode(binding(other, s)) == code:
					var oc := [_encode(binding(other, 0)), _encode(binding(other, 1))]
					oc[s] = ""
					values.bindings[other] = oc
	codes[slot] = code
	values.bindings[action] = codes
	set_value("bindings", values.bindings)


func reset_bindings() -> void:
	values.bindings = {}
	set_value("bindings", values.bindings)


static func event_name(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventKey:
		var pk := (e as InputEventKey).physical_keycode
		if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
			pk = DisplayServer.keyboard_get_keycode_from_physical(pk)    # the key's label on this layout
		return OS.get_keycode_string(pk)
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse",
			MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5", MOUSE_BUTTON_WHEEL_UP: "Wheel up",
			MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}.get((e as InputEventMouseButton).button_index, "Mouse %d" % (e as InputEventMouseButton).button_index)
	return "?"


func _kbm_events(action: String) -> Array:
	var out := []
	for e in InputMap.action_get_events(action):
		if (e is InputEventKey or e is InputEventMouseButton) and out.size() < 2:
			out.append(e)
	return out


func _set_kbm(action: String, a: InputEvent, b: InputEvent) -> void:
	for target in [action, MIRRORS.get(action, "")]:
		if target == "" or not InputMap.has_action(target):
			continue
		for e in InputMap.action_get_events(target):
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_erase_event(target, e)
		for e in [a, b]:
			if e and (target == action or e is InputEventKey):
				InputMap.action_add_event(target, e)


static func _encode(e: InputEvent) -> String:
	if e is InputEventKey:
		return "k%d" % (e as InputEventKey).physical_keycode
	if e is InputEventMouseButton:
		return "m%d" % (e as InputEventMouseButton).button_index
	return ""


static func _decode(code: String) -> InputEvent:
	if code.begins_with("k"):
		var k := InputEventKey.new()
		k.physical_keycode = int(code.substr(1)) as Key
		return k
	if code.begins_with("m"):
		var m := InputEventMouseButton.new()
		m.button_index = int(code.substr(1)) as MouseButton
		return m
	return null
