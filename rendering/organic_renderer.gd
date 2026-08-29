class_name OrganicRenderer
extends Node2D

var world: Variant
var cell_pixel_size := 2.0
var reduced_motion := false
var _clusters: Array = []
var _effects := PackedInt32Array()


func initialize(next_world: Variant, pixels_per_cell: float) -> void:
	world = next_world
	cell_pixel_size = pixels_per_cell
	queue_redraw()


func sync_visible(cell_area: Rect2i) -> void:
	if world == null: return
	_clusters = world.get_visible_fellable_clusters(cell_area)
	_effects = world.get_visible_organic_effects(cell_area)
	queue_redraw()


func _draw() -> void:
	for cluster: Dictionary in _clusters:
		var cells: PackedInt32Array = cluster.cells
		for index in range(0, cells.size(), 3):
			var color := Color("6f9b45") if cells[index + 2] == 22 else Color("80542f")
			draw_rect(Rect2(Vector2(cells[index], cells[index + 1]) * cell_pixel_size, Vector2.ONE * cell_pixel_size), color, true)
	for index in range(0, _effects.size(), 4):
		var center := (Vector2(_effects[index], _effects[index + 1]) + Vector2(0.5, 0.25)) * cell_pixel_size
		var temperature := _effects[index + 3]
		var intensity := clampf(float(temperature - 1500) / 1800.0, 0.15, 1.0)
		var height := cell_pixel_size * (2.2 if reduced_motion else 3.0 + 0.4 * sin(float(_effects[index] * 17 + _effects[index + 1] * 31)))
		draw_circle(center, cell_pixel_size * (1.0 + intensity), Color(1.0, 0.31, 0.04, 0.08 + intensity * 0.13))
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-0.62, 0.65) * cell_pixel_size,
			center + Vector2(0.0, -height),
			center + Vector2(0.62, 0.65) * cell_pixel_size,
		]), Color(1.0, 0.32 + intensity * 0.35, 0.05, 0.45 + intensity * 0.5))
