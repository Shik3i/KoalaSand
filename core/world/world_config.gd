class_name WorldConfig
extends RefCounted

const CHUNK_SIZE := 128
const CELLS_PER_CHUNK := CHUNK_SIZE * CHUNK_SIZE
const DEFAULT_TEMPERATURE_CENTI_C := 2000
const CHUNK_SLEEP_AFTER_STABLE_TICKS := 8

const MATERIAL_BYTES_PER_CELL := 4
const TEMPERATURE_BYTES_PER_CELL := 4
const FLAGS_BYTES_PER_CELL := 1
const BACKING_BYTES_PER_CELL := (
	MATERIAL_BYTES_PER_CELL + TEMPERATURE_BYTES_PER_CELL + FLAGS_BYTES_PER_CELL
)
const BACKING_BYTES_PER_CHUNK := CELLS_PER_CHUNK * BACKING_BYTES_PER_CELL


static func floor_div(value: int, divisor: int) -> int:
	assert(divisor > 0)
	if value >= 0:
		@warning_ignore("integer_division")
		return value / divisor
	@warning_ignore("integer_division")
	return -((-value + divisor - 1) / divisor)


static func world_to_chunk(world_cell: Vector2i) -> Vector2i:
	return Vector2i(
		floor_div(world_cell.x, CHUNK_SIZE),
		floor_div(world_cell.y, CHUNK_SIZE)
	)


static func world_to_local(world_cell: Vector2i) -> Vector2i:
	var chunk_coordinate := world_to_chunk(world_cell)
	return world_cell - chunk_coordinate * CHUNK_SIZE


static func chunk_local_to_world(chunk_coordinate: Vector2i, local: Vector2i) -> Vector2i:
	assert(local.x >= 0 and local.x < CHUNK_SIZE)
	assert(local.y >= 0 and local.y < CHUNK_SIZE)
	return chunk_coordinate * CHUNK_SIZE + local


static func local_to_index(local: Vector2i) -> int:
	assert(local.x >= 0 and local.x < CHUNK_SIZE)
	assert(local.y >= 0 and local.y < CHUNK_SIZE)
	return local.y * CHUNK_SIZE + local.x


static func index_to_local(index: int) -> Vector2i:
	assert(index >= 0 and index < CELLS_PER_CHUNK)
	@warning_ignore("integer_division")
	return Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE)
