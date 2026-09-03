extends SceneTree

# An exception must never leave the simulation.
#
# C++ that throws through a GDExtension boundary calls std::terminate. There is no Godot error,
# no line in user://logs/godot.log and no crash dialog -- the process is simply gone, which is
# what the New Game crash looked like from the player's side: "the window just closed". That
# failure mode is unreportable, and an alpha that cannot be reported cannot be fixed.
#
# step() now catches instead. This test injects a throw, then asserts the three properties that
# make the guard worth having:
#
#   1. the process survives -- if it did not, this script would never print anything at all,
#      which is precisely how the original bug hid;
#   2. the reason is retrievable from GDScript, so the HUD can show it and the log can carry it;
#   3. a faulted world stops simulating and a new world clears the fault.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_a_thrown_exception_does_not_take_the_process_down()
	_test_a_faulted_world_stops_simulating()
	_test_a_new_world_clears_the_fault()
	if failures.is_empty():
		print("PASS: %d fault guard checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("FAULT_GUARD: " + failure)
	print("FAIL: %d of %d fault guard checks" % [failures.size(), checks])
	quit(1)

# ---------------------------------------------------------------------------------------

func _world() -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 909, "generation_version": 5}, 4)
	world.request_chunk_region(Rect2i(-1, 4, 3, 2), 0)
	world.flush_generation()
	return world


func _test_a_thrown_exception_does_not_take_the_process_down() -> void:
	var world: Variant = _world()
	_check(not world.is_faulted(), "a fresh world is not faulted")
	_check(world.get_fault_message() == "", "a fresh world has no fault message")

	world.inject_step_fault_for_test()
	world.step()

	# Reaching this line at all is the assertion. Without the guard the interpreter is gone.
	_check(world.is_faulted(), "the world reports the fault instead of terminating")
	var message: String = world.get_fault_message()
	_check(message.contains("injected simulation fault"),
		"the fault message names what was thrown (%s)" % message)
	_check(message.contains("step"), "the fault message names the stage (%s)" % message)
	_check(message.contains("tick"), "the fault message names the tick (%s)" % message)


func _test_a_faulted_world_stops_simulating() -> void:
	var world: Variant = _world()
	var spawn: Vector2i = world.get_character_spawn()
	world.set_cell(spawn + Vector2i(0, -8), 2)
	var before: String = world.material_state_hash()
	var tick_before: int = int(world.get_statistics().get("tick", 0))

	world.inject_step_fault_for_test()
	world.step()
	_check(world.is_faulted(), "the world faulted")

	# Further steps are refused rather than retried: whatever id was stale is still stale, and
	# a fault that re-throws every frame would bury the first, useful message under thousands.
	for _index in range(8):
		_equal(world.step(), 0, "a faulted world reports no movement")
	_equal(world.material_state_hash(), before, "a faulted world does not change its matter")
	_equal(int(world.get_statistics().get("tick", 0)), tick_before,
		"a faulted world does not advance its tick")


func _test_a_new_world_clears_the_fault() -> void:
	var world: Variant = _world()
	world.inject_step_fault_for_test()
	world.step()
	_check(world.is_faulted(), "the world faulted")

	world.configure_world({"seed": 5150, "generation_version": 5}, 4)
	_check(not world.is_faulted(), "starting a new world clears the fault")
	_equal(world.get_fault_message(), "", "starting a new world clears the fault message")

	world.request_chunk_region(Rect2i(-1, 4, 3, 2), 0)
	world.flush_generation()
	var spawn: Vector2i = world.get_character_spawn()
	world.set_cell(spawn + Vector2i(0, -8), 2)
	var before: String = world.material_state_hash()
	for _index in range(12): world.step()
	_check(world.material_state_hash() != before, "the recovered world simulates again")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
