extends SceneTree

# What one frame of painting costs the player.
#
# The editor drives the real scene: a Creative game is started, then the pointer is dragged at
# several speeds while the brush is held down, through the same _paint_line the mouse handler
# calls. Painting is the first thing anyone does in this game, so its frame cost is a release
# gate, not a curiosity.

const BUDGET_MS := 16.6

class Driver extends Node:
	var tree_ref: SceneTree
	var scene: Node
	var frames := 0
	var cursor := Vector2i.ZERO
	var speeds: Array[int] = [4, 16, 40, 80, 160]
	var speed_index := 0
	var samples: Array[float] = []
	var last_usec := 0
	var results: Array[Dictionary] = []
	var failures: Array[String] = []

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last_usec) / 1000.0
		last_usec = now
		frames += 1
		if frames == 20:
			scene.call("_start_phase11_game", GameModeCapabilities.Preset.CREATIVE, 8675309, "BrushBenchmark")
			return
		if frames == 40:
			var spawn: Vector2i = scene.get("world").get_character_spawn()
			cursor = Vector2i(spawn.x - 400, spawn.y - 24)
			scene.set("_painting", true)
			scene.set("brush_radius", 3)
			return
		if frames < 40 or speed_index >= speeds.size():
			return
		if samples.size() >= 40:
			_finish_speed()
			return
		var speed: int = speeds[speed_index]
		var next := cursor + Vector2i(speed, ((frames % 7) - 3) * 2)
		if next.x > 700: next = Vector2i(-700, cursor.y)
		scene.call("_paint_line", cursor, next)
		cursor = next
		if frames > 42: samples.append(frame_ms)

	func _finish_speed() -> void:
		samples.sort()
		var total := 0.0
		for value in samples: total += value
		var mean := total / samples.size()
		var p95: float = samples[int(samples.size() * 0.95)]
		var speed: int = speeds[speed_index]
		print("brush_frame drag_cells=%d mean_ms=%.2f p50=%.2f p95=%.2f worst=%.2f fps=%.0f" % [
			speed, mean, samples[samples.size() / 2], p95, samples[samples.size() - 1],
			1000.0 / maxf(0.001, mean)])
		if p95 > BUDGET_MS:
			failures.append("drag of %d cells/frame costs %.2f ms at p95, over the %.1f ms frame budget" % [speed, p95, BUDGET_MS])
		samples.clear()
		speed_index += 1
		if speed_index >= speeds.size():
			scene.set("_painting", false)
			if failures.is_empty():
				print("BRUSH_BENCHMARK_PASS")
				tree_ref.quit(0)
			else:
				for failure in failures: push_error("BRUSH_BENCHMARK: " + failure)
				print("BRUSH_BENCHMARK_FAIL count=%d" % failures.size())
				tree_ref.quit(1)


func _initialize() -> void: call_deferred("_boot")

func _boot() -> void:
	var packed: PackedScene = load("res://scenes/debug_world.tscn")
	if packed == null:
		print("SCENE_LOAD_FAILED"); quit(1); return
	var scene := packed.instantiate()
	root.add_child(scene)
	var driver := Driver.new()
	driver.tree_ref = self
	driver.scene = scene
	driver.last_usec = Time.get_ticks_usec()
	root.add_child(driver)
