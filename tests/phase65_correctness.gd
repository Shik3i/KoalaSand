extends SceneTree

const RAW := 2
const FINE := 6
const HEAVY := 7
const IRON_CONCENTRATE := 8
const GLASS := 10
const IRON := 11
const GOLD := 12
const STONE := 1
const CHARCOAL := 23
const SCREEN := 6
const MAGNET := 7

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_definitions_and_properties()
	_test_physical_screen()
	_test_screen_blocking_identity_and_determinism()
	_test_physical_magnet()
	_test_physical_furnace()
	_test_magnet_blocking_overlap_and_conservation()
	_test_cross_chunk_and_negative_coordinates()
	_test_idle_scheduling_and_overlay()
	_test_world_command_replay_and_modes()
	if failures.is_empty():
		print("PASS: %d checks across 9 Phase 6.5 suites hash=%s" % [checks, _golden_hash()])
		quit(0)
		return
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d checks failed" % [failures.size(), checks])
	quit(1)

func _world(seed: int = 65001) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, 1)
	world.set_game_mode(1)
	return world

func _signature_for(world: Variant, profile: int, constituent: int, grain_class: int = -1) -> int:
	for signature in range(0, 65536):
		if world.get_hidden_constituent(profile, signature) != constituent:
			continue
		world.set_cell_with_metadata(Vector2i(9000, 9000), RAW, profile, signature)
		var size: int = world.get_grain_size_class(Vector2i(9000, 9000))
		world.set_cell(Vector2i(9000, 9000), 0)
		if grain_class < 0 or size == grain_class:
			return signature
	return -1

func _test_definitions_and_properties() -> void:
	var world: Variant = _world()
	var definitions: Dictionary = {}
	for definition: Dictionary in world.get_structure_definitions(): definitions[int(definition.type_id)] = definition
	_check_equal(definitions[SCREEN].display_name, "Vibrating Screen", "screen production name")
	_check_equal(definitions[MAGNET].display_name, "Overbelt Magnetic Separator", "magnet production name")
	var profile := 2386
	var iron_signature := _signature_for(world, profile, 1)
	var gold_signature := _signature_for(world, profile, 0)
	world.set_cell_with_metadata(Vector2i.ZERO, HEAVY, profile, iron_signature)
	world.set_cell_with_metadata(Vector2i.ONE, HEAVY, profile, gold_signature)
	_check(world.get_magnetic_susceptibility(Vector2i.ZERO) >= 800, "iron constituent strongly magnetic")
	_check_equal(world.get_magnetic_susceptibility(Vector2i.ONE), 0, "gold constituent nonmagnetic")

func _test_physical_screen() -> void:
	var world: Variant = _world(65002)
	var profile := 2386
	var fine_signature := _signature_for(world, profile, 0, 0)
	var coarse_signature := _signature_for(world, profile, 0, 2)
	_check(fine_signature >= 0 and coarse_signature >= 0, "stable fine and coarse signatures found")
	_check(world.place_structure(SCREEN, Vector2i.ZERO, 0) > 0, "physical screen placed")
	world.set_cell_with_metadata(Vector2i(4, 2), RAW, profile, fine_signature)
	world.set_cell_with_metadata(Vector2i(6, 2), RAW, profile, coarse_signature)
	world.step()
	_check_equal(world.get_cell(Vector2i(4, 3)), FINE, "fine grain physically enters mesh and relabels")
	_check_equal(world.get_cell(Vector2i(6, 3)), 0, "coarse grain does not cross mesh")
	_check_equal(world.get_provenance(Vector2i(4, 3)), profile, "screen preserves provenance")
	_check_equal(world.get_mineral_signature(Vector2i(4, 3)), fine_signature, "screen preserves signature")
	var stats: Dictionary = world.get_physical_processing_statistics()
	_check_equal(stats.screen_passes, 1, "screen pass counted at boundary")
	_check(stats.vibration_evaluations >= 1, "screen physically evaluates vibration")

func _test_screen_blocking_identity_and_determinism() -> void:
	var first: Variant = _world(65003)
	var second: Variant = _world(65003)
	var profile := 2386
	var probe: Variant = _world(65003)
	var signature := _signature_for(probe, profile, 0, 0)
	for world: Variant in [first, second]:
		world.place_structure(SCREEN, Vector2i.ZERO, 0)
		for x in range(1, 9): world.set_cell(Vector2i(x, 4), STONE)
		world.set_cell_with_metadata(Vector2i(4, 2), RAW, profile, signature)
		for _tick in 12: world.step()
	_check_equal(first.physical_processing_hash(), second.physical_processing_hash(), "screen repeated run deterministic")
	_check_equal(first.get_cell(Vector2i(4, 3)), FINE, "blocked lower collection backs up on mesh")
	_check_equal(first.get_cell(Vector2i(4, 4)), STONE, "screen never teleports through blocked collector")
	_check_equal(first.get_mineral_signature(Vector2i(4, 3)), signature, "blocked screen grain identity conserved")

func _test_physical_magnet() -> void:
	var world: Variant = _world(65004)
	var profile := 2386
	var iron_signature := _signature_for(world, profile, 1)
	var gold_signature := _signature_for(world, profile, 0)
	world.place_structure(MAGNET, Vector2i.ZERO, 0)
	world.place_conveyor_line(Vector2i(1, 6), Vector2i(10, 6), 1)
	world.set_cell_with_metadata(Vector2i(4, 5), HEAVY, profile, iron_signature)
	world.set_cell_with_metadata(Vector2i(7, 5), HEAVY, profile, gold_signature)
	world.step()
	_check_equal(world.get_cell(Vector2i(4, 4)), IRON_CONCENTRATE, "magnetic grain rises one physical cell")
	_check_equal(_row_material_count(world, 5, HEAVY), 1, "nonmagnetic grain remains on lower route")
	_check_equal(world.get_provenance(Vector2i(4, 4)), profile, "magnet preserves provenance")
	_check_equal(world.get_mineral_signature(Vector2i(4, 4)), iron_signature, "magnet preserves signature")
	for _tick in 4: world.step()
	_check(world.get_cell(Vector2i(4, 4)) == 0, "captured grain continues through physical field")
	_check(world.get_physical_processing_statistics().magnetic_moves_total >= 2, "magnetic lift produces cell-by-cell moves")

func _test_magnet_blocking_overlap_and_conservation() -> void:
	var world: Variant = _world(65005)
	var profile := 2386
	var probe: Variant = _world(65005)
	var iron_signature := _signature_for(probe, profile, 1)
	world.place_structure(MAGNET, Vector2i.ZERO, 0)
	world.place_structure(MAGNET, Vector2i(12, 0), 0)
	for x in range(-1, 25): world.set_cell(Vector2i(x, 6), STONE)
	world.set_cell(Vector2i(5, 4), STONE)
	world.set_cell_with_metadata(Vector2i(5, 5), HEAVY, profile, iron_signature)
	var before := _material_count(world, [HEAVY, IRON_CONCENTRATE])
	world.step()
	_check_equal(world.get_cell(Vector2i(5, 5)), HEAVY, "solid cell blocks magnetic lift")
	_check_equal(_material_count(world, [HEAVY, IRON_CONCENTRATE]), before, "overlapping fields conserve magnetic grains")
	var first_hash: String = world.physical_processing_hash()
	var replay: Variant = _world(65005)
	replay.place_structure(MAGNET, Vector2i.ZERO, 0)
	replay.place_structure(MAGNET, Vector2i(12, 0), 0)
	for x in range(-1, 25): replay.set_cell(Vector2i(x, 6), STONE)
	replay.set_cell(Vector2i(5, 4), STONE)
	replay.set_cell_with_metadata(Vector2i(5, 5), HEAVY, profile, iron_signature)
	replay.step()
	_check_equal(replay.physical_processing_hash(), first_hash, "overlapping fields combine deterministically")

func _test_cross_chunk_and_negative_coordinates() -> void:
	for origin in [Vector2i(58, 0), Vector2i(-66, -10)]:
		var world: Variant = _world(65006 + origin.x)
		var profile := 2386
		var signature := _signature_for(world, profile, 1)
		world.place_structure(MAGNET, origin, 0)
		world.place_conveyor_line(origin + Vector2i(1, 6), origin + Vector2i(10, 6), 1)
		var source: Vector2i = origin + Vector2i(6, 5)
		world.set_cell_with_metadata(source, HEAVY, profile, signature)
		world.step()
		_check_equal(world.get_cell(source + Vector2i.UP), IRON_CONCENTRATE, "cross-chunk/negative field lift %s" % origin)

func _test_physical_furnace() -> void:
	var world: Variant = _world(65008)
	var profile := 2386
	var signature := _signature_for(world, profile, 0)
	_check(world.place_structure(5, Vector2i.ZERO, 0) > 0, "radiant furnace placed")
	for x in range(1, 9): world.set_cell(Vector2i(x, 4), STONE)
	world.set_material_state(Vector2i(2, 3), CHARCOAL, 255, 3000)
	world.set_cell_with_metadata(Vector2i(4, 3), RAW, profile, signature)
	var initial_temperature: int = world.get_temperature(Vector2i(4, 3))
	world.step()
	_check(world.get_temperature(Vector2i(4, 3)) > initial_temperature, "furnace heats physical cell in place")
	for _tick in 30: world.step()
	_check(world.get_cell(Vector2i(4, 3)) != RAW, "sustained heat causes in-place material reaction")
	_check_equal(world.get_provenance(Vector2i(4, 3)), profile, "thermal reaction preserves provenance")
	_check_equal(world.get_mineral_signature(Vector2i(4, 3)), signature, "thermal reaction preserves signature")
	_check(world.get_physical_processing_statistics().heat_reactions_total >= 1, "physical heat reaction counted")
	var upgraded: Variant = _world(65018)
	for material_id in [GLASS, IRON, GOLD]: _check(upgraded.credit_research_material_for_test(material_id, 10000), "thermal research fixture credit %d" % material_id)
	upgraded.set_game_mode(0)
	_check(upgraded.try_unlock_research("furnace.fuel_economy_1"), "Thermal Efficiency unlock")
	_check(upgraded.try_unlock_research("furnace.throughput_1"), "Radiant Intensity unlock")
	upgraded.set_game_mode(1)
	upgraded.place_structure(5, Vector2i.ZERO, 0)
	for x in range(1, 9): upgraded.set_cell(Vector2i(x, 4), STONE)
	upgraded.set_material_state(Vector2i(2, 3), CHARCOAL, 255, 3000)
	upgraded.set_cell_with_metadata(Vector2i(4, 3), RAW, profile, signature)
	upgraded.step()
	_check(upgraded.get_temperature(Vector2i(4, 3)) > initial_temperature, "thermal upgrades transfer physical fuel heat without a recipe timer")

func _test_idle_scheduling_and_overlay() -> void:
	var world: Variant = _world(65007)
	for index in 100:
		world.place_structure(MAGNET, Vector2i((index % 20) * 14, (index / 20) * 8), 0)
		world.place_structure(SCREEN, Vector2i((index % 20) * 14, 80 + (index / 20) * 7), 0)
	for _tick in 3: world.step()
	var stats: Dictionary = world.get_physical_processing_statistics()
	_check_equal(stats.magnets_active, 0, "idle magnets sleep without global scan")
	_check_equal(stats.screens_active, 0, "idle screens sleep without global scan")
	_check_equal(stats.magnetic_cells_tested, 0, "idle magnets test zero cells")
	var sample: Dictionary = world.get_magnetic_field_sample(Rect2i(Vector2i.ZERO, Vector2i(40, 20)), 2)
	_check_equal(sample.mode, "MAGNETIC_FIELD", "generic overlay sample identifies mode")
	_check(sample.samples.size() > 0, "visible magnetic overlay samples on demand")

func _test_world_command_replay_and_modes() -> void:
	var first: Variant = _world(65009)
	var second: Variant = _world(65009)
	var bus := WorldCommandBus.new()
	var commands: Array[WorldCommand] = [
		WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": 3, "y": 4, "material_id": RAW}, 2),
		WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 2, "x": 3, "y": 5, "orientation": 0}, 3),
		WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": -65, "y": 4, "material_id": RAW}, 4),
	]
	for command in commands: _check(bus.submit(first, command), "WorldCommand applies: %d" % command.type)
	var serialized: Array[PackedByteArray] = bus.serialize_log()
	_check_equal(serialized.size(), commands.size(), "command log serialization count")
	_check(WorldCommand.deserialize(serialized[0]) != null, "command byte round trip")
	var replay_bus := WorldCommandBus.new()
	_check(replay_bus.replay(second, serialized), "canonical command replay succeeds")
	_check_equal(first.physical_processing_hash(), second.physical_processing_hash(), "command replay produces deterministic world hash")
	var switch_command := WorldCommand.new(WorldCommand.Type.CREATE_AUTOMATION_COMPONENT, {"type_id": 1, "x": 8, "y": 8, "configuration": {"enabled": false}}, 5)
	_check(bus.submit(first, switch_command), "automation component creation uses WorldCommand")
	var switch_id := int(bus.last_result)
	_check(bus.submit(first, WorldCommand.new(WorldCommand.Type.SET_MANUAL_SWITCH, {"component_id": switch_id, "enabled": true}, 6)), "automation mutation uses WorldCommand")
	_check(bool(first.get_automation_component_state(switch_id).enabled), "automation command applies switch state")
	var creative := GameModeCapabilities.for_mode(GameModeCapabilities.Mode.CREATIVE)
	var character := GameModeCapabilities.for_mode(GameModeCapabilities.Mode.CHARACTER)
	var spectator := GameModeCapabilities.for_mode(GameModeCapabilities.Mode.SPECTATOR)
	_check(creative.world_edit and creative.commands, "Creative capability preset can mutate world")
	_check(character.character and character.commands and not character.world_edit, "future Character capability is command-limited")
	_check(spectator.free_camera and not spectator.commands and not spectator.build, "Spectator capability is read-only")

func _material_count(world: Variant, ids: Array[int]) -> int:
	var count := 0
	var cells: PackedInt32Array = world.get_non_empty_cells()
	for index in range(0, cells.size(), 3):
		if ids.has(cells[index + 2]): count += 1
	return count

func _row_material_count(world: Variant, y: int, material_id: int) -> int:
	var count := 0
	for x in range(-4, 20):
		if world.get_cell(Vector2i(x, y)) == material_id: count += 1
	return count

func _golden_hash() -> String:
	var world: Variant = _world(65100)
	var profile := 2386
	var iron := _signature_for(world, profile, 1)
	world.place_structure(MAGNET, Vector2i.ZERO, 0)
	world.place_conveyor_line(Vector2i(1, 6), Vector2i(10, 6), 1)
	world.set_cell_with_metadata(Vector2i(5, 5), HEAVY, profile, iron)
	for _tick in 8: world.step()
	return world.physical_processing_hash()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s: expected %s, got %s" % [label, expected, actual])
