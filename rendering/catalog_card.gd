class_name CatalogCard
extends Button

signal tool_activated(tool: Dictionary)

var tool: Dictionary = {}
var _icon: ToolSlot
var _name_label: Label
var _category_label: Label
var _badge_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(236, 80)
	text = ""
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	_build_content()
	pressed.connect(_activate)


func configure(value: Dictionary, is_new := false, selected := false) -> void:
	tool = value.duplicate(true)
	if _icon == null:
		_build_content()
	_icon.configure(tool, 0, 0, false, true)
	_name_label.text = str(tool.get("name", "Unnamed component"))
	_category_label.text = "Research required" if bool(tool.get("locked", false)) else str(tool.get("display_category", tool.get("category", "Component")))
	_badge_label.text = "NEW" if is_new else ""
	_badge_label.visible = is_new
	toggle_mode = true
	button_pressed = selected
	disabled = bool(tool.get("locked", false))
	var help := Dictionary(tool.get("help", {"title":_name_label.text, "description":"Select this Component for physical world interaction."})).duplicate(true)
	if disabled and str(help.get("disabled_reason", "")).is_empty():
		help.disabled_reason = "Requires Research before it can be selected."
	HelpCatalog.attach(self, help)
	set_meta("layout_role", "catalog_card")
	set_meta("accessibility_description", "%s · %s" % [_name_label.text, _category_label.text])


func set_selected(value: bool) -> void:
	button_pressed = value


func apply_ui_scale(ui_scale: float) -> void:
	var scale := clampf(ui_scale, 0.75, 2.0)
	custom_minimum_size = Vector2(236.0 * scale, 80.0 * scale)
	_icon.custom_minimum_size = Vector2(54.0 * scale, 54.0 * scale)


func layout_rects() -> Dictionary:
	return {
		"card": get_global_rect(),
		"icon": _icon.get_global_rect(),
		"name": _name_label.get_global_rect(),
		"category": _category_label.get_global_rect(),
		"badge": _badge_label.get_global_rect() if _badge_label.visible else Rect2(),
	}


func _build_content() -> void:
	if _icon != null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	_icon = ToolSlot.new()
	_icon.custom_minimum_size = Vector2(54, 54)
	_icon.flat = true
	_icon.focus_mode = Control.FOCUS_NONE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(name_row)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_name_label)
	_badge_label = Label.new()
	_badge_label.theme_type_variation = "WarningLabel"
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_badge_label)
	_category_label = Label.new()
	_category_label.theme_type_variation = "CaptionLabel"
	_category_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_category_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_category_label)


func _activate() -> void:
	if not tool.is_empty() and not disabled:
		tool_activated.emit(tool)


func _get_drag_data(_position: Vector2) -> Variant:
	if tool.is_empty() or disabled:
		return null
	var preview := Label.new()
	preview.text = str(tool.get("name", "Component"))
	preview.add_theme_color_override("font_color", KoalaSandTheme.COLOR_ACCENT_BRIGHT)
	set_drag_preview(preview)
	return {"tool":tool.duplicate(true), "source_page":0, "source_index":0, "catalog":true}
