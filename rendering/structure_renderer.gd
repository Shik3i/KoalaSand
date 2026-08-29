class_name StructureRenderer
extends Node2D

@export_range(1.0, 8.0, 1.0) var cell_pixel_size := 2.0
@export_enum("Paged", "Legacy Pipe Only", "Legacy Double Draw") var render_mode := 0

var _world: Variant
var _instances := MultiMeshInstance2D.new()
var _machines := MultiMeshInstance2D.new()
var _pipes := MultiMeshInstance2D.new()
var _infrastructure_pages := Node2D.new()
var _page_sprites: Dictionary = {}
var _page_dynamic_textures: Dictionary = {}
var _page_topology_bytes: Dictionary = {}
var _page_dynamic_bytes: Dictionary = {}
var _visible_chunks := Rect2i()
var _last_revision := -1
var _last_machine_revision := -1
var _last_power_revision := -1
var _last_pipe_revision := -1
var last_update_ms := 0.0
var last_render_tiles := 0
var last_machine_instances := 0
var last_pipe_instances := 0
var last_page_count := 0
var last_visibility_ms := 0.0
var last_cpu_prepare_ms := 0.0
var last_upload_ms := 0.0
var last_upload_bytes := 0
var overview_mode := false

const PAGE_CELLS := 64
const DENSE_PAGE_MIN_INSTANCES := 512


func _ready() -> void:
	_instances.name = "BatchedStructures"
	_instances.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_instances.material = _build_material()
	add_child(_instances)
	_machines.name = "BatchedMachines"
	_machines.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_machines.material = _build_machine_material()
	add_child(_machines)
	_pipes.name = "BatchedPipes"
	_pipes.visible = false
	add_child(_pipes)
	_infrastructure_pages.name = "InfrastructureRenderPages"
	add_child(_infrastructure_pages)


func initialize(world: Variant) -> void:
	_world = world
	_last_revision = -1
	_last_machine_revision = -1
	_last_power_revision = -1
	_last_pipe_revision = -1


func clear() -> void:
	_instances.multimesh = null
	_machines.multimesh = null
	_pipes.multimesh = null
	for sprite in _page_sprites.values():
		sprite.queue_free()
	_page_sprites.clear()
	_page_dynamic_textures.clear()
	_page_topology_bytes.clear()
	_page_dynamic_bytes.clear()
	_last_revision = -1
	_last_machine_revision = -1
	_last_power_revision = -1
	_last_pipe_revision = -1
	last_render_tiles = 0
	last_machine_instances = 0
	last_pipe_instances = 0
	last_page_count = 0

func set_overview_mode(enabled: bool) -> void:
	if overview_mode == enabled:
		return
	overview_mode = enabled
	_instances.visible = not enabled
	_machines.visible = not enabled
	_pipes.visible = not enabled and render_mode != 0
	_last_revision = -1


func sync_visible(chunk_area: Rect2i, force: bool = false) -> void:
	if _world == null:
		return
	var statistics: Dictionary = _world.get_structure_statistics()
	var revision := int(statistics.get("structure_revision", 0))
	var machine_revision := int(statistics.get("machine_visual_revision", 0))
	var power_revision := int(_world.get_power_statistics().get("revision", 0)) if _world.has_method("get_power_statistics") else 0
	var pipe_revision := int(_world.get_pipe_statistics().get("revision", 0)) if _world.has_method("get_pipe_statistics") else 0
	if not force and revision == _last_revision and machine_revision == _last_machine_revision and power_revision == _last_power_revision and pipe_revision == _last_pipe_revision and chunk_area == _visible_chunks:
		last_update_ms = 0.0
		last_visibility_ms = 0.0
		last_cpu_prepare_ms = 0.0
		last_upload_ms = 0.0
		last_upload_bytes = 0
		return
	var started := Time.get_ticks_usec()
	last_visibility_ms = 0.0
	last_cpu_prepare_ms = 0.0
	last_upload_ms = 0.0
	last_upload_bytes = 0
	var count := last_render_tiles
	if force or revision != _last_revision or chunk_area != _visible_chunks:
		var cells: PackedInt32Array = _world.get_visible_structure_cells(chunk_area)
		var page_counts: Dictionary = {}
		for index in cells.size() / 3:
			var counted_type := cells[index * 3 + 2]
			if not _is_dense_infrastructure(counted_type):
				continue
			var counted_page := _page_coordinate(Vector2i(cells[index * 3], cells[index * 3 + 1]))
			page_counts[counted_page] = int(page_counts.get(counted_page, 0)) + 1
		var filtered := PackedInt32Array()
		for index in cells.size() / 3:
			var type_id := cells[index * 3 + 2]
			if render_mode != 2 and _is_dense_infrastructure(type_id):
				var page := _page_coordinate(Vector2i(cells[index * 3], cells[index * 3 + 1]))
				var dense_conveyor := (type_id == 1 or type_id == 2) and int(page_counts.get(page, 0)) >= DENSE_PAGE_MIN_INSTANCES
				if type_id >= 10 or dense_conveyor:
					continue
			filtered.append(cells[index * 3])
			filtered.append(cells[index * 3 + 1])
			filtered.append(type_id)
		cells = filtered
		count = cells.size() / 3
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.instance_count = count
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * cell_pixel_size
		multimesh.mesh = quad
		for index in count:
			var cell := Vector2i(cells[index * 3], cells[index * 3 + 1])
			var type_id := cells[index * 3 + 2]
			var transform := Transform2D(0.0, (Vector2(cell) + Vector2(0.5, 0.5)) * cell_pixel_size)
			multimesh.set_instance_transform_2d(index, transform)
			multimesh.set_instance_color(index, _type_color(type_id))
			multimesh.set_instance_custom_data(index, Color(float(type_id) / 255.0, 0.0, 0.0, 1.0))
		_instances.multimesh = multimesh
		_instances.visible = not overview_mode
	if force or machine_revision != _last_machine_revision or power_revision != _last_power_revision or revision != _last_revision or chunk_area != _visible_chunks:
		_sync_machines(chunk_area)
	if force or pipe_revision != _last_pipe_revision or chunk_area != _visible_chunks:
		if render_mode == 0:
			_pipes.visible = false
			_infrastructure_pages.visible = true
			_sync_infrastructure_pages(chunk_area)
		else:
			_pipes.visible = true
			_infrastructure_pages.visible = false
			_sync_pipes(chunk_area)
	_visible_chunks = chunk_area
	_last_revision = revision
	_last_machine_revision = machine_revision
	_last_power_revision = power_revision
	_last_pipe_revision = pipe_revision
	last_render_tiles = count
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _sync_machines(chunk_area: Rect2i) -> void:
	var records: PackedInt32Array = _world.get_visible_machine_entities(chunk_area)
	var count := records.size() / 8
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * cell_pixel_size
	multimesh.mesh = quad
	for index in count:
		var origin := Vector2i(records[index * 8], records[index * 8 + 1])
		var type_id := records[index * 8 + 2]
		var size := Vector2i(records[index * 8 + 4], records[index * 8 + 5])
		var state := records[index * 8 + 6]
		var mechanical_speed := records[index * 8 + 7]
		var basis_x := Vector2(float(size.x), 0.0)
		var basis_y := Vector2(0.0, float(size.y))
		var position := (Vector2(origin) + Vector2(size) * 0.5) * cell_pixel_size
		multimesh.set_instance_transform_2d(index, Transform2D(basis_x, basis_y, position))
		multimesh.set_instance_color(index, _type_color(type_id))
		multimesh.set_instance_custom_data(index, Color(float(type_id) / 255.0, float(state) / 255.0, clampf(float(mechanical_speed) / 4000000.0, 0.0, 1.0), 1.0))
	_machines.multimesh = multimesh
	last_machine_instances = count


func _sync_pipes(chunk_area: Rect2i) -> void:
	var visibility_started := Time.get_ticks_usec()
	var records: PackedInt32Array = _world.get_visible_pipe_segments(chunk_area)
	last_visibility_ms = float(Time.get_ticks_usec() - visibility_started) / 1000.0
	var prepare_started := Time.get_ticks_usec()
	var count := records.size() / 11
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * cell_pixel_size
	multimesh.mesh = quad
	for index in count:
		var offset := index * 11
		var cell := Vector2i(records[offset], records[offset + 1])
		var type_id := records[offset + 2]
		var mass := records[offset + 4]
		var flow := records[offset + 5]
		var flags := records[offset + 6]
		var health := records[offset + 7]
		var connections := records[offset + 8]
		multimesh.set_instance_transform_2d(index, Transform2D(0.0, (Vector2(cell) + Vector2(0.5, 0.5)) * cell_pixel_size))
		var tint := Color(0.34, 0.45, 0.48, 1.0)
		if type_id == 14: tint = Color(0.72, 0.48, 0.16, 1.0)
		elif type_id == 15: tint = Color(0.62, 0.28, 0.18, 1.0)
		elif type_id == 12 or type_id == 13: tint = Color(0.28, 0.58, 0.62, 1.0)
		if health <= 0: tint = Color(0.42, 0.12, 0.08, 1.0)
		multimesh.set_instance_color(index, tint)
		multimesh.set_instance_custom_data(index, Color(float(mass) / 65535.0, clampf(float(flow) / 8192.0 * 0.5 + 0.5, 0.0, 1.0), float(flags) / 15.0, float(connections) / 15.0))
	last_cpu_prepare_ms = float(Time.get_ticks_usec() - prepare_started) / 1000.0
	var upload_started := Time.get_ticks_usec()
	_pipes.multimesh = multimesh
	last_upload_ms = float(Time.get_ticks_usec() - upload_started) / 1000.0
	last_upload_bytes = count * 48
	last_pipe_instances = count


func _sync_infrastructure_pages(chunk_area: Rect2i) -> void:
	var visibility_started := Time.get_ticks_usec()
	var page_records: Dictionary = {}
	var end := chunk_area.end
	for page_y in range(chunk_area.position.y, end.y):
		for page_x in range(chunk_area.position.x, end.x):
			var page := Vector2i(page_x, page_y)
			var record: Dictionary = _world.get_infrastructure_render_page(page)
			var count := int(record.get("infrastructure_count", 0))
			var pipes := int(record.get("pipe_count", 0))
			if count > 0 and (pipes > 0 or count >= DENSE_PAGE_MIN_INSTANCES):
				page_records[page] = record
	last_visibility_ms = float(Time.get_ticks_usec() - visibility_started) / 1000.0
	var prepare_started := Time.get_ticks_usec()
	var pipe_count := 0
	last_cpu_prepare_ms = float(Time.get_ticks_usec() - prepare_started) / 1000.0
	var upload_started := Time.get_ticks_usec()
	var visible_keys: Dictionary = {}
	for page in page_records:
		visible_keys[page] = true
		var record: Dictionary = page_records[page]
		var page_width := int(record.width)
		var page_height := int(record.height)
		var static_image := Image.create_from_data(page_width, page_height, false, Image.FORMAT_RGBA8, record.topology)
		var dynamic_image := Image.create_from_data(page_width, page_height, false, Image.FORMAT_RGBA8, record.dynamic)
		pipe_count += int(record.get("pipe_count", 0))
		var sprite: Sprite2D
		if _page_sprites.has(page):
			sprite = _page_sprites[page]
			if sprite.texture.get_width() != page_width or sprite.texture.get_height() != page_height:
				sprite.texture = ImageTexture.create_from_image(static_image)
				var resized_dynamic := ImageTexture.create_from_image(dynamic_image)
				_page_dynamic_textures[page] = resized_dynamic
				(sprite.material as ShaderMaterial).set_shader_parameter("dynamic_state", resized_dynamic)
				_page_topology_bytes[page] = record.topology
				_page_dynamic_bytes[page] = record.dynamic
				last_upload_bytes += page_width * page_height * 8
			elif _page_topology_bytes.get(page, PackedByteArray()) != record.topology:
				(sprite.texture as ImageTexture).update(static_image)
				_page_topology_bytes[page] = record.topology
				last_upload_bytes += page_width * page_height * 4
			if _page_dynamic_bytes.get(page, PackedByteArray()) != record.dynamic:
				(_page_dynamic_textures[page] as ImageTexture).update(dynamic_image)
				_page_dynamic_bytes[page] = record.dynamic
				last_upload_bytes += page_width * page_height * 4
		else:
			sprite = Sprite2D.new()
			sprite.name = "Page_%d_%d" % [page.x, page.y]
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.texture = ImageTexture.create_from_image(static_image)
			var dynamic_texture := ImageTexture.create_from_image(dynamic_image)
			sprite.material = _build_infrastructure_page_material(dynamic_texture)
			sprite.position = Vector2(record.cell_position) * cell_pixel_size
			sprite.scale = Vector2.ONE * cell_pixel_size
			_infrastructure_pages.add_child(sprite)
			_page_sprites[page] = sprite
			_page_dynamic_textures[page] = dynamic_texture
			_page_topology_bytes[page] = record.topology
			_page_dynamic_bytes[page] = record.dynamic
			last_upload_bytes += page_width * page_height * 8
		sprite.position = Vector2(record.cell_position) * cell_pixel_size
	for page in _page_sprites.keys():
		var sprite: Sprite2D = _page_sprites[page]
		sprite.visible = visible_keys.has(page)
	last_upload_ms = float(Time.get_ticks_usec() - upload_started) / 1000.0
	last_page_count = page_records.size()
	last_pipe_instances = pipe_count


func _is_dense_infrastructure(type_id: int) -> bool:
	return type_id == 1 or type_id == 2 or (type_id >= 10 and type_id <= 15)


func _page_coordinate(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(float(cell.x) / PAGE_CELLS), floori(float(cell.y) / PAGE_CELLS))


func _type_color(type_id: int) -> Color:
	match type_id:
		1, 2:
			return Color(0.31, 0.38, 0.42, 1.0)
		3:
			return Color(0.82, 0.48, 0.14, 1.0)
		4:
			return Color(0.18, 0.50, 0.56, 1.0)
		5:
			return Color(0.50, 0.25, 0.16, 1.0)
		6:
			return Color(0.42, 0.46, 0.42, 1.0)
		7:
			return Color(0.22, 0.34, 0.42, 1.0)
		8:
			return Color(0.32, 0.37, 0.35, 1.0)
		10, 11, 12, 13, 14, 15:
			return Color(0.30, 0.48, 0.52, 1.0)
		16:
			return Color(0.36, 0.43, 0.46, 1.0)
		17:
			return Color(0.44, 0.36, 0.24, 1.0)
		18, 19:
			return Color("e3a548")
		20, 21:
			return Color("42cfdf")
		22, 23:
			return Color("a879e8")
		26:
			return Color("c58b38")
		27:
			return Color("778995")
		28:
			return Color("52727f")
		29, 30:
			return Color("e0b44f")
		31:
			return Color("4ac4a1")
		32:
			return Color("a879e8")
		33:
			return Color("b87333")
		34:
			return Color("e95b28")
		37:
			return Color("68777b")
		38:
			return Color("76919a")
		39:
			return Color("c4bda8")
		40:
			return Color("8a4e36")
		41:
			return Color("6fabb0")
		42:
			return Color("566970")
		43:
			return Color("b88a3d")
		44:
			return Color("87745f")
		45:
			return Color("4f9298")
		46:
			return Color("b66f3c")
		47:
			return Color("6f8589")
		_:
			return Color(0.42, 0.52, 0.55, 1.0)


func _build_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

varying float instance_kind;

void vertex() {
	instance_kind = INSTANCE_CUSTOM.r;
	float kind = floor(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	if (kind < 2.5) {
		VERTEX.y *= 1.55;
	} else {
		VERTEX *= 1.12;
	}
}

void fragment() {
	float kind = floor(instance_kind * 255.0 + 0.5);
	vec3 base = COLOR.rgb;
	vec3 dark = base * 0.42;
	vec3 brass = vec3(0.92, 0.59, 0.19);
	float edge = step(UV.y, 0.18) + step(0.82, UV.y);
	vec3 result = mix(base, brass, clamp(edge, 0.0, 1.0) * 0.72);
	if (kind < 2.5) {
		float direction = kind < 1.5 ? -1.0 : 1.0;
		float tread = step(0.52, fract(UV.x * 3.0 - TIME * direction * 1.8));
		result = mix(result, dark, tread * (1.0 - clamp(edge, 0.0, 1.0)) * 0.50);
		float chevron = step(0.78, fract((UV.x + UV.y * direction) * 4.0 - TIME * direction));
		result = mix(result, brass, chevron * 0.34);
	} else if (kind < 36.5) {
		float rivet = step(0.86, fract(UV.x * 2.0)) * step(0.86, fract(UV.y * 2.0));
		result = mix(result, brass, rivet * 0.38);
		result *= 0.82 + 0.18 * (1.0 - UV.y);
	} else if (kind < 37.5) {
		float frame = max(max(step(UV.x, 0.10), step(0.90, UV.x)), max(step(UV.y, 0.12), step(0.88, UV.y)));
		float brace = step(abs(UV.x + UV.y - 1.0), 0.055) + step(abs(UV.x - UV.y), 0.055);
		result = mix(base * 0.48, base * 1.12, clamp(frame + brace * 0.55, 0.0, 1.0));
	} else if (kind < 38.5) {
		float seam = step(0.93, fract(UV.x * 3.0)) + step(0.93, fract(UV.y * 2.0));
		float rivet = step(0.84, fract(UV.x * 4.0)) * step(0.84, fract(UV.y * 3.0));
		result = mix(base * 0.58, base * 1.14, 0.34 + 0.24 * (1.0 - UV.y));
		result = mix(result, vec3(0.90, 0.72, 0.35), clamp(seam * 0.24 + rivet * 0.58, 0.0, 0.72));
	} else if (kind < 39.5) {
		float vertical = step(0.94, fract(UV.x * 4.0));
		float horizontal = step(0.91, fract(UV.y * 3.0));
		result = mix(base * 0.72, base * 1.12, 0.32 + 0.18 * (1.0 - UV.y));
		result *= 1.0 - clamp(vertical + horizontal, 0.0, 1.0) * 0.24;
	} else if (kind < 40.5) {
		float courses = step(0.87, fract(UV.y * 4.0));
		float stagger = step(0.92, fract(UV.x * 3.0 + floor(UV.y * 4.0) * 0.5));
		result = mix(base * 0.48, base * 1.08, 0.24 + 0.20 * (1.0 - UV.y));
		result = mix(result, vec3(0.18, 0.11, 0.08), clamp(courses + stagger, 0.0, 1.0) * 0.58);
	} else if (kind < 41.5) {
		float frame = max(max(step(UV.x, 0.08), step(0.92, UV.x)), max(step(UV.y, 0.10), step(0.90, UV.y)));
		float grid = step(0.82, fract(UV.x * 8.0)) + step(0.82, fract(UV.y * 6.0));
		result = mix(vec3(0.055, 0.09, 0.10), base * 1.20, clamp(frame + grid, 0.0, 1.0));
	} else if (kind < 42.5) {
		float support = step(UV.y, 0.20) + step(0.84, UV.y);
		float bars = step(0.62, fract(UV.x * 7.0));
		result = mix(vec3(0.04, 0.07, 0.08), base * 1.15, clamp(support + bars, 0.0, 1.0));
	} else if (kind < 43.5) {
		float floor_plate = step(0.67, UV.y);
		float ridges = step(0.65, fract(UV.x * 6.0 + UV.y * 1.6));
		result = mix(base * 0.42, base * 1.18, max(floor_plate * 0.72, ridges));
	} else if (kind < 44.5) {
		float layers = step(0.82, fract(UV.y * 5.0));
		result = mix(base * 0.58, vec3(0.28, 0.25, 0.23), layers * 0.72);
	} else if (kind < 45.5) {
		vec2 rotor_uv = UV - vec2(0.5);
		float ring = 1.0 - smoothstep(0.035, 0.07, abs(length(rotor_uv) - 0.25));
		float mount = step(0.72, UV.y);
		result = mix(base * 0.45, brass, mount * 0.58);
		result = mix(result, vec3(0.25, 0.72, 0.74), ring * 0.82);
	} else if (kind < 46.5) {
		vec2 curve = vec2((UV.x - 0.5) * 1.4, UV.y - 0.42);
		float horseshoe = (1.0 - smoothstep(0.035, 0.075, abs(length(curve) - 0.29))) * step(0.36, UV.y);
		float poles = step(0.72, UV.y) * step(abs(UV.x - 0.5), 0.34);
		result = mix(base * 0.42, vec3(0.20, 0.72, 0.78), clamp(horseshoe + poles * 0.45, 0.0, 1.0));
	} else {
		vec2 fan_uv = UV - vec2(0.5);
		float ring = 1.0 - smoothstep(0.035, 0.075, abs(length(fan_uv) - 0.27));
		float blades = step(0.18, cos(atan(fan_uv.y, fan_uv.x) * 5.0)) * step(length(fan_uv), 0.25);
		result = mix(base * 0.48, vec3(0.60, 0.76, 0.76), max(ring, blades * 0.44));
	}
	COLOR = vec4(result, COLOR.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _build_machine_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

varying float instance_kind;
varying float instance_state;
varying float instance_speed;

void vertex() {
	instance_kind = INSTANCE_CUSTOM.r;
	instance_state = INSTANCE_CUSTOM.g;
	instance_speed = INSTANCE_CUSTOM.b;
	float kind = floor(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	float state = floor(INSTANCE_CUSTOM.g * 255.0 + 0.5);
	if (kind > 5.5 && kind < 6.5 && state > 2.5) {
		VERTEX.x += sin(TIME * 22.0 + VERTEX.y * 4.0) * 0.012;
	}
}

void fragment() {
	float kind = floor(instance_kind * 255.0 + 0.5);
	float state = floor(instance_state * 255.0 + 0.5);
	vec3 metal = COLOR.rgb;
	vec3 shadow = metal * 0.28;
	vec3 brass = vec3(0.95, 0.58, 0.15);
	float alpha = 1.0;
	vec3 result = metal;
	if (kind < 3.5) {
		float edge = abs(UV.x - 0.5);
		float slope = mix(0.43, 0.10, UV.y);
		alpha = 1.0 - step(0.075, abs(edge - slope));
		result = mix(shadow, brass, step(0.035, abs(edge - slope)));
	} else if (kind < 4.5) {
		float walls = max(step(UV.x, 0.13), step(0.87, UV.x));
		float floor_plate = step(0.82, UV.y);
		alpha = max(walls, floor_plate);
		float ribs = step(0.72, fract(UV.y * 6.0));
		result = mix(metal, brass, ribs * walls * 0.45);
	} else if (kind < 5.5) {
		float side_frame = max(step(UV.x, 0.08), step(0.92, UV.x));
		float radiant_hood = step(UV.y, 0.26);
		float heater_bar = radiant_hood * step(0.55, fract(UV.x * 7.0));
		alpha = max(side_frame, radiant_hood);
		result = mix(metal * 0.74, brass, side_frame * 0.78);
		vec3 furnace_glow = state > 2.5 && state < 4.5 ? vec3(1.0, 0.35 + 0.12 * sin(TIME * 5.0), 0.04) : vec3(0.12, 0.25, 0.29);
		result = mix(result, furnace_glow, heater_bar * (state > 2.5 ? 0.94 : 0.58));
	} else if (kind < 6.5) {
		float side_frame = max(step(UV.x, 0.08), step(0.92, UV.x));
		float top_crossbar = step(UV.y, 0.14);
		float deck = step(0.57, UV.y) * step(UV.y, 0.69);
		float mesh = deck * step(0.48, fract(UV.x * 20.0 + sin(TIME * 18.0) * 0.08));
		alpha = max(max(side_frame, top_crossbar), deck);
		result = mix(metal * 0.70, brass, max(side_frame, top_crossbar) * 0.65 + mesh * 0.38);
	} else if (kind < 7.5) {
		float side_frame = max(step(UV.x, 0.07), step(0.93, UV.x));
		float capture_belt = step(UV.y, 0.34);
		alpha = max(side_frame, capture_belt);
		vec2 center = vec2(UV.x - 0.5, (UV.y - 0.17) * 2.1);
		float ring = 1.0 - smoothstep(0.025, 0.055, abs(length(center) - 0.22));
		float rotor = step(0.78, cos(atan(center.y, center.x) * 6.0 + TIME * 4.0));
		result = mix(metal * 0.62, vec3(0.35, 0.70, 0.78), ring * (0.35 + rotor * 0.35));
		result = mix(result, brass, side_frame * 0.55);
	} else if (kind < 16.5) {
		float frame = max(max(step(UV.x, 0.075), step(0.925, UV.x)), max(step(UV.y, 0.09), step(0.91, UV.y)));
		float intake = step(0.20, UV.x) * step(UV.x, 0.80) * step(0.16, UV.y) * step(UV.y, 0.38);
		float display = step(0.23, UV.x) * step(UV.x, 0.77) * step(0.53, UV.y) * step(UV.y, 0.78);
		float count_lines = step(0.62, fract(UV.x * 9.0 + TIME * 0.35));
		vec3 status_color = state > 5.5 && state < 7.5 ? vec3(1.0, 0.63, 0.16) : state > 7.5 ? vec3(0.95, 0.18, 0.08) : vec3(0.16, 0.34, 0.34);
		result = mix(metal * 0.55, shadow, intake * 0.80);
		result = mix(result, status_color, display * (0.58 + count_lines * 0.32));
		result = mix(result, brass, frame * 0.70);
	} else if (kind < 25.5) {
		float wall = max(step(UV.x, 0.055), step(0.945, UV.x));
		float floor_plate = step(0.78, UV.y);
		float riffles = step(0.72, UV.y) * step(0.76, fract(UV.x * 18.0));
		float water = step(0.58, UV.y) * step(UV.y, 0.79) * (1.0 - wall);
		float sparkle = step(0.82, fract(UV.x * 24.0 - TIME * 3.2));
		alpha = max(max(wall, floor_plate), water);
		result = mix(metal * 0.62, brass, max(wall, riffles) * 0.78);
		result = mix(result, vec3(0.05, 0.58, 0.72) + sparkle * vec3(0.18, 0.22, 0.12), water * 0.88);
	} else {
		float frame = max(max(step(UV.x, 0.06), step(0.94, UV.x)), max(step(UV.y, 0.08), step(0.92, UV.y)));
		vec2 rotor_uv = UV - vec2(0.5);
		float radius = length(rotor_uv);
		float ring = 1.0 - smoothstep(0.025, 0.060, abs(radius - 0.24));
		float angle = atan(rotor_uv.y, rotor_uv.x) + TIME * (0.5 + instance_speed * 16.0);
		float spokes = step(0.72, cos(angle * 6.0)) * step(radius, 0.25);
		float electric = step(0.72, fract(UV.x * 8.0 + UV.y * 5.0));
		vec3 power_glow = kind < 28.5 ? vec3(0.96, 0.52, 0.12) : kind < 31.5 ? vec3(0.96, 0.78, 0.23) : vec3(0.22, 0.88, 0.72);
		result = mix(metal * 0.52, brass, frame * 0.72);
		result = mix(result, power_glow, max(ring, spokes) * (0.35 + instance_speed * 0.55));
		result = mix(result, power_glow, electric * 0.10 * step(28.5, kind));
	}
	COLOR = vec4(result, alpha * COLOR.a * 0.96);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _build_pipe_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

varying vec4 pipe_state;

void vertex() {
	pipe_state = INSTANCE_CUSTOM;
}

void fragment() {
	float fill = pipe_state.r;
	float flow = (pipe_state.g - 0.5) * 2.0;
	float flags = floor(pipe_state.b * 15.0 + 0.5);
	float mask = floor(pipe_state.a * 15.0 + 0.5);
	float north = mod(mask, 2.0);
	float east = mod(floor(mask / 2.0), 2.0);
	float south = mod(floor(mask / 4.0), 2.0);
	float west = mod(floor(mask / 8.0), 2.0);
	float core = step(abs(UV.x - 0.5), 0.24) * step(abs(UV.y - 0.5), 0.24);
	float arms = north * step(abs(UV.x - 0.5), 0.24) * step(UV.y, 0.5)
		+ south * step(abs(UV.x - 0.5), 0.24) * step(0.5, UV.y)
		+ west * step(abs(UV.y - 0.5), 0.24) * step(UV.x, 0.5)
		+ east * step(abs(UV.y - 0.5), 0.24) * step(0.5, UV.x);
	float body = clamp(core + arms, 0.0, 1.0);
	float inner = step(abs(UV.x - 0.5), 0.12) * step(abs(UV.y - 0.5), 0.12);
	inner += north * step(abs(UV.x - 0.5), 0.12) * step(UV.y, 0.5);
	inner += south * step(abs(UV.x - 0.5), 0.12) * step(0.5, UV.y);
	inner += west * step(abs(UV.y - 0.5), 0.12) * step(UV.x, 0.5);
	inner += east * step(abs(UV.y - 0.5), 0.12) * step(0.5, UV.x);
	inner = clamp(inner, 0.0, 1.0);
	float motion = step(0.64, fract((UV.x + UV.y) * 7.0 - TIME * sign(flow) * 2.8)) * step(0.02, abs(flow));
	vec3 metal = mix(COLOR.rgb * 0.48, COLOR.rgb * 1.15, body);
	vec3 water = mix(vec3(0.04, 0.30, 0.44), vec3(0.10, 0.72, 0.86), 0.45 + motion * 0.35);
	vec3 result = mix(metal, water, inner * fill);
	float breached = mod(floor(flags / 4.0), 2.0);
	result = mix(result, vec3(0.95, 0.18, 0.04), breached * step(0.55, fract((UV.x - UV.y) * 6.0)) * 0.8);
	COLOR = vec4(result, body * COLOR.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _build_infrastructure_page_material(dynamic_texture: ImageTexture) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D dynamic_state : filter_nearest, repeat_disable;

void fragment() {
	vec4 topology = texture(TEXTURE, UV);
	vec4 dynamic = texture(dynamic_state, UV);
	float kind = floor(topology.r * 255.0 + 0.5);
	if (kind < 0.5) { discard; }
	vec2 cells = vec2(textureSize(TEXTURE, 0));
	vec2 cell_uv = fract(UV * cells);
	vec3 brass = vec3(0.92, 0.59, 0.19);
	if (kind < 2.5) {
		float horizontal = kind < 1.5 ? 1.0 : 0.0;
		float lane = mix(step(abs(cell_uv.x - 0.5), 0.31), step(abs(cell_uv.y - 0.5), 0.31), horizontal);
		float along = mix(cell_uv.y, cell_uv.x, horizontal);
		float tread = step(0.52, fract(along * 3.0 - TIME * (horizontal > 0.5 ? 1.8 : -1.8)));
		vec3 belt = mix(vec3(0.13, 0.18, 0.20), vec3(0.31, 0.38, 0.42), tread * 0.55);
		float rail = step(0.23, abs(mix(cell_uv.x, cell_uv.y, horizontal) - 0.5));
		COLOR = vec4(mix(belt, brass, rail * 0.65), lane);
	} else {
	float mask = floor(topology.g * 15.0 + 0.5);
	float north = mod(mask, 2.0);
	float east = mod(floor(mask / 2.0), 2.0);
	float south = mod(floor(mask / 4.0), 2.0);
	float west = mod(floor(mask / 8.0), 2.0);
	float core = step(abs(cell_uv.x - 0.5), 0.25) * step(abs(cell_uv.y - 0.5), 0.25);
	float arms = north * step(abs(cell_uv.x - 0.5), 0.25) * step(cell_uv.y, 0.5)
		+ south * step(abs(cell_uv.x - 0.5), 0.25) * step(0.5, cell_uv.y)
		+ west * step(abs(cell_uv.y - 0.5), 0.25) * step(cell_uv.x, 0.5)
		+ east * step(abs(cell_uv.y - 0.5), 0.25) * step(0.5, cell_uv.x);
	float body = clamp(core + arms, 0.0, 1.0);
	float inner = step(abs(cell_uv.x - 0.5), 0.12) * step(abs(cell_uv.y - 0.5), 0.12);
	inner += north * step(abs(cell_uv.x - 0.5), 0.12) * step(cell_uv.y, 0.5);
	inner += south * step(abs(cell_uv.x - 0.5), 0.12) * step(0.5, cell_uv.y);
	inner += west * step(abs(cell_uv.y - 0.5), 0.12) * step(cell_uv.x, 0.5);
	inner += east * step(abs(cell_uv.y - 0.5), 0.12) * step(0.5, cell_uv.x);
	inner = clamp(inner, 0.0, 1.0);
	float fill = dynamic.r;
	float flow = (dynamic.g - 0.5) * 2.0;
	float motion = step(0.64, fract((cell_uv.x + cell_uv.y) * 7.0 - TIME * sign(flow) * 2.8)) * step(0.02, abs(flow));
	vec3 tint = vec3(0.34, 0.45, 0.48);
	if (kind > 13.5 && kind < 14.5) tint = vec3(0.72, 0.48, 0.16);
	else if (kind > 14.5 && kind < 15.5) tint = vec3(0.62, 0.28, 0.18);
	else if (kind > 11.5 && kind < 13.5) tint = vec3(0.28, 0.58, 0.62);
	vec3 metal = mix(tint * 0.48, tint * 1.15, body);
	vec3 water = mix(vec3(0.04, 0.30, 0.44), vec3(0.10, 0.72, 0.86), 0.45 + motion * 0.35);
	vec3 result = mix(metal, water, inner * fill);
	float breached = step(0.49, mod(floor(dynamic.b * 15.0 + 0.5) / 4.0, 2.0));
	result = mix(result, vec3(0.95, 0.18, 0.04), breached * step(0.55, fract((cell_uv.x - cell_uv.y) * 6.0)) * 0.8);
	float far_lod = step(2.5, fwidth(cell_uv.x) * cells.x);
	result = mix(result, mix(tint * 0.70, water, fill * 0.65), far_lod * 0.55);
	COLOR = vec4(result, body);
	}
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("dynamic_state", dynamic_texture)
	return material
