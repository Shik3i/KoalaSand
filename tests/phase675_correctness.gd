extends SceneTree

const CHARCOAL := 23

const RAW := 2
const STONE := 1
const HEAVY := 7

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_thermal_encoding()
	_test_combined_physical_worker_parity()
	_test_world_command_worker_parity()
	_test_platform_contract()
	if failures.is_empty():
		print("PASS: %d checks across 4 Phase 6.75 suites" % checks)
		quit(0)
		return
	for failure in failures: push_error("PHASE675: " + failure)
	print("FAIL: %d of %d Phase 6.75 checks failed" % [failures.size(), checks])
	quit(1)


func _world(workers: int = 1) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(67501, workers)
	world.set_game_mode(1)
	return world


func _test_thermal_encoding() -> void:
	var world: Variant = _world()
	var layout: Dictionary = world.get_memory_layout()
	_check_equal(layout.temperature_storage, "uint16", "thermal type")
	_check_equal(layout.temperature_bytes_per_cell, 2, "thermal bytes")
	_check_equal(layout.temperature_unit, "quarter_kelvin", "thermal unit")
	_check_equal(layout.temperature_units_per_kelvin, 4, "thermal scale")
	_check_equal(layout.temperature_precision_kelvin, 0.25, "thermal precision")
	_check_equal(layout.temperature_min_units, 0, "thermal minimum units")
	_check_equal(layout.temperature_max_units, 65535, "thermal maximum units")
	_check_equal(layout.temperature_max_kelvin, 16383.75, "thermal maximum Kelvin")
	_check_equal(layout.temperature_ambient_units, 1173, "ambient reference is 293.25 K")
	_check(bool(layout.temperature_saturation), "thermal arithmetic saturates")
	_check_equal(layout.simulation_bytes_per_cell, 9, "thermal migration preserves nine-byte cell")


func _test_combined_physical_worker_parity() -> void:
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(workers)
		world.place_structure(6, Vector2i(0, 0))
		world.place_structure(7, Vector2i(20, 0))
		world.place_structure(5, Vector2i(40, 0))
		world.place_conveyor_line(Vector2i(19, 6), Vector2i(32, 6), 1)
		for x in range(41, 49): world.set_cell(Vector2i(x, 4), STONE)
		world.set_material_state(Vector2i(42, 3), CHARCOAL, 255, 3000)
		world.set_cell_with_metadata(Vector2i(4, 2), RAW, 2386, 1)
		world.set_cell_with_metadata(Vector2i(24, 5), HEAVY, 2386, 2)
		world.set_cell_with_metadata(Vector2i(44, 3), RAW, 2386, 3)
		for tick in 20: world.step()
		hashes.append(world.physical_processing_hash())
		_check(world.get_physical_processing_statistics().heat_reactions_total >= 1, "worker %d executes physical heat" % workers)
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "combined physical hash worker %d" % [1, 2, 4, 8][index])


func _test_world_command_worker_parity() -> void:
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(workers)
		var bus := WorldCommandBus.new()
		var commands: Array[WorldCommand] = [
			WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": 3, "y": 4, "material_id": RAW}, 1),
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 2, "x": 3, "y": 5, "orientation": 0}, 2),
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 5, "x": 10, "y": 10, "orientation": 0}, 3),
		]
		for command in commands: _check(bus.submit(world, command), "worker %d accepts command %d" % [workers, command.type])
		for x in range(11, 19): world.set_cell(Vector2i(x, 14), STONE)
		world.set_material_state(Vector2i(12, 13), CHARCOAL, 255, 3000)
		world.set_cell_with_metadata(Vector2i(14, 13), RAW, 2386, 3)
		for tick in 12: world.step()
		hashes.append(world.physical_processing_hash())
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "WorldCommand replay hash worker %d" % [1, 2, 4, 8][index])


func _test_platform_contract() -> void:
	_check(FileAccess.file_exists("res://native/core/fluid_prototype.hpp"), "portable fluid prototype header exists")
	_check(FileAccess.file_exists("res://native/core/worker_backend.hpp"), "thread backend abstraction exists")
	_check(FileAccess.file_exists("res://tests/benchmark_phase675_render.gd"), "Compatibility render benchmark exists")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
