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

static func build(ui_scale := 1.0) -> Theme:
	var scale := clampf(ui_scale, 0.75, 2.0)
	var result := Theme.new()
	result.set_type_variation("HudPanel", "PanelContainer")
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
	_set_label(result, "CaptionLabel", 11, COLOR_TEXT_DISABLED, scale)
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
	if reduced_motion:
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	control.position.y += 6.0
	var tween := control.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, MOTION_EMPHASIS if emphasis else MOTION_STANDARD)
	tween.tween_property(control, "position:y", control.position.y - 6.0, MOTION_EMPHASIS if emphasis else MOTION_STANDARD)

static func _set_label(theme: Theme, variation: String, size: int, color: Color, scale: float) -> void:
	theme.set_font_size("font_size", variation, roundi(size * scale))
	theme.set_color("font_color", variation, color)

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
