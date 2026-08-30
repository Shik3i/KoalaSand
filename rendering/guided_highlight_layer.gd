class_name GuidedHighlightLayer
extends Control

var reduced_motion := false
var _target: Control
var _message := ""
var _phase := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 900
	set_process(false)


func show_step(target: Control, message: String) -> void:
	_target = target
	_message = message
	_phase = 0.0
	set_process(true)
	queue_redraw()


func clear() -> void:
	_target = null
	_message = ""
	set_process(false)
	queue_redraw()


func active() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_visible_in_tree()


func _process(delta: float) -> void:
	if not active():
		clear()
		return
	if not reduced_motion:
		_phase = fmod(_phase + delta * 3.0, TAU)
	queue_redraw()


func _draw() -> void:
	if not active():
		return
	var rect := _target.get_global_rect().grow(5.0)
	var pulse := 0.0 if reduced_motion else sin(_phase) * 2.0
	rect = rect.grow(pulse)
	draw_style_box(_outline_box(), rect)
	var arrow_tip := Vector2(rect.position.x - 8.0, rect.get_center().y)
	draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_tip + Vector2(-12, -8), arrow_tip + Vector2(-12, 8)]), KoalaSandTheme.COLOR_ACCENT_BRIGHT)
	if not _message.is_empty():
		var message_position := Vector2(maxf(12.0, rect.position.x - 300.0), maxf(24.0, rect.position.y - 8.0))
		draw_string(ThemeDB.fallback_font, message_position, _message, HORIZONTAL_ALIGNMENT_LEFT, 280.0, 14, KoalaSandTheme.COLOR_ACCENT_BRIGHT)


func _outline_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = KoalaSandTheme.COLOR_ACCENT_BRIGHT
	box.set_border_width_all(3)
	box.set_corner_radius_all(7)
	return box
