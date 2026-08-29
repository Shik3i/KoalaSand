class_name IndustrialBackdrop
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), KoalaSandTheme.COLOR_WORLD_INK)
	for band in 12:
		var t := float(band) / 11.0
		var color := Color("0b151b").lerp(Color("15242a"), t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / 11.0 + 2.0), color)
	var horizon := size.y * 0.58
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon), Vector2(size.x * 0.14, horizon - 86), Vector2(size.x * 0.28, horizon - 31),
		Vector2(size.x * 0.43, horizon - 112), Vector2(size.x * 0.58, horizon - 42), Vector2(size.x * 0.74, horizon - 101),
		Vector2(size.x, horizon - 24), Vector2(size.x, size.y), Vector2(0, size.y)
	]), Color("0a1116"))
	for layer in 6:
		var y := horizon + 34.0 + layer * 34.0
		var layer_color := Color("3f3022").lerp(Color("171d1d"), float(layer) / 7.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, y), Vector2(size.x * 0.17, y - 13 - layer * 3), Vector2(size.x * 0.36, y + 7),
			Vector2(size.x * 0.55, y - 10), Vector2(size.x * 0.76, y + 4), Vector2(size.x, y - 14),
			Vector2(size.x, size.y), Vector2(0, size.y)
		]), layer_color)
	for x in range(0, roundi(size.x), 48):
		var height := 3.0 + float((x * 37) % 13)
		draw_line(Vector2(x, horizon + 9), Vector2(x + 18, horizon + 9 - height), Color("d6a34766"), 2.0)
	for x in range(0, roundi(size.x), 96):
		draw_line(Vector2(x, size.y - 2), Vector2(x + 58, horizon + 8), Color("23353b2e"), 1.0)
	for y in range(roundi(horizon), roundi(size.y), 48):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("23353b24"), 1.0)
