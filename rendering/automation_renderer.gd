class_name AutomationRenderer
extends Node2D

@export_range(1.0, 8.0, 1.0) var cell_pixel_size := 2.0

var _world: Variant
var _cell_area := Rect2i()
var _components := PackedInt32Array()
var _connections := PackedInt32Array()
var _last_revision := -1
var wiring_mode := false
var selected_component_id := 0
var pending_source_id := 0
var preview_cell := Vector2i.ZERO
var invalid_target := false
var last_topology_rebuild_ms := 0.0
var last_wire_draw_ms := 0.0
var _component_instances := MultiMeshInstance2D.new()
var _wire_instances := MultiMeshInstance2D.new()

func _ready() -> void:
	_component_instances.name = "BatchedAutomationComponents"
	_wire_instances.name = "BatchedSignalWires"
	add_child(_wire_instances)
	add_child(_component_instances)
	_wire_instances.visible = false

func initialize(world: Variant) -> void:
	_world = world
	_last_revision = -1

func clear() -> void:
	_components = PackedInt32Array()
	_connections = PackedInt32Array()
	_last_revision = -1
	selected_component_id = 0
	pending_source_id = 0
	_component_instances.multimesh = null
	_wire_instances.multimesh = null
	queue_redraw()

func sync_visible(chunk_area: Rect2i, force: bool = false) -> void:
	if _world == null:
		return
	var area := Rect2i(chunk_area.position * 64, chunk_area.size * 64)
	var revision := int(_world.get_automation_statistics().revision)
	if not force and revision == _last_revision and area == _cell_area:
		return
	var started := Time.get_ticks_usec()
	_components = _world.get_visible_automation_components(area)
	_connections = _world.get_visible_automation_connections(area)
	_cell_area = area
	_last_revision = revision
	last_topology_rebuild_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_rebuild_component_batch()
	if wiring_mode:
		_rebuild_wire_batch()
	queue_redraw()

func set_wiring_mode(enabled: bool) -> void:
	wiring_mode = enabled
	_wire_instances.visible = enabled
	_component_instances.modulate.a = 1.0 if enabled else 0.38
	if enabled:
		_rebuild_wire_batch()
	if not enabled:
		pending_source_id = 0
		invalid_target = false
	queue_redraw()

func select_component(component_id: int) -> void:
	selected_component_id = component_id
	queue_redraw()

func pick_component(cell: Vector2i, radius: int = 3) -> int:
	var best_id := 0
	var best_distance := radius * radius + 1
	for index in _components.size() / 7:
		var delta := Vector2i(_components[index * 7 + 1], _components[index * 7 + 2]) - cell
		var distance := delta.x * delta.x + delta.y * delta.y
		if distance < best_distance:
			best_distance = distance
			best_id = _components[index * 7]
	return best_id

func pick_connection(cell: Vector2i, radius: float = 3.0) -> int:
	var point := Vector2(cell)
	var best_id := 0
	var best_distance := radius
	for index in _connections.size() / 6:
		var source := Vector2(_connections[index * 6 + 1], _connections[index * 6 + 2])
		var target := Vector2(_connections[index * 6 + 3], _connections[index * 6 + 4])
		var middle_x := (source.x + target.x) * 0.5
		for segment in [[source, Vector2(middle_x, source.y)], [Vector2(middle_x, source.y), Vector2(middle_x, target.y)], [Vector2(middle_x, target.y), target]]:
			var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
			var distance := point.distance_to(closest)
			if distance < best_distance:
				best_distance = distance
				best_id = _connections[index * 6]
	return best_id

func set_preview(cell: Vector2i, invalid: bool) -> void:
	preview_cell = cell
	invalid_target = invalid
	if wiring_mode and pending_source_id > 0:
		queue_redraw()

func _draw() -> void:
	var started := Time.get_ticks_usec()
	if pending_source_id > 0:
		var source_cell := _component_cell(pending_source_id)
		_draw_wire(Vector2(source_cell) * cell_pixel_size, Vector2(preview_cell) * cell_pixel_size, Color("e45555") if invalid_target else Color("e9c66b"), 1.0)
	if selected_component_id > 0:
		var state: Dictionary = _world.get_automation_component_state(selected_component_id)
		if not state.is_empty():
			var cell := Vector2(state.position) * cell_pixel_size
			draw_rect(Rect2(cell - Vector2.ONE * 1.6, Vector2.ONE * 3.2), Color("fff1bd"), false, 0.8)
			if wiring_mode:
				draw_string(ThemeDB.fallback_font, cell + Vector2(3, -3), "%s  IN:%d/%d  OUT:%d" % [_symbol(state.type_id), state.input_a, state.input_b, state.output], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color("f1eee2"))
	last_wire_draw_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _rebuild_component_batch() -> void:
	var count := _components.size() / 7
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	for index in count:
		var position := Vector2(_components[index * 7 + 1], _components[index * 7 + 2]) * cell_pixel_size
		var output := _components[index * 7 + 4]
		multimesh.set_instance_transform_2d(index, Transform2D(Vector2(2.1, 0), Vector2(0, 2.1), position))
		multimesh.set_instance_color(index, Color("f6c453") if output != 0 else Color("5f8589"))
	_component_instances.multimesh = multimesh

func _rebuild_wire_batch() -> void:
	var started := Time.get_ticks_usec()
	var segment_count := _connections.size() / 6 * 3
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.instance_count = segment_count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	var segment_index := 0
	for index in _connections.size() / 6:
		var source := Vector2(_connections[index * 6 + 1], _connections[index * 6 + 2]) * cell_pixel_size
		var target := Vector2(_connections[index * 6 + 3], _connections[index * 6 + 4]) * cell_pixel_size
		var middle_x := (source.x + target.x) * 0.5
		var color := Color("f2b84b") if _connections[index * 6 + 5] != 0 else Color("5d7f84")
		for points in [[source, Vector2(middle_x, source.y)], [Vector2(middle_x, source.y), Vector2(middle_x, target.y)], [Vector2(middle_x, target.y), target]]:
			var from: Vector2 = points[0]
			var to: Vector2 = points[1]
			var delta := to - from
			var basis_x := Vector2(maxf(absf(delta.x), 0.35), 0.0)
			var basis_y := Vector2(0.0, maxf(absf(delta.y), 0.35))
			if absf(delta.x) >= absf(delta.y):
				basis_y = Vector2(0.0, 0.65)
			else:
				basis_x = Vector2(0.65, 0.0)
			multimesh.set_instance_transform_2d(segment_index, Transform2D(basis_x, basis_y, (from + to) * 0.5))
			multimesh.set_instance_color(segment_index, color)
			segment_index += 1
	_wire_instances.multimesh = multimesh
	last_topology_rebuild_ms = float(Time.get_ticks_usec() - started) / 1000.0

func _draw_wire(source: Vector2, target: Vector2, color: Color, width: float) -> void:
	var middle_x := (source.x + target.x) * 0.5
	draw_polyline(PackedVector2Array([source, Vector2(middle_x, source.y), Vector2(middle_x, target.y), target]), color, width, false)

func _component_cell(component_id: int) -> Vector2i:
	for index in _components.size() / 7:
		if _components[index * 7] == component_id:
			return Vector2i(_components[index * 7 + 1], _components[index * 7 + 2])
	return Vector2i.ZERO

func _symbol(type_id: int) -> String:
	var symbols := ["", "SW", "MAT", "LVL", "NOT", "AND", "OR", "CMP", "M", "T", "MEM", "BELT", "EN", "GATE"]
	return symbols[type_id] if type_id >= 0 and type_id < symbols.size() else "?"
