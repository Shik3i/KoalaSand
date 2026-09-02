class_name KoalaSandTheme
extends RefCounted

# Canonical Phase 13.6 presentation tokens. Player-facing UI must source its
# palette, sizing and motion from here instead of inventing local constants.
const COLOR_WORLD_INK := Color("081015")
const COLOR_PANEL := Color("101a20f2")
const COLOR_PANEL_ELEVATED := Color("16242bf7")
const COLOR_PANEL_MODAL := Color("0b1217fc")
const COLOR_BORDER := Color("496069a6")
const COLOR_SEPARATOR := Color("2c424a9c")
const COLOR_TEXT := Color("e8e5dc")
const COLOR_TEXT_SECONDARY := Color("a5b5b5")
const COLOR_TEXT_DISABLED := Color("66777b")
const COLOR_ACCENT := Color("d9a441")
const COLOR_ACCENT_BRIGHT := Color("f2c264")
const COLOR_WARNING := Color("e8a64a")
const COLOR_DANGER := Color("e4644f")
const COLOR_SUCCESS := Color("65c39f")
const COLOR_INFO := Color("68b9c7")
const COLOR_SELECTION := Color("f0bd5c")
const COLOR_STATE_UNKNOWN := Color("34454c")
const COLOR_STATE_STALE := Color("6a756d")
const COLOR_STATE_LIVE := Color("6fc7ad")

const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const RADIUS_SMALL := 4
const RADIUS_MEDIUM := 7
const RADIUS_LARGE := 10
const ICON_SMALL := 18
const ICON_MEDIUM := 28
const ICON_LARGE := 42
const MOTION_FAST := 0.08
const MOTION_STANDARD := 0.12
const MOTION_EMPHASIS := 0.18

static var reduced_motion := false

static func build(ui_scale := 1.0) -> Theme:
	var scale := clampf(ui_scale, 0.75, 2.0)
	var result := Theme.new()
	result.set_type_variation("HudPanel", "PanelContainer")
	result.set_type_variation("DockCanvas", "PanelContainer")
	result.set_type_variation("ElevatedPanel", "PanelContainer")
	result.set_type_variation("ModalPanel", "PanelContainer")
	result.set_type_variation("PrimaryButton", "Button")
	result.set_type_variation("DangerButton", "Button")
	result.set_type_variation("QuietButton", "Button")
	result.set_type_variation("DisplayLabel", "Label")
	result.set_type_variation("ScreenTitleLabel", "Label")
	result.set_type_variation("SectionTitleLabel", "Label")
	result.set_type_variation("SecondaryLabel", "Label")
	result.set_type_variation("CaptionLabel", "Label")
	result.set_type_variation("NumericLabel", "Label")
	result.set_type_variation("SuccessLabel", "Label")
	result.set_type_variation("WarningLabel", "Label")
	result.set_type_variation("DangerLabel", "Label")

	result.set_stylebox("panel", "PanelContainer", _box(COLOR_PANEL, COLOR_BORDER, 1, RADIUS_MEDIUM, 12.0 * scale, 7))
	result.set_stylebox("panel", "HudPanel", _box(Color("0d171ddf"), Color("40545c7a"), 1, RADIUS_MEDIUM, 10.0 * scale, 5))
	result.set_stylebox("panel", "DockCanvas", StyleBoxEmpty.new())
	result.set_stylebox("panel", "ElevatedPanel", _box(COLOR_PANEL_ELEVATED, Color("62747bba"), 1, RADIUS_LARGE, 16.0 * scale, 9))
	var modal := _box(COLOR_PANEL_MODAL, Color("b98b3ed6"), 1, RADIUS_LARGE, 20.0 * scale, 12)
	result.set_stylebox("panel", "ModalPanel", modal)
	result.set_stylebox("panel", "PopupPanel", modal)
	result.set_stylebox("panel", "TooltipPanel", result.get_stylebox("panel", "ElevatedPanel"))

	_install_button(result, "Button", Color("172229f5"), COLOR_BORDER, COLOR_PANEL_ELEVATED, COLOR_ACCENT, Color("46351df7"), COLOR_ACCENT_BRIGHT, scale)
	_install_button(result, "PrimaryButton", Color("6e4d20fa"), Color("d9a441e8"), Color("855d25ff"), COLOR_ACCENT_BRIGHT, Color("9b6d2aff"), Color("ffe0a0"), scale)
	_install_button(result, "DangerButton", Color("3b2222f5"), Color("8d4b45d0"), Color("512827ff"), COLOR_DANGER, Color("682d29ff"), Color("ffaca0"), scale)
	_install_button(result, "QuietButton", Color("10191fc8"), Color("34474e78"), Color("1b2a31e8"), COLOR_INFO, Color("24343be8"), Color("a8dce4"), scale)
	for control in ["OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			result.set_stylebox(state, control, result.get_stylebox(state, "Button"))
	_install_check(result, scale)
	result.set_stylebox("normal", "LineEdit", _box(Color("0c151bf2"), COLOR_BORDER, 1, RADIUS_SMALL, 10.0 * scale, 0))
	result.set_stylebox("focus", "LineEdit", _box(Color("101d24fa"), COLOR_ACCENT, 1, RADIUS_SMALL, 10.0 * scale, 2))
	result.set_stylebox("read_only", "LineEdit", _box(Color("10171bd9"), COLOR_SEPARATOR, 1, RADIUS_SMALL, 10.0 * scale, 0))

	result.set_color("font_color", "Label", COLOR_TEXT)
	result.set_color("font_color", "Button", COLOR_TEXT)
	result.set_color("font_hover_color", "Button", Color("fff0c8"))
	result.set_color("font_pressed_color", "Button", Color("fff4db"))
	result.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	result.set_color("font_color", "LineEdit", COLOR_TEXT)
	result.set_color("font_placeholder_color", "LineEdit", COLOR_TEXT_DISABLED)
	result.set_color("caret_color", "LineEdit", COLOR_ACCENT_BRIGHT)
	result.set_color("selection_color", "LineEdit", Color("725421b8"))
	result.set_font_size("font_size", "Label", roundi(14 * scale))
	result.set_font_size("font_size", "Button", roundi(13 * scale))
	result.set_font_size("font_size", "LineEdit", roundi(14 * scale))
	_set_label(result, "DisplayLabel", 38, COLOR_ACCENT_BRIGHT, scale)
	_set_label(result, "ScreenTitleLabel", 25, COLOR_TEXT, scale)
	_set_label(result, "SectionTitleLabel", 17, COLOR_ACCENT_BRIGHT, scale)
	_set_label(result, "SecondaryLabel", 13, COLOR_TEXT_SECONDARY, scale)
	_set_label(result, "CaptionLabel", 12, COLOR_TEXT_DISABLED, scale)
	_set_label(result, "NumericLabel", 14, COLOR_TEXT, scale)
	_set_label(result, "SuccessLabel", 13, COLOR_SUCCESS, scale)
	_set_label(result, "WarningLabel", 13, COLOR_WARNING, scale)
	_set_label(result, "DangerLabel", 13, COLOR_DANGER, scale)
	result.set_constant("separation", "HBoxContainer", roundi(SPACE_2 * scale))
	result.set_constant("separation", "VBoxContainer", roundi(SPACE_2 * scale))
	result.set_constant("h_separation", "GridContainer", roundi(SPACE_2 * scale))
	result.set_constant("v_separation", "GridContainer", roundi(SPACE_2 * scale))
	return result

static func animate_in(control: Control, reduced_motion := false, emphasis := false) -> void:
	if reduced_motion or KoalaSandTheme.reduced_motion:
		control.modulate.a = 1.0
		return
	control.show()
	control.modulate.a = 0.0
	var tween := control.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, MOTION_EMPHASIS if emphasis else MOTION_STANDARD)

static func show_panel(control: Control, emphasis := false) -> void:
	control.show()
	animate_in(control, false, emphasis)

static func hide_panel(control: Control, finished := Callable()) -> void:
	if KoalaSandTheme.reduced_motion:
		control.hide()
		if finished.is_valid():
			finished.call()
		return
	var tween := control.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", 0.0, MOTION_FAST)
	tween.tween_property(control, "scale", Vector2(0.985, 0.985), MOTION_FAST)
	tween.chain().tween_callback(func() -> void:
		control.hide()
		control.modulate.a = 1.0
		control.scale = Vector2.ONE
		if finished.is_valid(): finished.call()
	)

static func apply_preferences(root: Node, ui_scale: float, motion_reduced: bool) -> void:
	KoalaSandTheme.reduced_motion = motion_reduced
	var next_theme := build(ui_scale)
	_apply_theme_recursive(root, next_theme)

static func _apply_theme_recursive(node: Node, next_theme: Theme) -> void:
	if node is Control and (node == node.get_tree().current_scene or (node as Control).theme != null):
		(node as Control).theme = next_theme
	if node.has_method("apply_ui_scale"):
		node.call("apply_ui_scale", float(next_theme.get_font_size("font_size", "Label")) / 14.0)
	for child in node.get_children():
		_apply_theme_recursive(child, next_theme)

static func _set_label(theme: Theme, variation: String, size: int, color: Color, scale: float) -> void:
	theme.set_font_size("font_size", variation, roundi(size * scale))
	theme.set_color("font_color", variation, color)

# CheckBox and CheckButton had no authored styling, so they inherited the Button slab and
# Godot's stock icons: an unchecked box rendered with no visible box at all, which is the
# worst possible state for a setting a player has to read.
static func _install_check(theme: Theme, scale: float) -> void:
	for control in ["CheckBox", "CheckButton"]:
		for state in ["normal", "pressed", "disabled"]:
			theme.set_stylebox(state, control, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, RADIUS_SMALL, 6.0 * scale, 0))
		theme.set_stylebox("hover", control, _box(Color("16232ac0"), Color("40545c8a"), 1, RADIUS_SMALL, 6.0 * scale, 0))
		theme.set_stylebox("hover_pressed", control, theme.get_stylebox("hover", control))
		theme.set_stylebox("focus", control, _box(Color("16232ac0"), COLOR_SELECTION, 2, RADIUS_SMALL, 6.0 * scale, 0))
		theme.set_color("font_color", control, COLOR_TEXT)
		theme.set_color("font_hover_color", control, Color("fff0c8"))
		theme.set_color("font_pressed_color", control, COLOR_TEXT)
		theme.set_color("font_disabled_color", control, COLOR_TEXT_DISABLED)
		theme.set_font_size("font_size", control, roundi(13 * scale))
		theme.set_constant("h_separation", control, roundi(9 * scale))
		var box := roundi(16 * scale)
		theme.set_icon("unchecked", control, _check_icon(box, false, false))
		theme.set_icon("checked", control, _check_icon(box, true, false))
		theme.set_icon("unchecked_disabled", control, _check_icon(box, false, true))
		theme.set_icon("checked_disabled", control, _check_icon(box, true, true))


# The mark is drawn, not just tinted: state must survive a monochrome or colour-blind read.
static func _check_icon(size: int, checked: bool, disabled: bool) -> ImageTexture:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var border := COLOR_TEXT_DISABLED if disabled else (COLOR_ACCENT if checked else COLOR_TEXT_SECONDARY)
	var fill := Color("1b2a31e0") if checked and not disabled else Color("0d151ac0")
	for y in size:
		for x in size:
			var edge := x <= 1 or y <= 1 or x >= size - 2 or y >= size - 2
			image.set_pixel(x, y, border if edge else fill)
	if checked:
		var mark := COLOR_TEXT_DISABLED if disabled else COLOR_ACCENT_BRIGHT
		var low := roundi(size * 0.30)
		var mid := roundi(size * 0.52)
		var high := roundi(size * 0.72)
		for step in range(low, mid + 1):
			var y := mid + (step - low)
			for thickness in 2:
				if step + thickness < size and y < size: image.set_pixel(step + thickness, y, mark)
		for step in range(mid, high + 1):
			var y := mid + (mid - low) - (step - mid)
			for thickness in 2:
				if step + thickness < size and y >= 0 and y < size: image.set_pixel(step + thickness, y, mark)
	return ImageTexture.create_from_image(image)


static func _install_button(theme: Theme, control: String, base: Color, border: Color, hover_base: Color, hover_border: Color, pressed_base: Color, pressed_border: Color, scale: float) -> void:
	theme.set_stylebox("normal", control, _box(base, border, 1, RADIUS_SMALL, 9.0 * scale, 0))
	theme.set_stylebox("hover", control, _box(hover_base, hover_border, 1, RADIUS_SMALL, 9.0 * scale, 2))
	theme.set_stylebox("pressed", control, _box(pressed_base, pressed_border, 1, RADIUS_SMALL, 9.0 * scale, 1))
	theme.set_stylebox("focus", control, _box(hover_base, COLOR_SELECTION, 2, RADIUS_SMALL, 9.0 * scale, 2))
	theme.set_stylebox("disabled", control, _box(Color("10171bd9"), COLOR_SEPARATOR, 1, RADIUS_SMALL, 9.0 * scale, 0))

static func _box(background: Color, border: Color, width: int, radius: int, margin: float, shadow_size: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin * 0.7
	box.content_margin_bottom = margin * 0.7
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2(0, 3)
	return box
