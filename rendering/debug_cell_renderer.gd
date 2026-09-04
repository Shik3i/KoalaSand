class_name DebugCellRenderer
extends Node2D

@export_range(1.0, 8.0, 1.0) var cell_pixel_size: float = 2.0

var _world: Variant
var _chunk_sprites: Dictionary = {}
var last_update_ms: float = 0.0
var last_chunks_rendered: int = 0
var last_dirty_pixels: int = 0
var last_upload_pixels: int = 0
var last_water_upload_ms: float = 0.0
var last_water_upload_bytes: int = 0
var _material_page_sprite: Sprite2D
var _material_page_area := Rect2i()
var _water_sprite: Sprite2D
var _water_revision: int = -1
var _water_page_area := Rect2i()


func initialize(world: Variant) -> void:
	_world = world
	if _world is CellWorld:
		render_dirty_chunks()
	queue_redraw()


func clear_chunks() -> void:
	for sprite: Sprite2D in _chunk_sprites.values():
		sprite.queue_free()
	_chunk_sprites.clear()
	if _material_page_sprite != null:
		_material_page_sprite.queue_free()
		_material_page_sprite = null
	_material_page_area = Rect2i()
	if _water_sprite != null:
		_water_sprite.queue_free()
		_water_sprite = null
	_water_revision = -1


func render_dirty_chunks(chunk_area: Rect2i = Rect2i()) -> void:
	if _world == null:
		return
	var start_usec := Time.get_ticks_usec()
	last_chunks_rendered = 0
	last_dirty_pixels = 0
	last_upload_pixels = 0
	if not _world is CellWorld:
		_remove_evicted_native_chunks()
		if _world.has_method("consume_dirty_render_page") and chunk_area.size.x > 0 and chunk_area.size.y > 0:
			_render_native_material_page(chunk_area)
		else:
			_render_native_chunks(_world.consume_dirty_render_chunks())
		_render_native_water_page(chunk_area)
		# Two counters, not the whole diagnostic picture: get_statistics() walks every resident
		# chunk and merges five dictionaries that walk it again, and this runs every frame.
		var counters: Dictionary = _world.get_frame_counters()
		last_dirty_pixels = counters.get("dirty_render_pixels", 0)
		last_upload_pixels = counters.get("render_upload_pixels", 0)
		last_update_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0
		return
	for chunk in _world.get_dirty_chunks():
		_render_chunk(chunk)
		chunk.mark_clean()
		last_chunks_rendered += 1
	last_update_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0


func _render_native_material_page(page_area: Rect2i) -> void:
	var force := _material_page_sprite == null or page_area != _material_page_area
	var page: Dictionary = _world.consume_dirty_render_page(page_area, force)
	if page.is_empty():
		return
	for sprite: Sprite2D in _chunk_sprites.values():
		sprite.queue_free()
	_chunk_sprites.clear()
	var width := int(page.width)
	var height := int(page.height)
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, page.pixels)
	if _material_page_sprite == null:
		_material_page_sprite = Sprite2D.new()
		_material_page_sprite.name = "VisibleMaterialPage"
		_material_page_sprite.centered = false
		_material_page_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_material_page_sprite.z_index = 0
		add_child(_material_page_sprite)
	var texture := _material_page_sprite.texture as ImageTexture
	if texture == null or texture.get_width() != width or texture.get_height() != height:
		_material_page_sprite.texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_material_page_sprite.position = Vector2(page.cell_position) * cell_pixel_size
	_material_page_sprite.scale = Vector2.ONE * cell_pixel_size
	_material_page_area = page_area
	last_chunks_rendered = 1


func _render_native_water_page(requested_area: Rect2i = Rect2i()) -> void:
	if not _world.has_method("get_fluid_render_page"):
		return
	var stats: Dictionary = _world.get_fluid_statistics()
	var revision := int(stats.get("fluid_render_revision", 0))
	if int(stats.get("fluid_mass_total", 0)) == 0:
		if _water_sprite != null:
			_water_sprite.visible = false
		_water_revision = revision
		last_water_upload_ms = 0.0
		last_water_upload_bytes = 0
		return
	var page_area := requested_area
	if page_area.size.x <= 0 or page_area.size.y <= 0:
		var first := true
		var minimum := Vector2i.ZERO
		var maximum := Vector2i.ZERO
		for coordinate_value: Variant in _chunk_sprites.keys():
			var coordinate := coordinate_value as Vector2i
			if first:
				minimum = coordinate
				maximum = coordinate
				first = false
			else:
				minimum = Vector2i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y))
				maximum = Vector2i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y))
		if first:
			return
		page_area = Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	if revision == _water_revision and page_area == _water_page_area:
		last_water_upload_ms = 0.0
		last_water_upload_bytes = 0
		return
	var started := Time.get_ticks_usec()
	var page: Dictionary = _world.get_fluid_render_page(page_area)
	if page.is_empty():
		return
	var width := int(page["width"])
	var height := int(page["height"])
	var image := Image.create_from_data(width, height, false, Image.FORMAT_R8, page["pixels"])
	if _water_sprite == null:
		_water_sprite = Sprite2D.new()
		_water_sprite.name = "DynamicWaterPage"
		_water_sprite.centered = false
		_water_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_water_sprite.z_index = 1
		_water_sprite.material = _create_water_material()
		add_child(_water_sprite)
	_water_sprite.visible = true
	var texture := _water_sprite.texture as ImageTexture
	if texture == null or texture.get_width() != width or texture.get_height() != height:
		_water_sprite.texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_water_sprite.position = Vector2(page["cell_position"]) * cell_pixel_size
	_water_sprite.scale = Vector2.ONE * cell_pixel_size
	_water_revision = revision
	_water_page_area = page_area
	last_water_upload_bytes = int(page["bytes"])
	last_water_upload_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _create_water_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 deep_color : source_color = vec4(0.025, 0.26, 0.39, 0.96);
uniform vec4 body_color : source_color = vec4(0.035, 0.58, 0.72, 0.94);
uniform vec4 surface_color : source_color = vec4(0.38, 0.86, 0.91, 0.98);
void fragment() {
	ivec2 size_i = textureSize(TEXTURE, 0);
	vec2 size = vec2(size_i);
	float mass = texture(TEXTURE, UV).r;
	vec2 inside_cell = fract(UV * size);
	if (mass <= 0.001 || inside_cell.y < 1.0 - mass) {
		COLOR = vec4(0.0);
	} else {
		float above = texture(TEXTURE, UV - vec2(0.0, 1.0 / size.y)).r;
		float below = texture(TEXTURE, UV + vec2(0.0, 1.0 / size.y)).r;
		float exposed = 1.0 - step(0.002, above);
		float surface_y = 1.0 - mass;
		float surface_line = 1.0 - smoothstep(0.0, 0.16, abs(inside_cell.y - surface_y));
		float depth = smoothstep(0.0, 1.0, below);
		vec4 color = mix(body_color, deep_color, depth * 0.42);
		color = mix(color, surface_color, exposed * surface_line * 0.82);
		COLOR = color;
	}
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _remove_evicted_native_chunks() -> void:
	if not _world.has_method("consume_evicted_chunks"):
		return
	for coordinate: Vector2i in _world.consume_evicted_chunks():
		var sprite := _chunk_sprites.get(coordinate) as Sprite2D
		if sprite != null:
			sprite.queue_free()
		_chunk_sprites.erase(coordinate)


func _render_native_chunks(updates: Array) -> void:
	for update: Dictionary in updates:
		var coordinate: Vector2i = update["coordinate"]
		var pixels: PackedByteArray = update["pixels"]
		var image := Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, pixels)
		var sprite := _chunk_sprites.get(coordinate) as Sprite2D
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position = Vector2(coordinate * 64) * cell_pixel_size
			sprite.scale = Vector2.ONE * cell_pixel_size
			add_child(sprite)
			_chunk_sprites[coordinate] = sprite
		var texture := sprite.texture as ImageTexture
		if texture == null:
			sprite.texture = ImageTexture.create_from_image(image)
		else:
			texture.update(image)
		last_chunks_rendered += 1


func _render_chunk(chunk: SimChunk) -> void:
	var image := MaterialVisualResolver.build_chunk_image(_world, chunk)

	var sprite := _chunk_sprites.get(chunk.coordinate) as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(chunk.coordinate * WorldConfig.CHUNK_SIZE) * cell_pixel_size
		sprite.scale = Vector2.ONE * cell_pixel_size
		add_child(sprite)
		_chunk_sprites[chunk.coordinate] = sprite
	var texture := sprite.texture as ImageTexture
	if texture == null:
		sprite.texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
