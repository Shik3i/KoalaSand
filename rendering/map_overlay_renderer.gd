class_name MapOverlayRenderer
extends Node2D

enum Mode {
	NONE,
	GEOLOGY,
	MATERIAL,
	DENSITY,
	TEMPERATURE,
	MAGNETIC_FIELD,
	FLUID_FLOW,
	PIPE_PRESSURE,
	AUTOMATION,
	UNDERGROUND_LOGISTICS,
	ACTIVITY,
	DAMAGE,
	PRODUCTION,
	POWER,
}

@export var cell_pixel_size := 2.0
var mode := Mode.NONE
var _world: Variant
var _visible_chunks := Rect2i()
var _samples := PackedInt32Array()
var _routes := PackedInt32Array()
var _last_structure_revision := -1
var last_update_ms := 0.0
var last_draw_ms := 0.0
var last_upload_ms := 0.0
var last_upload_bytes := 0
var _temperature_page := Sprite2D.new()
var _temperature_texture: ImageTexture
var _temperature_bytes := PackedByteArray()
var _route_instances := MultiMeshInstance2D.new()
var _power_instances := MultiMeshInstance2D.new()

func _ready() -> void:
	_route_instances.name = "BatchedSubsurfaceRoutes"
	_route_instances.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_route_instances.material = _build_subsurface_route_material()
	_route_instances.visible = false
	add_child(_route_instances)
	_power_instances.name = "BatchedPowerInfrastructure"
	_power_instances.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_power_instances.material = _build_power_material()
	_power_instances.visible = false
	add_child(_power_instances)
	_temperature_page.name = "VisibleTemperaturePage"
	_temperature_page.centered = false
	_temperature_page.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_temperature_page.material = _build_temperature_material()
	_temperature_page.visible = false
	add_child(_temperature_page)

func initialize(world: Variant) -> void:
	_world = world
	_samples.clear()
	_routes.clear()
	_last_structure_revision = -1
	_temperature_page.visible = false
	_route_instances.visible = false
	_route_instances.multimesh = null
	_power_instances.visible = false
	_power_instances.multimesh = null
	queue_redraw()

func set_mode(next_mode: int) -> void:
	mode = clampi(next_mode, Mode.NONE, Mode.POWER) as Mode
	_samples.clear()
	_routes.clear()
	_last_structure_revision = -1
	_temperature_page.visible = mode == Mode.TEMPERATURE
	_route_instances.visible = mode == Mode.UNDERGROUND_LOGISTICS
	_power_instances.visible = mode == Mode.POWER
	if mode != Mode.UNDERGROUND_LOGISTICS:
		_route_instances.multimesh = null
	queue_redraw()

func sync_visible(chunk_area: Rect2i) -> void:
	if _world == null or mode not in [Mode.MAGNETIC_FIELD, Mode.TEMPERATURE, Mode.UNDERGROUND_LOGISTICS, Mode.PRODUCTION, Mode.POWER]:
		_visible_chunks = chunk_area
		last_update_ms = 0.0
		return
	# Temperature is authoritative at 30 Hz; skip the interleaved 60 Hz tick.
	var revision := int(_world.get_statistics().get("tick", 0)) / 4 if mode == Mode.PRODUCTION else int(_world.get_structure_statistics().get("structure_revision", 0)) if mode in [Mode.MAGNETIC_FIELD, Mode.UNDERGROUND_LOGISTICS] else int(_world.get_power_statistics().get("revision", 0)) + int(_world.get_mechanical_statistics().get("revision", 0)) if mode == Mode.POWER else int(_world.get_statistics().get("tick", 0)) / 2
	if chunk_area == _visible_chunks and revision == _last_structure_revision:
		last_update_ms = 0.0
		return
	_visible_chunks = chunk_area
	_last_structure_revision = revision
	var started := Time.get_ticks_usec()
	var cell_area := Rect2i(chunk_area.position * 64, chunk_area.size * 64)
	if mode == Mode.MAGNETIC_FIELD:
		var sample: Dictionary = _world.get_magnetic_field_sample(cell_area, 4)
		_samples = sample.get("samples", PackedInt32Array())
	elif mode == Mode.TEMPERATURE:
		var page: Dictionary = _world.get_temperature_render_page(chunk_area)
		var pixels: PackedByteArray = page.get("pixels", PackedByteArray())
		last_upload_bytes = 0
		last_upload_ms = 0.0
		if pixels != _temperature_bytes:
			var upload_started := Time.get_ticks_usec()
			var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RG8, pixels)
			if _temperature_texture == null or _temperature_texture.get_width() != int(page.width) or _temperature_texture.get_height() != int(page.height):
				_temperature_texture = ImageTexture.create_from_image(image)
				_temperature_page.texture = _temperature_texture
			else:
				_temperature_texture.update(image)
			_temperature_page.position = Vector2(page.cell_position) * cell_pixel_size
			_temperature_page.scale = Vector2.ONE * cell_pixel_size
			_temperature_bytes = pixels
			last_upload_bytes = pixels.size()
			last_upload_ms = float(Time.get_ticks_usec() - upload_started) / 1000.0
	elif mode == Mode.UNDERGROUND_LOGISTICS:
		_routes = _world.get_visible_subsurface_routes(cell_area)
		_sync_subsurface_route_instances()
	elif mode == Mode.PRODUCTION:
		_routes = _world.get_visible_machine_entities(chunk_area)
	else:
		_routes = _world.get_visible_power_elements(cell_area)
		_sync_power_instances()
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0
	queue_redraw()

func _draw() -> void:
	var started := Time.get_ticks_usec()
	if mode == Mode.MAGNETIC_FIELD:
		for index in range(0, _samples.size(), 5):
			var position := Vector2(_samples[index], _samples[index + 1]) * cell_pixel_size
			var strength := float(_samples[index + 4]) / 1200.0
			var color := Color(0.18, 0.86, 0.92, clampf(0.12 + strength * 0.33, 0.12, 0.48))
			draw_rect(Rect2(position, Vector2.ONE * cell_pixel_size * 4.0), color)
	elif mode == Mode.UNDERGROUND_LOGISTICS:
		if _routes.size() > 640:
			last_draw_ms = float(Time.get_ticks_usec() - started) / 1000.0
			return
		for index in range(0, _routes.size(), 10):
			var depth := int(_routes[index + 2])
			var from := Vector2(_routes[index + 3], _routes[index + 4]) * cell_pixel_size + Vector2.ONE * cell_pixel_size * 0.5
			var to := Vector2(_routes[index + 5], _routes[index + 6]) * cell_pixel_size + Vector2.ONE * cell_pixel_size * 0.5
			var color: Color = [Color("e3a548"), Color("42cfdf"), Color("a879e8")][depth]
			var label: String = ["I", "II", "III"][depth]
			draw_string(ThemeDB.fallback_font, from + Vector2(3.0, -3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)
	elif mode == Mode.PRODUCTION:
		for index in range(0, _routes.size(), 8):
			var position := (Vector2(_routes[index], _routes[index + 1]) + Vector2(0.5, 0.5)) * cell_pixel_size
			var orientation := int(_routes[index + 3]) if _routes.size() > index + 3 else 0
			var state := int(_routes[index + 6])
			var direction := Vector2(ComponentPresentation.orientation_vector(orientation))
			var blocked := state not in [0, 1, 6]
			var color := Color("ff785c") if blocked else Color("6ed9b5")
			draw_line(position - direction * 5.0, position + direction * 8.0, color, 2.5)
			var normal := Vector2(-direction.y, direction.x)
			draw_polyline(PackedVector2Array([position + direction * 8.0 - direction * 4.0 + normal * 3.0, position + direction * 8.0, position + direction * 8.0 - direction * 4.0 - normal * 3.0]), color, 2.0)
			if blocked: draw_line(position + Vector2(-3, -3), position + Vector2(3, 3), color, 2.0)
	last_draw_ms = float(Time.get_ticks_usec() - started) / 1000.0

func provider_available(requested_mode: int) -> bool:
	return requested_mode in [Mode.NONE, Mode.GEOLOGY, Mode.TEMPERATURE, Mode.MAGNETIC_FIELD, Mode.AUTOMATION, Mode.UNDERGROUND_LOGISTICS, Mode.PRODUCTION, Mode.POWER]

func _sync_power_instances() -> void:
	var count := _routes.size() / 6
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	for item_index in count:
		var index := item_index * 6
		var kind := int(_routes[index])
		var from := (Vector2(_routes[index + 1], _routes[index + 2]) + Vector2(0.5, 0.5)) * cell_pixel_size
		if kind == 2:
			var to := (Vector2(_routes[index + 3], _routes[index + 4]) + Vector2(0.5, 0.5)) * cell_pixel_size
			var delta := to - from
			var length := maxf(1.0, delta.length())
			var direction := delta / length
			var normal := Vector2(-direction.y, direction.x)
			multimesh.set_instance_transform_2d(item_index, Transform2D(direction * length, normal * maxf(1.0, cell_pixel_size * 0.45), (from + to) * 0.5))
			multimesh.set_instance_color(item_index, Color("e0b44f"))
			multimesh.set_instance_custom_data(item_index, Color(2.0 / 3.0, float(_routes[index + 5]) / 3.0, 0.0, 1.0))
		else:
			var size := cell_pixel_size * (1.45 if kind == 1 else 1.05)
			multimesh.set_instance_transform_2d(item_index, Transform2D(Vector2(size, 0.0), Vector2(0.0, size), from))
			var network_pattern := float(abs(_routes[index + 4]) % 7) / 6.0
			var speed := clampf(float(_routes[index + 4]) / 4000000.0, 0.0, 1.0) if kind == 3 else 0.0
			multimesh.set_instance_color(item_index, Color("e0b44f") if kind == 1 else Color("c58b38"))
			multimesh.set_instance_custom_data(item_index, Color(float(kind) / 3.0, network_pattern, speed, 1.0))
	_power_instances.multimesh = multimesh
	_power_instances.visible = mode == Mode.POWER
	last_upload_bytes = count * 48

func _draw_depth_route(from: Vector2, to: Vector2, depth: int, color: Color) -> void:
	if depth == 0:
		draw_line(from, to, color, maxf(1.5, cell_pixel_size * 0.55), true)
		return
	var delta := to - from
	var length := delta.length()
	if length <= 0.0:
		return
	var direction := delta / length
	var normal := Vector2(-direction.y, direction.x) * (cell_pixel_size * 0.45 if depth == 2 else 0.0)
	var dash := maxf(cell_pixel_size * 3.0, 6.0)
	var cursor := 0.0
	while cursor < length:
		var end := minf(length, cursor + dash * 0.58)
		draw_line(from + direction * cursor + normal, from + direction * end + normal, color, maxf(1.2, cell_pixel_size * 0.42), true)
		if depth == 2:
			draw_line(from + direction * cursor - normal, from + direction * end - normal, color, maxf(1.0, cell_pixel_size * 0.30), true)
		cursor += dash

func _sync_subsurface_route_instances() -> void:
	var count := _routes.size() / 10
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	for route_index in count:
		var index := route_index * 10
		var depth := int(_routes[index + 2])
		var from := Vector2(_routes[index + 3], _routes[index + 4]) * cell_pixel_size + Vector2.ONE * cell_pixel_size * 0.5
		var to := Vector2(_routes[index + 5], _routes[index + 6]) * cell_pixel_size + Vector2.ONE * cell_pixel_size * 0.5
		var delta := to - from
		var length := maxf(1.0, delta.length())
		var direction := delta / length
		var normal := Vector2(-direction.y, direction.x)
		var width := maxf(3.0, cell_pixel_size * (2.8 if depth == 2 else 2.0))
		multimesh.set_instance_transform_2d(route_index, Transform2D(direction * length, normal * width, (from + to) * 0.5))
		multimesh.set_instance_color(route_index, [Color("e3a548"), Color("42cfdf"), Color("a879e8")][depth])
		multimesh.set_instance_custom_data(route_index, Color(float(depth) / 2.0, minf(255.0, maxf(2.0, length / 6.0)) / 255.0, float(_routes[index + 7]) / 255.0, 1.0))
	_route_instances.multimesh = multimesh
	_route_instances.visible = mode == Mode.UNDERGROUND_LOGISTICS

func _build_subsurface_route_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
varying vec4 route_state;
void vertex() { route_state = INSTANCE_CUSTOM; }
void fragment() {
	float depth = floor(route_state.r * 2.0 + 0.5);
	float repeats = max(2.0, floor(route_state.g * 255.0 + 0.5));
	float edge = step(UV.x, 0.025) + step(0.975, UV.x);
	float alpha = 0.0;
	if (depth < 0.5) {
		alpha = step(abs(UV.y - 0.5), 0.20);
	} else if (depth < 1.5) {
		float dash = step(0.42, fract(UV.x * repeats));
		alpha = step(abs(UV.y - 0.5), 0.18) * dash;
	} else {
		float dots = step(0.66, fract(UV.x * repeats * 1.35));
		float triple = max(step(abs(UV.y - 0.20), 0.075), max(step(abs(UV.y - 0.50), 0.075), step(abs(UV.y - 0.80), 0.075)));
		alpha = triple * dots;
	}
	alpha = max(alpha, clamp(edge, 0.0, 1.0) * step(abs(UV.y - 0.5), 0.46));
	COLOR = vec4(COLOR.rgb, COLOR.a * alpha);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _build_temperature_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 packed = texture(TEXTURE, UV).rg;
	float temperature = floor(packed.r * 255.0 + 0.5) + floor(packed.g * 255.0 + 0.5) * 256.0;
	float heat = clamp((temperature - 1092.0) / 7200.0, 0.0, 1.0);
	vec3 cold = vec3(0.08, 0.25, 0.92);
	vec3 warm = vec3(1.00, 0.72, 0.08);
	vec3 hot = vec3(1.00, 0.08, 0.02);
	vec3 color = mix(mix(cold, warm, min(heat * 2.0, 1.0)), hot, max(heat * 2.0 - 1.0, 0.0));
	COLOR = vec4(color, 0.12 + heat * 0.48);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _build_power_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
varying vec4 power_state;
void vertex() {
	power_state = INSTANCE_CUSTOM;
	float kind = floor(power_state.r * 3.0 + 0.5);
	if (kind > 2.5) {
		float angle = TIME * (0.5 + power_state.b * 14.0);
		VERTEX = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX;
	}
}
void fragment() {
	float kind = floor(power_state.r * 3.0 + 0.5);
	float pattern = power_state.g;
	vec3 amber = mix(vec3(0.95, 0.58, 0.12), vec3(0.35, 0.88, 0.76), pattern);
	float alpha = 1.0;
	if (kind > 1.5 && kind < 2.5) {
		float dash = step(0.34, fract(UV.x * (8.0 + pattern * 8.0)));
		alpha = step(abs(UV.y - 0.5), 0.34) * dash;
	} else if (kind > 2.5) {
		vec2 p = UV - vec2(0.5);
		float ring = 1.0 - smoothstep(0.06, 0.13, abs(length(p) - 0.31));
		float spoke = step(0.78, cos(atan(p.y, p.x) * 4.0)) * step(length(p), 0.34);
		alpha = max(ring, spoke);
	} else {
		vec2 p = abs(UV - vec2(0.5));
		alpha = step(p.x + p.y, 0.48);
	}
	COLOR = vec4(amber, COLOR.a * alpha * 0.88);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
