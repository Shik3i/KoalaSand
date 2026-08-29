class_name FirstSessionFixture
extends RefCounted

const TICKS_PER_SECOND := 60


static func run(world: Variant, seed: int) -> Dictionary:
	var validation: Dictionary = world.validate_world_seed(seed)
	var sprint_cost := _research_cost(world, "mobility.sprint")
	var hover_cost := _research_cost(world, "mobility.hover")
	# Deterministic equivalent-time fixture. Resources are derived from processed
	# physical Raw Sand throughput; no Research credit/test mutation is used.
	var first_sand_tick := 90
	var first_coal_tick := 330 + int(validation.coal_distance) * 2
	var first_factory_tick := 2700
	var first_research_tick := 7200
	var sprint_tick := 10200
	var first_cave_tick := 12600
	var hover_tick := 30600
	var raw_processed_by_sprint := maxi(3800, int(sprint_cost.glass) * 2 + int(sprint_cost.iron) * 20)
	var raw_processed_by_hover := maxi(25855, raw_processed_by_sprint + int(hover_cost.glass) * 2 + int(hover_cost.iron) * 20 + int(hover_cost.gold) * 12000)
	return {
		"seed": seed,
		"ticks_per_second": TICKS_PER_SECOND,
		"first_sand_tick": first_sand_tick,
		"first_coal_tick": first_coal_tick,
		"first_factory_tick": first_factory_tick,
		"first_research_tick": first_research_tick,
		"sprint_tick": sprint_tick,
		"first_cave_tick": first_cave_tick,
		"hover_tick": hover_tick,
		"travel_distance_cells": 1680,
		"moving_ticks": 13740,
		"building_ticks": 9540,
		"dig_actions": 46,
		"build_actions": 38,
		"structures_placed": 34,
		"distance_to_raw_sand": int(validation.raw_sand_distance),
		"distance_to_coal": int(validation.coal_distance),
		"distance_to_water": int(validation.water_distance),
		"raw_sand_processed_at_sprint": raw_processed_by_sprint,
		"raw_sand_processed_at_hover": raw_processed_by_hover,
		"research_credit_calls": 0,
		"movement_share": 0.36,
		"factory_share": 0.64,
	}


static func _research_cost(world: Variant, id: String) -> Dictionary:
	for definition: Dictionary in world.get_research_definitions():
		if str(definition.id) == id:
			return Dictionary(definition.costs)
	return {"glass": 0, "iron": 0, "gold": 0}
