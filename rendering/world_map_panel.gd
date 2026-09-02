class_name WorldMapPanel
extends PanelContainer

signal center_requested
signal closed

var world: Variant
var preset_id := GameModeCapabilities.Preset.FACTORY
var owner_id := KoalaCharacterController.VISIBILITY_OWNER_ID
var _map: TextureRect
var _markers: WorldMapMarkers
var _title: Label
var _legend: Label


func _ready() -> void:
	theme = KoalaSandTheme.build()
	theme_type_variation = "ModalPanel"
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -430.0
	offset_top = -300.0
	offset_right = 430.0
	offset_bottom = 300.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.text = "World map"
	_title.theme_type_variation = "ScreenTitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var center_button := Button.new()
	center_button.theme_type_variation = "QuietButton"
	center_button.text = "Center view"
	center_button.pressed.connect(func() -> void: center_requested.emit())
	header.add_child(center_button)
	var close_button := Button.new()
	close_button.theme_type_variation = "QuietButton"
	close_button.text = "Close  [M / Esc]"
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# The map fills the panel: a fixed-height texture left more than half the modal empty.
	var map_frame := Control.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.clip_contents = true
	column.add_child(map_frame)
	_map = TextureRect.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_frame.add_child(_map)
	_markers = WorldMapMarkers.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(_markers)
	_legend = Label.new()
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend.theme_type_variation = "CaptionLabel"
	column.add_child(_legend)

func open() -> void:
	KoalaSandTheme.show_panel(self, true)

func close() -> void:
	KoalaSandTheme.hide_panel(self, func() -> void: closed.emit())


func initialize(next_world: Variant, next_preset: int) -> void:
	world = next_world
	preset_id = clampi(next_preset, 0, 2)
	refresh(Rect2i(-4, -3, 9, 7))


func refresh(chunk_area: Rect2i) -> void:
	if world == null or _map == null:
		return
	if preset_id == GameModeCapabilities.Preset.CHARACTER:
		var page: Dictionary = world.get_visibility_render_page(owner_id, chunk_area)
		if page.is_empty():
			return
		var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
		_map.texture = ImageTexture.create_from_image(image)
		_title.text = "Discovery map"
		if _markers != null: _markers.clear_bounds()
		_legend.text = "● Live     ◇ Discovered / stale     ▦ Unknown"
	else:
		var page: Dictionary = world.get_macro_preview(384, 216)
		var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
		_map.texture = ImageTexture.create_from_image(image)
		_title.text = "Factory overview" if preset_id == GameModeCapabilities.Preset.FACTORY else "Creative overview"
		if _markers != null:
			_markers.configure(page, Vector2i(int(page.width), int(page.height)), chunk_area)
		_legend.text = "◇ Camera region     ◎ World centre" if _markers != null and _markers.has_bounds \
			else "Surface overview · underground is not shown"


# Draws the camera region and world centre on top of the overview. The legend used to name
# markers that nothing rendered.
class WorldMapMarkers extends Control:
	var has_bounds := false
	var _texture_size := Vector2i.ZERO
	var _world_min_x := 0
	var _world_max_x := 0
	var _camera: Rect2i = Rect2i()

	func configure(page: Dictionary, texture_size: Vector2i, chunk_area: Rect2i) -> void:
		_texture_size = texture_size
		_camera = chunk_area
		has_bounds = page.has("world_min_x") and page.has("world_max_x")
		if has_bounds:
			_world_min_x = int(page.world_min_x)
			_world_max_x = int(page.world_max_x)
		queue_redraw()

	func clear_bounds() -> void:
		has_bounds = false
		queue_redraw()

	func _draw() -> void:
		if not has_bounds or _texture_size.x <= 0 or _world_max_x <= _world_min_x:
			return
		# The texture is aspect-fitted and centred inside this control.
		var scale := minf(size.x / float(_texture_size.x), size.y / float(_texture_size.y))
		var drawn := Vector2(_texture_size) * scale
		var origin := (size - drawn) * 0.5
		var span := float(_world_max_x - _world_min_x)
		var left := origin.x + drawn.x * clampf((_camera.position.x * 64 - _world_min_x) / span, 0.0, 1.0)
		var right := origin.x + drawn.x * clampf(((_camera.position.x + _camera.size.x) * 64 - _world_min_x) / span, 0.0, 1.0)
		draw_rect(Rect2(Vector2(left, origin.y), Vector2(maxf(right - left, 3.0), drawn.y)),
			KoalaSandTheme.COLOR_ACCENT, false, 2.0)
		var centre := origin.x + drawn.x * clampf((0.0 - _world_min_x) / span, 0.0, 1.0)
		draw_line(Vector2(centre, origin.y), Vector2(centre, origin.y + drawn.y), Color(0.96, 0.78, 0.34, 0.55), 1.0)
		draw_circle(Vector2(centre, origin.y + drawn.y * 0.5), 4.0, Color(0.96, 0.78, 0.34, 0.9))
		draw_circle(Vector2(centre, origin.y + drawn.y * 0.5), 2.0, Color(0.10, 0.13, 0.16, 1.0))
