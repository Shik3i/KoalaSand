extends SceneTree

const WATER := 3
const STEAM := 17
const PowerContractDefinition := preload("res://core/power/power_contract.gd")

var checks := 0
var suites := 0
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed: int, workers: int) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	return world


func _run() -> void:
	_power_contract()
	_gas_worker_conservation()
	_gas_equilibrium()
	_pipe_worker_conservation()
	_pipe_rupture_accounting()
	print("PASS: %d checks across %d Phase 9.5 suites" % [checks, suites] if not failed else "FAIL: Phase 9.5 correctness")
	quit(0 if not failed else 1)


func _power_contract() -> void:
	suites += 1
	_check_equal(PowerContractDefinition.SCHEMA_VERSION, 1, "power schema")
	_check_equal(PowerContractDefinition.MECHANICAL_TICK_HZ, 30, "mechanical cadence")
	_check_equal(PowerContractDefinition.ELECTRICAL_TICK_HZ, 30, "electrical cadence")
	_check_equal(PowerContractDefinition.POWER_OVERLAY_PROVIDER_ID, 13, "Power overlay stable ID")
	_check_equal(PowerContractDefinition.EnergyKind.THERMAL, 1, "Thermal energy ID")
	_check_equal(PowerContractDefinition.EnergyKind.MECHANICAL, 2, "Mechanical energy ID")
	_check_equal(PowerContractDefinition.EnergyKind.ELECTRICAL, 3, "Electrical energy ID")
	_check_equal(PowerContractDefinition.PortRole.PRODUCER, 1, "producer role ID")
	_check_equal(PowerContractDefinition.PortRole.CONSUMER, 2, "consumer role ID")
	_check_equal(PowerContractDefinition.PortRole.STORAGE, 3, "storage role ID")
	_check_equal(PowerContractDefinition.PortRole.CONNECTION, 4, "connection role ID")
	_check_equal(PowerContractDefinition.ConsumerPriority.CRITICAL, 0, "critical priority ID")
	_check_equal(PowerContractDefinition.ConsumerPriority.LOW, 3, "low priority ID")
	_check_equal(PowerContractDefinition.FutureCommandId.SET_POWER_SWITCH, 21, "Power Switch command ID")
	_check_equal(PowerContractDefinition.FutureCommandId.SET_POWER_PRIORITY, 22, "Power priority command ID")
	_check_equal(PowerContractDefinition.FutureCommandId.CONFIGURE_POWER_PORT, 23, "Power port command ID")
	_check_equal(PowerContractDefinition.BLUEPRINT_FIELDS.switch_closed, "power_switch_closed", "Power blueprint field")
	var architecture: Dictionary = PowerContractDefinition.architecture()
	_check(bool(architecture.automation_network_separate), "Automation and Power remain separate")
	_check(bool(architecture.implemented_gameplay), "Phase 10 gameplay enabled")
	_check_equal(architecture.topology, "cached connected components; union additions; localized split rebuild after removals", "event-driven topology contract")
	var port: Dictionary = PowerContractDefinition.port_metadata(PowerContractDefinition.PortRole.CONSUMER, 240, PowerContractDefinition.ConsumerPriority.HIGH)
	_check_equal(port, {"schema": 1, "role": 2, "rate_quanta_per_tick": 240, "priority": 1}, "future PowerPort record")
	var overlay := MapOverlayRenderer.new()
	get_root().add_child(overlay)
	_check_equal(MapOverlayRenderer.Mode.POWER, PowerContractDefinition.POWER_OVERLAY_PROVIDER_ID, "overlay enum matches contract")
	_check(overlay.provider_available(MapOverlayRenderer.Mode.POWER), "Power overlay exposes native provider")
	overlay.free()


func _gas_worker_conservation() -> void:
	suites += 1
	var hashes: Array[String] = []
	var worker_counts: Array[int] = [1, 2, 4, 8]
	for workers: int in worker_counts:
		var world: Variant = _world(9501, workers)
		world.fill_pattern_state(Rect2i(0, 0, 256, 256), STEAM, 64, 192, 1700, 1700)
		var mass_before: int = world.get_total_phase_family_mass(1)
		var energy_before: int = world.get_total_thermal_enthalpy()
		for tick in 24:
			world.step()
		_check_equal(world.get_total_phase_family_mass(1), mass_before, "gas mass exact workers=%d" % workers)
		_check_equal(world.get_total_thermal_enthalpy(), energy_before, "gas enthalpy exact workers=%d" % workers)
		hashes.append(world.authoritative_physical_hash())
	for index in range(1, hashes.size()):
		_check_equal(hashes[index], hashes[0], "gas worker parity workers=%d" % worker_counts[index])
	print("phase95_gas_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])


func _gas_equilibrium() -> void:
	suites += 1
	var world: Variant = _world(9502, 8)
	world.fill_rect_state(Rect2i(0, 0, 128, 128), STEAM, 255, 1700)
	world.fill_rect(Rect2i(-1, -1, 130, 1), 1)
	world.fill_rect(Rect2i(-1, 128, 130, 1), 1)
	world.fill_rect(Rect2i(-1, 0, 1, 128), 1)
	world.fill_rect(Rect2i(128, 0, 1, 128), 1)
	for tick in 40:
		world.step()
	var stats: Dictionary = world.get_fluid_statistics()
	_check_equal(stats.fluid_cells_visited, 0, "sealed Steam sleeps")
	_check_equal(world.get_gas_statistics().transfers, 0, "sealed Steam has no residual pressure chatter")


func _pipe_worker_conservation() -> void:
	suites += 1
	var hashes: Array[String] = []
	var worker_counts: Array[int] = [1, 2, 4, 8]
	for workers: int in worker_counts:
		var world: Variant = _world(9503, workers)
		world.place_pipe_line(Vector2i.ZERO, Vector2i(4095, 0))
		for x in 4096:
			world.set_pipe_fluid(Vector2i(x, 0), STEAM, 16384 if x % 2 == 0 else 49152, 1800)
		var mass_before: int = world.get_pipe_statistics().steam_mass
		var energy_before: int = world.get_total_thermal_enthalpy()
		for tick in 16:
			world.step()
		_check_equal(world.get_pipe_statistics().steam_mass, mass_before, "Pipe Steam mass exact workers=%d" % workers)
		_check_equal(world.get_total_thermal_enthalpy(), energy_before, "Pipe Steam enthalpy exact workers=%d" % workers)
		hashes.append(world.authoritative_physical_hash())
	for index in range(1, hashes.size()):
		_check_equal(hashes[index], hashes[0], "Pipe worker parity workers=%d" % worker_counts[index])
	print("phase95_pipe_worker_parity workers=[1, 2, 4, 8] hash=%s" % hashes[0])


func _pipe_rupture_accounting() -> void:
	suites += 1
	var world: Variant = _world(9504, 8)
	world.place_pipe_line(Vector2i.ZERO, Vector2i(511, 0))
	for x in 512:
		world.set_pipe_fluid(Vector2i(x, 0), STEAM, 65535, 3000)
	var family_before: int = world.get_total_phase_family_mass(1) + int(world.get_pipe_statistics().steam_mass)
	var energy_before: int = world.get_total_thermal_enthalpy()
	for tick in 16:
		world.step()
	var stats: Dictionary = world.get_pipe_statistics()
	var family_after: int = world.get_total_phase_family_mass(1) + int(stats.steam_mass) + int(stats.water_mass)
	_check(int(stats.breached_segments) > 0, "overpressure creates local ruptures")
	_check(int(stats.leak_mass_total) > 0, "ruptures emit physical matter")
	_check(world.get_total_phase_family_mass(1) > 0, "rupture Steam exists in world cells")
	_check_equal(family_after, family_before, "rupture accounts exact Pipe plus world mass")
	_check_equal(world.get_total_thermal_enthalpy(), energy_before, "rupture accounts exact Pipe plus world enthalpy")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failed = true
	push_error("PHASE95: " + message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s: expected %s, got %s" % [message, expected, actual])
