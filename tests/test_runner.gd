extends SceneTree

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_coordinate_mapping()
	_test_material_registry()
	_test_chunk_storage_and_mutation()
	_test_determinism()
	_test_simulation_clock()
	_test_granular_rules()
	_test_cross_chunk_granular()
	_test_activity_scheduling()
	_test_deterministic_replay()
	_test_golden_simulation()
	_test_visual_foundation()

	if _failures.is_empty():
		print("PASS: %d checks across 11 Phase 0 + Phase 1 suites" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d checks failed" % [_failures.size(), _checks])
	quit(1)


func _test_coordinate_mapping() -> void:
	var cases := [
		[Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0)],
		[Vector2i(127, 127), Vector2i(0, 0), Vector2i(127, 127)],
		[Vector2i(128, 128), Vector2i(1, 1), Vector2i(0, 0)],
		[Vector2i(-1, -1), Vector2i(-1, -1), Vector2i(127, 127)],
		[Vector2i(-128, -128), Vector2i(-1, -1), Vector2i(0, 0)],
		[Vector2i(-129, 255), Vector2i(-2, 1), Vector2i(127, 127)],
	]
	for test_case in cases:
		var world_cell: Vector2i = test_case[0]
		var expected_chunk: Vector2i = test_case[1]
		var expected_local: Vector2i = test_case[2]
		_check_equal(WorldConfig.world_to_chunk(world_cell), expected_chunk, "world to chunk %s" % world_cell)
		_check_equal(WorldConfig.world_to_local(world_cell), expected_local, "world to local %s" % world_cell)
		_check_equal(
			WorldConfig.chunk_local_to_world(expected_chunk, expected_local),
			world_cell,
			"coordinate round trip %s" % world_cell
		)
	for index in [0, 127, 128, 16383]:
		_check_equal(WorldConfig.local_to_index(WorldConfig.index_to_local(index)), index, "index round trip %d" % index)


func _test_material_registry() -> void:
	var registry := MaterialRegistry.new()
	_check_equal(registry.load_directory(), OK, "registry loads")
	_check_equal(registry.size(), 28, "registry definition count")
	_check_equal(registry.get_id(&"raw_sand"), 2, "stable Raw Sand ID")
	_check_equal(registry.get_id(&"coal"), 4, "stable Coal ID")
	_check_equal(registry.get_id(&"bedrock"), 5, "stable Bedrock ID")
	_check(registry.get_definition(3) != null, "valid material lookup")
	_check(registry.get_definition(9999) == null, "invalid material lookup")
	var duplicate := MaterialDefinition.new()
	duplicate.stable_id = 3
	duplicate.key = &"duplicate"
	_check_equal(registry.register(duplicate), ERR_ALREADY_EXISTS, "duplicate stable ID rejected")


func _test_chunk_storage_and_mutation() -> void:
	var registry := MaterialRegistry.new()
	_check_equal(registry.load_directory(), OK, "world registry loads")
	var world := CellWorld.new(42, registry)
	_check_equal(world.get_cell(Vector2i(1000, 1000)), MaterialRegistry.EMPTY_ID, "missing chunks read as empty")
	_check_equal(world.chunk_count(), 0, "read does not allocate chunk")
	for position in [Vector2i(-129, 0), Vector2i(-1, -1), Vector2i(0, 0), Vector2i(128, 128)]:
		_check_equal(world.set_cell(position, 2), OK, "set valid cell %s" % position)
		_check_equal(world.get_cell(position), 2, "get stored cell %s" % position)
	_check_equal(world.chunk_count(), 4, "cells span four chunks")
	_check_equal(world.set_cell(Vector2i.ZERO, 9999), ERR_INVALID_PARAMETER, "invalid material mutation rejected")

	var origin_chunk := world.get_chunk(Vector2i.ZERO)
	origin_chunk.mark_clean()
	var previous_revision := origin_chunk.revision
	world.set_temperature(Vector2i(2, 3), 12345)
	_check_equal(world.get_temperature(Vector2i(2, 3)), 12345, "temperature round trip")
	_check(origin_chunk.is_dirty(), "temperature mutation marks chunk dirty")
	_check_equal(origin_chunk.revision, previous_revision + 1, "mutation advances revision")
	origin_chunk.sleep()
	world.set_cell(Vector2i(3, 3), 1)
	_check((origin_chunk.state_flags & SimChunk.StateFlag.ACTIVE) != 0, "mutation wakes sleeping chunk")
	_check_equal(world.approximate_backing_bytes(), 4 * 147456, "world backing byte estimate")


func _test_determinism() -> void:
	var first := GeologySampler.new(8675309)
	var second := GeologySampler.new(8675309)
	var different := GeologySampler.new(8675310)
	for coordinate in [Vector2i.ZERO, Vector2i(-81, 14), Vector2i(999, -333)]:
		_check_equal(first.sample_region(coordinate), second.sample_region(coordinate), "same geology seed %s" % coordinate)
	_check(first.sample_region(Vector2i(7, 9)) != different.sample_region(Vector2i(7, 9)), "different geology seed differs")
	_check_equal(
		DeterministicHash.hash_2d(12, Vector2i(-4, 99), 5),
		DeterministicHash.hash_2d(12, Vector2i(-4, 99), 5),
		"stable deterministic hash"
	)


func _test_simulation_clock() -> void:
	var single_delta := SimulationClock.new(30)
	var split_delta := SimulationClock.new(30)
	_check_equal(single_delta.advance(1.0), 30, "one-second clock step")
	var split_ticks := 0
	for _index in 100:
		split_ticks += split_delta.advance(0.01)
	_check_equal(split_ticks, 30, "split render deltas produce same ticks")
	_check_equal(split_delta.tick_index, single_delta.tick_index, "tick index independent of render partitions")
	_check_equal(split_delta.set_speed(2), OK, "2x speed accepted")
	_check_equal(split_delta.advance(0.5), 30, "2x speed clock")
	_check_equal(split_delta.set_speed(3), ERR_INVALID_PARAMETER, "unsupported speed rejected")
	split_delta.set_paused(true)
	_check_equal(split_delta.advance(10.0), 0, "paused clock consumes no ticks")


func _test_granular_rules() -> void:
	var straight := _new_world(101)
	straight.set_cell(Vector2i.ZERO, straight.materials.get_id(&"raw_sand"))
	var straight_sim := GranularSimulator.new(straight)
	_check_equal(straight_sim.step(), 1, "straight fall moves once")
	_check_equal(straight.get_cell(Vector2i(0, 1)), 2, "straight fall destination")
	_check_equal(straight.get_cell(Vector2i(0, 2)), 0, "particle does not double-move")
	straight_sim.step()
	_check_equal(straight.get_cell(Vector2i(0, 2)), 2, "straight fall advances next tick")

	var supported := _new_world(102)
	supported.set_cell(Vector2i.ZERO, 2)
	for x in range(-1, 2):
		supported.set_cell(Vector2i(x, 1), 1)
	var supported_sim := GranularSimulator.new(supported)
	_check_equal(supported_sim.step(), 0, "solid support prevents movement")
	_check_equal(supported.get_cell(Vector2i.ZERO), 2, "supported sand remains")

	var diagonal := _new_world(103)
	diagonal.set_cell(Vector2i.ZERO, 2)
	diagonal.set_cell(Vector2i(0, 1), 1)
	diagonal.set_cell(Vector2i(1, 1), 1)
	var diagonal_sim := GranularSimulator.new(diagonal)
	_check_equal(diagonal_sim.step(), 1, "single valid diagonal moves")
	_check_equal(diagonal.get_cell(Vector2i(-1, 1)), 2, "single valid diagonal selected")

	var tie_a := _new_world(104)
	var tie_b := _new_world(104)
	for world in [tie_a, tie_b]:
		world.set_cell(Vector2i.ZERO, 2)
		world.set_cell(Vector2i(0, 1), 1)
	var tie_a_sim := GranularSimulator.new(tie_a)
	var tie_b_sim := GranularSimulator.new(tie_b)
	tie_a_sim.step()
	tie_b_sim.step()
	_check_equal(tie_a.material_state_hash(), tie_b.material_state_hash(), "two-diagonal choice deterministic")
	_check(tie_a.get_cell(Vector2i(-1, 1)) == 2 or tie_a.get_cell(Vector2i(1, 1)) == 2, "two-diagonal choice is valid")

	var water_block := _new_world(105)
	water_block.set_cell(Vector2i.ZERO, 2)
	water_block.set_cell(Vector2i(0, 1), 3)
	water_block.set_cell(Vector2i(-1, 1), 1)
	water_block.set_cell(Vector2i(1, 1), 1)
	var water_sim := GranularSimulator.new(water_block)
	_check_equal(water_sim.step(), 0, "water remains non-flowing and non-displaced")
	_check_equal(water_block.get_cell(Vector2i(0, 1)), 3, "water definition remains static")


func _test_cross_chunk_granular() -> void:
	var vertical := _new_world(201)
	vertical.set_cell(Vector2i(0, 127), 2)
	var vertical_sim := GranularSimulator.new(vertical)
	vertical_sim.step()
	_check_equal(vertical.get_cell(Vector2i(0, 128)), 2, "vertical chunk-edge fall")
	_check(vertical.get_chunk(Vector2i(0, 1)).is_dirty(), "vertical destination chunk dirty")

	var right := _new_world(202)
	right.set_cell(Vector2i(127, 0), 2)
	right.set_cell(Vector2i(127, 1), 1)
	right.set_cell(Vector2i(126, 1), 1)
	var right_sim := GranularSimulator.new(right)
	right_sim.step()
	_check_equal(right.get_cell(Vector2i(128, 1)), 2, "right chunk-edge diagonal")

	var left := _new_world(203)
	left.set_cell(Vector2i(-128, 0), 2)
	left.set_cell(Vector2i(-128, 1), 1)
	left.set_cell(Vector2i(-127, 1), 1)
	var left_sim := GranularSimulator.new(left)
	left_sim.step()
	_check_equal(left.get_cell(Vector2i(-129, 1)), 2, "left chunk-edge diagonal")

	var corner := _new_world(204)
	corner.set_cell(Vector2i(127, 127), 2)
	corner.set_cell(Vector2i(127, 128), 1)
	corner.set_cell(Vector2i(126, 128), 1)
	var corner_sim := GranularSimulator.new(corner)
	corner_sim.step()
	_check_equal(corner.get_cell(Vector2i(128, 128)), 2, "corner chunk transition")

	var negative := _new_world(205)
	negative.set_cell(Vector2i(-129, -129), 2)
	var negative_sim := GranularSimulator.new(negative)
	negative_sim.step()
	_check_equal(negative.get_cell(Vector2i(-129, -128)), 2, "negative-coordinate chunk transition")


func _test_activity_scheduling() -> void:
	var stable := _new_world(301)
	for x in range(-8, 9):
		stable.set_cell(Vector2i(x, 10), 1)
	for y in range(4, 10):
		for x in range(-2, 3):
			stable.set_cell(Vector2i(x, y), 2)
	var stable_sim := GranularSimulator.new(stable)
	var last_movement_tick := -1
	for tick in 80:
		if stable_sim.step() > 0:
			last_movement_tick = tick
	_check(last_movement_tick >= 0, "pile reports movement before settling")
	_check_equal(stable_sim.last_movements, 0, "stable pile stops reporting movement")
	_check_equal(stable.active_chunk_count(), 0, "stable chunks eventually sleep")
	_check_equal(stable.sleeping_chunk_count(), stable.chunk_count(), "all stable chunks sleeping")

	var sleeping_origin := stable.get_chunk(Vector2i.ZERO)
	stable.set_cell(Vector2i(4, 0), 2)
	_check(sleeping_origin.is_active(), "paint into sleeping chunk wakes it")

	var boundary := _new_world(302)
	boundary.set_cell(Vector2i(0, 127), 2)
	for x in range(-1, 2):
		boundary.set_cell(Vector2i(x, 128), 1)
	var unrelated := boundary.get_or_create_chunk(Vector2i(10, 10))
	unrelated.sleep()
	var boundary_sim := GranularSimulator.new(boundary)
	for _tick in WorldConfig.CHUNK_SLEEP_AFTER_STABLE_TICKS:
		boundary_sim.step()
	_check(boundary.get_chunk(Vector2i.ZERO).is_sleeping(), "supported upper chunk sleeps")
	boundary.set_cell(Vector2i(0, 128), 0)
	_check(boundary.get_chunk(Vector2i.ZERO).is_active(), "support removal wakes dependent upper chunk")
	_check(unrelated.is_sleeping(), "boundary disturbance does not wake distant chunk")
	boundary_sim.step()
	_check_equal(boundary.get_cell(Vector2i(0, 128)), 2, "woken boundary sand resumes falling")
	_check(boundary.get_chunk(Vector2i(0, 1)).is_active(), "movement wakes destination chunk")

	var no_allocate := _new_world(303)
	no_allocate.set_cell(Vector2i(0, 0), 1)
	var allocated_before := no_allocate.chunk_count()
	for coordinate in [Vector2i(5000, 5000), Vector2i(-5000, -5000)]:
		_check_equal(no_allocate.get_cell(coordinate), 0, "missing-space query is empty")
		no_allocate.set_cell(coordinate, 0)
	_check_equal(no_allocate.chunk_count(), allocated_before, "empty query/erase does not allocate chunks")


func _test_deterministic_replay() -> void:
	var first := GranularFixtures.build("split_over_obstacle", 401)
	var second := GranularFixtures.build("split_over_obstacle", 401)
	var first_sim := GranularSimulator.new(first)
	var second_sim := GranularSimulator.new(second)
	for _tick in 100:
		_check_equal(first_sim.step(), second_sim.step(), "replay movement count at tick %d" % _tick)
	_check_equal(first.material_state_hash(), second.material_state_hash(), "100-tick deterministic replay hash")


func _test_golden_simulation() -> void:
	var expected_hashes := {
		"single_falling_column": "18a0bbfc",
		"small_sand_pile": "1471d40f",
		"narrow_funnel": "23dc3106",
		"split_over_obstacle": "45a4677e",
		"cross_chunk_pile": "20c81915",
	}
	for fixture_name in GranularFixtures.GOLDEN_TICKS.keys():
		var world := GranularFixtures.build(fixture_name)
		var simulator := GranularSimulator.new(world)
		for _tick in GranularFixtures.GOLDEN_TICKS[fixture_name]:
			simulator.step()
		_check_equal(world.material_state_hash(), expected_hashes[fixture_name], "golden %s" % fixture_name)


func _test_visual_foundation() -> void:
	var world := _new_world(501)
	var sand := world.materials.get_id(&"raw_sand")
	var stone := world.materials.get_id(&"stone")
	var water := world.materials.get_id(&"water")
	for material_id in [sand, stone, water]:
		var definition := world.materials.get_definition(material_id)
		_check(definition.visual_palette.size() >= 4, "material %d has restrained visual palette" % material_id)
		_check((definition.visual_flags & MaterialDefinition.VisualFlag.FINE_VARIATION) != 0, "material %d enables deterministic fine variation" % material_id)

	for y in range(3):
		for x in range(3):
			world.initialize_cell(Vector2i(x, y), stone)
	var surface := MaterialVisualResolver.sample(world, Vector2i(1, 0), stone)
	var interior := MaterialVisualResolver.sample(world, Vector2i(1, 1), stone)
	_check_equal(surface, MaterialVisualResolver.sample(world, Vector2i(1, 0), stone), "visual sampling deterministic")
	_check(surface != interior, "neighbor-aware exposed surface differs from interior")

	var varied_colors: Dictionary = {}
	for x in range(16, 48):
		world.initialize_cell(Vector2i(x, 8), sand)
		varied_colors[MaterialVisualResolver.sample(world, Vector2i(x, 8), sand).to_html()] = true
	_check(varied_colors.size() > 1, "deterministic palette produces fine per-cell variation")
	_check(varied_colors.size() <= 16, "fine variation remains palette-bounded")

	var origin_chunk := world.get_chunk(Vector2i.ZERO)
	var first_image := MaterialVisualResolver.build_chunk_image(world, origin_chunk)
	var second_image := MaterialVisualResolver.build_chunk_image(world, origin_chunk)
	_check_equal(first_image.get_data(), second_image.get_data(), "chunk image bytes deterministic")

	var boundary := _new_world(502)
	for position in [Vector2i(126, 8), Vector2i(127, 7), Vector2i(127, 8), Vector2i(127, 9), Vector2i(128, 8)]:
		boundary.initialize_cell(position, stone)
	var left_chunk := boundary.get_chunk(Vector2i.ZERO)
	var right_chunk := boundary.get_chunk(Vector2i.RIGHT)
	left_chunk.mark_clean()
	right_chunk.mark_clean()
	var joined_color := MaterialVisualResolver.sample(boundary, Vector2i(127, 8), stone)
	boundary.set_cell(Vector2i(128, 8), MaterialRegistry.EMPTY_ID)
	var exposed_color := MaterialVisualResolver.sample(boundary, Vector2i(127, 8), stone)
	_check(right_chunk.is_dirty(), "boundary mutation dirties owning chunk")
	_check(left_chunk.is_dirty(), "boundary mutation invalidates visual neighbor chunk")
	_check(joined_color != exposed_color, "cross-chunk neighbor changes rendered edge")

	left_chunk.sleep()
	left_chunk.mark_clean()
	_check_equal(boundary.initialize_cell(Vector2i(4, 4), sand), OK, "bulk initialization accepts valid material")
	_check(left_chunk.is_sleeping(), "bulk initialization does not wake simulation")
	_check(left_chunk.is_dirty(), "bulk initialization still invalidates rendering")
	_check_equal(boundary.initialize_cell(Vector2i(4, 4), 9999), ERR_INVALID_PARAMETER, "bulk initialization rejects invalid material")


func _new_world(seed: int) -> CellWorld:
	var materials := MaterialRegistry.new()
	assert(materials.load_directory() == OK)
	return CellWorld.new(seed, materials)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
