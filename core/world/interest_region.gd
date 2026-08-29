class_name InterestRegion
extends RefCounted

enum Purpose { CHARACTER, GOD_CAMERA, VISION_SOURCE, SPECTATOR, PREFETCH }

var source_id: int
var priority: int
var bounds: Rect2i
var purpose: Purpose
var generation_budget: int


func _init(next_source_id := 0, next_priority := 1, next_bounds := Rect2i(), next_purpose := Purpose.GOD_CAMERA, next_budget := 64) -> void:
	source_id = next_source_id
	priority = clampi(next_priority, 0, 100)
	bounds = next_bounds
	purpose = next_purpose
	generation_budget = maxi(0, next_budget)


func request(world: Variant) -> int:
	if purpose == Purpose.SPECTATOR and bounds.get_area() > generation_budget:
		var limited_size := Vector2i(mini(bounds.size.x, generation_budget), 1)
		return world.request_chunk_region(Rect2i(bounds.position, limited_size), priority)
	return world.request_chunk_region(bounds, priority)


func serialize() -> Dictionary:
	return {"source_id": source_id, "priority": priority, "bounds": bounds, "purpose": purpose, "generation_budget": generation_budget}
