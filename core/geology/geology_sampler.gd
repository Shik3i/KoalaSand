class_name GeologySampler
extends RefCounted

enum Component {
	SILICA,
	IRON_BEARING,
	HEAVY_MINERALS,
	TRACE_GOLD,
	COUNT,
}

var world_seed: int


func _init(seed: int) -> void:
	world_seed = seed


func sample_region(region_coordinate: Vector2i) -> PackedFloat32Array:
	var composition := PackedFloat32Array()
	composition.resize(Component.COUNT)
	var iron := 0.05 + DeterministicHash.unit_float(world_seed, region_coordinate, 11) * 0.18
	var heavy := 0.01 + DeterministicHash.unit_float(world_seed, region_coordinate, 23) * 0.06
	var gold := DeterministicHash.unit_float(world_seed, region_coordinate, 47) * 0.001
	composition[Component.IRON_BEARING] = iron
	composition[Component.HEAVY_MINERALS] = heavy
	composition[Component.TRACE_GOLD] = gold
	composition[Component.SILICA] = 1.0 - iron - heavy - gold
	return composition
