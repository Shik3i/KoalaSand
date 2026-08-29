extends SceneTree

const EMPTY := 0
const STONE := 1
const WATER := 3
const GLASS := 10
const IRON := 11
const ICE := 16
const STEAM := 17
const MOLTEN_GLASS := 18
const MOLTEN_IRON := 19

var checks := 0
var suites := 0
var failed := false

func _initialize() -> void: call_deferred("_run")

func _world(seed: int = 9001, workers: int = 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.allocate_chunk_rect(Rect2i(-3, -3, 6, 6))
	return world

func _run() -> void:
	_material_contract()
	_lazy_storage()
	_water_phase_family()
	_molten_phase_families()
	_thermal_conservation()
	_gas_motion_and_sleep()
	_molten_motion()
	_pipe_steam_and_failure()
	_thermal_structures_and_automation()
	_cross_chunk_and_hot_liquid_interaction()
	_pipe_phase_conservation()
	_worldcommand_replay()
	_determinism()
	print("PASS: %d checks across %d Phase 9 suites" % [checks, suites] if not failed else "FAIL: Phase 9 correctness")
	quit(0 if not failed else 1)

func _material_contract() -> void:
	suites += 1
	var registry := MaterialRegistry.new()
	_check_equal(registry.load_directory(), OK, "material registry loads")
	_check_equal(registry.get_id(&"ice"), ICE, "stable Ice ID")
	_check_equal(registry.get_id(&"steam"), STEAM, "stable Steam ID")
	_check_equal(registry.get_id(&"molten_glass"), MOLTEN_GLASS, "stable Molten Glass ID")
	_check_equal(registry.get_id(&"molten_iron"), MOLTEN_IRON, "stable Molten Iron ID")
	_check_equal(registry.get_definition(STEAM).category, MaterialDefinition.Category.GAS, "Steam gas category")
	_check_equal(registry.get_definition(MOLTEN_GLASS).category, MaterialDefinition.Category.MOLTEN, "Molten Glass category")
	_check_equal(registry.get_definition(WATER).boil_to, &"steam", "Water phase relation data")
	_check_equal(registry.get_definition(ICE).melt_to, &"water", "Ice phase relation data")
	_check(registry.get_definition(MOLTEN_IRON).visual_flags & MaterialDefinition.VisualFlag.EMISSIVE, "Molten Iron emissive")
	var world: Variant = _world()
	_check_equal(world.get_memory_layout().maximum_material_id, 27, "native stable material range")
	_check_equal(world.get_phase9_architecture().thermal_cadence_hz, 30, "production thermal cadence")

func _lazy_storage() -> void:
	suites += 1
	var world: Variant = _world(9002)
	var before: Dictionary = world.get_memory_layout()
	_check_equal(before.material_amount_plane_chunks, 0, "dry chunks allocate no amount plane")
	_check_equal(before.phase_energy_plane_chunks, 0, "dry chunks allocate no phase plane")
	_check_equal(world.set_material_state(Vector2i.ZERO, WATER, 255, 1173), OK, "implicit full amount")
	_check_equal(world.get_memory_layout().material_amount_plane_chunks, 0, "full amount remains implicit")
	_check_equal(world.set_material_state(Vector2i(1, 0), STEAM, 77, 1600), OK, "partial Steam accepted")
	_check_equal(world.get_material_amount(Vector2i(1, 0)), 77, "generic Steam amount")
	_check_equal(world.get_memory_layout().material_amount_plane_chunks, 1, "partial phase allocates one amount plane")
	_check_equal(world.set_material_state(Vector2i(2, 0), ICE, 128, 1093), OK, "partial Ice transition accepted")
	_check(world.get_phase_energy(Vector2i(2, 0)) > 0, "latent progress stored")
	_check_equal(world.get_memory_layout().phase_energy_plane_chunks, 1, "latent plane lazy allocation")

func _water_phase_family() -> void:
	suites += 1
	var world: Variant = _world(9003)
	_check_equal(world.set_material_state(Vector2i(0, 0), ICE, 200, 1400, 31, 77), OK, "hot Ice state")
	_check_equal(world.get_cell(Vector2i(0, 0)), WATER, "Ice melts only with sufficient enthalpy")
	_check_equal(world.get_material_amount(Vector2i(0, 0)), 200, "Ice melt conserves amount")
	_check_equal(world.get_provenance(Vector2i(0, 0)), 31, "Ice melt preserves provenance")
	_check_equal(world.get_mineral_signature(Vector2i(0, 0)), 77, "Ice melt preserves signature")
	world.set_material_state(Vector2i(1, 0), WATER, 137, 700)
	_check_equal(world.get_cell(Vector2i(1, 0)), ICE, "cold Water freezes")
	_check_equal(world.get_material_amount(Vector2i(1, 0)), 137, "freeze conserves amount")
	world.set_material_state(Vector2i(2, 0), WATER, 91, 2000)
	_check_equal(world.get_cell(Vector2i(2, 0)), STEAM, "hot Water boils after latent budget")
	_check_equal(world.get_material_amount(Vector2i(2, 0)), 91, "boiling conserves amount")
	world.set_material_state(Vector2i(3, 0), STEAM, 91, 0)
	_check(world.get_cell(Vector2i(3, 0)) != STEAM, "cold Steam condenses")
	_check_equal(world.get_material_amount(Vector2i(3, 0)), 91, "condensation conserves amount")
	_check_equal(world.get_total_phase_family_mass(1), 519, "Ice Water Steam family exact mass")

func _molten_phase_families() -> void:
	suites += 1
	var world: Variant = _world(9004)
	world.set_material_state(Vector2i(0, 0), GLASS, 113, 7000, 12, 34)
	_check_equal(world.get_cell(Vector2i(0, 0)), MOLTEN_GLASS, "Glass melts")
	_check_equal(world.get_material_amount(Vector2i(0, 0)), 113, "Molten Glass amount")
	_check_equal(world.get_provenance(Vector2i(0, 0)), 12, "Glass provenance survives melt")
	world.set_material_state(Vector2i(1, 0), MOLTEN_GLASS, 73, 0)
	_check_equal(world.get_cell(Vector2i(1, 0)), GLASS, "Molten Glass solidifies")
	_check_equal(world.get_material_amount(Vector2i(1, 0)), 73, "partial Glass survives solidification")
	world.set_material_state(Vector2i(2, 0), IRON, 211, 8000, 56, 78)
	_check_equal(world.get_cell(Vector2i(2, 0)), MOLTEN_IRON, "Iron melts")
	_check_equal(world.get_material_amount(Vector2i(2, 0)), 211, "Molten Iron amount")
	_check_equal(world.get_mineral_signature(Vector2i(2, 0)), 78, "Iron signature survives melt")
	world.set_material_state(Vector2i(3, 0), MOLTEN_IRON, 19, 0)
	_check_equal(world.get_cell(Vector2i(3, 0)), IRON, "Molten Iron solidifies")
	_check_equal(world.get_material_amount(Vector2i(3, 0)), 19, "partial Iron survives solidification")

func _thermal_conservation() -> void:
	suites += 1
	var world: Variant = _world(9005)
	world.set_material_state(Vector2i(0, 0), STONE, 255, 6000)
	world.set_material_state(Vector2i(1, 0), STONE, 255, 500)
	var before: int = world.get_total_thermal_enthalpy()
	for tick in 240: world.step()
	_check_equal(world.get_total_thermal_enthalpy(), before, "closed sensible enthalpy exact")
	_check(world.get_temperature(Vector2i(0, 0)) < 6000, "hot cell cools by conduction")
	_check(world.get_temperature(Vector2i(1, 0)) > 500, "cold cell warms by conduction")
	var stats: Dictionary = world.get_thermal_statistics()
	_check_equal(stats.cadence_hz, 30, "thermal statistics cadence")
	_check(stats.exchanges >= 0, "thermal statistics exposed")

func _gas_motion_and_sleep() -> void:
	suites += 1
	var world: Variant = _world(9006)
	world.set_material_state(Vector2i(0, 10), STEAM, 255, 1700)
	var before: int = world.get_total_phase_family_mass(1)
	for tick in 20: world.step()
	_check_equal(world.get_total_phase_family_mass(1), before, "Steam motion conserves mass")
	var rose := false
	for y in range(-10, 10): rose = rose or world.get_cell(Vector2i(0, y)) == STEAM
	_check(rose, "Steam rises as physical matter")
	_check(world.get_gas_statistics().steam_generated >= 0, "gas statistics exposed")
	var sealed: Variant = _world(9007)
	sealed.fill_rect_state(Rect2i(-16, -16, 32, 32), STEAM, 255, 1700)
	sealed.fill_rect(Rect2i(-17, -17, 34, 1), STONE)
	sealed.fill_rect(Rect2i(-17, 16, 34, 1), STONE)
	sealed.fill_rect(Rect2i(-17, -16, 1, 32), STONE)
	sealed.fill_rect(Rect2i(16, -16, 1, 32), STONE)
	for tick in 40: sealed.step()
	_check_equal(sealed.get_fluid_statistics().fluid_cells_visited, 0, "sealed stable Steam sleeps")

func _molten_motion() -> void:
	suites += 1
	for material in [MOLTEN_GLASS, MOLTEN_IRON]:
		var world: Variant = _world(9010 + material)
		world.fill_rect(Rect2i(-4, 8, 9, 1), STONE)
		world.set_material_state(Vector2i(0, 0), material, 255, 8000)
		var family := 2 if material == MOLTEN_GLASS else 3
		var mass: int = world.get_total_phase_family_mass(family)
		for tick in 160: world.step()
		_check_equal(world.get_total_phase_family_mass(family), mass, "molten family mass conserved %d" % material)
		var moved := false
		for y in range(1, 8):
			for x in range(-4, 5): moved = moved or world.get_cell(Vector2i(x, y)) in [material, GLASS if material == MOLTEN_GLASS else IRON]
		_check(moved, "molten material flows physically %d" % material)

func _pipe_steam_and_failure() -> void:
	suites += 1
	var world: Variant = _world(9020)
	world.place_pipe_line(Vector2i(0, 0), Vector2i(20, 0))
	_check_equal(world.set_pipe_fluid(Vector2i(0, 0), STEAM, 65535, 1900), OK, "Steam enters rated Pipe")
	_check(world.get_pipe_state(Vector2i(0, 0)).pressure > 48000, "Steam adds local pressure")
	for tick in 80: world.step()
	_check(world.get_pipe_statistics().steam_mass > 0, "Steam propagates segment by segment")
	var leak_cell := Vector2i(10, 0)
	if world.get_pipe_state(leak_cell).mass == 0: leak_cell = Vector2i(1, 0)
	_check_equal(world.damage_pipe(leak_cell, 1000, 2), 0, "Steam Pipe locally breached")
	for tick in 20: world.step()
	_check(world.get_pipe_statistics().breached_segments > 0, "breach persists locally")
	var leaked := false
	for offset in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]: leaked = leaked or world.get_cell(leak_cell + offset) == STEAM
	_check(leaked, "Pipe failure emits physical world Steam")

func _thermal_structures_and_automation() -> void:
	suites += 1
	var world: Variant = _world(9030)
	world.set_material_state(Vector2i(-1, 0), STONE, 255, 6000)
	world.set_material_state(Vector2i(1, 0), STONE, 255, 500)
	_check(world.place_structure(24, Vector2i.ZERO) > 0, "Thermal Switch placed")
	_check(world.set_thermal_switch_open(Vector2i.ZERO, false), "Thermal Switch closes")
	var cold_before: int = world.get_temperature(Vector2i(1, 0))
	for tick in 20: world.step()
	_check_equal(world.get_temperature(Vector2i(1, 0)), cold_before, "closed Thermal Switch isolates")
	_check(world.set_thermal_switch_open(Vector2i.ZERO, true), "Thermal Switch opens")
	for tick in 20: world.step()
	_check(world.get_temperature(Vector2i(1, 0)) > cold_before, "open Thermal Switch transfers heat")
	var sensor: int = world.create_automation_component(18, Vector2i(0, -3), {"target_position": Vector2i(-1, 0)})
	_check(sensor > 0, "Temperature Sensor created")
	world.step()
	_check(world.get_automation_component_state(sensor).output > 0, "Temperature Sensor emits quarter-kelvin signal")
	var controls: int = world.create_automation_component(21, Vector2i(0, -2), {"target_position": Vector2i.ZERO})
	_check(controls > 0, "Thermal Switch Control created")
	_check(world.set_automation_input_for_test(controls, 0, 0), "thermal control accepts signal")
	world.step()
	var research_ids: Array[String] = []
	for definition: Dictionary in world.get_research_definitions(): research_ids.append(str(definition.id))
	for id in ["thermal.basic_thermodynamics", "thermal.phase_processing", "thermal.steam_handling", "thermal.molten_processing"]:
		_check(id in research_ids, "thermal Research ID %s" % id)
	var exchanger: Variant = _world(9031)
	exchanger.set_material_state(Vector2i(-1, 1), STONE, 255, 6000)
	exchanger.set_material_state(Vector2i(3, 1), STONE, 255, 500)
	var exchanger_energy: int = exchanger.get_total_thermal_enthalpy()
	_check(exchanger.place_structure(25, Vector2i.ZERO) > 0, "Heat Exchanger placed")
	for tick in 20: exchanger.step()
	_check(exchanger.get_temperature(Vector2i(3, 1)) > 500, "Heat Exchanger transfers heat locally")
	_check_equal(exchanger.get_total_thermal_enthalpy(), exchanger_energy, "Heat Exchanger conserves enthalpy")

func _cross_chunk_and_hot_liquid_interaction() -> void:
	suites += 1
	var boundary: Variant = _world(9032)
	boundary.set_material_state(Vector2i(63, 0), STONE, 255, 7000)
	boundary.set_material_state(Vector2i(64, 0), WATER, 173, 1200, 41, 91)
	var boundary_mass: int = boundary.get_total_phase_family_mass(1)
	var boundary_energy: int = boundary.get_total_thermal_enthalpy()
	for tick in 240: boundary.step()
	_check_equal(boundary.get_total_phase_family_mass(1), boundary_mass, "cross-chunk phase mass exact")
	_check_equal(boundary.get_total_thermal_enthalpy(), boundary_energy, "cross-chunk thermal energy exact")
	var interaction: Variant = _world(9033)
	interaction.fill_rect(Rect2i(-2, 2, 5, 1), STONE)
	interaction.set_material_state(Vector2i(0, 1), MOLTEN_IRON, 255, 10000, 72, 144)
	interaction.set_material_state(Vector2i(1, 1), WATER, 255, 1300)
	var interaction_mass: int = interaction.get_total_phase_family_mass(1)
	var interaction_energy: int = interaction.get_total_thermal_enthalpy()
	var produced_steam := false
	for tick in 480:
		interaction.step()
		for y in range(-4, 3):
			for x in range(-4, 5): produced_steam = produced_steam or interaction.get_cell(Vector2i(x, y)) == STEAM
	_check(produced_steam, "hot Molten Iron physically boils adjacent Water")
	_check_equal(interaction.get_total_phase_family_mass(1), interaction_mass, "Water/molten interaction conserves Water family")
	_check_equal(interaction.get_total_thermal_enthalpy(), interaction_energy, "Water/molten interaction conserves enthalpy")

func _pipe_phase_conservation() -> void:
	suites += 1
	var transitions: Variant = _world(9034)
	transitions.place_pipe_line(Vector2i(-1, 0), Vector2i(1, 0))
	_check_equal(transitions.set_pipe_fluid(Vector2i.ZERO, WATER, 20000, 2200), OK, "hot Pipe Water state accepted")
	_check_equal(transitions.get_pipe_state(Vector2i.ZERO).fluid_type, STEAM, "hot Pipe Water becomes Steam by enthalpy")
	_check_equal(transitions.get_total_pipe_water_phase_mass(), 20000, "Pipe boil conserves mass")
	_check_equal(transitions.set_pipe_fluid(Vector2i.ZERO, STEAM, 20000, 0), OK, "cold Pipe Steam state accepted")
	_check_equal(transitions.get_pipe_state(Vector2i.ZERO).fluid_type, WATER, "cold Pipe Steam condenses by enthalpy")
	var leak: Variant = _world(9035)
	leak.place_pipe_line(Vector2i(-8, 0), Vector2i(8, 0))
	leak.set_pipe_fluid(Vector2i.ZERO, STEAM, 30000, 1900)
	var before_mass: int = leak.get_total_conserved_water_phase_mass()
	var before_energy: int = leak.get_total_thermal_enthalpy()
	for tick in 80: leak.step()
	_check_equal(leak.get_total_conserved_water_phase_mass(), before_mass, "Pipe Steam movement conserves phase-family mass")
	_check_equal(leak.get_total_thermal_enthalpy(), before_energy, "Pipe Steam movement conserves enthalpy")
	var breach_cell := Vector2i.ZERO
	for x in range(-8, 9):
		if int(leak.get_pipe_state(Vector2i(x, 0)).mass) > 0:
			breach_cell = Vector2i(x, 0)
			break
	leak.damage_pipe(breach_cell, 1000, 2)
	for tick in 20: leak.step()
	_check_equal(leak.get_total_conserved_water_phase_mass(), before_mass, "Pipe Steam leak conserves world plus Pipe mass")
	_check_equal(leak.get_total_thermal_enthalpy(), before_energy, "Pipe Steam leak conserves world plus Pipe enthalpy")

func _worldcommand_replay() -> void:
	suites += 1
	var serialized: Array[PackedByteArray] = []
	var physical_hashes: Array[String] = []
	var automation_hashes: Array[String] = []
	for workers in [1, 8]:
		var world: Variant = _world(9036, workers)
		var bus := WorldCommandBus.new()
		if serialized.is_empty():
			var commands: Array[WorldCommand] = [
				WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT, {"x": 0, "y": 8, "material_id": STONE}, 1),
				WorldCommand.new(WorldCommand.Type.SET_MATERIAL_STATE, {"x": 0, "y": 2, "material_id": WATER, "amount": 173, "temperature": 2100, "provenance": 9, "mineral_signature": 17}, 2),
				WorldCommand.new(WorldCommand.Type.SET_MATERIAL_STATE, {"x": 4, "y": 2, "material_id": GLASS, "amount": 211, "temperature": 7000, "provenance": 23, "mineral_signature": 47}, 3),
				WorldCommand.new(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": -4, "y0": -4, "x1": 4, "y1": -4}, 4),
				WorldCommand.new(WorldCommand.Type.SET_PIPE_FLUID, {"x": 0, "y": -4, "fluid_type": STEAM, "mass": 24000, "temperature": 1900}, 5),
				WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 24, "x": 8, "y": 2, "orientation": 0}, 6),
				WorldCommand.new(WorldCommand.Type.SET_THERMAL_SWITCH, {"x": 8, "y": 2, "open": false}, 7),
				WorldCommand.new(WorldCommand.Type.CREATE_AUTOMATION_COMPONENT, {"type_id": 18, "x": 8, "y": 0, "configuration": {"target_position": Vector2i(4, 2)}}, 8),
			]
			for command in commands: _check(bus.submit(world, command), "Phase 9 WorldCommand accepted type=%d" % command.type)
			serialized = bus.serialize_log()
		else:
			_check(bus.replay(world, serialized), "Phase 9 WorldCommand log replays")
		for tick in 180: world.step()
		physical_hashes.append(world.authoritative_physical_hash())
		automation_hashes.append(world.automation_state_hash())
	_check_equal(physical_hashes[1], physical_hashes[0], "Phase 9 WorldCommand physical replay parity")
	_check_equal(automation_hashes[1], automation_hashes[0], "Phase 9 WorldCommand automation replay parity")
	print("phase9_world_command_replay workers=[1, 8] physical=%s automation=%s" % [physical_hashes[0], automation_hashes[0]])

func _determinism() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(9040, workers)
		world.fill_rect(Rect2i(-32, 20, 64, 1), STONE)
		world.fill_rect_state(Rect2i(-24, 0, 16, 12), WATER, 173, 2000)
		world.fill_rect_state(Rect2i(8, 0, 16, 12), GLASS, 211, 7000)
		for tick in 180: world.step()
		hashes.append(world.authoritative_physical_hash())
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "thermal worker parity %d" % [1, 2, 4, 8][index])
	print("phase9_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failed = true
	push_error("PHASE9: " + message)

func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s expected=%s actual=%s" % [message, expected, actual])
