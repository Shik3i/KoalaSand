extends SceneTree

# Starting a second world must forget the first one completely.
#
# configure_world() is the call behind every "New Game". It used to clear machine_entities_ and
# a handful of logistics lists while leaving physical_processors_, the active magnet, screen,
# heater and sluice sets, the thermal switch and heat exchanger cells, and the whole automation,
# power, pipe, organic and phase13 registries populated with the previous world's ids. The first
# step() of the new world then walked a heater id that no longer had a machine behind it and
# machine_entities_.at(id) threw std::out_of_range, which is an uncaught exception in a
# GDExtension and takes the process down without a Godot error, a log line or a crash dialog.
#
# The player-facing shape of that bug: start the game, play, start a new world, and the game
# vanishes. This test builds a world that populates as many registries as it can, starts a
# second world on top of it, and asserts both that nothing survived and that the new world can
# actually be stepped.

var checks := 0
var failures: Array[String] = []

const HASHES := [
	"phase13_state_hash", "organic_state_hash", "power_state_hash", "automation_state_hash",
	"pipe_state_hash", "logistics_state_hash", "processing_state_hash", "subsurface_state_hash",
	"physical_processing_hash",
]

# Every statistic that reports the size of a registry a world owns. These are the containers
# that must be empty in a new world, and the ones that were quietly carried over.
const REGISTRY_CENSUS := [
	["get_physical_processing_statistics", "magnets_total"],
	["get_physical_processing_statistics", "screens_total"],
	["get_physical_processing_statistics", "heaters_total"],
	["get_physical_processing_statistics", "registered_region_chunks"],
	["get_automation_statistics", "components_total"],
	["get_automation_statistics", "wires_total"],
	["get_power_statistics", "networks"],
	["get_power_statistics", "poles"],
	["get_power_statistics", "consumers"],
	["get_power_statistics", "generators"],
	["get_power_statistics", "accumulators"],
	["get_power_statistics", "transformers"],
	["get_mechanical_statistics", "members"],
	["get_mechanical_statistics", "networks"],
	["get_pipe_statistics", "segments_total"],
	["get_organic_statistics", "active_clusters"],
	["get_structure_statistics", "structures_allocated"],
]

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_second_world_forgets_the_first()
	_test_second_world_can_be_stepped()
	_test_reset_and_configure_agree()
	if failures.is_empty():
		print("PASS: %d new world state checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("NEW_WORLD_STATE: " + failure)
	print("FAIL: %d of %d new world state checks" % [failures.size(), checks])
	quit(1)

# ---------------------------------------------------------------------------------------

func _test_second_world_forgets_the_first() -> void:
	var used: Variant = _world(11)
	var placed := _populate(used)
	_check(placed > 0, "the first world placed structures to leave behind (%d)" % placed)

	# A brand new object, configured the same way, is the reference for what a new world is.
	var fresh: Variant = _world(4242)

	# Prove the registries are actually dirty before the reconfigure, so that the assertions
	# below mean something. A test that passes because nothing was ever registered is worse
	# than no test: it reports safety it never checked.
	var populated := _census(used)
	var occupied := 0
	for entry in populated:
		if int(populated[entry]) > 0: occupied += 1
	_check(occupied >= 4, "the first world populated several registries (%d of %d)" % [occupied, REGISTRY_CENSUS.size()])

	used.configure_world({"seed": 4242, "generation_version": 5}, 4)

	var after := _census(used)
	for entry in after:
		_equal(int(after[entry]), 0, "%s is empty in a new world" % entry)

	for hash_name: String in HASHES:
		if not used.has_method(hash_name):
			continue
		_equal(used.call(hash_name), fresh.call(hash_name),
			"%s of a reconfigured world matches a new one" % hash_name)

	var layout: Dictionary = used.get_memory_layout()
	if layout.has("port_watch_cells"):
		_equal(int(layout.port_watch_cells), 0, "no machine port watchers survive into the new world")


func _test_second_world_can_be_stepped() -> void:
	# The crash was in the first step of the second world, not in configure_world itself.
	var world: Variant = _world(11)
	_populate(world)
	world.configure_world({"seed": 4242, "generation_version": 5}, 4)
	world.request_chunk_region(Rect2i(-1, 4, 3, 2), 0)
	world.flush_generation()
	for _tick in range(120):
		world.step()
	_check(true, "the second world survives 120 ticks")
	_check(world.chunk_count() > 0, "the second world generated chunks")


func _test_reset_and_configure_agree() -> void:
	# The two entry points that begin a world clear the same state, because they now share one
	# list. If they ever drift apart again, this is where it shows.
	var by_reset: Variant = _world(11)
	_populate(by_reset)
	by_reset.reset(4242, 4)

	var by_configure: Variant = _world(11)
	_populate(by_configure)
	by_configure.configure_world({"seed": 4242, "generation_version": 5}, 4)

	for hash_name: String in HASHES:
		if not by_reset.has_method(hash_name):
			continue
		_equal(by_reset.call(hash_name), by_configure.call(hash_name),
			"reset and configure_world leave the same %s" % hash_name)

# ---------------------------------------------------------------------------------------

func _world(seed_value: int) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed_value, "generation_version": 5}, 4)
	return world


func _populate(world: Variant) -> int:
	# Place one of every structure the world will accept, so the registries that a new world has
	# to forget are actually populated rather than assumed to be.
	world.set_game_mode(1)
	world.request_chunk_region(Rect2i(-2, 4, 5, 3), 0)
	world.flush_generation()
	var origin: Vector2i = world.get_character_spawn()
	var placed := 0
	var column := origin.x - 240
	for definition: Dictionary in world.get_structure_definitions():
		var type_id := int(definition.get("type_id", 0))
		if type_id <= 0:
			continue
		var footprint: Vector2i = definition.get("footprint", Vector2i(1, 1))
		var placed_here := false
		for depth in range(0, 40, 4):
			var cell := Vector2i(column, origin.y + 8 + depth)
			# Clear room for the footprint, then put the structure in it.
			world.paint_stroke(cell, cell + Vector2i(footprint.x, 0), maxi(footprint.x, footprint.y) + 2, 0)
			if world.can_place_structure(type_id, cell, 0) and int(world.place_structure(type_id, cell, 0)) > 0:
				placed += 1
				placed_here = true
				break
		if placed_here:
			column += maxi(4, footprint.x + 6)
	for _tick in range(20):
		world.step()
	return placed


func _census(world: Variant) -> Dictionary:
	var counts := {}
	for entry: Array in REGISTRY_CENSUS:
		var method_name: String = entry[0]
		var key: String = entry[1]
		if not world.has_method(method_name):
			continue
		var statistics: Dictionary = world.call(method_name)
		if not statistics.has(key):
			continue
		counts["%s.%s" % [method_name, key]] = int(statistics[key])
	return counts


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
