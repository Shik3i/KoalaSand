class_name VisibilityRenderer
extends Node2D

var world: Variant
var owner_id := 1
var cell_pixel_size := 2.0
var enabled := false
var last_update_ms := 0.0
var last_upload_bytes := 0
var _sprite: Sprite2D
var _page_area := Rect2i()
var _revision := -1


func initialize(next_world: Variant, next_owner_id := 1, pixels_per_cell := 2.0) -> void:
	world = next_world
	owner_id = next_owner_id
	cell_pixel_size = pixels_per_cell
	_revision = -1
	queue_redraw()


func set_discovery_enabled(value: bool) -> void:
	enabled = value
	visible = value
	_revision = -1


func sync_visible(chunk_area: Rect2i, force := false) -> void:
	if not enabled or world == null or chunk_area.size.x <= 0 or chunk_area.size.y <= 0:
		return
	var stats: Dictionary = world.get_visibility_statistics(owner_id)
	var revision := int(stats.get("revision", 0))
	if not force and revision == _revision and chunk_area == _page_area:
		last_update_ms = 0.0
		last_upload_bytes = 0
		return
	var started := Time.get_ticks_usec()
	var page: Dictionary = world.get_visibility_render_page(owner_id, chunk_area)
	if page.is_empty():
		return
	var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "DiscoveryFogPage"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.z_index = 30
		add_child(_sprite)
	var texture := _sprite.texture as ImageTexture
	if texture == null or texture.get_width() != int(page.width) or texture.get_height() != int(page.height):
		_sprite.texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	_sprite.position = Vector2(page.cell_position) * cell_pixel_size
	_sprite.scale = Vector2.ONE * cell_pixel_size
	_page_area = chunk_area
	_revision = revision
	last_upload_bytes = int(page.bytes)
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0
