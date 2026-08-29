extends SceneTree

const PowerContractDefinition := preload("res://core/power/power_contract.gd")
const STEAM := 17

var checks := 0
var suites := 0
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int, workers: int = 8) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.fill_rect(Rect2i(-128, -64, 256, 128), 0)
	return world


func _run() -> void:
	_contract_and_catalog()
	_mechanical_topology()
	_physical_power_train()
	_priority_and_storage()
	_switch_topology()
	_automation_and_separation()
	_serialization_boundary()
	_world_command_replay()
	_blueprint_configuration()
	_worker_determinism()
	_large_cached_topologies()
	print("PASS: %d checks across %d Phase 10 suites" % [checks, suites] if not failed else "FAIL: Phase 10 correctness")
	quit(0 if not failed else 1)


func _contract_and_catalog() -> void:
	suites += 1
	_check_equal(PowerContractDefinition.SCHEMA_VERSION, 1, "power schema")
	_check_equal(PowerContractDefinition.MECHANICAL_TICK_HZ, 30, "mechanical cadence")
	_check_equal(PowerContractDefinition.ELECTRICAL_TICK_HZ, 30, "electrical cadence")
	_check(PowerContractDefinition.architecture().implemented_gameplay, "Phase 10 gameplay enabled")
	var world: Variant = _world(10001)
	var architecture: Dictionary = world.get_phase10_architecture()
	_check_equal(architecture.mechanical_tick_hz, 30, "native mechanical cadence")
	_check_equal(architecture.electrical_tick_hz, 30, "native electrical cadence")
	_check(not architecture.authoritative_floats, "integer authoritative power state")
	_check(architecture.automation_separate, "automation network stays separate")
	var names: Dictionary = {}
	for definition: Dictionary in world.get_structure_definitions(): names[int(definition.type_id)] = definition.display_name
	for entry in [[26, "Mechanical Shaft"], [27, "Steam Turbine"], [28, "Generator"], [29, "Power Pole"], [30, "Power Switch"], [31, "Accumulator"], [33, "Flywheel"], [34, "Resistive Heater"]]:
		_check_equal(names.get(entry[0], ""), entry[1], "structure %d catalog" % entry[0])
	_check(not names.has(32), "Transformer deferred instead of exposed as a nonphysical black box")
	var research_ids: Dictionary = {}
	for definition: Dictionary in world.get_research_definitions(): research_ids[String(definition.id)] = true
	for research_id in ["power.steam_generation", "power.electrical_distribution", "power.electrified_industry", "power.energy_storage", "power.mechanical_storage", "power.grid_control"]:
		_check(research_ids.has(research_id), "research %s" % research_id)


func _mechanical_topology() -> void:
	suites += 1
	var world: Variant = _world(10002)
	_check_equal(world.place_mechanical_shaft_line(Vector2i(0, 0), Vector2i(99, 0)), 100, "place 100 shaft segments")
	world.finalize_initialization(); world.step()
	var initial: Dictionary = world.get_mechanical_statistics()
	_check_equal(initial.segments, 100, "shaft segment count")
	_check_equal(initial.networks, 1, "shaft cached component")
	var stable_network: int = world.get_power_state_at(Vector2i(0, 0)).mechanical_network_id
	_check_equal(world.get_power_state_at(Vector2i(99, 0)).mechanical_network_id, stable_network, "stable component identity")
	world.remove_structure_at(Vector2i(50, 0)); world.step()
	_check_equal(world.get_mechanical_statistics().networks, 2, "shaft split rebuild")
	_check(world.place_structure(26, Vector2i(50, 0), 0), "shaft merge placement")
	world.step()
	_check_equal(world.get_mechanical_statistics().networks, 1, "shaft merge rebuild")


func _build_train(world: Variant, origin := Vector2i.ZERO, add_storage := true) -> void:
	_check(world.place_structure(27, origin, 0), "place physical Steam Turbine")
	_check_equal(world.place_pipe_line(origin + Vector2i(-1, 1), origin + Vector2i(-1, 1)), 1, "place turbine inlet Pipe")
	_check_equal(world.set_pipe_fluid(origin + Vector2i(-1, 1), STEAM, 30000, 2200), 0, "fill inlet with physical Steam")
	_check_equal(world.place_pipe_line(origin + Vector2i(6, 1), origin + Vector2i(6, 1)), 1, "place turbine exhaust Pipe")
	_check_equal(world.place_mechanical_shaft_line(origin + Vector2i(6, 2), origin + Vector2i(13, 2)), 8, "connect physical shaft")
	_check(world.place_structure(28, origin + Vector2i(14, 0), 0), "place shaft Generator")
	_check(world.place_structure(29, origin + Vector2i(20, 2), 0), "place Power Pole")
	if add_storage: _check(world.place_structure(31, origin + Vector2i(24, 0), 0), "place Accumulator")
	_check(world.place_structure(34, origin + Vector2i(29, 0), 0), "place Resistive Heater")
	_check(world.configure_power_structure(origin + Vector2i(29, 0), {"priority": 1}), "configure consumer priority")
	world.set_material_state(origin + Vector2i(0, 5), 1, 255, 1173)
	world.finalize_initialization()


func _physical_power_train() -> void:
	suites += 1
	var world: Variant = _world(10003)
	_build_train(world)
	var inlet_before: int = world.get_pipe_state(Vector2i(-1, 1)).mass
	var exhaust_before: int = world.get_pipe_state(Vector2i(6, 1)).mass
	for tick in 30: world.step()
	var inlet_after: Dictionary = world.get_pipe_state(Vector2i(-1, 1))
	var exhaust_after: Dictionary = world.get_pipe_state(Vector2i(6, 1))
	var turbine: Dictionary = world.get_power_state_at(Vector2i.ZERO)
	var generator: Dictionary = world.get_power_state_at(Vector2i(14, 0))
	var energy: Dictionary = world.get_energy_accounting()
	print("phase10_train turbine=%s generator=%s energy=%s" % [turbine, generator, energy])
	_check(int(inlet_after.mass) < inlet_before, "Turbine consumes inlet Steam")
	_check(int(exhaust_after.mass) > exhaust_before, "Turbine emits physical exhaust Steam")
	_check_equal(int(inlet_after.mass) + int(exhaust_after.mass), inlet_before + exhaust_before, "Turbine Pipe Steam mass exact")
	_check(int(turbine.steam_mass_throughput) > 0, "Turbine throughput telemetry")
	_check(int(turbine.speed_millirpm) > 0, "shaft has physical speed")
	_check(int(energy.thermal_into_turbines) > 0, "thermal energy entered Turbine")
	_check(int(energy.mechanical_produced) > 0, "Turbine produced mechanical energy")
	_check(int(energy.electrical_produced) > 0, "Generator produced electrical energy")
	_check(int(generator.electrical_output) >= 0, "Generator runtime state exposed")
	_check(int(energy.thermal_into_turbines) >= int(energy.mechanical_produced) + int(energy.turbine_losses), "Turbine accounting bounded")


func _priority_and_storage() -> void:
	suites += 1
	var world: Variant = _world(10004)
	_build_train(world)
	for offset in [34, 38, 42]:
		world.place_structure(34, Vector2i(offset, 0), 0)
		world.configure_power_structure(Vector2i(offset, 0), {"priority": clampi(int((offset - 30) / 4), 0, 3)})
	world.place_structure(29, Vector2i(40, 2), 0)
	for tick in 40: world.step()
	var network_id: int = world.get_power_state_at(Vector2i(29, 0)).power_network_id
	var network: Dictionary = world.get_power_network_state(network_id)
	var ratios: PackedInt32Array = network.satisfaction_by_priority
	_check_equal(ratios.size(), 4, "four priority classes")
	_check(ratios[0] >= ratios[1] and ratios[1] >= ratios[2] and ratios[2] >= ratios[3], "deterministic priority shedding")
	var accumulator: Dictionary = world.get_power_state_at(Vector2i(24, 0))
	_check(int(accumulator.charge) >= 0 and int(accumulator.charge) <= int(accumulator.capacity), "Accumulator charge bounded")
	_check(int(world.get_energy_accounting().storage_losses) >= 0, "storage loss accounting")
	_check(world.configure_power_structure(Vector2i(42, 0), {"priority": 3, "pole_position": Vector2i(40, 2)}), "explicit Power Pole reassignment")
	world.step()
	_check(int(world.get_power_state_at(Vector2i(42, 0)).assigned_pole_id) != 0, "consumer retains explicit pole assignment")


func _switch_topology() -> void:
	suites += 1
	var world: Variant = _world(10005)
	world.place_structure(29, Vector2i(0, 0), 0)
	world.place_structure(30, Vector2i(12, 0), 0)
	world.place_structure(29, Vector2i(26, 0), 0)
	world.finalize_initialization(); world.step()
	_check_equal(world.get_power_statistics().networks, 1, "closed switch joins pole components")
	_check(world.set_power_switch_closed(Vector2i(12, 0), false), "open Power Switch")
	world.step()
	_check_equal(world.get_power_statistics().networks, 2, "open switch splits cached grid")
	_check(world.set_power_switch_closed(Vector2i(12, 0), true), "close Power Switch")
	world.step()
	_check_equal(world.get_power_statistics().networks, 1, "closed switch merges cached grid")


func _automation_and_separation() -> void:
	suites += 1
	var world: Variant = _world(10006)
	_build_train(world)
	var power_sensor: int = world.create_automation_component(22, Vector2i(0, -10), {"mode": 0, "target_position": Vector2i(20, 2)})
	var shaft_sensor: int = world.create_automation_component(23, Vector2i(3, -10), {"target_position": Vector2i(8, 2)})
	_check(power_sensor > 0 and shaft_sensor > 0, "Power and shaft sensors created")
	for tick in 20: world.step()
	_check(int(world.get_automation_component_state(power_sensor).output) >= 0, "Power sensor emits integer signal")
	_check(int(world.get_automation_component_state(shaft_sensor).output) > 0, "shaft speed sensor reads real RPM")
	_check(world.get_phase10_architecture().automation_separate, "logic wires do not carry electrical energy")


func _serialization_boundary() -> void:
	suites += 1
	var world: Variant = _world(10007)
	_build_train(world)
	world.configure_power_structure(Vector2i.ZERO, {"target_millirpm": 1200000, "max_throttle": 700})
	for tick in 8: world.step()
	var serialized: Dictionary = world.serialize_power_state()
	_check_equal(serialized.schema, 1, "power serialization schema")
	_check(not serialized.mechanical_runtime.is_empty(), "active rotational energy included in production save state")
	_check(not serialized.electrical_runtime.is_empty(), "active electrical network state included in production save state")
	_check(world.deserialize_power_state(serialized), "power configuration round trip")
	_check(world.power_state_hash().length() == 8, "power hash stable width")


func _world_command_replay() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 8]:
		var world: Variant = _world(10070, workers)
		var bus := WorldCommandBus.new()
		var commands: Array[WorldCommand] = [
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 27, "x": 0, "y": 0, "orientation": 0}, 1),
			WorldCommand.new(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": -1, "y0": 1, "x1": -1, "y1": 1}, 2),
			WorldCommand.new(WorldCommand.Type.SET_PIPE_FLUID, {"x": -1, "y": 1, "fluid_type": STEAM, "mass": 30000, "temperature": 2200}, 3),
			WorldCommand.new(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": 6, "y0": 1, "x1": 6, "y1": 1}, 4),
		]
		for x in range(6, 14): commands.append(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 26, "x": x, "y": 2, "orientation": 0}, 5 + x))
		commands.append_array([
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 28, "x": 14, "y": 0, "orientation": 0}, 20),
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 29, "x": 20, "y": 2, "orientation": 0}, 21),
			WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": 34, "x": 29, "y": 0, "orientation": 0}, 22),
			WorldCommand.new(WorldCommand.Type.SET_POWER_PRIORITY, {"x": 29, "y": 0, "priority": 1}, 23),
		])
		var applied := true
		for command in commands: applied = bus.submit(world, WorldCommand.deserialize(command.serialize())) and applied
		_check(applied, "Power WorldCommand replay applies workers=%d" % workers)
		world.finalize_initialization()
		for tick in 24: world.step()
		hashes.append(world.authoritative_physical_hash())
	_check_equal(hashes[1], hashes[0], "Power WorldCommand replay worker parity")
	_check_equal(WorldCommand.deserialize(WorldCommand.new(WorldCommand.Type.CONFIGURE_POWER_PORT, {"x": 0, "y": 0, "configuration": {"max_throttle": 700}}).serialize()).type, WorldCommand.Type.CONFIGURE_POWER_PORT, "Power command serialization max ID")
	print("phase10_world_command_replay workers=[1, 8] hash=%s" % hashes[0])


func _blueprint_configuration() -> void:
	suites += 1
	var world: Variant = _world(10071)
	var blueprint := BlueprintDefinition.new("power-cell", "Power cell", "Configuration-only Power Blueprint")
	blueprint.add_structure(1, 27, Vector2i(0, 0), 0, {"target_millirpm": 1200000, "max_throttle": 700})
	blueprint.add_structure(2, 30, Vector2i(10, 0), 0, {"closed": false})
	blueprint.add_structure(3, 34, Vector2i(20, 0), 0, {"priority": 3})
	var serialized := blueprint.serialize()
	var restored := BlueprintDefinition.deserialize(serialized)
	_check(restored != null, "Power Blueprint deserialize")
	_check_equal(restored.entries.size(), 3, "Power Blueprint entry count")
	_check_equal(restored.entries[0].configuration.max_throttle, 700, "Turbine governor Blueprint configuration")
	var result: Dictionary = WorldCommandBus.new().submit_batch(world, restored.instantiate(Vector2i.ZERO, 7, 1))
	_check_equal(result.applied, 3, "Power Blueprint applies atomically")
	_check_equal(world.get_power_state_at(Vector2i.ZERO).target_millirpm, 1200000, "Turbine Blueprint target restored")
	_check_equal(world.get_power_state_at(Vector2i(10, 0)).closed, false, "Power Switch Blueprint state restored")
	_check_equal(world.get_power_state_at(Vector2i(20, 0)).priority, 3, "Power priority Blueprint state restored")


func _worker_determinism() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(10008, workers)
		_build_train(world)
		for tick in 24: world.step()
		hashes.append(world.authoritative_physical_hash())
	for index in range(1, hashes.size()): _check_equal(hashes[index], hashes[0], "Power worker parity %d" % [1, 2, 4, 8][index])
	print("phase10_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])


func _large_cached_topologies() -> void:
	suites += 1
	var shafts: Variant = _world(10009)
	shafts.configure_power_benchmark(0, 100000)
	_check_equal(shafts.get_mechanical_statistics().segments, 100000, "100k shaft segments")
	_check_equal(shafts.get_mechanical_statistics().networks, 1, "100k shaft cached component")
	var first: Variant = _world(10010)
	var second: Variant = _world(10010)
	first.configure_power_benchmark(2, 10000); second.configure_power_benchmark(2, 10000)
	_check_equal(first.get_power_statistics().poles, 10000, "10k pole graph")
	_check_equal(first.power_state_hash(), second.power_state_hash(), "large topology deterministic hash")
	_check(int(first.get_power_statistics().pole_record_bytes) > 0, "power memory telemetry")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition: return
	failed = true
	push_error("CHECK FAILED: %s" % label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected: return
	failed = true
	push_error("CHECK FAILED: %s expected=%s actual=%s" % [label, expected, actual])
