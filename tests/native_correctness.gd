extends SceneTree

const FIXTURES: Array[String] = [
	"single_falling_column",
	"small_sand_pile",
	"narrow_funnel",
	"split_over_obstacle",
	"cross_chunk_pile",
]
const PHASE7_GOLDEN_HASHES := {
	"single_falling_column": "29d3f601",
	"small_sand_pile": "6e6c54a8",
	"narrow_funnel": "4f24e45a",
	"split_over_obstacle": "3fbc3051",
	"cross_chunk_pile": "1467bcf2",
}

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for fixture_name in FIXTURES:
		_compare_fixture(fixture_name)
	_compare_worker_counts()
	if _failures == 0:
		print("PASS: native Phase-7 canonical goldens and worker-count determinism")
	quit(0 if _failures == 0 else 1)


func _compare_fixture(fixture_name: String) -> void:
	var reference := GranularFixtures.build(fixture_name)
	var expected_count := _reference_cells(reference).size() / 3
	var serial := NativeSandWorld.new()
	var parallel := NativeSandWorld.new()
	serial.reset(24681357, 1)
	parallel.reset(24681357, mini(8, OS.get_processor_count()))
	GranularFixtures.populate(serial, fixture_name)
	GranularFixtures.populate(parallel, fixture_name)
	for tick in GranularFixtures.GOLDEN_TICKS[fixture_name]:
		var expected_movements: int = serial.step()
		_check(parallel.step() == expected_movements, "%s scheduler parity mismatch at tick %d" % [fixture_name, tick])
	var native_cells: PackedInt32Array = serial.get_non_empty_cells()
	_check(native_cells == parallel.get_non_empty_cells(), "%s serial/parallel final cell mismatch" % fixture_name)
	_check_equal(native_cells.size() / 3, expected_count, "%s material count conservation" % fixture_name)
	_check_equal(serial.material_state_hash(), PHASE7_GOLDEN_HASHES[fixture_name], "%s Phase-7 canonical hash" % fixture_name)
	print("correctness fixture=%s ticks=%d cells=%d phase7_hash=%s" % [
		fixture_name, GranularFixtures.GOLDEN_TICKS[fixture_name], native_cells.size() / 3, serial.material_state_hash()
	])


func _compare_worker_counts() -> void:
	var worker_counts: Array[int] = [1, 2, 4, mini(8, OS.get_processor_count())]
	var worlds: Array[Variant] = []
	for worker_count in worker_counts:
		var world := NativeSandWorld.new()
		world.reset(97531, worker_count)
		GranularFixtures.populate(world, "split_over_obstacle")
		worlds.append(world)
	for tick in 120:
		var expected_movements: int = worlds[0].step()
		worlds[0].consume_dirty_render_chunks()
		for index in range(1, worlds.size()):
			_check(worlds[index].step() == expected_movements, "worker-count movement mismatch workers=%d tick=%d" % [worker_counts[index], tick])
			worlds[index].consume_dirty_render_chunks()
	var expected_cells: PackedInt32Array = worlds[0].get_non_empty_cells()
	for index in range(1, worlds.size()):
		_check(expected_cells == worlds[index].get_non_empty_cells(), "worker-count final cell state mismatch workers=%d" % worker_counts[index])
	print("determinism workers=%s ticks=120 hash=%s" % [
		worker_counts, worlds[0].material_state_hash()
	])


func _reference_cells(world: CellWorld) -> PackedInt32Array:
	var cells: Array[Vector3i] = []
	for coordinate in world.get_chunk_coordinates():
		var chunk := world.get_chunk(coordinate)
		var origin := coordinate * WorldConfig.CHUNK_SIZE
		for index in WorldConfig.CELLS_PER_CHUNK:
			var material_id := chunk.material_ids[index]
			if material_id == MaterialRegistry.EMPTY_ID:
				continue
			cells.append(Vector3i(
				origin.x + index % WorldConfig.CHUNK_SIZE,
				origin.y + index / WorldConfig.CHUNK_SIZE,
				material_id
			))
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var result := PackedInt32Array()
	for cell in cells:
		result.append(cell.x)
		result.append(cell.y)
		result.append(cell.z)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [message, expected, actual])


func _cells_to_map(cells: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for index in range(0, cells.size(), 3):
		result[Vector2i(cells[index], cells[index + 1])] = cells[index + 2]
	return result
