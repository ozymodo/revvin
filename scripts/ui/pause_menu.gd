extends CanvasLayer
## Esc: pauses the game and opens this menu. Resume, settings (display,
## graphics, audio, controls with key rebinding, gameplay), restart the
## SKYWAY lap, quit. Every setting applies the moment it changes and is
## saved when the menu closes (settings.gd).

signal closed()

const ACCENT := Color(1.0, 0.62, 0.22)
const BG := Color(0.07, 0.08, 0.1, 0.96)
const TEXT := Color(0.9, 0.92, 0.95)
const DIM := Color(0.6, 0.64, 0.7)

var restart_run := Callable()       # set by main
var recover_car := Callable()

var _root: Control
var _pause_page: Control
var _settings_page: Control
var _tabs: TabContainer
var _first_button: Button
var _controls := {}                 # settings key -> [control, kind, extra]
var _syncing := false
var _bind_buttons := {}             # "action|slot" -> Button
var _listen: Array = []             # [action, slot] while waiting for a key


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = _theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_build_pause()
	_build_settings()
	Settings.changed.connect(_on_changed)
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_page(_pause_page)


func close() -> void:
	_listen = []
	Settings.save()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


# ------------------------------------------------------------------ pages

func _show_page(p: Control) -> void:
	_pause_page.visible = p == _pause_page
	_settings_page.visible = p == _settings_page
	if p == _pause_page:
		_first_button.grab_focus.call_deferred()
	else:
		_tabs.get_tab_bar().grab_focus.call_deferred()


func _build_pause() -> void:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	_pause_page = c
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", ACCENT)
	v.add_child(title)
	_first_button = _button(v, "Resume", close)
	_button(v, "Settings", func() -> void: _show_page(_settings_page))
	_button(v, "Respawn at checkpoint", func() -> void:
		close()
		if recover_car.is_valid():
			recover_car.call())
	_button(v, "Restart SKYWAY lap", func() -> void:
		close()
		if restart_run.is_valid():
			restart_run.call())
	_button(v, "Quit to desktop", func() -> void:
		Settings.save()
		get_tree().quit())


func _build_settings() -> void:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	_settings_page = c
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 680)
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", ACCENT)
	v.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)

	var S := Settings
	var tab := _tab("Display")
	_option(tab, "Window mode", "window_mode", S.WINDOW_MODES)
	_option(tab, "Resolution (windowed)", "resolution", S.RESOLUTIONS, true)
	_option(tab, "V-Sync", "vsync", S.VSYNC_MODES)
	var caps := []
	for f in S.FPS_CAPS:
		caps.append("Unlimited" if f == 0 else "%d fps" % f)
	_option(tab, "Frame rate limit", "max_fps", caps)
	_slider(tab, "Render scale", "render_scale", 0.5, 1.5, 0.05, func(x: float) -> String: return "%d%%" % roundi(x * 100.0))
	_option(tab, "Upscaling", "upscaler", S.UPSCALERS)
	_slider(tab, "Field of view", "fov", 60.0, 110.0, 1.0, func(x: float) -> String: return "%d°" % roundi(x))
	_slider(tab, "Brightness", "brightness", 0.5, 1.5, 0.05, func(x: float) -> String: return "%d%%" % roundi(x * 100.0))

	tab = _tab("Graphics")
	_option(tab, "Quality preset", "preset", S.PRESETS)
	_option(tab, "Anti-aliasing", "aa", S.AA_MODES)
	_option(tab, "Shadow quality", "shadows", S.QUALITY)
	_option(tab, "Level of detail", "lod", S.LOD)
	_check(tab, "Ambient occlusion (SSAO)", "ssao")
	_check(tab, "Bloom / glow", "glow")
	_check(tab, "Volumetric fog and light shafts", "volumetric_fog")

	tab = _tab("Audio")
	var pct := func(x: float) -> String: return "%d%%" % roundi(x * 100.0)
	_slider(tab, "Master volume", "master_volume", 0.0, 1.0, 0.01, pct)
	_slider(tab, "Vehicle (motors, tyres, wind)", "vehicle_volume", 0.0, 1.0, 0.01, pct)
	_slider(tab, "Air (jets, thrusters, tank fill)", "air_volume", 0.0, 1.0, 0.01, pct)
	_slider(tab, "Effects (tricks, combat, smashing)", "effects_volume", 0.0, 1.0, 0.01, pct)
	_slider(tab, "Ambience (city, wildlife)", "ambience_volume", 0.0, 1.0, 0.01, pct)
	_check(tab, "Mute when the window is in the background", "mute_unfocused")

	tab = _tab("Controls")
	_slider(tab, "Mouse sensitivity", "mouse_sens", 0.1, 3.0, 0.05, func(x: float) -> String: return "%.2fx" % x)
	_check(tab, "Invert mouse look (vertical)", "invert_mouse_y")
	_check(tab, "Invert controller air pitch", "invert_air_pitch")
	_slider(tab, "Controller stick deadzone", "deadzone", 0.05, 0.5, 0.01, pct)
	var hint := Label.new()
	hint.text = "Keyboard and mouse bindings. Click a slot, then press a key or mouse button (Esc cancels, Delete clears)."
	hint.add_theme_color_override("font_color", DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(hint)
	for row in S.REBINDABLE:
		var h := _row(tab, row[1])
		for slot in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 0)
			var a: String = row[0]
			b.pressed.connect(func() -> void: _start_listen(a, slot))
			h.add_child(b)
			_bind_buttons["%s|%d" % [a, slot]] = b
	_button(tab, "Reset key bindings", func() -> void: Settings.reset_bindings())

	tab = _tab("Gameplay")
	_option(tab, "Speed units", "units", S.UNITS)
	_option(tab, "Default camera", "camera", S.CAMERAS)
	_slider(tab, "Camera shake", "shake", 0.0, 1.5, 0.05, pct)
	_check(tab, "Show HUD", "show_hud")
	_check(tab, "Show controls overlay", "show_help")
	_check(tab, "Show frame rate", "show_fps")

	var foot := HBoxContainer.new()
	v.add_child(foot)
	_button(foot, "Reset this tab", _reset_tab)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	_button(foot, "Back", func() -> void:
		Settings.save()
		_show_page(_pause_page))
	_sync_all()


const TAB_KEYS := {
	"Display": ["window_mode", "resolution", "vsync", "max_fps", "render_scale", "upscaler", "fov", "brightness"],
	"Graphics": ["preset", "aa", "shadows", "lod", "ssao", "glow", "volumetric_fog"],
	"Audio": ["master_volume", "vehicle_volume", "air_volume", "effects_volume", "ambience_volume", "mute_unfocused"],
	"Controls": ["mouse_sens", "invert_mouse_y", "invert_air_pitch", "deadzone"],
	"Gameplay": ["units", "camera", "shake", "show_hud", "show_help", "show_fps"],
}

func _reset_tab() -> void:
	var name := _tabs.get_tab_title(_tabs.current_tab)
	Settings.reset(TAB_KEYS[name])
	if name == "Controls":
		Settings.reset_bindings()


# ------------------------------------------------------------------ widgets

func _tab(name: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return v


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(380, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _option(parent: Control, text: String, key: String, items: Array, by_name := false) -> void:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(380, 0)
	for it in items:
		o.add_item(str(it))
	o.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			Settings.set_value(key, items[i] if by_name else i))
	_row(parent, text).add_child(o)
	_controls[key] = [o, "option", items if by_name else null]


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(300, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := Label.new()
	l.custom_minimum_size = Vector2(70, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x: float) -> void:
		l.text = fmt.call(x)
		if not _syncing:
			Settings.set_value(key, x))
	h.add_child(s)
	h.add_child(l)
	_controls[key] = [s, "slider", [l, fmt]]


func _check(parent: Control, text: String, key: String) -> void:
	var c := CheckButton.new()
	c.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			Settings.set_value(key, on))
	_row(parent, text).add_child(c)
	_controls[key] = [c, "check", null]


# ------------------------------------------------------------------ sync

func _on_changed(_key: String) -> void:
	_sync_all()


func _sync_all() -> void:
	_syncing = true
	for key in _controls:
		var entry: Array = _controls[key]
		var v: Variant = Settings.get_value(key)
		match entry[1]:
			"option":
				var o: OptionButton = entry[0]
				if entry[2] != null:
					var i: int = (entry[2] as Array).find(v)
					o.select(maxi(i, 0))
				else:
					o.select(int(v))
			"slider":
				var s: HSlider = entry[0]
				s.value = v
				(entry[2][0] as Label).text = (entry[2][1] as Callable).call(float(v))
			"check":
				(entry[0] as CheckButton).button_pressed = v
	for k in _bind_buttons:
		var parts: PackedStringArray = (k as String).split("|")
		(_bind_buttons[k] as Button).text = Settings.event_name(Settings.binding(parts[0], int(parts[1])))
	_syncing = false


# ------------------------------------------------------------------ rebinding

func _start_listen(action: String, slot: int) -> void:
	_listen = [action, slot]
	(_bind_buttons["%s|%d" % [action, slot]] as Button).text = "press a key…"


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _listen.is_empty():
		var e: InputEvent = null
		if event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_ESCAPE:
				_listen = []
				_sync_all()
				get_viewport().set_input_as_handled()
				return
			if k == KEY_DELETE:
				Settings.rebind(_listen[0], _listen[1], null)
				_listen = []
				get_viewport().set_input_as_handled()
				return
			var ke := InputEventKey.new()
			ke.physical_keycode = k
			e = ke
		elif event is InputEventMouseButton and event.pressed:
			var me := InputEventMouseButton.new()
			me.button_index = (event as InputEventMouseButton).button_index
			e = me
		if e:
			var a: String = _listen[0]
			var slot: int = _listen[1]
			_listen = []
			Settings.rebind(a, slot, e)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _settings_page.visible:
			Settings.save()
			_show_page(_pause_page)
		else:
			close()


# ------------------------------------------------------------------ look

func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var box := func(c: Color, border := Color(0, 0, 0, 0), radius := 6) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = c
		s.set_corner_radius_all(radius)
		s.set_content_margin_all(10)
		s.border_color = border
		s.set_border_width_all(2 if border.a > 0 else 0)
		return s
	var panel: StyleBoxFlat = box.call(BG, Color(1, 1, 1, 0.08), 10)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, box.call(Color(0.14, 0.15, 0.19)))
		t.set_stylebox("hover", cls, box.call(Color(0.2, 0.21, 0.26), ACCENT * Color(1, 1, 1, 0.6)))
		t.set_stylebox("pressed", cls, box.call(ACCENT * Color(0.6, 0.6, 0.6)))
		t.set_stylebox("focus", cls, box.call(Color(0, 0, 0, 0), ACCENT))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("panel", "TabContainer", box.call(Color(0.1, 0.11, 0.14), Color(0, 0, 0, 0), 6))
	t.set_stylebox("tab_selected", "TabContainer", box.call(Color(0.1, 0.11, 0.14), ACCENT, 4))
	t.set_stylebox("tab_unselected", "TabContainer", box.call(Color(0.06, 0.07, 0.09), Color(0, 0, 0, 0), 4))
	t.set_stylebox("tab_hovered", "TabContainer", box.call(Color(0.14, 0.15, 0.19), Color(0, 0, 0, 0), 4))
	t.set_color("font_selected_color", "TabContainer", ACCENT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.2, 0.21, 0.25)
	groove.set_corner_radius_all(3)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	var fill := groove.duplicate() as StyleBoxFlat
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t
