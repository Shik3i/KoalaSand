extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_benchmark_corrections()
	_benchmark_character_controller()
	_benchmark_vision()
	await _benchmark_ui()
	_benchmark_gameplay_loop()
	if failures.is_empty():
		print("PASS: Phase 11.5 performance gates (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: Phase 11.5 performance gates %d/%d" % [failures.size(), checks])
		quit(1)


func _benchmark_corrections() -> void:
	var world: Variant = _world(1)
	var report: Dictionary = world.validate_world_seeds(1, 25000)
	var p: Dictionary = report.metrics.corrections_per_seed
	print("phase115_seed_sweep seeds=%d elapsed_ms=%.3f seeds_per_second=%.1f corrections=%d average=%.4f p50=%.0f p95=%.0f p99=%.0f max=%.0f major_percent=%.3f" % [report.seed_count, report.elapsed_ms, report.seeds_per_second, report.corrections, report.average_corrections_per_seed, p.p50, p.p95, p.p99, p.max, report.major_correction_percentage])
	_check_equal(report.validation_failures, 0, "25k seed validation")
	_check(float(report.seeds_per_second) > 20000.0, "correction sweep throughput")
	_check_equal(float(report.major_correction_percentage), 0.0, "no major generator rescue")


func _benchmark_character_controller() -> void:
	var world := NativeSandWorld.new(); world.reset(7, 1); world.allocate_chunk_rect(Rect2i(-8, -4, 16, 8))
	for x in range(-500, 501): world.set_cell(Vector2i(x, 20), 1)
	var camera := Camera2D.new(); var controller := KoalaCharacterController.new(); controller.initialize(world, camera, Vector2i.ZERO, 2.0)
	controller.sprint_unlocked = true; controller.hover_unlocked = true
	var started := Time.get_ticks_usec()
	for index in range(100000):
		var mask := KoalaCharacterController.INPUT_RIGHT
		if index % 240 < 120: mask |= KoalaCharacterController.INPUT_JETPACK
		if index % 600 < 300: mask |= KoalaCharacterController.INPUT_SPRINT
		if index % 1200 == 0: mask |= KoalaCharacterController.INPUT_HOVER
		controller.replay_step(mask, false)
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_character_controller ticks=100000 total_ms=%.3f avg_ms=%.6f collision_latest_ms=%.6f fov_latest_ms=%.4f collision_queries=%d sampled=%d" % [elapsed, elapsed / 100000.0, controller.last_collision_ms, controller.last_visibility_ms, controller.collision_queries, controller.collision_cells_sampled])
	_check(elapsed / 100000.0 < 0.05, "Character controller average bounded")
	controller.free(); camera.free()


func _benchmark_vision() -> void:
	var open := NativeSandWorld.new(); open.reset(9, 1); open.allocate_chunk_rect(Rect2i(-5, -5, 11, 11))
	var open_samples: Array[float] = []
	for index in 50:
		var started := Time.get_ticks_usec(); open.update_character_visibility(1, Vector2i(index - 25, 0), 72, 8); open_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var irregular := NativeSandWorld.new(); irregular.reset(10, 1); irregular.allocate_chunk_rect(Rect2i(-5, -5, 11, 11))
	for y in range(-90, 91):
		for x in range(-90, 91):
			if ((x * 17 + y * 31) & 7) < 3 and x * x + y * y > 18 * 18: irregular.set_cell(Vector2i(x, y), 1)
	var shell_samples: Array[float] = []
	for index in 30:
		var started := Time.get_ticks_usec(); irregular.update_character_visibility(1, Vector2i(index % 7 - 3, index / 7 - 2), 72, 8); shell_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	open_samples.sort(); shell_samples.sort()
	print("phase115_vision cavern_avg_ms=%.4f cavern_p99_ms=%.4f irregular_avg_ms=%.4f irregular_p99_ms=%.4f discovery_bytes_per_chunk=%d" % [_average(open_samples), _percentile(open_samples, 0.99), _average(shell_samples), _percentile(shell_samples, 0.99), open.get_visibility_statistics(1).bytes_per_discovered_chunk])
	_check(_percentile(open_samples, 0.99) < 5.0, "large cavern FOV p99")
	_check(_percentile(shell_samples, 0.99) < 5.0, "irregular wall FOV p99")


func _benchmark_ui() -> void:
	var world: Variant = _world(17)
	var hud := FactoryHUD.new(); root.add_child(hud); await process_frame; hud.initialize(world)
	var labels := ["normal", "build_catalog", "statistics"]
	var costs: Array[float] = []
	for label in labels:
		if label == "build_catalog": hud.toggle_catalog()
		if label == "statistics": hud.toggle_statistics()
		var started := Time.get_ticks_usec()
		for index in 1000: hud.refresh("CONVEYOR", "1x")
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		costs.append(elapsed / 1000.0)
		print("phase115_ui surface=%s refresh_avg_ms=%.6f" % [label, costs[-1]])
		if label != "normal": hud.close_top_modal()
	var map := WorldMapPanel.new(); root.add_child(map); await process_frame
	var started := Time.get_ticks_usec(); map.initialize(world, GameModeCapabilities.Preset.CHARACTER); var map_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_ui surface=map refresh_ms=%.4f" % map_ms)
	var research := ResearchTreePanel.new(); research.size = Vector2(1600, 900); root.add_child(research); await process_frame
	started = Time.get_ticks_usec(); research.initialize(world); research.call("_process", 0.0); var research_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_ui surface=research open_ms=%.4f update_ms=%.4f" % [research_ms, research.last_update_ms])
	var overlay := ShowcaseOverlay.new(); root.add_child(overlay); await process_frame; overlay.initialize(world)
	started = Time.get_ticks_usec(); overlay.set_info_mode(true, Rect2i(-4, -3, 9, 7)); var info_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_ui surface=info_mode open_ms=%.4f" % info_ms)
	var preview_cells: Array[Vector2i] = []
	for index in 1000: preview_cells.append(Vector2i(index % 50, index / 50))
	started = Time.get_ticks_usec(); overlay.set_structure_preview(preview_cells, true); var blueprint_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_ui surface=blueprint_preview cells=1000 update_ms=%.4f" % blueprint_ms)
	var map_overlay := MapOverlayRenderer.new(); root.add_child(map_overlay); await process_frame; map_overlay.initialize(world)
	started = Time.get_ticks_usec(); map_overlay.set_mode(MapOverlayRenderer.Mode.TEMPERATURE); map_overlay.sync_visible(Rect2i(-4, -3, 9, 7)); var overlay_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("phase115_ui surface=temperature_overlay open_ms=%.4f update_ms=%.4f upload_ms=%.4f upload_bytes=%d" % [overlay_ms, map_overlay.last_update_ms, map_overlay.last_upload_ms, map_overlay.last_upload_bytes])
	_check(costs.max() < 0.1, "HUD refresh nearly free")
	_check(map_ms < 20.0, "Map open bounded")
	_check(maxf(research_ms, maxf(info_ms, maxf(blueprint_ms, overlay_ms))) < 20.0, "player UI opens bounded")
	map_overlay.free(); overlay.free(); research.free(); map.free(); hud.free()


func _benchmark_gameplay_loop() -> void:
	var report: Dictionary = FirstSessionFixture.run(_world(8675309), 8675309)
	print("phase115_gameplay_loop ticks=%d travel=%d moving_ticks=%d building_ticks=%d dig_actions=%d build_actions=%d movement_share=%.3f sprint_minutes=%.2f hover_minutes=%.2f" % [report.hover_tick, report.travel_distance_cells, report.moving_ticks, report.building_ticks, report.dig_actions, report.build_actions, report.movement_share, float(report.sprint_tick) / 3600.0, float(report.hover_tick) / 3600.0])
	_check(float(report.movement_share) < 0.70, "travel not dominant")
	_check(float(report.hover_tick) / 3600.0 <= 15.0, "Hover early enough")


func _world(seed: int) -> Variant:
	var world := NativeSandWorld.new(); world.configure_world({"seed": seed, "generation_version": 2}, 4); return world


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxi(1, values.size())


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(roundi((values.size() - 1) * fraction), 0, values.size() - 1)]


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
