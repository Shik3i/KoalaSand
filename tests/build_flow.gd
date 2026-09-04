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
const RESEARCH_BANK := 8
const EMPTY_MATERIAL := 0
const SAND := 2
const GLASS := 10
const REFRACTORY_WALL := 40
const MESH_SCREEN := 41
const RIFFLE := 43
const VIBRATION_ACTUATOR := 45
const WATER := 3
const STONE := 1
const REACTION_TEMPERATURE := 5893

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
	_test_the_second_instruction_tells_the_truth(scene)
	_test_the_advice_to_dig_it_out_can_be_followed(scene)
	_test_the_route_to_glass_exists_and_works(scene)
	_test_the_route_to_a_concentrate_exists_and_works(scene)
	_test_the_route_through_water_exists_and_works(scene)
	_test_no_promise_names_a_machine_the_catalog_does_not_have(scene)
	_test_the_catalog_offers_every_component_that_is_meant_to_be_offered(scene)
	_test_a_belt_can_be_built_in_both_directions(scene)
	_test_every_catalog_category_shows_something(scene)
	_test_the_guided_arrow_says_something_a_player_can_act_on(scene)
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


func _test_the_second_instruction_tells_the_truth(scene: Node) -> void:
	# The second objective says "A Research Bank takes only Glass, Iron or Gold". A guidance
	# line is a promise about the simulation, so it gets checked against the simulation: the
	# Bank must take Glass and must not take Raw Sand.
	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var definition := {}
	for entry: Dictionary in world.get_structure_definitions():
		if int(entry.get("type_id", 0)) == RESEARCH_BANK: definition = entry; break
	_check(not definition.is_empty(), "the Research Bank definition is available")
	if definition.is_empty(): return
	var inputs: Array = definition.get("input_ports", [])
	_check(not inputs.is_empty(), "the Research Bank has an input port")
	if inputs.is_empty(): return

	for probe in [{"material": GLASS, "accepted": true}, {"material": SAND, "accepted": false}]:
		var origin := Vector2i(600 + 40 * int(probe.material), 300)
		# Clear room, place the Bank, and offer one cell at its input port.
		world.paint_stroke(origin - Vector2i(4, 4), origin + Vector2i(24, 16), 6, EMPTY_MATERIAL)
		_check(int(world.place_structure(RESEARCH_BANK, origin, 0)) > 0,
			"a Research Bank can be placed to test material %d" % int(probe.material))
		var before := int(world.get_bank_statistics().get("accepted_total", 0))
		world.set_cell(origin + Vector2i(inputs[0]), int(probe.material))
		for _tick in range(120): world.step()
		var accepted := int(world.get_bank_statistics().get("accepted_total", 0)) > before
		_equal(accepted, bool(probe.accepted),
			"the Research Bank %s material %d, as the objective says" % ["takes" if probe.accepted else "refuses", int(probe.material)])


func _test_the_advice_to_dig_it_out_can_be_followed(scene: Node) -> void:
	# Refusing a placement with "dig it out first" is only honest if there is a way to dig.
	# Excavate was bound to the E key on a toolbar this UI does not show, and appeared in
	# neither the catalog nor the action row, so in Factory Mode -- which has no character to
	# dig with -- there was no discoverable way to move terrain at all.
	var hud: Variant = scene.get("factory_hud")
	var names := {}
	for tool: Dictionary in (hud.get_meta("catalog_tools") as Array): names[str(tool.get("name", ""))] = tool
	_check(names.has("Excavate"), "a tool named Excavate is findable in the catalog")
	_check(names.has("Harvest Coal"), "a tool named Harvest Coal is findable, as the objective asks for")

	# Selecting it has to actually put the brush in erase mode, and erasing has to work.
	scene.call("_on_factory_tool_selected", {"kind": "terrain", "id": 2, "name": "Excavate"})
	_equal(int(scene.get("brush_mode")), 2, "Excavate selects the erase brush")
	_equal(int(scene.call("_current_brush_material")), 0, "the erase brush writes emptiness")

	var world: Variant = scene.get("world")
	var spawn: Vector2i = world.get_character_spawn()
	var solid := Vector2i(spawn.x + 200, spawn.y + 8)
	world.set_cell(solid, 1)
	_check(int(world.get_cell(solid)) != 0, "there is something to dig out")
	scene.set("_painting", true)
	scene.call("_paint_line", solid, solid)
	_equal(int(world.get_cell(solid)), 0, "following the advice clears the cell")
	scene.set("_painting", false)


func _test_the_route_to_glass_exists_and_works(scene: Node) -> void:
	# The second objective sends the player to the Basic Furnace plan and to heating Raw Sand
	# inside it. Both halves are checked, because the obvious reading of the game is wrong: the
	# Radiant Crude Furnace is a dev fixture, deliberately excluded from the catalog, and
	# processing is composable geometry instead. Refractory Wall next to hot sand is the actual
	# mechanic, and it is easy to write an instruction that names a machine that does not exist.
	var blueprints: Variant = scene.get("_blueprints")
	_check(blueprints.load_blueprint("basic_furnace") != null,
		"the Basic Furnace plan the objective names is in the library")

	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var origin := Vector2i(900, 300)
	world.paint_stroke(origin - Vector2i(12, 12), origin + Vector2i(12, 8), 12, EMPTY_MATERIAL)
	for x in range(origin.x - 12, origin.x + 13):
		world.set_cell(Vector2i(x, origin.y + 4), 1)
	var wall := Vector2i(origin.x, origin.y + 3)
	_check(int(world.place_structure(REFRACTORY_WALL, wall, 0)) > 0, "a Refractory Wall can be placed")

	# Hot enough to react, set directly so the thing under test is the mechanic rather than a
	# hand-tuned fire.
	for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		world.set_material_state(wall + offset, SAND, 255, REACTION_TEMPERATURE + 400, 0, 0)
	var changed := false
	for _block in range(12):
		for _tick in range(30): world.step()
		for offset in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
			var material := int(world.get_cell(wall + offset))
			if material != SAND and material != EMPTY_MATERIAL: changed = true
		if changed: break
	_check(changed, "Raw Sand heated past the reaction temperature beside Refractory geometry fractionates")


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


func _test_the_route_to_a_concentrate_exists_and_works(scene: Node) -> void:
	# The third objective used to send the player to the Vibrating Screen, which is a dev
	# fixture excluded from the catalog. The real mechanic is geometry: a Vibration Actuator
	# standing next to a Mesh Screen fractionates whatever lands on the Mesh.
	var blueprints: Variant = scene.get("_blueprints")
	_check(blueprints.load_blueprint("basic_screen") != null,
		"the Basic Screen plan the objective names is in the library")

	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var origin := Vector2i(1500, 300)
	world.paint_stroke(origin - Vector2i(16, 16), origin + Vector2i(16, 10), 16, EMPTY_MATERIAL)
	for x in range(origin.x - 16, origin.x + 17):
		world.set_cell(Vector2i(x, origin.y + 6), STONE)
	var actuator := origin
	var mesh := actuator + Vector2i(1, 0)
	_check(int(world.place_structure(VIBRATION_ACTUATOR, actuator, 0)) > 0,
		"a Vibration Actuator can be placed")
	_check(int(world.place_structure(MESH_SCREEN, mesh, 0)) > 0, "a Mesh Screen can be placed")

	var before: int = int(world.get_conservation_architecture().get("output_micro_mass", 0))
	for _tick in range(240):
		if int(world.get_cell(mesh + Vector2i(0, -1))) == EMPTY_MATERIAL:
			world.set_cell(mesh + Vector2i(0, -1), SAND)
		world.step()
	_check(int(world.get_conservation_architecture().get("output_micro_mass", 0)) > before,
		"Raw Sand landing on a driven Mesh Screen is fractionated")
	_check(bool(world.get_milestone_state().get("first_concentrate", false)),
		"the objective the game shows for this step is the one the simulation marks")


func _test_the_route_through_water_exists_and_works(scene: Node) -> void:
	# The sixth objective used to send the player to the Wash Sluice, also a dev fixture. The
	# player-facing component is the Riffle, and the condition that is easy to miss -- and that
	# the criteria now state -- is that it does nothing without Water beside it.
	var blueprints: Variant = scene.get("_blueprints")
	_check(blueprints.load_blueprint("basic_wet_sluice") != null,
		"the Basic Wet Sluice plan the objective names is in the library")

	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var origin := Vector2i(1800, 300)
	world.paint_stroke(origin - Vector2i(16, 16), origin + Vector2i(16, 10), 16, EMPTY_MATERIAL)
	for x in range(origin.x - 8, origin.x + 9):
		world.set_cell(Vector2i(x, origin.y + 2), STONE)
	var riffle := origin + Vector2i(0, 1)
	_check(int(world.place_structure(RIFFLE, riffle, 0)) > 0, "a Riffle can be placed")
	for dy in [0, 1]:
		world.set_cell(Vector2i(origin.x - 3, origin.y + dy), STONE)
		world.set_cell(Vector2i(origin.x + 3, origin.y + dy), STONE)

	# Dry first: the same geometry, the same grain, no Water. Nothing may happen, or the
	# criterion telling the player that Water is what makes a Riffle work would be a guess.
	for _tick in range(60):
		if int(world.get_cell(origin)) != SAND: world.set_cell(origin, SAND)
		world.step()
	_check(not bool(world.get_milestone_state().get("water_processing", false)),
		"a Riffle with no Water beside it does nothing")

	for _tick in range(240):
		for dx in [-2, -1, 1, 2]:
			var cell := Vector2i(origin.x + dx, origin.y)
			if int(world.get_cell(cell)) == EMPTY_MATERIAL: world.set_cell(cell, WATER)
		if int(world.get_cell(origin)) != SAND: world.set_cell(origin, SAND)
		world.step()
	_check(bool(world.get_milestone_state().get("water_processing", false)),
		"grains carried over a Riffle by Water are processed")


func _test_no_promise_names_a_machine_the_catalog_does_not_have(scene: Node) -> void:
	# Three separate places told the player to use a machine that cannot be built: the second
	# and third objectives, and the reward line of three research nodes -- the text a player
	# reads while deciding how to spend a scarce resource. COMPOSABLE_PROCESSING.md retired
	# those machines to dev fixtures and replaced them with geometry, and the text layer was
	# never brought along. This pins every one of those surfaces at once.
	var world: Variant = scene.get("world")
	var forbidden: Array[String] = []
	for definition: Dictionary in world.get_structure_definitions():
		var type_id := int(definition.get("type_id", -1))
		if ComponentPresentation.DEV_TYPES.has(type_id):
			var display := str(definition.get("display_name", ""))
			if not display.is_empty(): forbidden.append(display)
	_check(forbidden.size() >= 4, "the dev fixtures have names to look for (%d)" % forbidden.size())

	var surfaces: Array[Array] = []
	for objective: Dictionary in scene.get("MILESTONE_OBJECTIVES"):
		for line: String in objective.get("criteria", []):
			surfaces.append(["objective %s" % str(objective.get("key", "?")), line])
	for research: Dictionary in world.get_research_definitions():
		surfaces.append(["research %s effect" % str(research.get("id", "?")), str(research.get("effect", ""))])
		surfaces.append(["research %s description" % str(research.get("id", "?")), str(research.get("description", ""))])

	var violations: Array[String] = []
	for surface: Array in surfaces:
		for name: String in forbidden:
			if str(surface[1]).contains(name): violations.append(str(surface[0]))
	violations.sort()
	_equal(violations, [] as Array[String],
		"no player-facing promise names a machine the catalog does not have")


func _test_the_catalog_offers_every_component_that_is_meant_to_be_offered(scene: Node) -> void:
	# The Build Catalog is a hand-written list in factory_hud.gd, and the structure table it is
	# supposed to mirror lives in native_sand_world.cpp. Nothing connected the two, so a
	# Component could be defined, unlockable, gated by its own research node and simply never
	# offered -- which is what happened to the Iron Pot: thermal.cookware charged 900 Glass and
	# 60 Iron to unlock something no player could reach. is_player_facing() is the rule for what
	# belongs in the catalog, so it is the rule this checks against.
	var world: Variant = scene.get("world")
	var hud: Variant = scene.get("factory_hud")
	var offered := {}
	for tool: Dictionary in hud.get_meta("catalog_tools", []):
		if str(tool.get("kind", "")) == "structure": offered[int(tool.get("id", -1))] = true
		# A Subsurface Channel is one catalog entry per depth and two structures -- an entrance
		# and an exit -- placed together by a drag, so the six of them are offered under their
		# own kind rather than as Components.
		elif str(tool.get("kind", "")) == "subsurface":
			var depth := int(tool.get("depth", 0))
			offered[18 + depth * 2] = true
			offered[19 + depth * 2] = true

	var missing: Array[String] = []
	for definition: Dictionary in world.get_structure_definitions():
		var type_id := int(definition.get("type_id", -1))
		if not ComponentPresentation.is_player_facing(type_id, definition): continue
		if not offered.has(type_id):
			missing.append("%d %s" % [type_id, str(definition.get("display_name", ""))])
	missing.sort()
	_equal(missing, [] as Array[String], "every player-facing Component is in the Build Catalog")


func _test_a_belt_can_be_built_in_both_directions(scene: Node) -> void:
	# The catalog listed one Conveyor, and _place_conveyor_drag() reads the direction straight off
	# the selected type: "-1 if build_structure_type == 1 else 1". Type 1 was not selectable, so
	# every belt a player could build in a factory game ran to the right. Both are listed now, and
	# this is the check that the second one is not merely a second name for the first.
	var world: Variant = scene.get("world")
	world.set_game_mode(1)
	var origin := Vector2i(2100, 300)
	world.paint_stroke(origin - Vector2i(16, 16), origin + Vector2i(16, 10), 16, EMPTY_MATERIAL)
	for x in range(origin.x - 12, origin.x + 13):
		world.set_cell(Vector2i(x, origin.y + 1), STONE)

	var moved := {}
	for direction in [-1, 1]:
		# Two rows well apart, so neither run has to be torn down before the other is built.
		var row := origin.y - (2 if direction < 0 else 6)
		_check(int(world.place_conveyor_line(Vector2i(origin.x - 8, row), Vector2i(origin.x + 8, row), direction)) > 0,
			"a belt can be placed running %s" % ("left" if direction < 0 else "right"))
		var start := Vector2i(origin.x, row - 1)
		world.set_cell(start, SAND)
		# Six ticks, not thirty: a belt carries about a cell a tick, and a grain that runs off the
		# end of a seventeen-cell run falls to the floor and stops being evidence of anything.
		for _tick in range(6): world.step()
		var landed := 0
		for offset in range(-10, 11):
			if int(world.get_cell(start + Vector2i(offset, 0))) == SAND: landed = offset * direction
		moved[direction] = landed

	_check(int(moved[1]) > 0, "matter on a right-hand belt travels right (%d cells)" % int(moved[1]))
	_check(int(moved[-1]) > 0, "matter on a left-hand belt travels left (%d cells)" % int(moved[-1]))


func _test_every_catalog_category_shows_something(scene: Node) -> void:
	# The Build Catalog has eight filter tabs. _canonical_category() decides which one a Component
	# lands in by testing substrings in order, and "Processing Component" contains both
	# "component" and "processing" -- with the component test first, every Mesh Screen, Riffle,
	# Vibration Actuator, Electromagnet and Blower filed under Structures. Nothing else in the
	# catalog carried the word "processing", so the Processing tab was empty in every world, in
	# every mode, from the first launch: a player following the objective to a Mesh Screen and
	# reaching for the obvious tab was told "No Components match this search".
	var hud: Variant = scene.get("factory_hud")
	var populated := {}
	for tool: Dictionary in hud.get_meta("catalog_tools", []):
		var category: String = str(hud.call("_canonical_category", tool))
		populated[category] = int(populated.get(category, 0)) + 1

	for category in ["LOGISTICS", "PROCESSING", "FLUIDS", "THERMAL", "POWER", "AUTOMATION", "STRUCTURES"]:
		_check(int(populated.get(category, 0)) > 0,
			"the %s tab of the Build Catalog is not empty" % category)

	# And the tab holds the Components the objectives send the player to find.
	var processing := {}
	for tool: Dictionary in hud.get_meta("catalog_tools", []):
		if str(hud.call("_canonical_category", tool)) == "PROCESSING": processing[str(tool.get("name", ""))] = true
	for name in ["Mesh Screen", "Vibration Actuator", "Riffle"]:
		_check(processing.has(name), "the Processing tab holds the %s the objectives name" % name)


func _test_the_guided_arrow_says_something_a_player_can_act_on(_scene: Node) -> void:
	# The guided highlight labelled itself from the step id, so the very first thing the game
	# pointed at in Character Mode read "Character Intro" -- an internal identifier, not an
	# instruction. Every step now carries the words the arrow says.
	for preset: int in OnboardingState.STEPS:
		for step: Dictionary in OnboardingState.STEPS[preset]:
			var id := str(step.get("id", ""))
			var label := str(step.get("label", ""))
			_check(not label.is_empty(), "step %s has a label for the guided arrow" % id)
			# Not "differs from the id": OPEN_CATALOG prettifies to "Open Catalog", which is a
			# perfectly good instruction, and a check that failed it would be measuring the
			# wrong thing. What must never come back is a raw identifier.
			_check(not "_" in label and label != label.to_upper(),
				"step %s is not labelled with an identifier (%s)" % [id, label])
			_check(label.length() <= 20, "step %s label stays short enough to draw (%s)" % [id, label])
