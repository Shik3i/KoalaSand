extends SceneTree

const EMPTY := 0
const STONE := 1
const SAND := 2
const BELT_LEFT := 1
const BELT_RIGHT := 2
const FUNNEL := 3
const BIN := 4
const FURNACE := 5

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_memory()
	_test_placement_and_removal()
	_test_belts_and_support()
	_test_conflicts_jams_and_double_move()
	_test_cross_chunk_negative_and_provenance()
	_test_funnel_bin_and_furnace()
	_test_streaming_and_determinism()
	_test_long_distance_transport()
	if _failures.is_empty():
		print("PASS: %d checks across 8 Phase 3 suites" % _checks)
		quit(0)
	else:
		for failure in _failures:
			push_error("PHASE3: %s" % failure)
		print("FAIL: %d failures across %d checks" % [_failures.size(), _checks])
		quit(1)


func _test_registry_and_memory() -> void:
	var world := NativeSandWorld.new()
	world.reset(30001, 1)
	var definitions: Array = world.get_structure_definitions()
	_check(definitions.size() >= 5, "Phase 3 definitions preserved")
	var unlocks: Dictionary = {}
	for definition: Dictionary in definitions:
		unlocks[definition["unlock_key"]] = true
	_check(unlocks.has("logistics.conveyor.basic"), "conveyor unlock metadata")
	_check(unlocks.has("logistics.funnel.basic"), "funnel unlock metadata")
	_check(unlocks.has("storage.bin.basic"), "bin unlock metadata")
	_check(unlocks.has("processing.crude_furnace"), "furnace unlock metadata")
	var memory: Dictionary = world.get_memory_layout()
	_check_equal(memory["base_simulation_bytes_per_cell"], 5, "compact base simulation bytes per cell")
	_check_equal(memory["provenance_bytes_per_cell"], 2, "provenance bytes per cell")
	_check_equal(memory["simulation_bytes_per_cell"], 9, "total simulation bytes per cell")
	_check_equal(memory["rgba_cache_bytes_per_cell"], 4, "RGBA bytes per cell")
	_check_equal(memory["structure_bytes_per_cell_when_allocated"], 1, "lazy occupancy byte per cell")


func _test_placement_and_removal() -> void:
	var world: Variant = _empty_world(30002)
	_check(world.can_place_structure(BELT_RIGHT, Vector2i(0, 10)), "valid belt placement")
	_check_equal(world.place_structure(BELT_RIGHT, Vector2i(0, 10)), 1, "belt placed")
	_check_equal(world.get_cell(Vector2i(0, 10)), EMPTY, "structure layer does not replace matter")
	_check_equal(world.get_structure(Vector2i(0, 10)), BELT_RIGHT, "structure occupancy distinct")
	_check(not world.can_place_structure(BELT_LEFT, Vector2i(0, 10)), "overlap rejected")
	world.set_cell(Vector2i(2, 10), STONE)
	_check(not world.can_place_structure(BELT_RIGHT, Vector2i(2, 10)), "terrain placement rejected")
	_check_equal(world.place_conveyor_line(Vector2i(4, 10), Vector2i(12, 10), 1), 9, "batch belt line")
	_check_equal(world.remove_structure_at(Vector2i(0, 10)), 1, "belt removal")
	_check_equal(world.get_cell(Vector2i(0, 10)), EMPTY, "removal preserves matter layer")
	_check_equal(world.remove_structures_rect(Rect2i(4, 10, 9, 1)), 9, "batch removal")


func _test_belts_and_support() -> void:
	var right: Variant = _empty_world(30003)
	right.place_conveyor_line(Vector2i(0, 10), Vector2i(8, 10), 1)
	right.set_cell_with_provenance(Vector2i(2, 9), SAND, 1234)
	right.step()
	_check_equal(right.get_cell(Vector2i(3, 9)), SAND, "right belt moves one cell")
	_check_equal(right.get_provenance(Vector2i(3, 9)), 1234, "right belt preserves provenance")
	right.step()
	_check_equal(right.get_cell(Vector2i(3, 9)), SAND, "belt rate is one cell per two ticks")
	right.step()
	_check_equal(right.get_cell(Vector2i(4, 9)), SAND, "right belt second move")

	var left: Variant = _empty_world(30004)
	left.place_conveyor_line(Vector2i(-8, 10), Vector2i(0, 10), -1)
	left.set_cell(Vector2i(-2, 9), SAND)
	left.step()
	_check_equal(left.get_cell(Vector2i(-3, 9)), SAND, "left belt moves one cell")

	var support: Variant = _empty_world(30005)
	support.place_conveyor_line(Vector2i(-1, 10), Vector2i(1, 10), 1)
	support.set_cell(Vector2i(1, 9), STONE)
	support.set_cell(Vector2i(0, 9), SAND)
	for _tick in 4:
		support.step()
	_check_equal(support.get_cell(Vector2i(0, 9)), SAND, "sand rests on structure support")
	support.remove_structures_rect(Rect2i(-1, 10, 3, 1))
	for _tick in 4:
		support.step()
	_check(_find_material_y(support, SAND, -4, 5, 8, 18) > 9, "support removal wakes falling sand")


func _test_conflicts_jams_and_double_move() -> void:
	var blocked: Variant = _empty_world(30006)
	blocked.place_conveyor_line(Vector2i(0, 10), Vector2i(4, 10), 1)
	blocked.set_cell(Vector2i(1, 9), SAND)
	blocked.set_cell(Vector2i(2, 9), STONE)
	var before: int = _count_material(blocked, SAND, Rect2i(0, 0, 8, 16))
	for _tick in 7:
		blocked.step()
	_check_equal(blocked.get_cell(Vector2i(1, 9)), SAND, "blocked belt jams in place")
	_check_equal(_count_material(blocked, SAND, Rect2i(0, 0, 8, 16)), before, "blocked fixture conserves matter")
	_check(int(blocked.get_structure_statistics()["blocked_belt_attempts"]) >= 1, "blocked attempt telemetry")

	var double_move: Variant = _empty_world(30007)
	double_move.place_conveyor_line(Vector2i(0, 10), Vector2i(5, 10), 1)
	double_move.set_cell(Vector2i(2, 8), SAND)
	double_move.step()
	_check_equal(double_move.get_cell(Vector2i(2, 9)), SAND, "gravity landing is not belt-moved same tick")

	var opposing_hash := ""
	for run in 3:
		var opposing: Variant = _empty_world(30008)
		opposing.place_conveyor_line(Vector2i(-4, 10), Vector2i(0, 10), 1)
		opposing.place_conveyor_line(Vector2i(1, 10), Vector2i(5, 10), -1)
		opposing.set_cell_with_provenance(Vector2i(0, 9), SAND, 101)
		opposing.set_cell_with_provenance(Vector2i(1, 9), SAND, 202)
		for _tick in 20:
			opposing.step()
		_check_equal(_count_material(opposing, SAND, Rect2i(-8, 0, 16, 20)), 2, "opposing belts conserve run=%d" % run)
		if opposing_hash.is_empty():
			opposing_hash = opposing.logistics_state_hash()
		else:
			_check_equal(opposing.logistics_state_hash(), opposing_hash, "opposing deterministic run=%d" % run)


func _test_cross_chunk_negative_and_provenance() -> void:
	var world: Variant = _empty_world(30009)
	_check_equal(world.place_conveyor_line(Vector2i(-70, 20), Vector2i(70, 20), 1), 141, "cross-chunk negative belt line")
	world.set_cell_with_provenance(Vector2i(-66, 19), SAND, 51001)
	world.set_cell_with_provenance(Vector2i(-62, 19), SAND, 62002)
	for _tick in 190:
		world.step()
	var profiles: Dictionary = _profile_counts(world, Rect2i(-80, 0, 180, 32))
	_check_equal(profiles.get(51001, 0), 1, "profile A conserved cross chunk")
	_check_equal(profiles.get(62002, 0), 1, "profile B conserved cross chunk")
	_check(_find_profile_x(world, 51001, Rect2i(-80, 0, 180, 32)) > 0, "profile A crossed zero/chunk boundaries")
	_check_equal(world.get_structure(Vector2i(-64, 20)), BELT_RIGHT, "negative chunk occupancy")


func _test_funnel_bin_and_furnace() -> void:
	var world: Variant = _empty_world(30010)
	var funnel_id: int = world.place_structure(FUNNEL, Vector2i(0, 10))
	_check(funnel_id > 0, "funnel entity placed")
	world.set_cell(Vector2i(1, 9), SAND)
	world.set_cell(Vector2i(5, 9), SAND)
	for _tick in 16:
		world.step()
	_check_equal(_count_material(world, SAND, Rect2i(-4, 0, 16, 32)), 2, "funnel conserves matter")
	_check(_count_material(world, SAND, Rect2i(2, 10, 3, 16)) >= 1, "funnel converges toward outlet")
	var blocked_funnel: Variant = _empty_world(30016)
	blocked_funnel.place_structure(FUNNEL, Vector2i(0, 10))
	blocked_funnel.set_cell(Vector2i(3, 14), STONE)
	for x in range(1, 6):
		blocked_funnel.set_cell(Vector2i(x, 8), SAND)
	for _tick in 20:
		blocked_funnel.step()
	_check_equal(_count_material(blocked_funnel, SAND, Rect2i(-4, 0, 16, 32)), 5, "blocked funnel physically backs up")

	var bin_world: Variant = _empty_world(30011)
	_check(bin_world.place_structure(BIN, Vector2i(20, 10)) > 0, "storage entity placed")
	for x in range(22, 26):
		for y in range(2, 8):
			bin_world.set_cell(Vector2i(x, y), SAND)
	for _tick in 50:
		bin_world.step()
	_check_equal(_count_material(bin_world, SAND, Rect2i(18, 0, 12, 24)), 24, "storage bin physical capacity conserves fill")
	_check(_count_material(bin_world, SAND, Rect2i(21, 10, 6, 7)) > 0, "storage contains physical cells")

	var furnace_world: Variant = _empty_world(30012)
	var furnace_id: int = furnace_world.place_structure(FURNACE, Vector2i(60, 30))
	_check(furnace_id > 0, "furnace stable machine identity")
	_check_equal(furnace_world.get_structure_statistics()["machine_entities"], 1, "furnace machine record")
	_check_equal(furnace_world.remove_structure_at(Vector2i(60, 31)), 14, "whole radiant furnace removed from one occupied cell")
	_check_equal(furnace_world.get_structure_statistics()["machine_entities"], 0, "furnace entity removed")


func _test_streaming_and_determinism() -> void:
	var settings: Dictionary = {"seed": 30013, "width": 16384, "depth": 4096, "sky": 512}
	var streamed: Variant = NativeSandWorld.new()
	streamed.configure_world(settings, 2)
	streamed.request_chunk(Vector2i.ZERO, 0)
	streamed.flush_generation()
	var empty := Vector2i(0, 0)
	streamed.set_cell(empty, EMPTY)
	_check(streamed.place_structure(BELT_RIGHT, empty) > 0, "structure placed in generated world")
	_check(not bool(streamed.get_chunk_state(Vector2i.ZERO)["pristine"]), "structure marks chunk modified")
	_check_equal(streamed.evict_pristine_outside(Rect2i(100, 100, 1, 1), 10), 0, "structure-bearing chunk protected from eviction")

	var expected := ""
	for run in 3:
		var world: Variant = _empty_world(30014)
		world.place_conveyor_line(Vector2i(-10, 10), Vector2i(80, 10), 1)
		for x in range(-8, 20, 3):
			world.set_cell_with_provenance(Vector2i(x, 9), SAND, 1000 + x + 8)
		for _tick in 180:
			world.step()
		if expected.is_empty(): expected = world.logistics_state_hash()
		else: _check_equal(world.logistics_state_hash(), expected, "logistics deterministic run=%d" % run)


func _test_long_distance_transport() -> void:
	var world: Variant = _empty_world(30015)
	_check_equal(world.place_conveyor_line(Vector2i(-1005, 40), Vector2i(1105, 40), 1), 2111, "long-distance line batch")
	world.set_cell_with_provenance(Vector2i(-1000, 39), SAND, 54321)
	for _tick in 4010:
		world.step()
	var x: int = _find_profile_x(world, 54321, Rect2i(-1010, 30, 2140, 20))
	_check(x >= 1000, "provenance-bearing sand moved at least 2000 cells x=%d" % x)
	_check_equal(_profile_counts(world, Rect2i(-1010, 30, 2140, 20)).get(54321, 0), 1, "long transport no loss or duplication")
	print("phase3_long_distance cells=%d hash=%s" % [x + 1000, world.logistics_state_hash()])


func _empty_world(seed: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world


func _count_material(world: Variant, material: int, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			count += 1 if world.get_cell(Vector2i(x, y)) == material else 0
	return count


func _profile_counts(world: Variant, area: Rect2i) -> Dictionary:
	var counts: Dictionary = {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) != SAND:
				continue
			var profile: int = world.get_provenance(cell)
			counts[profile] = counts.get(profile, 0) + 1
	return counts


func _find_profile_x(world: Variant, profile: int, area: Rect2i) -> int:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) == SAND and world.get_provenance(cell) == profile:
				return x
	return -2147483648


func _find_material_y(world: Variant, material: int, min_x: int, max_x: int, min_y: int, max_y: int) -> int:
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if world.get_cell(Vector2i(x, y)) == material:
				return y
	return -1


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
