extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _run() -> void:
	var world := NativeSandWorld.new(); world.reset(1399, 1)
	var audit_rows: Array[String] = []
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		for ui_scale: float in [1.0, 1.25, 1.5]:
			var host := Control.new(); host.size = Vector2(resolution); root.add_child(host)
			var hud := FactoryHUD.new(); hud.theme = KoalaSandTheme.build(ui_scale); host.add_child(hud)
			await process_frame
			hud.apply_ui_scale(ui_scale); hud.initialize(world); hud.configure_mode(GameModeCapabilities.Preset.FACTORY); hud.toggle_catalog()
			if resolution == Vector2i(1600, 900) and is_equal_approx(ui_scale, 1.5): hud.apply_layout_fixture(1.6)
			for ignored in 5: await process_frame
			var metrics: Dictionary = hud.layout_metrics()
			var viewport := Rect2(Vector2.ZERO, Vector2(resolution))
			var prefix := "%dx%d@%d%%" % [resolution.x, resolution.y, roundi(ui_scale * 100.0)]
			_check(UILayoutAudit.within(metrics.top, viewport), "%s top on-screen" % prefix)
			_check(UILayoutAudit.within(metrics.bottom, viewport), "%s bottom on-screen" % prefix)
			_check(UILayoutAudit.within(metrics.catalog, viewport), "%s catalog on-screen" % prefix)
			_check(UILayoutAudit.separated(metrics.top, metrics.bottom), "%s top/bottom separated" % prefix)
			_check(UILayoutAudit.separated(metrics.catalog, metrics.top), "%s catalog/top separated" % prefix)
			_check(UILayoutAudit.separated(metrics.catalog, metrics.bottom), "%s catalog/bottom separated" % prefix)
			_check(UILayoutAudit.separated(metrics.actions, metrics.quickbar), "%s actions/quickbar separated" % prefix)
			_check(UILayoutAudit.separated(metrics.actions, metrics.utilities), "%s actions/utilities separated" % prefix)
			_check(UILayoutAudit.separated(metrics.quickbar, metrics.utilities), "%s quickbar/utilities separated" % prefix)
			_check(int(metrics.catalog_columns) >= 2 and int(metrics.catalog_columns) <= 4, "%s responsive catalog columns" % prefix)
			var surfaces: Dictionary = hud.layout_surfaces()
			var top_overflow := UILayoutAudit.surface_overflow(surfaces.top)
			var bottom_overflow := UILayoutAudit.surface_overflow(surfaces.bottom)
			_check(top_overflow.is_empty(), "%s no top overflow: %s" % [prefix, ", ".join(top_overflow)])
			_check(bottom_overflow.is_empty(), "%s no bottom overflow: %s" % [prefix, ", ".join(bottom_overflow)])
			var card_failures := 0
			for rects: Dictionary in metrics.catalog_cards:
				card_failures += UILayoutAudit.catalog_card_failures(rects).size()
			_check(card_failures == 0, "%s catalog icon/text/status separation" % prefix)
			var tooltip_size := Vector2(minf(420.0, float(resolution.x) * 0.36), 240.0 * ui_scale)
			for target: Rect2 in [metrics.utilities, metrics.goal, metrics.catalog_cards[0].card]:
				var tooltip := UILayoutPolicy.best_tooltip_rect(target, tooltip_size, Vector2(resolution), [metrics.top, metrics.bottom], [metrics.catalog])
				_check(UILayoutPolicy.inside_viewport(tooltip, Vector2(resolution)), "%s tooltip on-screen" % prefix)
				_check(UILayoutPolicy.overlap_area(tooltip, target) == 0.0, "%s tooltip avoids target" % prefix)
				_check(UILayoutPolicy.overlap_area(tooltip, metrics.top) == 0.0 and UILayoutPolicy.overlap_area(tooltip, metrics.bottom) == 0.0, "%s tooltip avoids HUD safe regions" % prefix)
				_check(UILayoutPolicy.overlap_area(tooltip, metrics.catalog) == 0.0, "%s tooltip avoids modal" % prefix)
			audit_rows.append("%s columns=%d cards=%d top_overflow=%d bottom_overflow=%d card_failures=%d" % [prefix, metrics.catalog_columns, metrics.catalog_cards.size(), top_overflow.size(), bottom_overflow.size(), card_failures])
			hud.toggle_statistics(); await process_frame
			_check(hud.visible_modal_ids() == ["statistics"], "%s one internal modal at a time" % prefix)
			host.queue_free(); await process_frame

	var target_a := Button.new(); var target_b := Button.new(); root.add_child(target_a); root.add_child(target_b)
	var highlight := GuidedHighlightLayer.new(); root.add_child(highlight); await process_frame
	highlight.show_step(target_a, "FIRST"); highlight.queue_step(target_b, "SECOND")
	_check(highlight.active() and highlight.queued_count() == 1, "guided highlight queues without stealing current focus")
	highlight.complete_step(); _check(highlight.active() and highlight.queued_count() == 0, "guided highlight advances queued target")
	_check(UILayoutPolicy.tooltip_candidates(Rect2(100, 100, 40, 40), Vector2(320, 200)).size() == 4, "tooltip evaluates four placements")
	for row: String in audit_rows: print("phase139b_layout " + row)
	if failures.is_empty():
		print("PASS: %d Phase 13.9B responsive layout checks" % checks); quit(0)
	else:
		for failure: String in failures: push_error("PHASE139B: " + failure)
		print("FAIL: %d of %d Phase 13.9B checks" % [failures.size(), checks]); quit(1)
