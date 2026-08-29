extends SceneTree

const SCALE_CHUNKS: Array[int] = [16, 64, 256]
const RAW_SAND_ID := 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("KoalaSand Phase 0 + Phase 1 scalability probe")
	print("chunk_size=%d cells_per_chunk=%d backing_bytes_per_cell=%d" % [
		WorldConfig.CHUNK_SIZE,
		WorldConfig.CELLS_PER_CHUNK,
		WorldConfig.BACKING_BYTES_PER_CELL,
	])
	for chunk_count in SCALE_CHUNKS:
		_run_scale(chunk_count)
	_run_sparse_activity()
	_run_medium_falling_mass()
	_run_settled_world()
	quit(0)


func _run_scale(target_chunk_count: int) -> void:
	var world := CellWorld.new(123456)
	var width := 4 if target_chunk_count == 16 else 8 if target_chunk_count == 64 else 16
	var start_usec := Time.get_ticks_usec()
	for index in target_chunk_count:
		var coordinate := Vector2i(index % width, index / width)
		var chunk := world.get_or_create_chunk(coordinate)
		for cell_index in range(index % 97, WorldConfig.CELLS_PER_CHUNK, 97):
			chunk.material_ids[cell_index] = RAW_SAND_ID
	var initialization_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0

	start_usec = Time.get_ticks_usec()
	var checksum := 0
	for coordinate in world.get_chunk_coordinates():
		var chunk := world.get_chunk(coordinate)
		for cell_index in WorldConfig.CELLS_PER_CHUNK:
			checksum += chunk.material_ids[cell_index]
			checksum += chunk.cell_flags[cell_index]
	var traversal_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	print(
		"baseline chunks=%d cells=%d backing_bytes=%d init_ms=%.3f traversal_ms=%.3f checksum=%d"
		% [
			world.chunk_count(),
			world.total_allocated_cells(),
			world.approximate_backing_bytes(),
			initialization_ms,
			traversal_ms,
			checksum,
		]
	)


func _run_sparse_activity() -> void:
	var world := _new_world(7001)
	_allocate_sleeping_grid(world, 8, 8)
	for x in range(0, 65):
		world.set_cell(Vector2i(x, 110), 1)
	for y in range(0, 31):
		for x in range(20, 45):
			world.set_cell(Vector2i(x, y), 2)
	var simulator := GranularSimulator.new(world)
	_run_granular_scenario("sparse_activity", world, simulator, 60)


func _run_medium_falling_mass() -> void:
	var world := _new_world(7002)
	_allocate_sleeping_grid(world, 4, 4)
	for x in range(0, 512):
		world.set_cell(Vector2i(x, 300), 1)
	for y in range(18, 59):
		for x in range(16, 497, 2):
			world.set_cell(Vector2i(x, y), 2)
	var simulator := GranularSimulator.new(world)
	_run_granular_scenario("medium_falling_mass", world, simulator, 45)


func _run_settled_world() -> void:
	var world := _new_world(7003)
	for chunk_y in 8:
		for chunk_x in 8:
			var chunk := world.get_or_create_chunk(Vector2i(chunk_x, chunk_y))
			for local_x in WorldConfig.CHUNK_SIZE:
				chunk.material_ids[127 * WorldConfig.CHUNK_SIZE + local_x] = 1
			for local_y in range(110, 127):
				chunk.material_ids[local_y * WorldConfig.CHUNK_SIZE] = 1
				chunk.material_ids[local_y * WorldConfig.CHUNK_SIZE + 127] = 1
				for local_x in range(1, 127):
					chunk.material_ids[local_y * WorldConfig.CHUNK_SIZE + local_x] = 2
			chunk.state_flags |= SimChunk.StateFlag.DIRTY
			chunk.sleep()
	var simulator := GranularSimulator.new(world)
	_run_granular_scenario("settled_world", world, simulator, 120)


func _run_granular_scenario(
	name: String,
	world: CellWorld,
	simulator: GranularSimulator,
	tick_count: int
) -> void:
	var total_usec := 0
	var worst_usec := 0
	var movement_count := 0
	for _tick in tick_count:
		var start_usec := Time.get_ticks_usec()
		movement_count += simulator.step()
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		total_usec += elapsed_usec
		worst_usec = maxi(worst_usec, elapsed_usec)
	var render_ms := _measure_renderer_update(world)
	print(
		"granular scenario=%s allocated_cells=%d active_chunks=%d sleeping_chunks=%d ticks=%d avg_ms_per_tick=%.3f worst_ms_per_tick=%.3f movements=%d renderer_update_ms=%.3f"
		% [
			name,
			world.total_allocated_cells(),
			world.active_chunk_count(),
			world.sleeping_chunk_count(),
			tick_count,
			float(total_usec) / float(tick_count) / 1000.0,
			float(worst_usec) / 1000.0,
			movement_count,
			render_ms,
		]
	)


func _measure_renderer_update(world: CellWorld) -> float:
	var renderer := DebugCellRenderer.new()
	root.add_child(renderer)
	var start_usec := Time.get_ticks_usec()
	renderer.initialize(world)
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	renderer.free()
	return elapsed_ms


func _new_world(seed: int) -> CellWorld:
	var materials := MaterialRegistry.new()
	assert(materials.load_directory() == OK)
	return CellWorld.new(seed, materials)


func _allocate_sleeping_grid(world: CellWorld, width: int, height: int) -> void:
	for chunk_y in height:
		for chunk_x in width:
			var chunk := world.get_or_create_chunk(Vector2i(chunk_x, chunk_y))
			chunk.sleep()
			chunk.mark_clean()
