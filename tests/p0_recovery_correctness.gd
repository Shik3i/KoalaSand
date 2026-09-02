extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_generation_identity_and_determinism()
	_test_generation_stability()
	_test_intentional_destabilization()
	await _test_responsive_menu_and_hud()
	if failures.is_empty():
		print("PASS: %d P0 recovery correctness checks" % checks)
		quit(0)
	else:
		for failure: String in failures: push_error("P0_RECOVERY: " + failure)
		print("FAIL: %d of %d P0 recovery checks" % [failures.size(), checks])
		quit(1)


func _test_generation_identity_and_determinism() -> void:
	var area := Rect2i(-4, -1, 9, 12)
	var first: Variant = _world(8675309, 3, 1)
	var second: Variant = _world(8675309, 3, 8)
	first.request_chunk_region(area, 1); second.request_chunk_region(area, 1)
	first.flush_generation(); second.flush_generation()
	_check_equal(int(first.get_world_identity().generation_version), 3, "new worlds use generation version 3")
	_check_equal(first.get_region_content_hash(area), second.get_region_content_hash(area), "V3 worker-count deterministic")
	var v2: Variant = _world(8675309, 2, 4); v2.request_chunk_region(area, 1); v2.flush_generation()
	_check_equal(int(v2.get_world_identity().generation_version), 2, "legacy V2 remains selectable")
	_check(first.get_region_content_hash(area) != v2.get_region_content_hash(area), "V3 semantics have explicit new content hash")
	var before: String = first.authoritative_physical_hash()
	first.get_generation_stability_report(area)
	_check_equal(first.authoritative_physical_hash(), before, "stability diagnostics are read-only")


func _test_generation_stability() -> void:
	var area := Rect2i(-6, -1, 13, 14)
	for seed in [3, 2965, 8675309, 15508, 18076]:
		var world: Variant = _world(seed, 3, 8)
		world.request_chunk_region(area, 1); world.flush_generation()
		var report: Dictionary = world.get_generation_stability_report(area)
		if int(report.initially_active_dynamic_cells) > 0:
			print("p0_unstable_sample seed=%d sand=%s water=%s" % [seed, str(report.unsupported_sand_sample_xy), str(report.active_water_sample_xy)])
		_check_equal(int(report.chunks_inspected), area.get_area(), "seed %d publishes complete stability sample" % seed)
		_check_equal(int(report.unsupported_sand_cells), 0, "seed %d has no unsupported generated sand" % seed)
		_check_equal(int(report.initially_active_water_cells), 0, "seed %d has no initially active generated water" % seed)
		_check_equal(int(report.water_vertical_drop_cells), 0, "seed %d has no generated waterfalls" % seed)
		_check(bool(report.stable), "seed %d generated region is near equilibrium" % seed)
		_check(int(report.minimum_surface_roof_cells) >= 34, "seed %d preserves at least 34-cell surface roof" % seed)
		var limits: Array = report.void_fraction_limits
		var maxima: Array = report.maximum_chunk_void_fraction_by_depth_band
		for band in range(3):
			_check(float(maxima[band]) <= float(limits[band]) + 0.0001, "seed %d depth band %d respects void cap" % [seed, band])
		_check_equal(int(report.active_sand_chunks), 0, "seed %d publishes sleeping sand" % seed)
		_check_equal(int(report.active_fluid_chunks), 0, "seed %d publishes sleeping water" % seed)


func _test_intentional_destabilization() -> void:
	var area := Rect2i(-4, -1, 10, 8)
	var sand_world: Variant = _world(8675309, 3, 4)
	sand_world.request_chunk_region(area, 0); sand_world.flush_generation()
	var sand := _find_supported_cell(sand_world, area, 2)
	_check(sand != Vector2i(999999, 999999), "stable generated sand fixture found")
	if sand != Vector2i(999999, 999999):
		sand_world.set_cell(sand + Vector2i(0, 1), 0)
		var before_sand: int = sand_world.get_cell(sand)
		sand_world.step()
		_check(before_sand == 2 and (sand_world.get_cell(sand + Vector2i(0, 1)) == 2 or int(sand_world.get_statistics().cells_moved) > 0), "digging support wakes physical sand")

	var water_world: Variant = _world(8675309, 3, 4)
	water_world.request_chunk_region(Rect2i(-2, 0, 7, 8), 0); water_world.flush_generation()
	var water := _find_supported_cell(water_world, Rect2i(-2, 0, 7, 8), 3)
	_check(water != Vector2i(999999, 999999), "contained generated aquifer fixture found")
	if water != Vector2i(999999, 999999):
		water_world.set_cell(water + Vector2i(0, 1), 0)
		water_world.step()
		_check(water_world.get_cell(water + Vector2i(0, 1)) == 3, "breaching aquifer wakes physical water")


func _test_responsive_menu_and_hud() -> void:
	_check_equal(str(ProjectSettings.get_setting("display/window/stretch/aspect", "")), "expand", "viewport stretch expands without pillarboxing")
	var world: Variant = _world(1399, 3, 1)
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1920, 1200)]:
		var host := Control.new(); host.size = Vector2(resolution); root.add_child(host)
		var menu := NewGameScreen.new(); host.add_child(menu)
		for ignored in 5: await process_frame
		var menu_metrics: Dictionary = menu.layout_metrics()
		var viewport := Rect2(Vector2.ZERO, Vector2(resolution))
		_check(UILayoutAudit.within(menu_metrics.root, viewport, 0.1), "%s menu root on-screen" % resolution)
		_check(UILayoutAudit.within(menu_metrics.create, viewport, 0.1), "%s Create world visible" % resolution)
		_check_equal(int(menu_metrics.scroll_containers), 0, "%s main page has no ScrollContainer" % resolution)
		_check(UILayoutAudit.separated(menu_metrics.preview, menu_metrics.settings), "%s preview/settings separated" % resolution)
		for card: Rect2 in menu_metrics.mode_cards:
			_check(UILayoutAudit.within(card, viewport, 0.1), "%s mode card on-screen" % resolution)
		menu.queue_free(); await process_frame

		var hud := FactoryHUD.new(); host.add_child(hud); await process_frame
		hud.initialize(world); hud.configure_mode(GameModeCapabilities.Preset.FACTORY)
		for ignored in 4: await process_frame
		var hud_metrics: Dictionary = hud.layout_metrics()
		print("p0_ui resolution=%dx%d top_px=%.1f bottom_px=%.1f world_px=%.1f world_percent=%.2f" % [resolution.x, resolution.y, hud_metrics.top.size.y, hud_metrics.bottom.size.y, hud_metrics.bottom.position.y - hud_metrics.top.end.y, (hud_metrics.bottom.position.y - hud_metrics.top.end.y) * 100.0 / resolution.y])
		_check(UILayoutAudit.within(hud_metrics.top, viewport), "%s top HUD on-screen" % resolution)
		_check(UILayoutAudit.within(hud_metrics.bottom, viewport), "%s bottom HUD on-screen" % resolution)
		_check(float(hud_metrics.top.size.y) <= 72.0, "%s top HUD <=72 px at 100%%" % resolution)
		_check(float(hud_metrics.bottom.size.y) >= 90.0 and float(hud_metrics.bottom.size.y) <= 130.0, "%s bottom HUD 90..130 px" % resolution)
		var world_height := float(hud_metrics.bottom.position.y - hud_metrics.top.end.y)
		_check(world_height >= float(resolution.y) * 0.72, "%s keeps at least 72%% vertical world view" % resolution)
		_check(UILayoutAudit.surface_overflow(hud.layout_surfaces().top).is_empty(), "%s top HUD has no child overflow" % resolution)
		_check(UILayoutAudit.surface_overflow(hud.layout_surfaces().bottom).is_empty(), "%s bottom HUD has no child overflow" % resolution)
		host.queue_free(); await process_frame


func _find_supported_cell(world: Variant, chunk_area: Rect2i, material: int) -> Vector2i:
	var first := chunk_area.position * 64
	var end := (chunk_area.position + chunk_area.size) * 64
	for y in range(first.y, end.y):
		for x in range(first.x, end.x):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) == material and world.get_cell(cell + Vector2i(0, 1)) in [1, 4, 5]:
				return cell
	return Vector2i(999999, 999999)


func _world(seed: int, generation_version: int, workers: int) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed":seed, "generation_version":generation_version}, workers)
	return world


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
