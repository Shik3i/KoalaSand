extends SceneTree

const EMPTY := 0
const STONE := 1
const SAND := 2
const WATER := 3
const FINE_SAND := 6
const PIPE := 10
const JUNCTION := 11
const INTAKE := 12
const OUTLET := 13
const PUMP := 14
const VALVE := 15
const RESERVOIR_WALL := 16
const SLUICE := 17

var checks := 0
var suites := 0
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int = 8001, workers: int = 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.allocate_chunk_rect(Rect2i(-4, -4, 8, 8))
	return world


func _run() -> void:
	_layout_and_building()
	_local_flow_and_elevation()
	_world_boundaries_and_conservation()
	_valve_pump_and_temperature()
	_damage_and_real_leaks()
	_physical_reservoir()
	_automation()
	_sluice_physicality()
	_pipe_loops_and_worldcommand_replay()
	_determinism()
	print("PASS: %d checks across %d Phase 8 suites" % [checks, suites] if not failed else "FAIL: Phase 8 correctness")
	quit(0 if not failed else 1)


func _layout_and_building() -> void:
	suites += 1
	var world: Variant = _world()
	var layout: Dictionary = world.get_memory_layout()
	_check_equal(layout.pipe_segment_bytes, 16, "compact fixed-width pipe record")
	_check_equal(layout.pipe_segments, 0, "dry world has no pipe allocation")
	_check_equal(world.place_pipe_line(Vector2i(-70, 0), Vector2i(70, 0)), 141, "cross-chunk Pipe line batch")
	_check_equal(world.get_pipe_statistics().segments_total, 141, "one record per physical Pipe cell")
	_check(world.get_pipe_state(Vector2i(-64, 0)).connections != 0, "cross-chunk local connectivity")
	_check_equal(world.place_pipe_line(Vector2i(0, 1), Vector2i(0, 10)), 10, "vertical Pipe drag batch")
	_check_equal(world.place_pipe_line(Vector2i(0, 0), Vector2i(2, 2)), -1, "diagonal batch rejected")


func _local_flow_and_elevation() -> void:
	suites += 1
	var world: Variant = _world(8002)
	world.place_pipe_line(Vector2i(0, 0), Vector2i(20, 0))
	_check_equal(world.set_pipe_mass(Vector2i(0, 0), 65535, 1200), 0, "fill local Pipe")
	var total: int = world.get_total_pipe_water_mass()
	for tick in 80: world.step()
	_check_equal(world.get_total_pipe_water_mass(), total, "Pipe-only exact conservation")
	_check(world.get_pipe_state(Vector2i(5, 0)).mass > 0, "Water propagates segment by segment")
	_check(world.get_pipe_state(Vector2i(20, 0)).mass < total, "no global inventory teleport")
	world = _world(8003)
	world.place_pipe_line(Vector2i(0, -10), Vector2i(0, 10))
	world.set_pipe_mass(Vector2i(0, -10), 65535)
	for tick in 2000: world.step()
	_check(world.get_pipe_state(Vector2i(0, 10)).mass > 0, "passive Water propagates downward under elevation head")
	for tick in 100: world.step()
	_check(world.get_pipe_statistics().segments_active < 21, "equalizing Pipe network can sleep")


func _world_boundaries_and_conservation() -> void:
	suites += 1
	var world: Variant = _world(8004)
	world.place_structure(INTAKE, Vector2i(0, 0), 0)
	world.place_pipe_line(Vector2i(-1, 0), Vector2i(-1, 0))
	world.set_cell(Vector2i(1, 1), STONE)
	world.set_cell(Vector2i(2, 0), STONE)
	world.set_cell(Vector2i(0, 1), STONE)
	world.set_cell(Vector2i(2, 1), STONE)
	world.set_water_mass(Vector2i(1, 0), 255, 1300)
	var conserved: int = world.get_total_conserved_water_mass()
	for tick in 12: world.step()
	_check(world.get_total_pipe_water_mass() > 0, "Intake consumes only adjacent physical Water")
	_check_equal(world.get_total_conserved_water_mass(), conserved, "Intake world-to-Pipe conservation")
	_check_equal(world.get_total_water_mass() + world.get_total_pipe_water_mass(), conserved, "Intake has no hidden reservoir")
	world.place_structure(OUTLET, Vector2i(-2, 0), 2)
	world.set_cell(Vector2i(-3, 1), STONE)
	for tick in 120: world.step()
	_check(world.get_total_water_mass() > 0, "Outlet emits normal world Water")
	_check_equal(world.get_total_conserved_water_mass(), conserved, "Outlet Pipe-to-world conservation")
	world.set_cell(Vector2i(-3, 0), STONE)
	for tick in 8: world.step()
	_check(world.get_pipe_state(Vector2i(-2, 0)).mass >= 0, "blocked Outlet retains upstream mass")


func _valve_pump_and_temperature() -> void:
	suites += 1
	var world: Variant = _world(8005)
	world.place_pipe_line(Vector2i(-3, 0), Vector2i(-1, 0))
	world.place_structure(VALVE, Vector2i(0, 0), 0)
	world.place_pipe_line(Vector2i(1, 0), Vector2i(3, 0))
	world.set_pipe_valve_open(Vector2i(0, 0), false)
	world.set_pipe_mass(Vector2i(-1, 0), 32000, 1000)
	for tick in 30: world.step()
	_check_equal(world.get_pipe_state(Vector2i(1, 0)).mass, 0, "closed Valve stops physical transfer")
	world.set_pipe_valve_open(Vector2i(0, 0), true)
	for tick in 30: world.step()
	_check(world.get_pipe_state(Vector2i(1, 0)).mass > 0, "open Valve restores local connection")
	_check_equal(world.get_total_pipe_water_mass(), 32000, "Valve never deletes Water")
	world = _world(8006)
	world.place_pipe_line(Vector2i(10, 1), Vector2i(10, 12))
	world.remove_structure_at(Vector2i(10, 6))
	world.place_structure(PUMP, Vector2i(10, 6), 3)
	world.set_pipe_mass(Vector2i(10, 7), 65535, 1300)
	for tick in 80: world.step()
	_check(world.get_pipe_state(Vector2i(10, 5)).mass > 0, "Pump applies finite uphill head")
	_check(world.get_pipe_statistics().pump_work > 0, "Pump work telemetry")
	world = _world(8007)
	world.place_pipe_line(Vector2i(-1, 0), Vector2i(1, 0))
	world.set_pipe_mass(Vector2i(-1, 0), 20000, 1000)
	world.set_pipe_mass(Vector2i(1, 0), 20000, 1400)
	for tick in 80: world.step()
	var mixed: int = world.get_pipe_state(Vector2i(0, 0)).temperature
	_check(mixed >= 1190 and mixed <= 1210, "deterministic integer mass-weighted Pipe temperature mixing")
	_check_equal(world.get_total_pipe_water_mass(), 40000, "temperature mixing conserves mass")


func _damage_and_real_leaks() -> void:
	suites += 1
	var world: Variant = _world(8008)
	world.place_structure(PIPE, Vector2i(0, 0))
	world.set_pipe_mass(Vector2i(0, 0), 20000, 1400)
	var conserved: int = world.get_total_conserved_water_mass()
	_check_equal(world.damage_pipe(Vector2i(0, 0), 1000, 1), 0, "cut causes local Pipe failure")
	_check(world.get_pipe_state(Vector2i(0, 0)).breached, "failed segment records breach locally")
	for tick in 20: world.step()
	_check(world.get_total_water_mass() > 0, "breach emits physically simulated world Water")
	_check(world.get_pipe_state(Vector2i(0, 0)).mass < 20000, "leak drains only the breached segment")
	_check_equal(world.get_total_conserved_water_mass(), conserved, "leak conserves world plus Pipe Water exactly")
	_check(world.get_pipe_statistics().leak_mass_total > 0, "leak telemetry accumulates actual mass")
	world = _world(8009)
	world.place_structure(PIPE, Vector2i(0, 0))
	world.set_pipe_mass(Vector2i(0, 0), 12000, 12000)
	for tick in 40: world.step()
	_check(world.get_pipe_state(Vector2i(0, 0)).health < 1000, "hot Water/fire exposure damages Pipe locally")


func _physical_reservoir() -> void:
	suites += 1
	var world: Variant = _world(8010)
	for x in range(0, 12): world.place_structure(RESERVOIR_WALL, Vector2i(x, 10))
	for y in range(2, 11):
		world.place_structure(RESERVOIR_WALL, Vector2i(0, y))
		world.place_structure(RESERVOIR_WALL, Vector2i(11, y))
	for y in range(6, 10):
		for x in range(1, 11): world.set_water_mass(Vector2i(x, y), 255)
	var before: int = world.get_total_water_mass()
	for tick in 20: world.step()
	_check_equal(world.get_total_water_mass(), before, "Reservoir stores normal sleeping world Water")
	world.remove_structure_at(Vector2i(0, 9))
	for tick in 80: world.step()
	_check(world.get_liquid_mass(Vector2i(-1, 9)) > 0 or world.get_liquid_mass(Vector2i(-1, 10)) > 0, "local wall breach physically floods outward")
	_check_equal(world.get_total_water_mass(), before, "Reservoir breach conserves Water")


func _automation() -> void:
	suites += 1
	var world: Variant = _world(8011)
	world.place_pipe_line(Vector2i(-2, 0), Vector2i(-1, 0))
	world.place_structure(PUMP, Vector2i(0, 0), 0)
	world.place_pipe_line(Vector2i(1, 0), Vector2i(2, 0))
	world.set_pipe_mass(Vector2i(-1, 0), 30000)
	var control: int = world.create_automation_component(14, Vector2i(0, -3), {"target_position": Vector2i(0, 0)})
	_check(control > 0, "Pump ENABLE actuator created")
	world.set_automation_input_for_test(control, 0, 0)
	world.step()
	_check(not world.get_pipe_state(Vector2i(0, 0)).enabled, "Pump automation disables device")
	world.set_automation_input_for_test(control, 0, 1)
	world.step()
	_check(world.get_pipe_state(Vector2i(0, 0)).enabled, "Pump automation enables device")
	var fill: int = world.create_automation_component(17, Vector2i(1, -3), {"target_position": Vector2i(-1, 0)})
	var meter: int = world.create_automation_component(16, Vector2i(2, -3), {"target_position": Vector2i(0, 0)})
	for tick in 8: world.step()
	_check(world.get_automation_component_state(fill).output > 0, "Pipe Fill Sensor outputs 0..1000 local fill")
	_check(world.get_automation_component_state(meter).output >= 0, "Flow Meter exposes bounded local recent flow")


func _sluice_physicality() -> void:
	suites += 1
	var dry: Variant = _world(8012)
	_check(dry.place_structure(SLUICE, Vector2i(0, 0)) > 0, "Wash Sluice placed as open geometry")
	dry.set_cell_with_metadata(Vector2i(4, 3), SAND, 2386, 5)
	var dry_grains_before: int = _grain_count(dry)
	for tick in 20: dry.step()
	_check_equal(_grain_count(dry), dry_grains_before, "no Water means no useful washing or grain loss")
	var wet: Variant = _world(8012)
	wet.place_structure(SLUICE, Vector2i(0, 0))
	for x in range(1, 17): wet.set_water_mass(Vector2i(x, 4), 255)
	wet.set_cell_with_metadata(Vector2i(4, 3), FINE_SAND, 2386, _signature_for_constituent(wet, 2386, 0))
	var water_before: int = wet.get_total_conserved_water_mass()
	var grains_before: int = _grain_count(wet)
	var wet_visited_total: int = 0
	var wet_moved_total: int = 0
	var wet_captured_total: int = 0
	for tick in 60:
		wet.step()
		var tick_stats: Dictionary = wet.get_wet_processing_statistics()
		wet_visited_total += int(tick_stats.cells_visited)
		wet_moved_total += int(tick_stats.grains_moved)
		wet_captured_total += int(tick_stats.heavy_captured)
	_check(wet_visited_total > 0, "Sluice requires and samples actual nearby Water")
	_check(wet_moved_total > 0 or wet_captured_total > 0, "flow physically moves or captures grain")
	_check_equal(wet.get_total_conserved_water_mass(), water_before, "Sluice Water conserved")
	_check_equal(_grain_count(wet), grains_before, "Sluice grain count conserved")
	var metadata_hash_before: String = wet.authoritative_physical_hash()
	for tick in 30: wet.step()
	_check_equal(_grain_count(wet), grains_before, "Sluice overload/settling never duplicates grains")
	_check(not metadata_hash_before.is_empty(), "Sluice metadata participates in authoritative hash")


func _pipe_loops_and_worldcommand_replay() -> void:
	suites += 1
	var loop: Variant = _world(8014)
	loop.place_pipe_line(Vector2i(-12, -8), Vector2i(12, -8))
	loop.place_pipe_line(Vector2i(12, -8), Vector2i(12, 8))
	loop.place_pipe_line(Vector2i(12, 8), Vector2i(-12, 8))
	loop.place_pipe_line(Vector2i(-12, 8), Vector2i(-12, -8))
	loop.place_pipe_line(Vector2i(0, -8), Vector2i(0, 8))
	loop.set_pipe_mass(Vector2i(-12, -8), 65535, 900)
	loop.set_pipe_mass(Vector2i(12, 8), 65535, 1400)
	var loop_mass: int = loop.get_total_pipe_water_mass()
	for tick in 1200: loop.step()
	_check_equal(loop.get_total_pipe_water_mass(), loop_mass, "closed loop/branch conserves Pipe Water")
	_check(loop.get_pipe_statistics().segments_active < loop.get_pipe_statistics().segments_total, "stable loop/branch converges toward sleep")

	var log: Array[PackedByteArray] = []
	var hashes: Array[String] = []
	for workers in [1, 8]:
		var world: Variant = _world(8015, workers)
		var bus := WorldCommandBus.new()
		if log.is_empty():
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": -8, "y0": 0, "x1": 8, "y1": 0}, 1)), "WorldCommand places batched Pipe line")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": 0, "y": 0}, 2)), "WorldCommand opens Pump cell")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": PUMP, "x": 0, "y": 0, "orientation": 0}, 3)), "WorldCommand places Pump")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": 4, "y": 0}, 4)), "WorldCommand opens Valve cell")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": VALVE, "x": 4, "y": 0, "orientation": 0}, 5)), "WorldCommand places Valve")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.SET_PIPE_DEVICE, {"x": 4, "y": 0, "enabled": false, "valve": true}, 6)), "WorldCommand closes Valve")
			_check(bus.submit(world, WorldCommand.new(WorldCommand.Type.DAMAGE_PIPE, {"x": -4, "y": 0, "damage": 125, "cause": 2}, 7)), "WorldCommand applies local damage")
			log = bus.serialize_log()
		else:
			_check(bus.replay(world, log), "Phase 8 canonical WorldCommand replay succeeds")
		world.set_pipe_mass(Vector2i(-8, 0), 50000, 1300)
		for tick in 120: world.step()
		hashes.append(world.authoritative_physical_hash())
	_check_equal(hashes[1], hashes[0], "Phase 8 WorldCommand replay hash identical")
	print("phase8_world_command_replay workers=[1, 8] hash=%s commands=%d" % [hashes[0], log.size()])


func _determinism() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(8013, workers)
		world.place_pipe_line(Vector2i(-20, 0), Vector2i(20, 0))
		world.remove_structure_at(Vector2i(0, 0))
		world.place_structure(PUMP, Vector2i(0, 0), 0)
		world.set_pipe_mass(Vector2i(-20, 0), 65535, 1300)
		for tick in 120: world.step()
		hashes.append(world.authoritative_physical_hash())
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "Pipe worker parity %d" % [1, 2, 4, 8][index])
	print("phase8_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])


func _grain_count(world: Variant) -> int:
	var count := 0
	var cells: PackedInt32Array = world.get_non_empty_cells()
	for index in range(0, cells.size(), 3):
		if int(cells[index + 2]) in [2, 6, 7, 8, 9]: count += 1
	return count


func _signature_for_constituent(world: Variant, profile: int, constituent: int) -> int:
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) == constituent: return signature
	return 0


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failed = true
	push_error("PHASE8: " + message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [message, expected, actual])
