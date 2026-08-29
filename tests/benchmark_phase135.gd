extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, values.size())
func _percentile(values: Array[float], fraction: float) -> float:
	var sorted := values.duplicate(); sorted.sort(); return sorted[clampi(ceili(sorted.size() * fraction) - 1, 0, sorted.size() - 1)]

func _world(seed: int) -> Variant:
	var result := NativeSandWorld.new(); result.reset(seed, 8); result.set_game_mode(1); return result

func _fire_fixture(label: String, cells: int, seed: int) -> Dictionary:
	var world: Variant = _world(seed)
	var width := ceili(sqrt(float(cells)))
	for index in cells:
		var cell := Vector2i(index % width, index / width)
		world.set_material_state(cell, 21, 255, 2300)
		world.ignite_cell(cell, 24000000)
	world.finalize_initialization()
	for _warm in 10: world.step()
	var samples: Array[float] = []
	for _tick in 120:
		var started := Time.get_ticks_usec(); world.step(); samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	var report := {"label":label, "cells":cells, "avg_ms":_average(samples), "p99_ms":_percentile(samples, 0.99), "worst_ms":samples.max()}
	print("phase135_fire scenario=%s cells=%d avg_ms=%.4f p99_ms=%.4f worst_ms=%.4f" % [label, cells, report.avg_ms, report.p99_ms, report.worst_ms])
	return report

func _run() -> void:
	var materials := MaterialRegistry.new(); _check(materials.load_directory() == OK, "materials")
	var world: Variant = _world(13550); var blueprints := BlueprintLibrary.new(); MvpExampleBlueprints.install(blueprints); var codex := PhysicsCodex.new(); codex.rebuild(materials, world, blueprints)
	var codex_samples: Array[float] = []
	for iteration in 1000:
		var started := Time.get_ticks_usec(); codex.search(["heat", "steam", "screen", "gold", "oxygen"][iteration % 5]); codex_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	print("phase135_codex entries=%d search_avg_ms=%.4f search_p99_ms=%.4f" % [codex.entries.size(), _average(codex_samples), _percentile(codex_samples, 0.99)])
	_check(_percentile(codex_samples, 0.99) < 1.0, "Codex search p99 <1 ms")

	var mixer := AudioEventMixer.new(); root.add_child(mixer); await process_frame
	var sources: Array[Dictionary] = []
	for index in 300: sources.append({"event":["conveyor", "pump", "vibration", "turbine", "generator"][index % 5], "position":Vector2(index % 30, index / 30) * 12.0, "intensity":0.35 + float(index % 5) * 0.1, "parameter":float(index % 7) / 6.0, "category":"Machines"})
	var audio_samples: Array[float] = []
	for _frame in 240: mixer.update_aggregated_loops(sources, Vector2(100, 100), 1.5); audio_samples.append(mixer.last_mix_ms)
	var representative := sources.slice(0, 9)
	var representative_samples: Array[float] = []
	for _frame in 240: mixer.update_aggregated_loops(representative, Vector2(100, 100), 1.5); representative_samples.append(mixer.last_mix_ms)
	var audio := mixer.statistics()
	print("phase135_audio requested=%d actual=%d loops=%d dropped=%d representative_avg_ms=%.4f representative_p99_ms=%.4f stress300_avg_ms=%.4f stress300_p99_ms=%.4f" % [audio.requested_voices, audio.actual_voices, audio.aggregated_loops, audio.dropped_low_priority, _average(representative_samples), _percentile(representative_samples, 0.99), _average(audio_samples), _percentile(audio_samples, 0.99)])
	_check(audio.actual_voices <= 8, "audio voices bounded")
	_check(_average(representative_samples) < 0.5, "representative audio aggregation target")

	var vfx := PhysicalFeedbackRenderer.new(); root.add_child(vfx)
	for index in 96: vfx.emit([&"dig", &"cut", &"fire", &"steam", &"water"][index % 5], Vector2i(index % 16, index / 16), 1.0, true)
	var vfx_samples: Array[float] = []
	for _frame in 120: vfx._process(1.0 / 240.0); vfx_samples.append(vfx.last_update_ms)
	print("phase135_vfx pool=%d dropped=%d avg_ms=%.4f p99_ms=%.4f" % [PhysicalFeedbackRenderer.MAX_EFFECTS, vfx.dropped_effects, _average(vfx_samples), _percentile(vfx_samples, 0.99)])
	_check(_percentile(vfx_samples, 0.99) < 0.5, "VFX update p99 <0.5 ms")

	for fixture in [["small_campfire",16], ["charcoal_chamber",64], ["trees_20",400], ["trees_100",2000], ["industrial_fire",5000]]:
		var fire := _fire_fixture(str(fixture[0]), int(fixture[1]), 13600 + int(fixture[1]))
		_check(float(fire.p99_ms) < 16.67, "%s realistic fire p99" % fixture[0])

	mixer.queue_free(); vfx.queue_free()
	if failures.is_empty(): print("PASS: %d Phase 13.5 performance checks" % checks); quit(0)
	else:
		for failure in failures: push_error("PHASE135_BENCH: " + failure)
		print("FAIL: %d of %d Phase 13.5 performance checks" % [failures.size(), checks]); quit(1)
