extends SceneTree

# The path a player takes to place their first Component.
#
# Open the Build Catalog, pick a Conveyor, click in the world. Every step of that has to work,
# and when a placement is refused the player has to be told why. Silence is the failure mode
# that reads as "the game is broken": the owner reported being unable to place a conveyor at
# all, and both causes were silent.

var checks := 0
var failures: Array[String] = []

const CONVEYOR_RIGHT := 2

class Harness extends Node:
	var scene: Node
	var done := false
	var frames := 0
	var on_ready: Callable

	func _process(_delta: float) -> void:
		frames += 1
		if frames == 25 and not done:
			done = true
			on_ready.call()


func _initialize() -> void: call_deferred("_boot")

func _boot() -> void:
	var packed: PackedScene = load("res://scenes/debug_world.tscn")
	if packed == null:
		push_error("BUILD_FLOW: scene failed to load")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var harness := Harness.new()
	harness.scene = scene
	harness.on_ready = func(): _run(scene)
	root.add_child(harness)


func _run(scene: Node) -> void:
	_test_catalog_selection_returns_control_to_the_world(scene)
	_test_conveyor_places_where_the_preview_says_it_can(scene)
	_test_placing_on_solid_ground_says_why(scene)
	_test_a_refused_placement_says_why(scene)
	_test_the_objective_tracks_the_simulation(scene)
	_test_every_codex_link_in_the_ui_resolves(scene)
	_test_reaching_a_milestone_is_announced(scene)
	_test_experiments_that_claim_to_be_reachable_are(scene)
	_test_the_first_instruction_actually_works(scene)
	if failures.is_empty():
		print("PASS: %d build flow checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("BUILD_FLOW: " + failure)
	print("FAIL: %d of %d build flow checks" % [failures.size(), checks])
	quit(1)

# ---------------------------------------------------------------------------------------

func _test_catalog_selection_returns_control_to_the_world(scene: Node) -> void:
	# Picking a Component out of the catalog is the player saying "now let me place this".
	# While the catalog stays open every world click is swallowed by _pointer_over_ui(), so
	# the component is selected, the cursor shows a preview, and nothing can ever be built.
	scene.call("_start_phase11_game", GameModeCapabilities.Preset.FACTORY, 8675309, "BuildFlow")
	var hud: Variant = scene.get("factory_hud")

	hud.toggle_catalog()
	_check(hud.visible_modal_ids().has("build_catalog"), "the catalog opens")
	_check(hud.modal_open(), "an open catalog blocks world input")

	hud.call("_on_catalog_tool_activated", {"kind": "structure", "id": CONVEYOR_RIGHT, "name": "Conveyor"})
	_equal(int(scene.get("build_structure_type")), CONVEYOR_RIGHT, "the conveyor is selected")
	_check(not hud.visible_modal_ids().has("build_catalog"),
		"choosing a component closes the catalog")
	_check(not hud.modal_open(), "world input is available again after choosing a component")
	_check(not scene.call("_pointer_over_ui"), "a world click is no longer swallowed")


func _test_conveyor_places_where_the_preview_says_it_can(scene: Node) -> void:
	var world: Variant = scene.get("world")
	var spawn: Vector2i = world.get_character_spawn()
	var chunk := Vector2i(spawn.x >> 6, spawn.y >> 6)
	world.request_chunk_region(Rect2i(chunk.x - 2, chunk.y - 2, 5, 4), 0)
	world.flush_generation()

	var from_cell := Vector2i(spawn.x - 4, spawn.y - 6)
	var to_cell := Vector2i(spawn.x + 4, spawn.y - 6)
	_check(world.can_place_conveyor_line(from_cell, to_cell, 1), "open air above the surface accepts a conveyor")

	scene.set("build_structure_type", CONVEYOR_RIGHT)
	scene.set("_structure_dragging", true)
	scene.set("_structure_drag_start", from_cell)
	scene.call("_place_conveyor_drag", to_cell)

	var placed := 0
	for x in range(from_cell.x, to_cell.x + 1):
		if int(world.get_structure(Vector2i(x, from_cell.y))) == CONVEYOR_RIGHT: placed += 1
	_equal(placed, to_cell.x - from_cell.x + 1, "the whole dragged run is built")


func _test_placing_on_solid_ground_says_why(scene: Node) -> void:
	# The first thing anyone does is aim a Conveyor at the ground, the way belts work in every
	# other factory game. Here a Conveyor occupies the cell itself, so it needs empty space --
	# and the game used to refuse without a word, which reads as a broken build tool.
	var world: Variant = scene.get("world")
	var hud: Variant = scene.get("factory_hud")
	var spawn: Vector2i = world.get_character_spawn()
	var ground := Vector2i(spawn.x, spawn.y + 6)
	_check(int(world.get_cell(ground)) != 0, "the probe cell really is solid ground")

	hud.show_notification("", "INFO")
	scene.set("build_structure_type", CONVEYOR_RIGHT)
	scene.set("_structure_dragging", true)
	scene.set("_structure_drag_start", ground)
	scene.call("_place_conveyor_drag", ground + Vector2i(5, 0))

	_equal(int(world.get_structure(ground)), 0, "nothing is built into solid ground")
	var told: String = hud.last_notification()
	_check(not told.is_empty(), "the player is told why a Conveyor will not go into the ground")
	_check("clear" in told.to_lower() or "solid" in told.to_lower() or "material" in told.to_lower(),
		"and the message names the obstruction: %s" % told)


func _test_a_refused_placement_says_why(scene: Node) -> void:
	# Character Mode enforces an 18-cell build range. Refusing is correct; refusing in silence
	# is what makes the game look broken.
	scene.call("_start_phase11_game", GameModeCapabilities.Preset.CHARACTER, 8675309, "BuildFlowReach")
	var world: Variant = scene.get("world")
	var character: Variant = scene.get("_character")
	_check(character != null, "character mode has a character")
	if character == null: return
	var spawn: Vector2i = world.get_character_spawn()
	var chunk := Vector2i(spawn.x >> 6, spawn.y >> 6)
	world.request_chunk_region(Rect2i(chunk.x - 3, chunk.y - 3, 7, 6), 0)
	world.flush_generation()

	var hud: Variant = scene.get("factory_hud")
	hud.show_alert("")
	var origin: Vector2i = character.world_cell()
	var far_from := Vector2i(origin.x + 40, origin.y - 3)
	var far_to := Vector2i(origin.x + 46, origin.y - 3)
	scene.set("build_structure_type", CONVEYOR_RIGHT)
	scene.set("_structure_dragging", true)
	scene.set("_structure_drag_start", far_from)
	scene.call("_place_conveyor_drag", far_to)

	var placed := 0
	for x in range(far_from.x, far_to.x + 1):
		if int(world.get_structure(Vector2i(x, far_from.y))) == CONVEYOR_RIGHT: placed += 1
	_equal(placed, 0, "a run outside build range is refused")
	_check(not hud.last_notification().is_empty(),
		"a refused placement tells the player why")
	_check("range" in hud.last_notification().to_lower(),
		"and names the reason it can act on: %s" % hud.last_notification())


func _test_the_objective_tracks_the_simulation(scene: Node) -> void:
	# The objective was driven by a list of milestone keys kept by hand alongside the list
	# native actually publishes. Seven of the ten had drifted, the first one included, so the
	# lookup always missed and the objective never moved off step one for the whole game.
	# Names crossing a language boundary need a test or they rot silently.
	var world: Variant = scene.get("world")
	var published: Dictionary = world.get_milestone_state()
	var objectives: Array = scene.get("MILESTONE_OBJECTIVES")
	_check(not objectives.is_empty(), "the objective table is populated")
	for step: Dictionary in objectives:
		_check(published.has(str(step.key)),
			"milestone key '%s' is one the simulation publishes" % str(step.key))
		_check(not str(step.title).is_empty(), "'%s' has a title" % str(step.key))
		_check((step.criteria as Array).size() > 0, "'%s' says what to actually do" % str(step.key))
	_equal(objectives.size(), published.size(),
		"every published milestone has an objective, and none is invented")

	# "Open objective help" is only useful if the entry it points at exists. These ids cross
	# from the objective table into the Codex, which is the same kind of boundary the milestone
	# keys crossed, so it gets the same test rather than a second silent dead end.
	var codex: Variant = scene.get("_physics_codex")
	for step: Dictionary in objectives:
		_check(not codex.get_entry(str(step.help)).is_empty(),
			"objective help id '%s' resolves to a Codex entry" % str(step.help))

	# And the objective the player is shown has to be the first unmet one, not a fixed string.
	var hud: Variant = scene.get("factory_hud")
	scene.call("_update_phase135_feedback")
	var shown: String = str(hud.get("_goal_title").text)
	var expected := ""
	for step: Dictionary in objectives:
		if not bool(published.get(str(step.key), false)):
			expected = str(step.title)
			break
	_equal(shown, expected, "the objective shown is the first unmet milestone")


func _test_every_codex_link_in_the_ui_resolves(scene: Node) -> void:
	# Every Codex id the UI can send the player to, gathered from the source rather than
	# retyped here, so this cannot pass by agreeing with itself. Three of these were dead when
	# the objective table first shipped them, and a dead help link is the same silent dead end
	# as a swallowed click: the player asks the game a question and gets nothing.
	var codex: Variant = scene.get("_physics_codex")
	var ids := _codex_ids_referenced_in_source()
	_check(ids.size() > 30, "found the Codex links in the source (%d)" % ids.size())
	var dead: Array[String] = []
	for id: String in ids:
		if codex.get_entry(id).is_empty(): dead.append(id)
	_equal(", ".join(dead), "", "every Codex link the UI offers resolves to an entry")


func _codex_ids_referenced_in_source() -> Array[String]:
	var found := {}
	var pattern := RegEx.new()
	pattern.compile('"(concept|component|material|research|blueprint):[a-z0-9_.]+"')
	for root in ["res://debug", "res://rendering", "res://core"]:
		for path in _scripts_under(root):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null: continue
			var text := file.get_as_text()
			for hit in pattern.search_all(text):
				found[hit.get_string().substr(1, hit.get_string().length() - 2)] = true
	var ids: Array[String] = []
	for key: Variant in found.keys(): ids.append(str(key))
	ids.sort()
	return ids


func _test_reaching_a_milestone_is_announced(scene: Node) -> void:
	# _last_milestones was written every frame and never read, so the arc the objective walks
	# the player through was completed in silence: you achieve the thing the game asked for and
	# it says nothing at all.
	var hud: Variant = scene.get("factory_hud")
	var objectives: Array = scene.get("MILESTONE_OBJECTIVES")
	var first_key: String = str((objectives[0] as Dictionary).key)

	# A session that has already seen state does not replay it, so seed the previous frame.
	var seeded := {}
	for step: Dictionary in objectives: seeded[str(step.key)] = false
	scene.set("_last_milestones", seeded)
	hud.show_notification("", "INFO")

	var reached := seeded.duplicate()
	reached[first_key] = true
	scene.call("_announce_reached_milestones", reached)
	_check(hud.last_notification().contains(str((objectives[0] as Dictionary).title)),
		"reaching a milestone is announced: '%s'" % hud.last_notification())

	# And a session that starts already holding milestones stays quiet.
	scene.set("_last_milestones", {})
	hud.show_notification("", "INFO")
	scene.call("_announce_reached_milestones", reached)
	_check(hud.last_notification().is_empty(),
		"a loaded save does not replay its whole history as notifications")


# The simulation counters each Experiment waits on, and where the counter comes from. Four of
# the eight are known to have no counter at all: the key is read, nothing ever publishes it, and
# the Experiment can never complete. They are listed here rather than quietly ignored so that the
# gap is visible, cannot grow, and closes the moment someone implements the counter. Adding one
# of the missing counters makes this test tell you to move its entry into the wired list.
const EXPERIMENT_SOURCES := {
	"heavy_captured": "get_wet_processing_statistics",
	"charcoal_produced": "get_organic_statistics",
	"steam_generated": "get_gas_statistics",
	"steam_mass": "get_pipe_statistics",
}
const EXPERIMENTS_WITHOUT_A_COUNTER := [
	"wet_then_dry_events", "vessel_material_comparisons",
	"oxygen_starved_events", "modified_furnace_temperature_gain",
]

func _test_experiments_that_claim_to_be_reachable_are(scene: Node) -> void:
	var world: Variant = scene.get("world")
	for key: String in EXPERIMENT_SOURCES:
		var published: Dictionary = world.call(str(EXPERIMENT_SOURCES[key]))
		_check(published.has(key), "Experiment counter '%s' is published by %s" % [key, EXPERIMENT_SOURCES[key]])

	# And the ones with no counter still have none, so the list stays honest.
	var everywhere := {}
	for getter: String in ["get_wet_processing_statistics", "get_organic_statistics", "get_gas_statistics",
			"get_pipe_statistics", "get_processing_statistics", "get_physical_processing_statistics",
			"get_thermal_statistics", "get_structure_statistics", "get_power_statistics"]:
		for key: Variant in (world.call(getter) as Dictionary).keys(): everywhere[str(key)] = true
	for key: String in EXPERIMENTS_WITHOUT_A_COUNTER:
		_check(not everywhere.has(key),
			"'%s' still has no counter; if it now does, wire the Experiment to it" % key)


func _test_the_first_instruction_actually_works(scene: Node) -> void:
	# The game now tells a new player exactly this: "Place a Conveyor in open air above the
	# ground · Drop matter onto it · Watch it travel". Following those words has to reach the
	# milestone they are attached to, or the instruction is worse than no instruction.
	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var spawn: Vector2i = world.get_character_spawn()
	var chunk := Vector2i(spawn.x >> 6, spawn.y >> 6)
	world.request_chunk_region(Rect2i(chunk.x - 2, chunk.y - 2, 5, 4), 0)
	world.flush_generation()

	# Find the ground under the spawn, then the open air one cell above it.
	var ground_y := spawn.y
	for y in range(spawn.y - 20, spawn.y + 40):
		if int(world.get_cell(Vector2i(spawn.x, y))) != 0:
			ground_y = y
			break
	var belt_y := ground_y - 3
	var from_cell := Vector2i(spawn.x - 6, belt_y)
	var to_cell := Vector2i(spawn.x + 6, belt_y)

	_equal(int(world.place_conveyor_line(from_cell, to_cell, 1)), to_cell.x - from_cell.x + 1,
		"a Conveyor goes into the open air above the ground, as instructed")

	# Drop matter onto it -- from above, which is what "drop" means and what a player does.
	# Painting it directly into the cell above the belt would wake the belt through set_cell()
	# and prove nothing: the bug was that matter arriving by falling never woke anything.
	for x in range(from_cell.x, to_cell.x + 1):
		world.set_cell(Vector2i(x, belt_y - 4), 2)

	var moved := false
	for _tick in range(240):
		world.step()
		if int(world.get_structure_statistics().get("belt_moves", 0)) > 0:
			moved = true
			break
	_check(moved, "the matter travels once it lands on the Conveyor")
	_check(bool(world.get_milestone_state().get("first_material_flow", false)),
		"following the first instruction reaches the milestone it is attached to")


func _scripts_under(root: String) -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null: return paths
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var full := "%s/%s" % [root, name]
		if directory.current_is_dir():
			if not name.begins_with("."): paths.append_array(_scripts_under(full))
		elif name.ends_with(".gd"):
			paths.append(full)
		name = directory.get_next()
	directory.list_dir_end()
	return paths


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
