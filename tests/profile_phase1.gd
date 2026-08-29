extends SceneTree

const CHUNK_SIZES: Array[int] = [32, 64, 128]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := _build_medium_world()
	var simulator := GranularSimulator.new(world)
	for _tick in 44:
		simulator.step()

	print("KoalaSand Phase 1 profiling probe")
	print("state allocated_cells=%d active_chunks=%d sleeping_chunks=%d" % [
		world.total_allocated_cells(), world.active_chunk_count(), world.sleeping_chunk_count()
	])
	_profile_scheduling(world)
	_profile_scans(world)
	_profile_neighbor_queries(world)
	_profile_full_step(world, simulator)
	_profile_renderer(world)
	_profile_chunk_granularity(world)
	quit(0)


func _profile_scheduling(world: CellWorld) -> void:
	var start := Time.get_ticks_usec()
	var checksum := 0
	for _iteration in 2000:
		checksum += world.get_active_chunk_coordinates().size()
	var elapsed := Time.get_ticks_usec() - start
	print("profile scheduling iterations=2000 total_ms=%.3f per_tick_ms=%.6f checksum=%d" % [
		float(elapsed) / 1000.0, float(elapsed) / 2000.0 / 1000.0, checksum
	])


func _profile_scans(world: CellWorld) -> void:
	var coordinates := world.get_active_chunk_coordinates()
	var iterations := 20
	var start := Time.get_ticks_usec()
	var granular_count := 0
	for _iteration in iterations:
		for coordinate in coordinates:
			var chunk := world.get_chunk(coordinate)
			for material_id in chunk.material_ids:
				if world.materials.get_category(material_id) == MaterialDefinition.Category.GRANULAR:
					granular_count += 1
	var category_usec := Time.get_ticks_usec() - start

	start = Time.get_ticks_usec()
	var direct_count := 0
	for _iteration in iterations:
		for coordinate in coordinates:
			var chunk := world.get_chunk(coordinate)
			for material_id in chunk.material_ids:
				if material_id == 2:
					direct_count += 1
	var direct_usec := Time.get_ticks_usec() - start
	print("profile traversal cells_per_iteration=%d category_ms=%.3f direct_id_ms=%.3f category_overhead_ms=%.3f checksum=%d" % [
		coordinates.size() * WorldConfig.CELLS_PER_CHUNK,
		float(category_usec) / float(iterations) / 1000.0,
		float(direct_usec) / float(iterations) / 1000.0,
		float(category_usec - direct_usec) / float(iterations) / 1000.0,
		granular_count + direct_count,
	])


func _profile_neighbor_queries(world: CellWorld) -> void:
	var start := Time.get_ticks_usec()
	var queries := 0
	var checksum := 0
	for coordinate in world.get_active_chunk_coordinates():
		var chunk := world.get_chunk(coordinate)
		var origin := coordinate * WorldConfig.CHUNK_SIZE
		for index in WorldConfig.CELLS_PER_CHUNK:
			if chunk.material_ids[index] != 2:
				continue
			var cell := origin + WorldConfig.index_to_local(index)
			checksum += world.get_cell(cell + Vector2i.DOWN)
			checksum += world.get_cell(cell + Vector2i(-1, 1))
			checksum += world.get_cell(cell + Vector2i(1, 1))
			queries += 3
	var elapsed := Time.get_ticks_usec() - start
	print("profile neighbor_queries count=%d total_ms=%.3f ns_per_query=%.1f checksum=%d" % [
		queries, float(elapsed) / 1000.0, float(elapsed) * 1000.0 / maxi(1, queries), checksum
	])


func _profile_full_step(world: CellWorld, simulator: GranularSimulator) -> void:
	var start := Time.get_ticks_usec()
	var movements := simulator.step()
	var elapsed := Time.get_ticks_usec() - start
	print("profile full_step ms=%.3f visited=%d movements=%d" % [
		float(elapsed) / 1000.0, simulator.last_scanned_cells, movements
	])


func _profile_renderer(world: CellWorld) -> void:
	var images: Array[Image] = []
	var dirty_chunks := world.get_dirty_chunks()
	var start := Time.get_ticks_usec()
	for chunk in dirty_chunks:
		images.append(MaterialVisualResolver.build_chunk_image(world, chunk))
	var generation_usec := Time.get_ticks_usec() - start
	var textures: Array[ImageTexture] = []
	start = Time.get_ticks_usec()
	for image in images:
		textures.append(ImageTexture.create_from_image(image))
	var upload_usec := Time.get_ticks_usec() - start
	print("profile renderer chunks=%d pixels=%d generation_ms=%.3f upload_ms=%.3f" % [
		dirty_chunks.size(), dirty_chunks.size() * WorldConfig.CELLS_PER_CHUNK,
		float(generation_usec) / 1000.0, float(upload_usec) / 1000.0
	])


func _profile_chunk_granularity(world: CellWorld) -> void:
	var occupied: Array[Vector2i] = []
	for coordinate in world.get_chunk_coordinates():
		var chunk := world.get_chunk(coordinate)
		var origin := coordinate * WorldConfig.CHUNK_SIZE
		for index in WorldConfig.CELLS_PER_CHUNK:
			if chunk.material_ids[index] == 2:
				occupied.append(origin + WorldConfig.index_to_local(index))
	for chunk_size in CHUNK_SIZES:
		var chunks: Dictionary = {}
		for cell in occupied:
			var coordinate := Vector2i(_floor_div(cell.x, chunk_size), _floor_div(cell.y, chunk_size))
			if not chunks.has(coordinate):
				var cells := PackedByteArray()
				cells.resize(chunk_size * chunk_size)
				chunks[coordinate] = cells
			var local := cell - coordinate * chunk_size
			var cells: PackedByteArray = chunks[coordinate]
			cells[local.y * chunk_size + local.x] = 1
		var iterations := 100
		var start := Time.get_ticks_usec()
		var checksum := 0
		for _iteration in iterations:
			for cells: PackedByteArray in chunks.values():
				for value in cells:
					checksum += value
		var elapsed := Time.get_ticks_usec() - start
		print("profile chunk_size=%d active_chunks=%d visited_cells=%d scan_ms=%.3f checksum=%d" % [
			chunk_size, chunks.size(), chunks.size() * chunk_size * chunk_size,
			float(elapsed) / float(iterations) / 1000.0, checksum
		])


func _build_medium_world() -> CellWorld:
	var materials := MaterialRegistry.new()
	assert(materials.load_directory() == OK)
	var world := CellWorld.new(7002, materials)
	for chunk_y in 4:
		for chunk_x in 4:
			var chunk := world.get_or_create_chunk(Vector2i(chunk_x, chunk_y))
			chunk.sleep()
			chunk.mark_clean()
	for x in range(0, 512):
		world.set_cell(Vector2i(x, 300), 1)
	for y in range(18, 59):
		for x in range(16, 497, 2):
			world.set_cell(Vector2i(x, y), 2)
	return world


func _floor_div(value: int, divisor: int) -> int:
	if value >= 0:
		return value / divisor
	return -((-value + divisor - 1) / divisor)
