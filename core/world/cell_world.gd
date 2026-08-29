class_name CellWorld
extends RefCounted

var seed: int
var materials: MaterialRegistry
var _chunks: Dictionary = {}


func _init(world_seed: int = 1, material_registry: MaterialRegistry = null) -> void:
	seed = world_seed
	materials = material_registry


func get_or_create_chunk(chunk_coordinate: Vector2i) -> SimChunk:
	var existing := _chunks.get(chunk_coordinate) as SimChunk
	if existing != null:
		return existing
	var chunk := SimChunk.new(chunk_coordinate)
	_chunks[chunk_coordinate] = chunk
	return chunk


func get_chunk(chunk_coordinate: Vector2i) -> SimChunk:
	return _chunks.get(chunk_coordinate) as SimChunk


func get_cell(world_cell: Vector2i) -> int:
	var chunk := get_chunk(WorldConfig.world_to_chunk(world_cell))
	if chunk == null:
		return MaterialRegistry.EMPTY_ID
	return chunk.get_material(WorldConfig.world_to_local(world_cell))


func has_allocated_cell(world_cell: Vector2i) -> bool:
	return get_chunk(WorldConfig.world_to_chunk(world_cell)) != null


func set_cell(world_cell: Vector2i, material_id: int) -> Error:
	if materials != null and not materials.is_valid_id(material_id):
		return ERR_INVALID_PARAMETER
	var chunk_coordinate := WorldConfig.world_to_chunk(world_cell)
	var chunk := get_chunk(chunk_coordinate)
	if chunk == null and material_id == MaterialRegistry.EMPTY_ID:
		return OK
	if chunk == null:
		chunk = get_or_create_chunk(chunk_coordinate)
	if chunk.set_material(WorldConfig.world_to_local(world_cell), material_id):
		_wake_chunks_depending_on(world_cell)
		_invalidate_visual_neighbors(world_cell)
	return OK


func initialize_cell(world_cell: Vector2i, material_id: int) -> Error:
	if materials != null and not materials.is_valid_id(material_id):
		return ERR_INVALID_PARAMETER
	if material_id == MaterialRegistry.EMPTY_ID:
		return OK
	var chunk := get_or_create_chunk(WorldConfig.world_to_chunk(world_cell))
	var index := WorldConfig.local_to_index(WorldConfig.world_to_local(world_cell))
	if chunk.material_ids[index] == material_id:
		return OK
	chunk.material_ids[index] = material_id
	chunk.revision += 1
	chunk.mark_visual_dirty()
	return OK


func move_cell_if_empty(source: Vector2i, destination: Vector2i) -> bool:
	var source_chunk := get_chunk(WorldConfig.world_to_chunk(source))
	if source_chunk == null:
		return false
	var source_local := WorldConfig.world_to_local(source)
	var material_id := source_chunk.get_material(source_local)
	if material_id == MaterialRegistry.EMPTY_ID or get_cell(destination) != MaterialRegistry.EMPTY_ID:
		return false
	var destination_chunk := get_or_create_chunk(WorldConfig.world_to_chunk(destination))
	var destination_local := WorldConfig.world_to_local(destination)
	if not destination_chunk.set_material(destination_local, material_id):
		return false
	source_chunk.set_material(source_local, MaterialRegistry.EMPTY_ID)
	_wake_chunks_depending_on(source)
	_invalidate_visual_neighbors(source)
	_invalidate_visual_neighbors(destination)
	return true


func get_temperature(world_cell: Vector2i) -> int:
	var chunk := get_chunk(WorldConfig.world_to_chunk(world_cell))
	if chunk == null:
		return WorldConfig.DEFAULT_TEMPERATURE_CENTI_C
	return chunk.get_temperature(WorldConfig.world_to_local(world_cell))


func set_temperature(world_cell: Vector2i, temperature_centi_c: int) -> void:
	var chunk := get_or_create_chunk(WorldConfig.world_to_chunk(world_cell))
	chunk.set_temperature(WorldConfig.world_to_local(world_cell), temperature_centi_c)


func get_cell_flags(world_cell: Vector2i) -> int:
	var chunk := get_chunk(WorldConfig.world_to_chunk(world_cell))
	if chunk == null:
		return 0
	return chunk.get_flags(WorldConfig.world_to_local(world_cell))


func set_cell_flags(world_cell: Vector2i, flags: int) -> void:
	var chunk := get_or_create_chunk(WorldConfig.world_to_chunk(world_cell))
	chunk.set_flags(WorldConfig.world_to_local(world_cell), flags)


func get_chunk_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coordinate in _chunks.keys():
		result.append(coordinate as Vector2i)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func get_active_chunk_coordinates() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coordinate in _chunks.keys():
		var chunk := get_chunk(coordinate as Vector2i)
		if chunk.is_active():
			result.append(coordinate as Vector2i)
	return result


func get_dirty_chunks() -> Array[SimChunk]:
	var result: Array[SimChunk] = []
	for coordinate in get_chunk_coordinates():
		var chunk := get_chunk(coordinate)
		if chunk.is_dirty():
			result.append(chunk)
	return result


func chunk_count() -> int:
	return _chunks.size()


func active_chunk_count() -> int:
	var count := 0
	for chunk in _chunks.values():
		if (chunk as SimChunk).is_active():
			count += 1
	return count


func sleeping_chunk_count() -> int:
	var count := 0
	for chunk in _chunks.values():
		if (chunk as SimChunk).is_sleeping():
			count += 1
	return count


func total_allocated_cells() -> int:
	return chunk_count() * WorldConfig.CELLS_PER_CHUNK


func approximate_backing_bytes() -> int:
	return chunk_count() * WorldConfig.BACKING_BYTES_PER_CHUNK


func material_state_hash() -> String:
	var hash_value := DeterministicHash.mix_int(0x4b53414e, seed)
	for coordinate in get_chunk_coordinates():
		var chunk := get_chunk(coordinate)
		hash_value = DeterministicHash.mix_int(hash_value, coordinate.x)
		hash_value = DeterministicHash.mix_int(hash_value, coordinate.y)
		for index in WorldConfig.CELLS_PER_CHUNK:
			var material_id := chunk.material_ids[index]
			if material_id == MaterialRegistry.EMPTY_ID:
				continue
			hash_value = DeterministicHash.mix_int(hash_value, index)
			hash_value = DeterministicHash.mix_int(hash_value, material_id)
	return "%08x" % hash_value


func _wake_chunks_depending_on(changed_cell: Vector2i) -> void:
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]:
		var dependent_coordinate := WorldConfig.world_to_chunk(changed_cell + offset)
		var dependent := get_chunk(dependent_coordinate)
		if dependent != null:
			dependent.wake()


func _invalidate_visual_neighbors(changed_cell: Vector2i) -> void:
	var local := WorldConfig.world_to_local(changed_cell)
	var chunk_coordinate := WorldConfig.world_to_chunk(changed_cell)
	var offsets: Array[Vector2i] = []
	if local.x == 0:
		offsets.append(Vector2i.LEFT)
	elif local.x == WorldConfig.CHUNK_SIZE - 1:
		offsets.append(Vector2i.RIGHT)
	if local.y == 0:
		offsets.append(Vector2i.UP)
	elif local.y == WorldConfig.CHUNK_SIZE - 1:
		offsets.append(Vector2i.DOWN)
	for offset in offsets:
		var neighbor := get_chunk(chunk_coordinate + offset)
		if neighbor != null:
			neighbor.mark_visual_dirty()
