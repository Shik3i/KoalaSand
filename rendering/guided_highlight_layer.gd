class_name GuidedHighlightLayer
extends Control

const MAX_LABEL_WIDTH := 320.0
const MIN_LABEL_FONT_SIZE := 10

var reduced_motion := false
var _target: Control
var _message := ""
var _phase := 0.0
var _queue: Array[Dictionary] = []
var _safe_regions: Array[Rect2] = []
var _label_rect := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = UILayoutPolicy.LAYER_HIGHLIGHT
	set_process(false)


func show_step(target: Control, message: String) -> void:
	_target = target
	_message = message
	_phase = 0.0
	set_process(true)
	queue_redraw()


func queue_step(target: Control, message: String) -> void:
	if not is_instance_valid(target):
		return
	if not active():
		show_step(target, message)
		return
	_queue.append({"target":target, "message":message})


func complete_step() -> void:
	if _queue.is_empty():
		clear()
		return
	var next: Dictionary = _queue.pop_front()
	show_step(next.target, str(next.message))


func queued_count() -> int:
	return _queue.size()


func set_safe_regions(regions: Array[Rect2]) -> void:
	_safe_regions = regions.duplicate()
	queue_redraw()


func label_rect() -> Rect2:
	return _label_rect


func clear() -> void:
	_target = null
	_message = ""
	_queue.clear()
	set_process(false)
	queue_redraw()


func active() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_visible_in_tree()


func _process(delta: float) -> void:
	if not active():
		if _queue.is_empty():
			clear()
		else:
			complete_step()
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
	var viewport := get_viewport_rect().size
	var arrow_left := rect.position.x >= 56.0
	var arrow_tip := Vector2(rect.position.x - 8.0, rect.get_center().y) if arrow_left else Vector2(rect.end.x + 8.0, rect.get_center().y)
	var arrow_direction := -1.0 if arrow_left else 1.0
	draw_colored_polygon(PackedVector2Array([arrow_tip, arrow_tip + Vector2(12.0 * arrow_direction, -8), arrow_tip + Vector2(12.0 * arrow_direction, 8)]), KoalaSandTheme.COLOR_ACCENT_BRIGHT)
	if not _message.is_empty():
		# The box used to guess its width at eight pixels a character while the text was drawn at
		# font size 14, which is wider than that for most glyphs. draw_string() then clipped to
		# the box it had been given, so the very first thing the game points at read "Open Catal".
		# Ask the font how wide the string is instead, and shrink the type rather than the words
		# when the answer does not fit.
		var font := ThemeDB.fallback_font
		var font_size := 14
		var text_width := font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		while text_width + 16.0 > MAX_LABEL_WIDTH and font_size > MIN_LABEL_FONT_SIZE:
			font_size -= 1
			text_width = font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var label_size := Vector2(clampf(text_width + 16.0, 96.0, MAX_LABEL_WIDTH), 28.0)
		var label_rect := UILayoutPolicy.best_tooltip_rect(rect, label_size, viewport, _safe_regions)
		_label_rect = label_rect
		var box := StyleBoxFlat.new(); box.bg_color = Color("0b1217ed"); box.border_color = KoalaSandTheme.COLOR_ACCENT_BRIGHT; box.set_border_width_all(1); box.set_corner_radius_all(4)
		draw_style_box(box, label_rect)
		var baseline := label_rect.position + Vector2(8.0, (label_rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
		draw_string(font, baseline, _message, HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x - 16.0, font_size, KoalaSandTheme.COLOR_ACCENT_BRIGHT)


func _outline_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = KoalaSandTheme.COLOR_ACCENT_BRIGHT
	box.set_border_width_all(3)
	box.set_corner_radius_all(7)
	return box
