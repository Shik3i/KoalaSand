extends SceneTree

const SETTINGS := {
	"width": 16384,
	"depth": 4096,
	"sky": 512,
	"surface_baseline": 0,
	"surface_amplitude": 72,
	"sediment_depth": 18,
	"cave_density": 0.52,
	"coal_frequency": 0.73,
	"water_frequency": 0.72,
	"geology_scale": 512,
	"generation_version": 1,
}

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("KoalaSand Phase 2 procedural-world performance matrix")
	print("godot=%s os=%s cpu=%s logical_cores=%d generation_workers=2" % [
		Engine.get_version_info().get("string", "unknown"), OS.get_name(), OS.get_processor_name(), OS.get_processor_count()
	])
	_benchmark_single_and_100_chunks()
	_benchmark_long_pan()
	_benchmark_deep_load()
	_benchmark_eviction_regeneration()
	_benchmark_provenance_memory()
	print("PASS: Phase 2 performance gates" if not _failed else "FAIL: Phase 2 performance gates")
	quit(0 if not _failed else 1)


func _benchmark_single_and_100_chunks() -> void:
	var single: Variant = _new_world(7101)
	var started := Time.get_ticks_usec()
	single.request_chunk(Vector2i.ZERO, 0)
	single.flush_generation()
	var single_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var single_stats: Dictionary = single.get_generation_statistics()
	print("generation_single chunks=1 wall_ms=%.3f worker_ms=%.3f publish_ms=%.3f" % [
		single_ms,
		float(single_stats["generation_usec_average"]) / 1000.0,
		float(single_stats["publish_usec_last_frame"]) / 1000.0,
	])
	_check(single_ms < 50.0, "single chunk generation exceeded 50 ms")

	var hundred: Variant = _new_world(7102)
	started = Time.get_ticks_usec()
	hundred.request_chunk_region(Rect2i(-5, -1, 10, 10), 1)
	hundred.flush_generation()
	var hundred_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var statistics: Dictionary = hundred.get_generation_statistics()
	print("generation_100 chunks=%d wall_ms=%.3f avg_worker_ms=%.3f worst_worker_ms=%.3f queue_peak=%d allocated_mib=%.3f" % [
		hundred.chunk_count(), hundred_ms,
		float(statistics["generation_usec_average"]) / 1000.0,
		float(statistics["generation_usec_worst"]) / 1000.0,
		statistics["queue_peak"],
		float(hundred.simulation_backing_bytes() + hundred.presentation_backing_bytes()) / 1048576.0,
	])
	_check(hundred.chunk_count() == 100, "100-chunk benchmark did not publish 100 chunks")
	_check(hundred_ms < 2000.0, "100 chunk generation exceeded 2 s")


func _benchmark_long_pan() -> void:
	var world: Variant = _new_world(7201)
	var total_started := Time.get_ticks_usec()
	var worst_hop_ms := 0.0
	var peak_chunks := 0
	var hops := 0
	for center_x in range(-5000, 5001, 128):
		var center_chunk := floori(float(center_x) / 64.0)
		var visible := Rect2i(center_chunk - 4, -2, 9, 7)
		var started := Time.get_ticks_usec()
		world.request_chunk_region(Rect2i(visible.position - Vector2i.ONE, visible.size + Vector2i(2, 2)), 2)
		world.request_chunk_region(visible, 1)
		world.request_chunk(Vector2i(center_chunk, 0), 0)
		world.flush_generation()
		world.evict_pristine_outside(Rect2i(visible.position - Vector2i(3, 3), visible.size + Vector2i(6, 6)), 256)
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		worst_hop_ms = maxf(worst_hop_ms, elapsed_ms)
		peak_chunks = maxi(peak_chunks, world.chunk_count())
		hops += 1
	var total_ms := float(Time.get_ticks_usec() - total_started) / 1000.0
	print("camera_pan distance_cells=10000 hops=%d total_ms=%.3f worst_sync_hop_ms=%.3f peak_chunks=%d final_chunks=%d evicted=%d" % [
		hops, total_ms, worst_hop_ms, peak_chunks, world.chunk_count(), world.get_generation_statistics()["evicted_total"]
	])
	_check(peak_chunks < 180, "10k-cell pan retained too many pristine chunks")
	_check(worst_hop_ms < 250.0, "10k-cell pan synchronous stress hop exceeded 250 ms")


func _benchmark_deep_load() -> void:
	var world: Variant = _new_world(7301)
	var region := Rect2i(-5, 48, 10, 10)
	var started := Time.get_ticks_usec()
	world.request_chunk_region(region, 1)
	world.flush_generation()
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("deep_load depth_cells=%d chunks=%d wall_ms=%.3f hash=%s" % [
		region.position.y * 64, world.chunk_count(), elapsed_ms, world.get_region_content_hash(region)
	])
	_check(world.chunk_count() == 100, "deep load did not publish 100 chunks")
	_check(elapsed_ms < 2000.0, "deep 100-chunk load exceeded 2 s")


func _benchmark_eviction_regeneration() -> void:
	var world: Variant = _new_world(7401)
	var region := Rect2i(-4, 20, 8, 8)
	world.request_chunk_region(region, 1)
	world.flush_generation()
	var original_hash: String = world.get_region_content_hash(region)
	var started := Time.get_ticks_usec()
	var evicted: int = world.evict_pristine_outside(Rect2i(40, 40, 1, 1), 128)
	var eviction_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	world.request_chunk_region(region, 1)
	world.flush_generation()
	var regeneration_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var regenerated_hash: String = world.get_region_content_hash(region)
	print("eviction_regeneration chunks=%d eviction_ms=%.3f regeneration_ms=%.3f hash_match=%s" % [
		evicted, eviction_ms, regeneration_ms, original_hash == regenerated_hash
	])
	_check(evicted == 64, "deep pristine eviction did not remove all chunks")
	_check(original_hash == regenerated_hash, "regeneration changed deterministic content")


func _benchmark_provenance_memory() -> void:
	var world := NativeSandWorld.new()
	world.reset(7501, 1)
	world.allocate_chunk_rect(Rect2i(0, 0, 1, 1))
	var bytes_per_cell := float(world.simulation_backing_bytes()) / world.total_allocated_cells()
	var phase15_bytes_per_cell := 9.0
	var overhead_percent := (bytes_per_cell / phase15_bytes_per_cell - 1.0) * 100.0
	print("provenance_memory storage=uint16 temperature_storage=uint16_quarter_kelvin simulation_bytes_per_cell=%.1f phase15_bytes_per_cell=%.1f overhead_percent=%.1f" % [
		bytes_per_cell, phase15_bytes_per_cell, overhead_percent
	])
	_check(overhead_percent <= 15.0, "provenance simulation-backing overhead exceeds 15 percent")


func _new_world(seed: int) -> Variant:
	var settings := SETTINGS.duplicate()
	settings["seed"] = seed
	var world := NativeSandWorld.new()
	world.configure_world(settings, 2)
	return world


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("PERFORMANCE INVARIANT: %s" % message)
