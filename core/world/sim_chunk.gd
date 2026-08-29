class_name SimChunk
extends RefCounted

enum StateFlag {
	ACTIVE = 1 << 0,
	SLEEPING = 1 << 1,
	DIRTY = 1 << 2,
}

const CELL_FLAG_OCCUPIED_BY_MACHINE := 1 << 0

var coordinate: Vector2i
var material_ids := PackedInt32Array()
var temperatures_centi_c := PackedInt32Array()
var cell_flags := PackedByteArray()
var state_flags: int = StateFlag.ACTIVE | StateFlag.DIRTY
var revision: int = 0
var stable_tick_count: int = 0


func _init(chunk_coordinate: Vector2i = Vector2i.ZERO) -> void:
	coordinate = chunk_coordinate
	material_ids.resize(WorldConfig.CELLS_PER_CHUNK)
	material_ids.fill(MaterialRegistry.EMPTY_ID)
	temperatures_centi_c.resize(WorldConfig.CELLS_PER_CHUNK)
	temperatures_centi_c.fill(WorldConfig.DEFAULT_TEMPERATURE_CENTI_C)
	cell_flags.resize(WorldConfig.CELLS_PER_CHUNK)
	cell_flags.fill(0)


func get_material(local: Vector2i) -> int:
	return material_ids[WorldConfig.local_to_index(local)]


func set_material(local: Vector2i, material_id: int) -> bool:
	var index := WorldConfig.local_to_index(local)
	if material_ids[index] == material_id:
		return false
	material_ids[index] = material_id
	_mark_mutated()
	return true


func get_temperature(local: Vector2i) -> int:
	return temperatures_centi_c[WorldConfig.local_to_index(local)]


func set_temperature(local: Vector2i, temperature_centi_c: int) -> bool:
	var index := WorldConfig.local_to_index(local)
	if temperatures_centi_c[index] == temperature_centi_c:
		return false
	temperatures_centi_c[index] = temperature_centi_c
	_mark_mutated()
	return true


func get_flags(local: Vector2i) -> int:
	return cell_flags[WorldConfig.local_to_index(local)]


func set_flags(local: Vector2i, flags: int) -> bool:
	var index := WorldConfig.local_to_index(local)
	var packed_flags := flags & 0xff
	if cell_flags[index] == packed_flags:
		return false
	cell_flags[index] = packed_flags
	_mark_mutated()
	return true


func mark_clean() -> void:
	state_flags &= ~StateFlag.DIRTY


func sleep() -> void:
	state_flags &= ~StateFlag.ACTIVE
	state_flags |= StateFlag.SLEEPING


func wake() -> void:
	state_flags &= ~StateFlag.SLEEPING
	state_flags |= StateFlag.ACTIVE
	stable_tick_count = 0


func is_active() -> bool:
	return (state_flags & StateFlag.ACTIVE) != 0


func is_sleeping() -> bool:
	return (state_flags & StateFlag.SLEEPING) != 0


func record_simulation_result(had_movement: bool, sleep_threshold: int) -> void:
	if had_movement:
		wake()
		return
	stable_tick_count += 1
	if stable_tick_count >= sleep_threshold:
		sleep()


func is_dirty() -> bool:
	return (state_flags & StateFlag.DIRTY) != 0


func mark_visual_dirty() -> void:
	state_flags |= StateFlag.DIRTY


func approximate_backing_bytes() -> int:
	return WorldConfig.BACKING_BYTES_PER_CHUNK


func _mark_mutated() -> void:
	revision += 1
	wake()
	state_flags |= StateFlag.DIRTY
