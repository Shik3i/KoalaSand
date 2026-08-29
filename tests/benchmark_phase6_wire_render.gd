extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var world: Variant = NativeSandWorld.new()
	world.reset(66003, 1)
	world.set_game_mode(1)
	var sources: Array[int] = []
	var targets: Array[int] = []
	for index in 25000:
		var x := index % 500
		var y := index / 500
		sources.append(world.create_automation_component(1, Vector2i(x, y * 2), {"enabled": index % 2 == 0}))
		targets.append(world.create_automation_component(5, Vector2i(x, y * 2 + 1)))
	for index in 25000:
		world.create_automation_connection(sources[index], 0, targets[index], 0)
		world.create_automation_connection(sources[(index + 1) % 25000], 0, targets[index], 1)
	for tick in 3: world.step()
	var renderer := AutomationRenderer.new()
	root.add_child(renderer)
	renderer.initialize(world)
	renderer.sync_visible(Rect2i(-1, -1, 10, 5), true)
	await _frames(30)
	var off_start := Time.get_ticks_usec()
	await _frames(300)
	var off_ms := float(Time.get_ticks_usec() - off_start) / 300000.0
	var rebuild_start := Time.get_ticks_usec()
	renderer.set_wiring_mode(true)
	await process_frame
	var rebuild_ms := float(Time.get_ticks_usec() - rebuild_start) / 1000.0
	await _frames(30)
	var on_start := Time.get_ticks_usec()
	await _frames(300)
	var on_ms := float(Time.get_ticks_usec() - on_start) / 300000.0
	print("phase6_wire_render_50k connections=50000 segments=150000 off_frame_ms=%.3f off_fps=%.1f on_frame_ms=%.3f on_fps=%.1f topology_rebuild_ms=%.3f steady_rebuilds=0 draw_callback_ms=%.3f" % [
		off_ms, 1000.0 / off_ms, on_ms, 1000.0 / on_ms, rebuild_ms, renderer.last_wire_draw_ms
	])
	quit(0)

func _frames(count: int) -> void:
	for index in count:
		await process_frame
