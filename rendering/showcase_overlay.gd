class_name ShowcaseOverlay
extends Node2D

@export_range(1.0, 8.0, 1.0) var cell_pixel_size: float = 2.0
@export var light_cell := Vector2i(-42, 90)

var _world: Variant
var show_chunk_debug: bool = false
var show_geology_heatmap: bool = false
var worldgen_debug_layers: Dictionary = {}
var _brush_cell := Vector2i.ZERO
var _brush_radius: int = 1
var _brush_color := Color(0.96, 0.82, 0.48, 0.75)
var _show_brush_preview: bool = false
var _structure_preview_cells: Array[Vector2i] = []
var _structure_preview_valid := false
var _structure_preview_type := 0
var _structure_preview_orientation := 0
var _structure_preview_ports: Array = []
var _info_mode := false
var _info_chunks := Rect2i()
var _info_badges := MultiMeshInstance2D.new()
var _info_revision := -1
var _info_record_count := 0

func _ready() -> void:
	_info_badges.name = "BatchedInfoBadges"
	_info_badges.material = _build_info_badge_material()
	_info_badges.visible = false
	add_child(_info_badges)


func initialize(world: Variant) -> void:
	_world = world
	_info_revision = -1
	_info_badges.multimesh = null
	queue_redraw()


func set_brush_preview(world_cell: Vector2i, radius: int, color: Color, visible: bool) -> void:
	_brush_cell = world_cell
	_brush_radius = radius
	_brush_color = color
	_show_brush_preview = visible
	queue_redraw()


func set_structure_preview(cells: Array[Vector2i], valid: bool, type_id := 0, orientation := 0, ports: Array = []) -> void:
	_structure_preview_cells = cells
	_structure_preview_valid = valid
	_structure_preview_type = type_id
	_structure_preview_orientation = orientation
	_structure_preview_ports = ports.duplicate()
	queue_redraw()


func set_chunk_debug(visible: bool) -> void:
	show_chunk_debug = visible
	queue_redraw()


func set_geology_heatmap(visible: bool) -> void:
	show_geology_heatmap = visible
	queue_redraw()

func set_worldgen_debug_layers(layers: Array[String]) -> void:
	worldgen_debug_layers.clear()
	for layer in layers:
		worldgen_debug_layers[layer] = true
	queue_redraw()

func set_info_mode(enabled: bool, visible_chunks: Rect2i) -> void:
	_info_mode = enabled
	_info_chunks = visible_chunks
	_info_badges.visible = enabled
	if enabled:
		_sync_info_badges()
	queue_redraw()

func _sync_info_badges() -> void:
	if _world == null or _world is CellWorld:
		return
	var revision := int(_world.get_structure_statistics().get("machine_visual_revision", 0))
	if revision == _info_revision and _info_chunks == _info_badges.get_meta("chunks", Rect2i()):
		return
	var records: PackedInt32Array = _world.get_visible_machine_entities(_info_chunks)
	_info_record_count = records.size() / 8
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.instance_count = _info_record_count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	var badge_size := maxf(3.0, cell_pixel_size * 2.0)
	for badge_index in _info_record_count:
		var index := badge_index * 8
		var cell := Vector2(records[index], records[index + 1]) * cell_pixel_size + Vector2.ONE * cell_pixel_size * 1.5
		var state := int(records[index + 6])
		var color := Color("65dce7") if state in [0, 1, 6] else Color("ffb14f") if state in [3, 10] else Color("ff665c")
		multimesh.set_instance_transform_2d(badge_index, Transform2D(Vector2(badge_size, 0.0), Vector2(0.0, badge_size), cell))
		multimesh.set_instance_color(badge_index, color)
	_info_badges.multimesh = multimesh
	_info_badges.set_meta("chunks", _info_chunks)
	_info_revision = revision


func _draw() -> void:
	if _world == null:
		return
	if show_chunk_debug:
		var chunk_size := WorldConfig.CHUNK_SIZE if _world is CellWorld else 64
		var size := float(chunk_size) * cell_pixel_size
		for coordinate in _world.get_chunk_coordinates():
			var origin := Vector2(coordinate * chunk_size) * cell_pixel_size
			var active := false
			var dirty := false
			if _world is CellWorld:
				var chunk: SimChunk = _world.get_chunk(coordinate)
				active = chunk.is_active()
				dirty = chunk.is_dirty()
			else:
				var state: Dictionary = _world.get_chunk_state(coordinate)
				active = state.get("active", false)
				dirty = state.get("dirty", false)
			var color := Color(0.94, 0.65, 0.18, 0.8) if active else Color(0.24, 0.55, 0.68, 0.62)
			if dirty:
				color = Color(0.9, 0.28, 0.7, 0.85)
			draw_rect(Rect2(origin, Vector2(size, size)), color, false, 1.0)

	if show_geology_heatmap and not _world is CellWorld:
		for coordinate: Vector2i in _world.get_chunk_coordinates():
			var origin_cell := coordinate * 64
			for local_y in range(4, 64, 8):
				for local_x in range(4, 64, 8):
					var cell := origin_cell + Vector2i(local_x, local_y)
					if _world.get_cell(cell) != 2:
						continue
					var profile: Dictionary = _world.get_geology_profile(_world.get_provenance(cell))
					var iron := float(profile.get("iron_fraction", 0.0))
					var gold := float(profile.get("gold_ppm", 0.0))
					var intensity := clampf(log(1.0 + gold) / log(17.0), 0.0, 1.0)
					var color := Color(0.12 + iron * 2.2, 0.42, 0.86, 0.12)
					if intensity > 0.08:
						color = Color(1.0, 0.72, 0.12, 0.18 + intensity * 0.52)
					draw_rect(Rect2(Vector2(cell - Vector2i(4, 4)) * cell_pixel_size, Vector2.ONE * 8.0 * cell_pixel_size), color, true)

	if not worldgen_debug_layers.is_empty() and not _world is CellWorld:
		var coordinates: Array = _world.get_chunk_coordinates()
		if not coordinates.is_empty():
			var minimum := Vector2i(999999, 999999)
			var maximum := Vector2i(-999999, -999999)
			for coordinate: Vector2i in coordinates:
				minimum.x = mini(minimum.x, coordinate.x); minimum.y = mini(minimum.y, coordinate.y)
				maximum.x = maxi(maximum.x, coordinate.x); maximum.y = maxi(maximum.y, coordinate.y)
				if worldgen_debug_layers.has("macro_regions") and (posmod(coordinate.x, 8) == 0 or posmod(coordinate.y, 8) == 0):
					draw_rect(Rect2(Vector2(coordinate * 64) * cell_pixel_size, Vector2.ONE * 64.0 * cell_pixel_size), Color(0.92, 0.58, 0.18, 0.48), false, 1.5)
			var area := Rect2i(minimum * 64, (maximum - minimum + Vector2i.ONE) * 64)
			var sample: Dictionary = _world.get_worldgen_debug_sample(area, 12)
			var records: PackedInt32Array = sample.get("records", PackedInt32Array())
			for index in range(0, records.size(), int(sample.get("record_stride", 8))):
				var cell := Vector2i(records[index], records[index + 1])
				var cave := int(records[index + 3])
				var aquifer := bool(records[index + 4])
				var province := int(records[index + 7]) % 5
				var color := Color.TRANSPARENT
				if worldgen_debug_layers.has("aquifers") and aquifer: color = Color(0.10, 0.72, 0.92, 0.42)
				elif worldgen_debug_layers.has("cave_archetypes") and cave > 0: color = [Color.TRANSPARENT, Color(0.72,0.36,0.85,0.36), Color(0.26,0.82,0.64,0.38), Color(0.95,0.61,0.24,0.42), Color(0.95,0.31,0.27,0.44), Color(0.12,0.64,0.86,0.40)][clampi(cave, 0, 5)]
				elif worldgen_debug_layers.has("geology"):
					color = [Color(0.48,0.58,0.63,0.22), Color(0.61,0.43,0.68,0.22), Color(0.36,0.64,0.49,0.22), Color(0.72,0.57,0.33,0.22), Color(0.36,0.47,0.72,0.22)][province]
				if color.a > 0.0: draw_rect(Rect2(Vector2(cell - Vector2i(6, 6)) * cell_pixel_size, Vector2.ONE * 12.0 * cell_pixel_size), color, true)
			if worldgen_debug_layers.has("start_constraints"):
				draw_rect(Rect2(Vector2(-176, -96) * cell_pixel_size, Vector2(352, 340) * cell_pixel_size), Color(0.96, 0.78, 0.26, 0.72), false, 2.0)

	# Developer reference marker at a fixed world cell. It is not player-facing content and
	# only appears alongside the other chunk-debug overlays.
	if show_chunk_debug:
		var beacon_position := (Vector2(light_cell) + Vector2(0.5, 0.5)) * cell_pixel_size
		draw_circle(beacon_position, 5.0, Color(0.25, 0.12, 0.04, 0.9))
		draw_circle(beacon_position, 2.5, Color(1.0, 0.66, 0.22, 1.0))
		draw_line(beacon_position + Vector2(-7, 0), beacon_position + Vector2(7, 0), Color(0.86, 0.4, 0.12, 0.7), 1.0)
		draw_line(beacon_position + Vector2(0, -7), beacon_position + Vector2(0, 7), Color(0.86, 0.4, 0.12, 0.7), 1.0)

	if _show_brush_preview:
		var center := (Vector2(_brush_cell) + Vector2(0.5, 0.5)) * cell_pixel_size
		var radius_pixels := (float(_brush_radius) + 0.35) * cell_pixel_size
		draw_arc(center, radius_pixels, 0.0, TAU, 28, _brush_color, 1.0)
		draw_circle(center, 1.0, _brush_color)

	if not _structure_preview_cells.is_empty():
		var fill := Color(0.22, 0.72, 0.56, 0.20) if _structure_preview_valid else Color(0.85, 0.20, 0.16, 0.24)
		var line := KoalaSandTheme.COLOR_SUCCESS if _structure_preview_valid else KoalaSandTheme.COLOR_DANGER
		for cell in _structure_preview_cells:
			var rect := Rect2(Vector2(cell) * cell_pixel_size, Vector2.ONE * cell_pixel_size)
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, 1.0)
			if not _structure_preview_valid:
				draw_line(rect.position + Vector2(1, rect.size.y - 1), rect.end - Vector2(1, rect.size.y - 1), Color(line, 0.62), 1.0)
		if _structure_preview_type > 0:
			var bounds := Rect2(Vector2(_structure_preview_cells[0]) * cell_pixel_size, Vector2.ONE * cell_pixel_size)
			for cell in _structure_preview_cells: bounds = bounds.merge(Rect2(Vector2(cell) * cell_pixel_size, Vector2.ONE * cell_pixel_size))
			var center := bounds.get_center()
			var direction := Vector2(ComponentPresentation.orientation_vector(_structure_preview_orientation))
			if bool(ComponentPresentation.DIRECTIONAL_TYPES.get(_structure_preview_type, false)):
				draw_line(center - direction * 9.0, center + direction * 9.0, line, 3.0)
				var normal := Vector2(-direction.y, direction.x)
				draw_polyline(PackedVector2Array([center + direction * 9.0 - direction * 5.0 + normal * 4.0, center + direction * 9.0, center + direction * 9.0 - direction * 5.0 - normal * 4.0]), line, 2.0)
			for index in mini(5, _structure_preview_ports.size()):
				var angle := float(index) / maxf(1.0, float(_structure_preview_ports.size())) * TAU
				var port_position := center + Vector2.RIGHT.rotated(angle) * 14.0
				var port_name := str(_structure_preview_ports[index]).to_lower()
				var port_color := Color("59c7d3") if "fluid" in port_name or "water" in port_name else Color("d8e5e5") if "steam" in port_name else Color("e2a84b") if "mechan" in port_name else Color("d4c45b") if "power" in port_name else Color("9a85d6")
				draw_circle(port_position, 4.0, Color("0b1217dd"), true)
				draw_circle(port_position, 3.0, port_color, false, 2.0)

	if _info_mode and not _world is CellWorld:
		if _info_record_count <= 256:
			var records: PackedInt32Array = _world.get_visible_machine_entities(_info_chunks)
			for index in range(0, records.size(), 8):
				var cell := Vector2(records[index], records[index + 1]) * cell_pixel_size
				var state := int(records[index + 6])
				var color := Color("65dce7") if state in [0, 1, 6] else Color("ffb14f") if state in [3, 10] else Color("ff665c")
				draw_string(ThemeDB.fallback_font, cell + Vector2(4.0, -2.0), str(state), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, color)
		var routes: PackedInt32Array = _world.get_visible_subsurface_routes(Rect2i(_info_chunks.position * 64, _info_chunks.size * 64))
		for index in range(0, routes.size(), 10):
			var entrance := Vector2(routes[index + 3], routes[index + 4]) * cell_pixel_size
			var depth := int(routes[index + 2])
			var label: String = ["I", "II", "III"][depth]
			var color: Color = [Color("e3a548"), Color("42cfdf"), Color("a879e8")][depth]
			draw_string(ThemeDB.fallback_font, entrance + Vector2(3.0, -3.0), "%s · %d/%d" % [label, routes[index + 7], routes[index + 8]], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)

func _build_info_badge_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float circle = 1.0 - step(0.48, length(UV - vec2(0.5)));
	float core = 1.0 - step(0.18, length(UV - vec2(0.5)));
	vec3 color = mix(COLOR.rgb * 0.45, COLOR.rgb, core);
	COLOR = vec4(color, COLOR.a * circle);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
