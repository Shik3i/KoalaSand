class_name WorldMapPanel
extends PanelContainer

signal center_requested

var world: Variant
var preset_id := GameModeCapabilities.Preset.FACTORY
var owner_id := KoalaCharacterController.VISIBILITY_OWNER_ID
var _map: TextureRect
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
	_map = TextureRect.new()
	_map.custom_minimum_size = Vector2(820, 490)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(_map)
	_legend = Label.new()
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend.theme_type_variation = "CaptionLabel"
	column.add_child(_legend)
	KoalaSandTheme.animate_in(self, false, true)


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
		_legend.text = "● Live     ◇ Discovered / stale     ▦ Unknown"
	else:
		var page: Dictionary = world.get_macro_preview(256, 140)
		var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
		_map.texture = ImageTexture.create_from_image(image)
		_title.text = "Factory overview" if preset_id == GameModeCapabilities.Preset.FACTORY else "Creative overview"
		_legend.text = "● Current world     ◇ Camera region     ◎ Center"
