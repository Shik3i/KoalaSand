class_name ResearchTreePanel
extends Control

signal unlock_requested(research_id: String)

const NODE_SIZE := Vector2(232, 108)
const TREE_ORIGIN := Vector2(46, 120)
const TREE_SPACING := Vector2(250, 126)
const MIN_ZOOM := 0.34
const MAX_ZOOM := 1.20

var _world: Variant
var _definitions: Array = []
var _base_rects: Dictionary = {}
var _selected_id := "processing.dry_separation"
var _hovered_id := ""
var _last_revision := -1
var _pan := Vector2.ZERO
# Replaced on open by _fit_to_content(); this is only the value before the first layout.
var _zoom := 0.56
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
	draw_string(font, Vector2(34, 64), "Physical discoveries unlock new ways to shape matter.", HORIZONTAL_ALIGNMENT_LEFT, size.x - 68, 13, KoalaSandTheme.COLOR_TEXT_SECONDARY)
	draw_string(font, Vector2(34, 88), "UNLOCKED · AVAILABLE · LOCKED BY PREREQUISITE · bright cost = AFFORDABLE", HORIZONTAL_ALIGNMENT_LEFT, size.x - 68, 11, KoalaSandTheme.COLOR_INFO)
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
		# "NEEDS MATERIAL" without a number is not something a player can act on. Show what it
		# costs next to what they actually hold, so the button states what is still missing.
		var bank: Dictionary = _world.get_progression_state()
		var costs: Dictionary = selected_definition.get("costs", {})
		var parts: Array[String] = []
		var short := false
		for reserve: String in ["glass", "iron", "gold"]:
			var required := int(costs.get(reserve, 0))
			if required <= 0: continue
			var held := int(bank.get(reserve, 0))
			short = short or held < required
			parts.append("%s %d/%d" % [reserve.capitalize(), held, required])
		if not parts.is_empty():
			# Right-aligned on the UNLOCKS baseline: the footer has three lines and no room for
			# a fourth without colliding with the title.
			draw_string(font, Vector2(34, size.y - 21), "COST  %s" % "  ·  ".join(parts), HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 304, 12, KoalaSandTheme.COLOR_WARNING if short else KoalaSandTheme.COLOR_SUCCESS)
	var button_rect := _unlock_rect()
	var button_color := Color("c98225") if bool(selected_state.get("available", false)) and bool(selected_state.get("affordable", false)) else Color("34464a")
	draw_rect(button_rect, button_color, true)
	draw_rect(button_rect, Color("f2b84b") if button_color.r > 0.5 else Color("607579"), false, 2.0)
	var action := "UNLOCKED" if bool(selected_state.get("unlocked", false)) else "UNLOCK NOW" if bool(selected_state.get("available", false)) and bool(selected_state.get("affordable", false)) else "NEEDS MATERIAL" if bool(selected_state.get("available", false)) else "NEEDS PREREQUISITE"
	draw_string(font, button_rect.position + Vector2(22, 28), action, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("fff0c7") if button_color.r > 0.5 else Color("9eb0b2"))
	draw_string(font, Vector2(size.x - 270, 39), "Wheel zoom  ·  Drag pan  ·  %s close" % InputGlyphs.action(&"open_research"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, KoalaSandTheme.COLOR_TEXT_SECONDARY)

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
	# Row positions used to be fixed offsets multiplied by the zoom while every font size had a
	# floor of eight or nine pixels. Below about 0.7 zoom -- and the tree opens fitted, which on a
	# tree this wide is the 0.34 minimum -- the rows kept moving together while the glyphs stopped
	# shrinking, so the cost line and the two effect lines were drawn on top of each other. It was
	# survivable while every effect was one short line; it stopped being survivable the moment any
	# of them wrapped.
	#
	# A card fitted to the panel is roughly 37 pixels tall and cannot hold four rows of legible
	# text, so the rows are ranked rather than truncated from the bottom. The name comes first,
	# then what the node costs, then what it unlocks. The state label is last of all: the border
	# and fill already carry it, and the legend above the tree says so.
	var state_font := maxi(8, roundi(10.0 * _zoom))
	var title_font := maxi(9, roundi(14.0 * _zoom))
	var cost_font := maxi(8, roundi(11.0 * _zoom))
	var effect_font := maxi(8, roundi(10.0 * _zoom))
	var costs: Dictionary = definition.costs
	var cost_text := "Glass %d   Iron %d" % [costs.glass, costs.iron]
	if int(costs.gold) > 0:
		cost_text += "   Gold %d" % costs.gold
	# Wrap against the card's real width rather than a fixed character count, so a long effect
	# neither spills past the border at high zoom nor wraps needlessly at low zoom.
	var width := rect.size.x - 20.0 * _zoom
	var effect_columns := maxi(12, int(width / maxf(1.0, effect_font * 0.52)))
	var effect_lines := _wrap_words(str(definition.effect), effect_columns)

	var state_text := "UNLOCKED" if unlocked else "AVAILABLE" if available else "PREREQUISITE"
	var state_color := Color("7fd2b1") if unlocked else Color("f0b54c") if available else Color("738487")
	var ranked: Array = [
		[definition.display_name, title_font, Color("edf0e8"), 24.0],
		[cost_text, cost_font, Color("b9c5c3"), 24.0],
	]
	for line_index in mini(2, effect_lines.size()):
		ranked.append([effect_lines[line_index], effect_font, Color("d59d4a"), 15.0])
	ranked.append([state_text, state_font, state_color, 19.0])

	# Keep rows from the front of the ranking until the card runs out of height, then put the
	# state label back on top where it has always been drawn.
	var available_height := rect.size.y - 6.0
	var used := 0.0
	var kept: Array = []
	for row: Array in ranked:
		var step: float = maxf(float(row[3]) * _zoom, float(row[1]) + 3.0)
		if used + step > available_height: continue
		used += step
		kept.append(row)
	var state_index := kept.find(ranked[ranked.size() - 1])
	if state_index > 0:
		kept.remove_at(state_index)
		kept.insert(0, ranked[ranked.size() - 1])

	var cursor := 0.0
	var left := rect.position + Vector2(10.0 * _zoom, 0.0)
	for row: Array in kept:
		cursor += maxf(float(row[3]) * _zoom, float(row[1]) + 3.0)
		draw_string(font, left + Vector2(0, cursor), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, width, int(row[1]), row[2])

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
			_clamp_pan()
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
			_clamp_pan()
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
	_fit_to_content()
	_pan = Vector2(size.x * 0.5, size.y * 0.5) - rect.get_center() * _zoom
	_clamp_pan()


# Shrink to whatever shows the whole tree, so a first open never presents a half-cut card.
# The player can still wheel in; this only sets the default.
func _fit_to_content() -> void:
	var bounds := _content_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var view := _viewport_rect()
	var fit := minf(view.size.x / bounds.size.x, view.size.y / bounds.size.y)
	_zoom = clampf(minf(fit, 0.66), MIN_ZOOM, MAX_ZOOM)


# The default framing centred the selected node, which put the right-hand branches half
# outside the panel. Fit the whole tree when it fits, and never let a drag lose it.
func _content_bounds() -> Rect2:
	var bounds := Rect2()
	var first := true
	for id: Variant in _base_rects:
		var rect: Rect2 = _base_rects[id]
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	return bounds


func _viewport_rect() -> Rect2:
	return Rect2(Vector2(30.0, 190.0), Vector2(maxf(size.x - 60.0, 1.0), maxf(size.y - 310.0, 1.0)))


func _clamp_pan() -> void:
	var bounds := _content_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var view := _viewport_rect()
	var scaled := bounds.size * _zoom
	var origin := bounds.position * _zoom
	if scaled.x <= view.size.x:
		_pan.x = view.position.x + (view.size.x - scaled.x) * 0.5 - origin.x
	else:
		_pan.x = clampf(_pan.x, view.end.x - scaled.x - origin.x, view.position.x - origin.x)
	if scaled.y <= view.size.y:
		_pan.y = view.position.y + (view.size.y - scaled.y) * 0.5 - origin.y
	else:
		_pan.y = clampf(_pan.y, view.end.y - scaled.y - origin.y, view.position.y - origin.y)

func _unlock_rect() -> Rect2:
	return Rect2(size.x - 210, size.y - 72, 172, 44)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = KoalaSandTheme.COLOR_PANEL_MODAL
	style.border_color = Color("a77a34")
	style.set_border_width_all(2)
	style.set_corner_radius_all(KoalaSandTheme.RADIUS_LARGE)
	return style
