class_name ToolSlot
extends Button

signal slot_drop(target_page: int, target_index: int, data: Dictionary)
signal slot_clear(page: int, index: int)

var page := 0
var index := 0
var tool: Dictionary = {}
var catalog_entry := false
var icon_only := false

func configure(value: Dictionary, slot_page: int = 0, slot_index: int = 0, from_catalog: bool = false, only_icon: bool = false) -> void:
	tool = value.duplicate(true)
	page = slot_page
	index = slot_index
	catalog_entry = from_catalog
	icon_only = only_icon
	text = "" if tool.is_empty() or not catalog_entry else str(tool.get("name", "?"))
	remove_meta("ux_tooltip_spec")
	tooltip_text = ""
	if not tool.is_empty():
		var help := Dictionary(tool.get("help", {"title":str(tool.get("name", "Tool")), "description":"Select this player tool for physical world interaction."})).duplicate(true)
		if bool(tool.get("locked", false)) and str(help.get("disabled_reason", "")).is_empty():
			help.disabled_reason = "Requires Research before it can be selected."
		HelpCatalog.attach(self, help)
	disabled = bool(tool.get("locked", false))
	queue_redraw()

func _get_drag_data(_position: Vector2) -> Variant:
	if tool.is_empty() or bool(tool.get("locked", false)):
		return null
	var preview := Label.new()
	preview.text = str(tool.get("name", "Tool"))
	preview.add_theme_color_override("font_color", Color("f2bb55"))
	set_drag_preview(preview)
	return {"tool": tool.duplicate(true), "source_page": page, "source_index": index, "catalog": catalog_entry}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not catalog_entry and data is Dictionary and data.has("tool")

func _drop_data(_position: Vector2, data: Variant) -> void:
	slot_drop.emit(page, index, data)

func _gui_input(event: InputEvent) -> void:
	if not catalog_entry and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		slot_clear.emit(page, index)
		accept_event()

func _draw() -> void:
	if tool.is_empty():
		return
	var locked := bool(tool.get("locked", false))
	var color := KoalaSandTheme.COLOR_ACCENT_BRIGHT if not locked else KoalaSandTheme.COLOR_TEXT_DISABLED
	var secondary := KoalaSandTheme.COLOR_INFO if not locked else Color("46575c")
	var center := Vector2(size.x * 0.5, size.y * 0.5 if icon_only else size.y * 0.46)
	var key := _resolved_icon()
	match key:
		"pipe":
			draw_arc(center, 10, 0, TAU, 24, color, 3)
			draw_line(center + Vector2(-15, 0), center + Vector2(-10, 0), Color("67c7d8"), 3)
			draw_line(center + Vector2(10, 0), center + Vector2(15, 0), Color("67c7d8"), 3)
		"pipe_junction":
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]: draw_line(center, center + direction * 14.0, Color("67c7d8"), 4)
			draw_circle(center, 5, color, false, 2)
		"intake":
			draw_arc(center, 11, 0, TAU, 24, color, 3)
			draw_polyline(PackedVector2Array([center + Vector2(-16, -5), center + Vector2(-10, 0), center + Vector2(-16, 5)]), Color("67c7d8"), 3)
		"outlet":
			draw_arc(center, 11, 0, TAU, 24, color, 3)
			draw_polyline(PackedVector2Array([center + Vector2(11, -5), center + Vector2(17, 0), center + Vector2(11, 5)]), Color("67c7d8"), 3)
		"conveyor":
			draw_line(center + Vector2(-13, 7), center + Vector2(13, 7), color, 3)
			for x in [-10, -3, 4, 11]: draw_circle(center + Vector2(x, 7), 2.2, KoalaSandTheme.COLOR_WORLD_INK)
			draw_polyline(PackedVector2Array([center + Vector2(-8, -5), center, center + Vector2(-8, 5)]), color, 3)
		"funnel":
			draw_polyline(PackedVector2Array([center + Vector2(-13, -8), center + Vector2(13, -8), center + Vector2(4, 7), center + Vector2(4, 12)]), color, 3)
		"storage":
			draw_rect(Rect2(center + Vector2(-11, -10), Vector2(22, 21)), color, false, 3)
			draw_line(center + Vector2(-8, -3), center + Vector2(8, -3), color, 2)
		"furnace":
			draw_rect(Rect2(center + Vector2(-13, -9), Vector2(26, 8)), color, false, 3)
			for x in [-7, 0, 7]: draw_line(center + Vector2(x, 1), center + Vector2(x - 2, 10), Color("f16a32"), 2)
		"screen":
			draw_rect(Rect2(center + Vector2(-14, -9), Vector2(28, 18)), color, false, 2)
			for x in [-8, -2, 4, 10]: draw_line(center + Vector2(x, -7), center + Vector2(x, 7), secondary, 1)
			for y in [-4, 2]: draw_line(center + Vector2(-12, y), center + Vector2(12, y), secondary, 1)
		"riffle":
			draw_line(center + Vector2(-14, 8), center + Vector2(14, 8), color, 3)
			for x in [-10, -3, 4, 11]: draw_line(center + Vector2(x, 8), center + Vector2(x - 3, -5), secondary, 3)
		"grate":
			draw_line(center + Vector2(-14, -7), center + Vector2(14, -7), color, 4)
			for x in [-10, -4, 2, 8]: draw_line(center + Vector2(x, -3), center + Vector2(x, 9), secondary, 2)
		"magnet":
			draw_arc(center, 11, 0.05, PI - 0.05, 18, color, 4)
			draw_line(center + Vector2(-11, 0), center + Vector2(-11, 10), color, 4)
			draw_line(center + Vector2(11, 0), center + Vector2(11, 10), secondary, 4)
		"electromagnet":
			draw_arc(center, 10, 0.05, PI - 0.05, 18, secondary, 4)
			draw_line(center + Vector2(-10, 0), center + Vector2(-10, 10), color, 4)
			draw_line(center + Vector2(10, 0), center + Vector2(10, 10), color, 4)
			draw_polyline(PackedVector2Array([center + Vector2(-2, -12), center + Vector2(4, -4), center + Vector2(0, -4), center + Vector2(4, 5)]), KoalaSandTheme.COLOR_ACCENT_BRIGHT, 2)
		"pump":
			draw_circle(center, 11, color, false, 3)
			for angle in [0.0, 2.094, 4.188]:
				var direction := Vector2.RIGHT.rotated(angle)
				draw_line(center, center + direction * 8.0, secondary, 3)
			draw_polyline(PackedVector2Array([center + Vector2(13, -4), center + Vector2(18, 0), center + Vector2(13, 4)]), color, 2)
		"valve":
			draw_line(center + Vector2(-15, 0), center + Vector2(15, 0), secondary, 3)
			draw_polyline(PackedVector2Array([center + Vector2(-8, -8), center, center + Vector2(-8, 8), center + Vector2(8, -8), center, center + Vector2(8, 8)]), color, 3)
		"heater":
			draw_rect(Rect2(center + Vector2(-14, -10), Vector2(28, 20)), color, false, 2)
			draw_polyline(PackedVector2Array([center + Vector2(-10, 5), center + Vector2(-6, -5), center + Vector2(-2, 5), center + Vector2(2, -5), center + Vector2(6, 5), center + Vector2(10, -5)]), KoalaSandTheme.COLOR_DANGER, 2)
		"vibration":
			draw_circle(center, 7, color, false, 3)
			draw_circle(center + Vector2(4, -3), 2.5, secondary)
			for offset in [-15, 15]:
				draw_line(center + Vector2(offset, -7), center + Vector2(offset + sign(offset) * 4, -3), secondary, 2)
				draw_line(center + Vector2(offset, 7), center + Vector2(offset + sign(offset) * 4, 3), secondary, 2)
		"shaft":
			draw_circle(center, 10, color, false, 3)
			for angle in [0.0, PI * 0.5]: draw_line(center + Vector2.RIGHT.rotated(angle) * -13.0, center + Vector2.RIGHT.rotated(angle) * 13.0, secondary, 3)
			draw_circle(center, 3, KoalaSandTheme.COLOR_WORLD_INK)
		"turbine":
			draw_circle(center, 12, color, false, 3)
			for angle in [0.0, 1.571, 3.142, 4.712]:
				var direction := Vector2.RIGHT.rotated(angle)
				draw_colored_polygon(PackedVector2Array([center, center + direction.rotated(-0.35) * 10.0, center + direction.rotated(0.45) * 6.0]), secondary)
		"generator":
			draw_circle(center, 11, color, false, 3)
			draw_polyline(PackedVector2Array([center + Vector2(-7, 2), center + Vector2(-2, -6), center + Vector2(1, 5), center + Vector2(7, -3)]), secondary, 2)
		"power_pole":
			draw_line(center + Vector2(0, -13), center + Vector2(0, 13), color, 3)
			draw_line(center + Vector2(-11, -7), center + Vector2(11, -7), secondary, 3)
			for x in [-9, 9]: draw_circle(center + Vector2(x, -7), 2.5, color)
		"accumulator":
			draw_rect(Rect2(center + Vector2(-13, -9), Vector2(26, 18)), color, false, 3)
			draw_line(center + Vector2(-5, -4), center + Vector2(-5, 4), secondary, 3)
			draw_line(center + Vector2(-9, 0), center + Vector2(-1, 0), secondary, 3)
			draw_line(center + Vector2(3, 0), center + Vector2(10, 0), secondary, 3)
		"wall_structural":
			draw_rect(Rect2(center + Vector2(-13, -10), Vector2(26, 20)), color, false, 3)
			draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), secondary, 2)
		"wall_metal":
			draw_rect(Rect2(center + Vector2(-13, -10), Vector2(26, 20)), secondary, false, 3)
			for point in [Vector2(-8, -5), Vector2(8, -5), Vector2(-8, 5), Vector2(8, 5)]: draw_circle(center + point, 2, color)
		"wall_ceramic":
			draw_rect(Rect2(center + Vector2(-13, -10), Vector2(26, 20)), color, false, 2)
			for x in [-7, 0, 7]: draw_line(center + Vector2(x, -9), center + Vector2(x, 9), secondary, 1)
			draw_line(center + Vector2(-12, 0), center + Vector2(12, 0), secondary, 1)
		"wall_refractory":
			draw_rect(Rect2(center + Vector2(-14, -10), Vector2(28, 20)), KoalaSandTheme.COLOR_DANGER, false, 3)
			for y in [-5, 4]: draw_line(center + Vector2(-12, y), center + Vector2(12, y), color, 2)
			draw_line(center + Vector2(0, -9), center + Vector2(0, 9), color, 2)
		"bank":
			draw_rect(Rect2(center + Vector2(-11, -10), Vector2(22, 20)), color, false, 3)
			draw_circle(center, 5, Color("77d8c7"), false, 2)
		"sensor":
			draw_circle(center, 10, color, false, 3)
			draw_line(center, center + Vector2(10, -10), color, 2)
		"wire":
			draw_polyline(PackedVector2Array([center + Vector2(-14, 8), center + Vector2(-5, -7), center + Vector2(5, 7), center + Vector2(14, -8)]), Color("69d4c5"), 3)
		"remove":
			draw_line(center + Vector2(-9, -9), center + Vector2(9, 9), Color("e0654f"), 4)
			draw_line(center + Vector2(9, -9), center + Vector2(-9, 9), Color("e0654f"), 4)
		"dig":
			draw_line(center + Vector2(-10, 10), center + Vector2(9, -9), color, 4)
			draw_arc(center + Vector2(8, -8), 7, -2.8, 0.3, 10, color, 3)
		"blueprint":
			draw_rect(Rect2(center + Vector2(-12, -10), Vector2(24, 20)), Color("68c5d0"), false, 2)
			for x in [-6, 0, 6]: draw_line(center + Vector2(x, -8), center + Vector2(x, 8), Color("68c5d0", 0.65), 1)
			for y in [-5, 2]: draw_line(center + Vector2(-10, y), center + Vector2(10, y), Color("68c5d0", 0.65), 1)
		"select":
			draw_polyline(PackedVector2Array([center + Vector2(-10, -11), center + Vector2(-10, 9), center + Vector2(-4, 4), center + Vector2(1, 12)]), color, 3)
		"pipette":
			draw_line(center + Vector2(-9, 9), center + Vector2(9, -9), Color("68c5d0"), 4)
			draw_circle(center + Vector2(10, -10), 5, Color("68c5d0"), false, 2)
		_:
			draw_rect(Rect2(center - Vector2(9, 9), Vector2(18, 18)), color, false, 3)
	if locked:
		draw_rect(Rect2(center + Vector2(5, 2), Vector2(11, 10)), Color("0b1217e8"), true)
		draw_arc(center + Vector2(10.5, 2), 4.5, PI, TAU, 10, KoalaSandTheme.COLOR_TEXT_DISABLED, 2)
		draw_rect(Rect2(center + Vector2(6, 3), Vector2(9, 8)), KoalaSandTheme.COLOR_TEXT_DISABLED, false, 2)
	if not catalog_entry and not icon_only:
		var shortcut := "0" if index == 9 else str(index + 1)
		draw_string(ThemeDB.fallback_font, Vector2(5, 13), shortcut, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, KoalaSandTheme.COLOR_TEXT_SECONDARY)

func _resolved_icon() -> String:
	if str(tool.get("kind", "")) != "structure":
		return str(tool.get("icon", "tool"))
	match int(tool.get("id", -1)):
		11: return "pipe_junction"
		12: return "intake"
		13: return "outlet"
		14: return "pump"
		15: return "valve"
		16: return "storage"
		18: return "heater"
		26, 33: return "shaft"
		27: return "turbine"
		28: return "generator"
		29: return "power_pole"
		31: return "accumulator"
		34: return "heater"
		37: return "wall_structural"
		38: return "wall_metal"
		39: return "wall_ceramic"
		40: return "wall_refractory"
		41: return "screen"
		42: return "grate"
		43: return "riffle"
		45: return "vibration"
		46: return "electromagnet"
		_: return str(tool.get("icon", "tool"))
