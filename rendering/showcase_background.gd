class_name ShowcaseBackground
extends Node2D

@export_range(1.0, 8.0, 1.0) var cell_pixel_size: float = 2.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var world_rect := Rect2(Vector2(-900, -520), Vector2(1800, 1200))
	draw_rect(world_rect, Color(0.025, 0.045, 0.06, 1.0))

	var sky_top := Color(0.08, 0.19, 0.24, 1.0)
	var sky_bottom := Color(0.18, 0.26, 0.27, 1.0)
	for band in 12:
		var factor := float(band) / 11.0
		var band_rect := Rect2(Vector2(-900, -520 + band * 45), Vector2(1800, 46))
		draw_rect(band_rect, sky_top.lerp(sky_bottom, factor))

	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-900, -70), Vector2(-720, -150), Vector2(-560, -95),
			Vector2(-390, -175), Vector2(-210, -90), Vector2(20, -155),
			Vector2(250, -82), Vector2(440, -145), Vector2(650, -90),
			Vector2(900, -130), Vector2(900, 20), Vector2(-900, 20),
		]),
		Color(0.08, 0.13, 0.15, 1.0)
	)

	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-900, 22), Vector2(-720, 6), Vector2(-540, 28),
			Vector2(-350, 12), Vector2(-165, 34), Vector2(20, 9),
			Vector2(205, 27), Vector2(390, 5), Vector2(570, 31),
			Vector2(750, 13), Vector2(900, 24), Vector2(900, 680),
			Vector2(-900, 680),
		]),
		Color(0.035, 0.06, 0.075, 1.0)
	)
	for grid_y in range(1, 9):
		for grid_x in range(-10, 11):
			var cell := Vector2i(grid_x, grid_y)
			var noise := DeterministicHash.unit_float(0x4b53414e44, cell, 701)
			if noise < 0.34:
				continue
			var center := Vector2(grid_x * 92 + noise * 37.0, grid_y * 72 + 12.0) * cell_pixel_size
			var radius := lerpf(18.0, 52.0, noise)
			draw_circle(center, radius, Color(0.055, 0.085, 0.1, 0.34))
