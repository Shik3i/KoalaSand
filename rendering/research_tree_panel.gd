class_name ResearchTreePanel
extends Control

signal unlock_requested(research_id: String)

const NODE_SIZE := Vector2(232, 108)
const TREE_ORIGIN := Vector2(46, 96)
const TREE_SPACING := Vector2(250, 126)
const MIN_ZOOM := 0.58
const MAX_ZOOM := 1.20

var _world: Variant
var _definitions: Array = []
var _base_rects: Dictionary = {}
var _selected_id := "processing.dry_separation"
var _hovered_id := ""
var _last_revision := -1
var _pan := Vector2.ZERO
var _zoom := 0.66
var _dragging := false
var last_update_ms := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process(true)

func initialize(world: Variant) -> void:
	_world = world
	_definitions = world.get_research_definitions()
	_base_rects.clear()
	for definition: Dictionary in _definitions:
		var grid: Vector2i = definition.tree_position
		_base_rects[definition.id] = Rect2(TREE_ORIGIN + Vector2(grid) * TREE_SPACING, NODE_SIZE)
	_last_revision = -1
	_focus_selected()
	queue_redraw()

func toggle() -> void:
	visible = not visible
	if visible:
		KoalaSandTheme.animate_in(self, false, true)
		_focus_selected()
		queue_redraw()

func select_research(research_id: String) -> void:
	_selected_id = research_id
	_focus_selected()
	queue_redraw()

func _process(_delta: float) -> void:
	if not visible or _world == null:
		return
	var started := Time.get_ticks_usec()
	var revision := int(_world.get_progression_state().revision)
	if revision != _last_revision:
		_last_revision = revision
		queue_redraw()
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _screen_rect(research_id: String) -> Rect2:
	var base: Rect2 = _base_rects[research_id]
	return Rect2(base.position * _zoom + _pan, base.size * _zoom)

func _draw() -> void:
	if _world == null:
		return
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(34, 39), "RESEARCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, KoalaSandTheme.COLOR_ACCENT_BRIGHT)
	draw_string(font, Vector2(34, 64), "Physical discoveries unlock new ways to shape matter.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, KoalaSandTheme.COLOR_TEXT_SECONDARY)
	for definition: Dictionary in _definitions:
		var child_rect := _screen_rect(definition.id)
		for prerequisite: String in definition.prerequisites:
			var parent_rect := _screen_rect(prerequisite)
			var highlighted: bool = str(definition.id) == _selected_id or prerequisite == _selected_id
			var start := parent_rect.get_center() + Vector2(0, parent_rect.size.y * 0.5)
			var finish := child_rect.get_center() - Vector2(0, child_rect.size.y * 0.5)
			var middle_y := (start.y + finish.y) * 0.5
			var color := Color("d89a36") if highlighted else Color("52666a")
			draw_polyline(PackedVector2Array([start, Vector2(start.x, middle_y), Vector2(finish.x, middle_y), finish]), color, 3.0 if highlighted else 2.0)
	for definition: Dictionary in _definitions:
		_draw_node(definition, font)
	# Footer masks the graph so detail and action never collide with nodes.
	draw_rect(Rect2(1, size.y - 98, size.x - 2, 97), KoalaSandTheme.COLOR_PANEL_MODAL, true)
	draw_line(Vector2(24, size.y - 98), Vector2(size.x - 24, size.y - 98), KoalaSandTheme.COLOR_SEPARATOR, 1.0)
	var selected_state: Dictionary = _world.get_research_state(_selected_id)
	var selected_definition: Dictionary = {}
	for definition: Dictionary in _definitions:
		if str(definition.id) == _selected_id:
			selected_definition = definition
			break
	if not selected_definition.is_empty():
		var prerequisites: Array = selected_definition.prerequisites
		var prerequisite_names: Array[String] = []
		for prerequisite: String in prerequisites:
			for definition: Dictionary in _definitions:
				if str(definition.id) == prerequisite: prerequisite_names.append(str(definition.display_name)); break
		var prerequisite_text := "No prerequisite" if prerequisites.is_empty() else "Requires  %s" % ", ".join(prerequisite_names)
		draw_string(font, Vector2(34, size.y - 66), str(selected_definition.display_name), HORIZONTAL_ALIGNMENT_LEFT, size.x - 270, 17, KoalaSandTheme.COLOR_TEXT)
		draw_string(font, Vector2(34, size.y - 43), "%s  ·  %s" % [selected_definition.description, prerequisite_text], HORIZONTAL_ALIGNMENT_LEFT, size.x - 270, 12, KoalaSandTheme.COLOR_TEXT_SECONDARY)
		draw_string(font, Vector2(34, size.y - 21), "UNLOCKS  %s" % selected_definition.effect, HORIZONTAL_ALIGNMENT_LEFT, size.x - 270, 12, KoalaSandTheme.COLOR_ACCENT_BRIGHT)
	var button_rect := _unlock_rect()
	var button_color := Color("c98225") if bool(selected_state.get("available", false)) and bool(selected_state.get("affordable", false)) else Color("34464a")
	draw_rect(button_rect, button_color, true)
	draw_rect(button_rect, Color("f2b84b") if button_color.r > 0.5 else Color("607579"), false, 2.0)
	var action := "UNLOCK NOW" if not bool(selected_state.get("unlocked", false)) else "UNLOCKED"
	draw_string(font, button_rect.position + Vector2(22, 28), action, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0c7") if button_color.r > 0.5 else Color("9eb0b2"))
	draw_string(font, Vector2(size.x - 212, 39), "Wheel zoom  ·  Drag pan  ·  T close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, KoalaSandTheme.COLOR_TEXT_SECONDARY)

func _draw_node(definition: Dictionary, font: Font) -> void:
	var rect := _screen_rect(definition.id)
	if not Rect2(Vector2.ZERO, size).intersects(rect):
		return
	var state: Dictionary = _world.get_research_state(definition.id)
	var unlocked := bool(state.unlocked)
	var available := bool(state.available)
	var affordable := bool(state.affordable)
	var selected: bool = str(definition.id) == _selected_id
	var hovered: bool = str(definition.id) == _hovered_id
	var fill := Color("263b3e") if unlocked else Color("3a3126") if available and affordable else Color("242c2e") if available else Color("171e20")
	var border := Color("efb44a") if selected or hovered else Color("719196") if unlocked else Color("8b6733") if available else Color("3c4a4d")
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 4.0 if selected else 2.0)
	var icon_center := rect.position + Vector2(rect.size.x - 22.0 * _zoom, 20.0 * _zoom)
	draw_circle(icon_center, 10.0 * _zoom, Color(border, 0.24))
	draw_arc(icon_center, 7.0 * _zoom, 0.0, TAU, 16, border, maxf(1.0, 2.0 * _zoom))
	draw_line(icon_center - Vector2(4, 0) * _zoom, icon_center + Vector2(4, 0) * _zoom, border, maxf(1.0, 2.0 * _zoom))
	var scale_font := maxi(9, roundi(14.0 * _zoom))
	var state_text := "UNLOCKED" if unlocked else "AVAILABLE" if available else "PREREQUISITE"
	draw_string(font, rect.position + Vector2(10, 19) * _zoom, state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, roundi(10.0 * _zoom)), Color("7fd2b1") if unlocked else Color("f0b54c") if available else Color("738487"))
	draw_string(font, rect.position + Vector2(10, 43) * _zoom, definition.display_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0 * _zoom, scale_font, Color("edf0e8"))
	var costs: Dictionary = definition.costs
	var cost_text := "Glass %d   Iron %d" % [costs.glass, costs.iron]
	if int(costs.gold) > 0:
		cost_text += "   Gold %d" % costs.gold
	draw_string(font, rect.position + Vector2(10, 67) * _zoom, cost_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0 * _zoom, maxi(8, roundi(11.0 * _zoom)), Color("b9c5c3"))
	var effect_lines := _wrap_words(str(definition.effect), 31)
	for line_index in mini(2, effect_lines.size()):
		draw_string(font, rect.position + Vector2(10, 88 + line_index * 15) * _zoom, effect_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 20.0 * _zoom, maxi(8, roundi(10.0 * _zoom)), Color("d59d4a"))

func _wrap_words(text: String, max_chars: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" "):
		if current.is_empty() or current.length() + word.length() + 1 <= max_chars:
			current += ("" if current.is_empty() else " ") + word
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return lines

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_pan += event.relative
			queue_redraw()
			accept_event()
			return
		var next_hover := ""
		for research_id: String in _base_rects:
			if _screen_rect(research_id).has_point(event.position):
				next_hover = research_id
				break
		if next_hover != _hovered_id:
			_hovered_id = next_hover
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			accept_event()
			return
		if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var old_zoom := _zoom
			_zoom = clampf(_zoom * (1.10 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.90), MIN_ZOOM, MAX_ZOOM)
			_pan = event.position - (event.position - _pan) * (_zoom / old_zoom)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			for research_id: String in _base_rects:
				if _screen_rect(research_id).has_point(event.position):
					_selected_id = research_id
					queue_redraw()
					accept_event()
					return
			if _unlock_rect().has_point(event.position):
				unlock_requested.emit(_selected_id)
				accept_event()

func _focus_selected() -> void:
	if not _base_rects.has(_selected_id):
		return
	var rect: Rect2 = _base_rects[_selected_id]
	_pan = Vector2(size.x * 0.34, size.y * 0.38) - rect.get_center() * _zoom

func _unlock_rect() -> Rect2:
	return Rect2(size.x - 210, size.y - 72, 172, 44)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = KoalaSandTheme.COLOR_PANEL_MODAL
	style.border_color = Color("a77a34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(KoalaSandTheme.RADIUS_LARGE)
	return style
