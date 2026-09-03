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


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
