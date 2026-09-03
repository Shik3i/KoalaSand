extends SceneTree

# Every research node a player can buy has to change something a player can observe.
#
# Six of them did not. Processing used to run through machines -- a Radiant Crude Furnace, a
# Vibrating Screen, an Overbelt Magnetic Separator, a Wash Sluice -- and COMPOSABLE_PROCESSING.md
# replaced all four with geometry built from ordinary Components. The upgrade nodes were left
# pointing at the machines. is_physical_processor() is true for exactly those four, every one of
# them excluded from the Build Catalog, so the entire upgrade half of the processing branch
# charged Glass, Iron and Gold for an effect that could never occur. The most expensive node in
# the tree, at 6000 Glass, 400 Iron and 2 Gold, was among them.
#
# Each node now lands on the composable route that does the work its own description names, and
# this file measures the difference. Every test runs the same scenario twice against the same
# seed and the same cells -- once without the research, once with -- and asserts the numbers
# move. A test that only checked the researched run would pass just as well if the effect were
# unconditional.

var checks := 0
var failures: Array[String] = []

const SAND := 2
const STONE := 1
const FINE_SAND := 6
const HEAVY_CONCENTRATE := 7
const IRON_CONCENTRATE := 8
const CRUDE_RESIDUE := 13
const MOLTEN_IRON := 19
const EMPTY := 0

const STRUCTURAL_WALL := 37
const REFRACTORY_WALL := 40
const MESH_SCREEN := 41
const THERMAL_INSULATOR := 44
const VIBRATION_ACTUATOR := 45
const IRON_POT := 35

const REACTION_TEMPERATURE := 5893

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_precision_screening_enriches_the_concentrate()
	_test_concentrate_recovery_turns_residue_into_iron()
	_test_high_throughput_handling_buffers_twice_as_much()
	_test_radiant_intensity_reacts_a_second_cell()
	_test_thermal_efficiency_stops_the_insulator_leaking()
	_test_cookware_unlocks_something_that_can_be_placed()
	if failures.is_empty():
		print("PASS: %d research effect checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("RESEARCH_EFFECTS: " + failure)
	print("FAIL: %d of %d research effect checks" % [failures.size(), checks])
	quit(1)

# ---------------------------------------------------------------------------------------

func _world(research: Array[String]) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 4242, "generation_version": 5}, 4)
	# Credit first, unlock in progression mode, then return to sandbox mode so that placement is
	# free and the only thing separating the two runs is the research itself.
	world.set_game_mode(1)
	for material in [10, 11, 12]: world.credit_research_material_for_test(material, 1000000)
	world.set_game_mode(0)
	for id in research: _unlock(world, id)
	world.set_game_mode(1)
	return world


func _unlock(world: Variant, id: String) -> void:
	# Prerequisites resolved from the tree itself, so this does not have to be kept in step with
	# it by hand.
	for definition: Dictionary in world.get_research_definitions():
		if str(definition.get("id", "")) != id: continue
		for prerequisite: String in definition.get("prerequisites", []):
			_unlock(world, prerequisite)
		world.try_unlock_research(id)
		return
	failures.append("research id does not exist: %s" % id)


func _clear(world: Variant, centre: Vector2i, radius: int) -> void:
	world.paint_stroke(centre - Vector2i(radius, radius), centre + Vector2i(radius, radius), radius, EMPTY)


# The mass a route sends to each of its four channels, for one grain, with no world involved.
func _channels(world: Variant, material_id: int, route: int) -> Array:
	var report: Dictionary = world.split_composition_for_test(material_id, 1200, 31337, route)
	var masses: Array[int] = []
	for channel: Dictionary in report.get("channels", []):
		masses.append(int(channel.get("micro_mass", 0)))
	return masses


func _test_precision_screening_enriches_the_concentrate() -> void:
	# processing_result() has always spelled out what a precision deck is: PROCESS_SIEVE_PRECISION
	# differs from PROCESS_SIEVE by sending the heavy mineral to the concentrate instead of
	# letting it dilute the fines. The Mesh Screen now separates the same two ways. Channel 0 is
	# Fine Sand, channel 1 the concentrate.
	var plain := _channels(_world([]), SAND, 1)
	var precise := _channels(_world(["processing.precision_screening"]), SAND, 1)

	_check(plain.size() == 4 and precise.size() == 4, "the screen route reports four channels")
	_check(plain[1] > 0, "a plain deck already recovers something (%d)" % plain[1])
	_check(precise[1] > plain[1],
		"precision screening sends more mass to the concentrate (plain=%d precise=%d)" % [plain[1], precise[1]])
	_check(precise[0] < plain[0],
		"and correspondingly less to the fines (plain=%d precise=%d)" % [plain[0], precise[0]])
	_equal(plain[0] + plain[1], precise[0] + precise[1], "and no mass is created or lost by the upgrade")


func _test_concentrate_recovery_turns_residue_into_iron() -> void:
	# PROCESS_FURNACE_RECOVERY differed from PROCESS_FURNACE_RAW by recovering more metal out of
	# a concentrate rather than dropping it into residue. The thermal route now makes the same
	# distinction. Channel 1 is Molten Iron, channel 3 the residue.
	var raw := _channels(_world([]), IRON_CONCENTRATE, 3)
	var recovered := _channels(_world(["processing.concentrate_recovery"]), IRON_CONCENTRATE, 3)

	_check(raw[3] > 0, "a raw reaction leaves residue to recover (%d)" % raw[3])
	_check(recovered[1] > raw[1],
		"recovery yields more Iron from a concentrate (raw=%d recovered=%d)" % [raw[1], recovered[1]])
	_check(recovered[3] < raw[3],
		"and less residue (raw=%d recovered=%d)" % [raw[3], recovered[3]])
	_equal(raw[1] + raw[3], recovered[1] + recovered[3], "and no mass is created or lost by the upgrade")

	# Raw Sand was never concentrated, so the same research must leave it exactly alone.
	# Without this the node would be a global buff wearing a specific description.
	var sand_raw := _channels(_world([]), SAND, 3)
	var sand_recovered := _channels(_world(["processing.concentrate_recovery"]), SAND, 3)
	_equal(sand_recovered, sand_raw, "recovery does not touch a reaction on unconcentrated Raw Sand")


# A Mesh Screen whose four output cells are walled off, fed until it refuses. Returns how many
# grains it swallowed before stalling. The wall directly under the Mesh matters twice: it blocks
# the pass-side output, and it stops the feed falling straight through a deck that is permeable
# by design, so the grain is still in the source cell when the component runs.
func _run_blocked_screen(research: Array[String]) -> int:
	var world: Variant = _world(research)
	var origin := Vector2i(1500, 300)
	world.request_chunk_region(Rect2i(22, 3, 4, 4), 0)
	world.flush_generation()
	_clear(world, origin, 14)
	var actuator := origin
	var mesh := actuator + Vector2i(1, 0)
	world.place_structure(VIBRATION_ACTUATOR, actuator, 0)
	world.place_structure(MESH_SCREEN, mesh, 0)
	# The four output cells, plus enough wall to make a hopper of the source. A Mesh Screen is
	# permeable by design -- that is what a deck is -- so a grain dropped above one slides
	# straight through and off to the side unless something holds it there.
	for offset in [Vector2i(0, 1), Vector2i(1, -1), Vector2i(0, 2), Vector2i(2, -1),
			Vector2i(1, 0), Vector2i(1, 1), Vector2i(-1, 1)]:
		world.place_structure(STRUCTURAL_WALL, mesh + offset, 0)
	for _tick in range(400):
		if int(world.get_cell(mesh + Vector2i(0, -1))) == EMPTY:
			world.set_cell(mesh + Vector2i(0, -1), SAND)
		world.step()
	return int(world.get_processing_statistics().get("sieve_processed_total", 0))


func _test_high_throughput_handling_buffers_twice_as_much() -> void:
	# "Improve capture transport and physical feed handling" is worth something concrete in a
	# world where a Component's outputs are ordinary cells that something else has to clear: it
	# keeps taking feed for twice as long while they are backed up.
	var plain := _run_blocked_screen([])
	var buffered := _run_blocked_screen(["logistics.high_throughput_handling"])
	_check(plain > 0, "a blocked Component still accepts feed until it fills (%d)" % plain)
	_check(buffered > plain,
		"the researched Component accepts more before stalling (plain=%d buffered=%d)" % [plain, buffered])


# A Refractory Wall with hot grain resting on solid ground either side of it.
func _run_refractory(research: Array[String], feed_offsets: Array) -> int:
	var world: Variant = _world(research)
	var origin := Vector2i(1200, 300)
	world.request_chunk_region(Rect2i(18, 3, 4, 4), 0)
	world.flush_generation()
	_clear(world, origin, 14)
	var wall := origin
	world.place_structure(REFRACTORY_WALL, wall, 0)
	# A continuous floor under the whole row, not just under each feed cell. Granular material
	# runs diagonally as well as straight down, so a grain with an empty cell below and to one
	# side is gone before the component ever looks at it.
	for dx in range(-3, 4):
		world.set_cell(wall + Vector2i(dx, 1), STONE)
	# Twelve ticks, not forty. The ledger fills at around thirty grains whatever the research
	# says, so a long run measures the buffer depth both configurations share instead of the
	# rate that separates them.
	for _tick in range(12):
		# Rewritten every tick, temperature included: the thermal solver is cooling these cells
		# the whole time, and a grain that has dropped below the reaction temperature stops
		# qualifying, which would measure the cooling rate instead of the research.
		for offset: Vector2i in feed_offsets:
			world.set_material_state(wall + offset, SAND, 255, REACTION_TEMPERATURE + 400, 0, 0)
		world.step()
		# Keep the four output cells clear. Otherwise both runs simply fill their ledgers and
		# stall in the same place, and the measurement is of the buffer rather than the rate.
		for offset in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, -2), Vector2i(1, -2)]:
			if int(world.get_cell(wall + offset)) != EMPTY: world.set_cell(wall + offset, EMPTY)
	return int(world.get_processing_statistics().get("furnace_processed_total", 0))


func _test_radiant_intensity_reacts_a_second_cell() -> void:
	# Two qualifying grains beside the same Refractory Wall. Unresearched, the enclosure takes the
	# hotter one and waits a tick for the other.
	var plain := _run_refractory([], [Vector2i(-1, 0), Vector2i(1, 0)])
	var intense := _run_refractory(["furnace.throughput_1"], [Vector2i(-1, 0), Vector2i(1, 0)])
	_check(plain > 0, "the enclosure reacted at all (%d)" % plain)
	_check(intense > plain,
		"Radiant Intensity reacts more cells over the same ticks (plain=%d intense=%d)" % [plain, intense])


func _insulator_leak(research: Array[String]) -> int:
	var world: Variant = _world(research)
	var origin := Vector2i(1800, 300)
	world.request_chunk_region(Rect2i(27, 3, 4, 4), 0)
	world.flush_generation()
	_clear(world, origin, 12)
	var insulator := origin
	world.place_structure(THERMAL_INSULATOR, insulator, 0)
	var hot := insulator + Vector2i(-1, 0)
	var cold := insulator + Vector2i(1, 0)
	world.set_material_state(hot, STONE, 255, 4000, 0, 0)
	world.set_material_state(cold, STONE, 255, 1092, 0, 0)
	for _tick in range(80):
		world.set_material_state(hot, STONE, 255, 4000, 0, 0)
		world.step()
	return int(world.get_temperature(cold))


func _test_thermal_efficiency_stops_the_insulator_leaking() -> void:
	# Every one of these structures bridges heat across itself between its two opposite
	# neighbours, which is how a hot enclosure bleeds into whatever it is standing next to. The
	# Insulator is already at the floor of that coefficient -- conductivity 2, and 2/16 rounds to
	# the minimum of 1 -- so the only reduction left is to stop the bridge.
	var leaking := _insulator_leak([])
	var sealed := _insulator_leak(["furnace.fuel_economy_1"])
	_check(leaking > 1092, "an unresearched Insulator passes heat across itself (%d)" % leaking)
	_check(sealed < leaking,
		"Thermal Efficiency reduces what crosses it (leaking=%d sealed=%d)" % [leaking, sealed])


func _test_cookware_unlocks_something_that_can_be_placed() -> void:
	# Cookware gates only the Iron Pot, and the Pot was in DEV_TYPES, so the node cost 900 Glass
	# and 60 Iron for nothing placeable. PHYSICAL_COOKING.md documents the Pot as an implemented
	# vessel, so it belongs in the catalog rather than the node belonging in the bin.
	var world: Variant = _world([])
	var definition := {}
	for entry: Dictionary in world.get_structure_definitions():
		if int(entry.get("type_id", -1)) == IRON_POT: definition = entry
	_check(not definition.is_empty(), "the Iron Pot has a structure definition")
	_check(ComponentPresentation.is_player_facing(IRON_POT, definition),
		"the Iron Pot is offered to the player (category=%s)" % str(definition.get("category", "")))

	var locked: Variant = _world([])
	locked.set_game_mode(0)
	_check(not locked.is_structure_unlocked(IRON_POT), "the Iron Pot is locked before Cookware")
	var unlocked: Variant = _world(["thermal.cookware"])
	unlocked.set_game_mode(0)
	_check(unlocked.is_structure_unlocked(IRON_POT), "Cookware unlocks the Iron Pot")

	# And the promise on the node is now true, which is what the sweep in build_flow.gd measures
	# against every other node.
	for definition_entry: Dictionary in world.get_research_definitions():
		if str(definition_entry.get("id", "")) != "thermal.cookware": continue
		_check(str(definition_entry.get("effect", "")).contains("Iron Pot"),
			"Cookware still names the Iron Pot, and now it means it")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
