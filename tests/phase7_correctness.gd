extends SceneTree

const EMPTY := 0
const STONE := 1
const RAW := 2
const WATER := 3
const GATE := 9
const GATE_CONTROL := 13

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_representation_and_lazy_plane()
	_test_gravity_lateral_sleep_and_conservation()
	_test_cross_chunk_and_negative_coordinates()
	_test_streaming_boundary_deferral()
	_test_sand_displacement()
	_test_temperature_transfer_and_mixing()
	_test_gate_and_level_sensor()
	_test_worker_parity()
	_test_world_command_replay()
	if failures.is_empty():
		print("PASS: %d checks across 9 Phase 7 suites" % checks)
		quit(0)
		return
	for failure in failures: push_error("PHASE7: " + failure)
	print("FAIL: %d of %d Phase 7 checks failed" % [failures.size(), checks])
	quit(1)


func _world(seed: int = 70001, workers: int = 1, chunks := Rect2i(-2, -2, 4, 4)) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.allocate_chunk_rect(chunks)
	return world


func _test_representation_and_lazy_plane() -> void:
	var world: Variant = _world()
	var layout: Dictionary = world.get_memory_layout()
	_check_equal(layout.liquid_mass_bytes_per_allocated_fluid_chunk, 4096, "fluid plane size")
	_check_equal(layout.liquid_mass_plane_chunks, 0, "dry/full-only chunks start without plane")
	_check_equal(world.set_water_mass(Vector2i.ZERO, 255, 1173), OK, "full Water accepted")
	_check_equal(world.get_cell(Vector2i.ZERO), WATER, "positive mass owns Water material")
	_check_equal(world.get_liquid_mass(Vector2i.ZERO), 255, "full Water mass")
	_check_equal(world.get_memory_layout().liquid_mass_plane_chunks, 0, "full Water uses implicit mass")
	_check_equal(world.set_water_mass(Vector2i(1, 0), 64, 1200), OK, "partial Water accepted")
	_check_equal(world.get_memory_layout().liquid_mass_plane_chunks, 1, "partial Water allocates one plane")
	_check_equal(world.get_memory_layout().liquid_mass_backing_bytes, 4096, "one plane exact bytes")
	_check_equal(world.set_water_mass(Vector2i(1, 0), 0), OK, "zero mass accepted")
	_check_equal(world.get_cell(Vector2i(1, 0)), EMPTY, "zero mass clears material")
	_check_equal(world.get_liquid_mass(Vector2i(1, 0)), 0, "zero mass leaves no stale state")
	_check_equal(world.set_water_mass(Vector2i(2, 0), 256), ERR_INVALID_PARAMETER, "mass above uint8 rejected")


func _test_gravity_lateral_sleep_and_conservation() -> void:
	var world: Variant = _world(70002)
	for x in range(-12, 13): world.set_cell(Vector2i(x, 12), STONE)
	for y in range(4, 12):
		world.set_cell(Vector2i(-12, y), STONE)
		world.set_cell(Vector2i(12, y), STONE)
	for x in range(-5, 6): world.set_water_mass(Vector2i(x, 2), 255, 1173)
	var before: int = world.get_total_water_mass()
	var moved_down := false
	for tick in 120:
		world.step()
		moved_down = moved_down or world.get_cell(Vector2i(0, 11)) == WATER
	_check(moved_down, "Water falls into basin")
	_check_equal(world.get_total_water_mass(), before, "basin conserves exact mass")
	for tick in 4: world.step()
	var stats: Dictionary = world.get_fluid_statistics()
	_check_equal(stats.fluid_cells_visited, 0, "settled basin visits zero cells")
	_check_equal(stats.fluid_cells_active, 0, "settled basin has zero active cells")
	var previous_mass := -1
	var local_equilibrium := true
	for x in range(-11, 12):
		var mass := int(world.get_liquid_mass(Vector2i(x, 11)))
		if mass > 0 and previous_mass >= 0: local_equilibrium = local_equilibrium and absi(mass - previous_mass) <= 2
		if mass > 0: previous_mass = mass
	_check(local_equilibrium, "supported Water surface reaches deterministic two-unit deadband")


func _test_cross_chunk_and_negative_coordinates() -> void:
	var world: Variant = _world(70003, 4, Rect2i(-3, -2, 6, 5))
	for x in range(-70, 70): world.set_cell(Vector2i(x, 66), STONE)
	var before := 0
	for x in range(-66, -60):
		world.set_water_mass(Vector2i(x, 60), 255)
		before += 255
	for tick in 24: world.step()
	_check_equal(world.get_total_water_mass(), before, "negative cross-chunk flow conserves mass")
	_check(world.get_fluid_statistics().fluid_border_crossings >= 0, "cross-chunk telemetry available")
	var found_other_chunk := false
	for x in range(-64, -56): found_other_chunk = found_other_chunk or world.get_liquid_mass(Vector2i(x, 65)) > 0
	_check(found_other_chunk, "Water crosses x=-64 seam")


func _test_streaming_boundary_deferral() -> void:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 70031, "width": 4096, "depth": 1024, "sky": 256, "surface_baseline": 0, "surface_amplitude": 0, "water_frequency": 0.5}, 2)
	world.set_game_mode(1)
	world.request_chunk(Vector2i(0, -1), 0)
	world.flush_generation()
	world.set_cell(Vector2i(63, -9), STONE)
	world.set_cell(Vector2i(62, -10), STONE)
	world.set_cell(Vector2i(62, -9), STONE)
	_check_equal(world.set_water_mass(Vector2i(63, -10), 255), OK, "Creative Water accepted at streaming edge")
	var before: int = world.get_total_water_mass()
	world.step()
	_check_equal(world.get_generation_state(Vector2i(1, -1)), 1, "active Water prioritizes ungenerated neighbor halo")
	_check_equal(world.get_total_water_mass(), before, "ungenerated boundary defers without Water loss")
	_check_equal(world.get_liquid_mass(Vector2i(63, -10)), 255, "Water remains contained before neighbor publication")
	world.flush_generation()
	for _tick in 4: world.step()
	_check_equal(world.get_total_water_mass(), before, "published streaming continuation conserves Water")
	var crossed := false
	for y in range(-10, -4):
		for x in range(64, 69): crossed = crossed or world.get_liquid_mass(Vector2i(x, y)) > 0
	_check(crossed, "Water resumes across published streaming boundary")


func _test_sand_displacement() -> void:
	var world: Variant = _world(70004)
	world.set_cell(Vector2i(0, 4), STONE)
	world.set_cell(Vector2i(-1, 4), STONE)
	world.set_cell(Vector2i(1, 4), STONE)
	world.set_water_mass(Vector2i(0, 2), 200, 1300)
	world.set_cell_with_metadata(Vector2i(0, 1), RAW, 2386, 54321)
	var water_before: int = world.get_total_water_mass()
	for tick in 3: world.step()
	_check_equal(world.get_total_water_mass(), water_before, "sand displacement conserves Water mass")
	_check_equal(_count_material(world, RAW, Rect2i(-3, -2, 7, 8)), 1, "sand displacement conserves sand count")
	var sand_position := _find_material(world, RAW, Rect2i(-3, -2, 7, 8))
	_check(sand_position.y >= 2, "dense Raw Sand sinks into Water")
	_check_equal(world.get_provenance(sand_position), 2386, "sand displacement preserves provenance")
	_check_equal(world.get_mineral_signature(sand_position), 54321, "sand displacement preserves signature")


func _test_temperature_transfer_and_mixing() -> void:
	var world: Variant = _world(70005)
	for x in range(-1, 3): world.set_cell(Vector2i(x, 2), STONE)
	world.set_cell(Vector2i(-1, 1), STONE)
	world.set_cell(Vector2i(2, 1), STONE)
	world.set_water_mass(Vector2i(0, 1), 200, 1200)
	world.set_water_mass(Vector2i(1, 1), 50, 1450)
	var before: int = world.get_total_phase_family_mass(1)
	world.step()
	_check_equal(world.get_total_phase_family_mass(1), before, "thermal mixing conserves Water-family mass")
	var mixed_cell := Vector2i(1, 1) if world.get_liquid_mass(Vector2i(1, 1)) == 125 else Vector2i(0, 1)
	_check_equal(world.get_liquid_mass(mixed_cell), 125, "lateral transfer moves exact half-difference")
	_check(world.get_temperature(mixed_cell) > 1200 and world.get_temperature(mixed_cell) < 1450, "mass-weighted temperature remains between source temperatures")
	var source_cell := Vector2i.ZERO + Vector2i(0, 1) if mixed_cell == Vector2i(1, 1) else Vector2i(1, 1)
	_check(world.get_temperature(source_cell) >= 1150 and world.get_temperature(source_cell) < 1450, "partial source remains within conservative diffusion bounds")


func _test_gate_and_level_sensor() -> void:
	var world: Variant = _world(70006)
	for x in range(-4, 5): world.set_cell(Vector2i(x, 6), STONE)
	for y in range(2, 6):
		world.set_cell(Vector2i(-1, y), STONE)
		world.set_cell(Vector2i(1, y), STONE)
	_check(world.place_structure(GATE, Vector2i(0, 4)) > 0, "Control Gate placed")
	_check_equal(world.set_water_mass(Vector2i(0, 3), 255), OK, "dam Water placed")
	for tick in 3: world.step()
	_check_equal(world.get_liquid_mass(Vector2i(0, 5)), 0, "closed Gate blocks Water")
	var sensor: int = world.create_automation_component(3, Vector2i(-3, 1), {"target_position": Vector2i(0, 3), "probe_size": Vector2i(1, 1), "mode": 1})
	var control: int = world.create_automation_component(GATE_CONTROL, Vector2i(3, 1), {"target_position": Vector2i(0, 4)})
	_check(sensor > 0 and control > 0, "Level Sensor and Gate Control created")
	_check(world.create_automation_connection(sensor, 0, control, 0) > 0, "Water automation connected")
	var gate_opened := false
	for tick in 5:
		world.step()
		gate_opened = gate_opened or bool(world.get_automation_component_state(control).gate_actual_open)
	_check(gate_opened, "Level Sensor opens physical Gate")
	for tick in 5: world.step()
	_check(world.get_liquid_mass(Vector2i(0, 5)) > 0, "Water flows through automated Gate")
	var mass_before_close: int = world.get_total_water_mass()
	world.set_automation_input_for_test(control, 0, 0)
	world.step()
	var gate_state: Dictionary = world.get_automation_component_state(control)
	_check_equal(world.get_total_water_mass(), mass_before_close, "Gate close attempt never deletes Water")
	_check(not bool(gate_state.gate_close_blocked) or bool(gate_state.gate_actual_open), "blocked close leaves Gate open")


func _test_worker_parity() -> void:
	var hashes: Array[String] = []
	var masses: Array[int] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(70007, workers, Rect2i(-2, -2, 5, 5))
		for x in range(-30, 31): world.set_cell(Vector2i(x, 24), STONE)
		for x in range(-20, 1):
			for y in range(3, 12): world.set_water_mass(Vector2i(x, y), 255, 1250 + ((x + y) & 31))
		for x in range(2, 18): world.set_cell_with_metadata(Vector2i(x, 2), RAW, 2386, 40000 + x)
		world.place_structure(GATE, Vector2i(0, 20))
		var gate: int = world.create_automation_component(GATE_CONTROL, Vector2i(4, 18), {"target_position": Vector2i(0, 20)})
		world.set_automation_input_for_test(gate, 0, 1)
		var initial_mass: int = world.get_total_phase_family_mass(1)
		for tick in 90: world.step()
		hashes.append(world.authoritative_physical_hash())
		masses.append(world.get_total_phase_family_mass(1))
		_check_equal(masses[-1], initial_mass, "worker %d conserves Water family" % workers)
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "physical hash parity worker %d" % [1, 2, 4, 8][index])
	print("phase7_worker_parity workers=[1, 2, 4, 8] hash=%s mass=%d" % [hashes[0], masses[0]])


func _test_world_command_replay() -> void:
	var logs: Array[PackedByteArray] = []
	var hashes: Array[String] = []
	for workers in [1, 8]:
		var world: Variant = _world(70008, workers)
		var bus := WorldCommandBus.new()
		if logs.is_empty():
			for x in range(-4, 5): bus.submit(world, WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": x, "y": 8, "material_id": STONE}, 1))
			for y in range(2, 7): bus.submit(world, WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": -2, "y": y, "material_id": WATER}, 2))
			bus.submit(world, WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": GATE, "x": 0, "y": 7}, 3))
			logs = bus.serialize_log()
		else:
			_check(bus.replay(world, logs), "WorldCommand Water replay accepted")
		for tick in 40: world.step()
		hashes.append(world.authoritative_physical_hash())
	_check_equal(hashes[1], hashes[0], "WorldCommand Water replay serial/parallel parity")
	print("phase7_world_command_replay workers=[1, 8] hash=%s" % hashes[0])


func _count_material(world: Variant, material: int, area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x): count += 1 if world.get_cell(Vector2i(x, y)) == material else 0
	return count


func _find_material(world: Variant, material: int, area: Rect2i) -> Vector2i:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if world.get_cell(Vector2i(x, y)) == material: return Vector2i(x, y)
	return Vector2i(999999, 999999)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])
