class_name PauseMenu
extends Control

signal resume_requested
signal save_requested(world_name: String)
signal return_to_menu_requested
signal exit_requested
signal diagnostics_requested

var world_name := "World"
var _name_input: LineEdit
var _autosave: SpinBox
var _ui_scale: SpinBox
var _reduced_motion: CheckBox
var _screen_shake: CheckBox
var _window_mode: OptionButton
var _master_audio: HSlider
var _audio_sliders: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = KoalaSandTheme.build()
	visible = false
	_build_ui()


func open(current_world_name: String) -> void:
	world_name = current_world_name
	_name_input.text = current_world_name
	visible = true
	KoalaSandTheme.animate_in(get_child(1) as Control)


func close() -> void:
	visible = false


func settings() -> Dictionary:
	return {
		"autosave_minutes": int(_autosave.value),
		"ui_scale": _ui_scale.value,
		"reduced_motion": _reduced_motion.button_pressed,
		"screen_shake": _screen_shake.button_pressed,
		"window_mode": _window_mode.selected,
		"master": _master_audio.value,
		"ui": _audio_sliders.UI.value,
		"character": _audio_sliders.Character.value,
		"environment": _audio_sliders.Environment.value,
		"machines": _audio_sliders.Machines.value,
		"music": _audio_sliders.Music.value,
	}


func apply_settings(values: Dictionary) -> void:
	_autosave.value = int(values.get("autosave_minutes", 5))
	_ui_scale.value = float(values.get("ui_scale", 1.0))
	_reduced_motion.button_pressed = bool(values.get("reduced_motion", false))
	_screen_shake.button_pressed = bool(values.get("screen_shake", true))
	_window_mode.select(clampi(int(values.get("window_mode", 0)), 0, 2))
	_master_audio.value = float(values.get("master", values.get("master_audio", 1.0)))
	for category: String in _audio_sliders:
		_audio_sliders[category].value = float(values.get(category.to_lower(), 1.0))


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.018, 0.024, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ModalPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_top = -300
	panel.offset_right = 330
	panel.offset_bottom = 300
	add_child(panel)
	var scroll := ScrollContainer.new(); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_child(scroll)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new(); title.text = "Paused"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.theme_type_variation = "ScreenTitleLabel"; column.add_child(title)
	var resume := Button.new(); resume.theme_type_variation = "PrimaryButton"; resume.text = "Resume"; resume.pressed.connect(func(): resume_requested.emit()); column.add_child(resume)
	_name_input = LineEdit.new(); _name_input.placeholder_text = "World name"; column.add_child(_name_input)
	var save := Button.new(); save.text = "Save world"; save.pressed.connect(func(): save_requested.emit(_name_input.text.strip_edges())); column.add_child(save)
	column.add_child(HSeparator.new())
	var settings_title := Label.new(); settings_title.text = "Settings"; settings_title.theme_type_variation = "SectionTitleLabel"; column.add_child(settings_title)
	_window_mode = OptionButton.new(); _window_mode.add_item("Windowed"); _window_mode.add_item("Borderless"); _window_mode.add_item("Fullscreen"); column.add_child(_labeled("Window / resolution mode", _window_mode))
	_ui_scale = SpinBox.new(); _ui_scale.min_value = 0.75; _ui_scale.max_value = 2.0; _ui_scale.step = 0.05; _ui_scale.value = 1.0; column.add_child(_labeled("UI scale", _ui_scale))
	_autosave = SpinBox.new(); _autosave.min_value = 1; _autosave.max_value = 30; _autosave.value = 5; _autosave.suffix = " min"; column.add_child(_labeled("Autosave", _autosave))
	_master_audio = _volume_slider(); column.add_child(_labeled("Master volume", _master_audio))
	for category in ["UI", "Character", "Environment", "Machines", "Music"]:
		var slider := _volume_slider(); _audio_sliders[category] = slider; column.add_child(_labeled("%s volume" % category, slider))
	_reduced_motion = CheckBox.new(); _reduced_motion.text = "Reduced motion"; column.add_child(_reduced_motion)
	_screen_shake = CheckBox.new(); _screen_shake.text = "Screen shake"; _screen_shake.button_pressed = true; column.add_child(_screen_shake)
	var controls := Label.new(); controls.text = "Planning Pause keeps camera and construction controls active."; controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; controls.theme_type_variation = "CaptionLabel"; column.add_child(controls)
	var support := Button.new(); support.theme_type_variation = "QuietButton"; support.text = "Export local diagnostics"; support.tooltip_text = "Creates a local ZIP. Nothing is uploaded."; support.pressed.connect(func(): diagnostics_requested.emit()); column.add_child(support)
	var version := Label.new(); version.text = BuildInfo.display(); version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; version.theme_type_variation = "CaptionLabel"; column.add_child(version)
	column.add_child(HSeparator.new())
	var menu := Button.new(); menu.text = "Save and return to main menu"; menu.pressed.connect(func(): return_to_menu_requested.emit()); column.add_child(menu)
	var exit := Button.new(); exit.theme_type_variation = "DangerButton"; exit.text = "Save and exit"; exit.pressed.connect(func(): exit_requested.emit()); column.add_child(exit)


func _labeled(label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new(); label.text = label_text; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
	control.custom_minimum_size.x = 190
	row.add_child(control)
	return row

func _volume_slider() -> HSlider:
	var slider := HSlider.new(); slider.min_value = 0; slider.max_value = 1; slider.step = 0.05; slider.value = 1
	return slider
