extends SceneTree

const WATER := 3
const STONE := 1


func _init() -> void:
	print("KoalaSand Phase 7 production R8 render-page matrix")
	_benchmark_page("small_waterfall", Rect2i(-2, -4, 4, 8), Rect2i(-90, -180, 12, 150), false)
	_benchmark_page("fullscreen_moving_water", Rect2i(-8, -4, 16, 8), Rect2i(-500, -210, 1000, 190), false)
	_benchmark_page("large_settled_lake", Rect2i(-8, -4, 16, 8), Rect2i(-500, -190, 1000, 170), true)
	_benchmark_page("factory_water", Rect2i(-6, -3, 12, 6), Rect2i(-300, -120, 600, 100), true)
	print("PASS: Phase 7 production R8 render-page matrix")
	quit(0)


func _benchmark_page(label: String, page_chunks: Rect2i, water_rect: Rect2i, settled: bool) -> void:
	var world: Variant = NativeSandWorld.new()
	world.reset(0x7a11, 8)
	world.allocate_chunk_rect(page_chunks)
	var floor_y := water_rect.position.y + water_rect.size.y
	world.fill_rect(Rect2i(water_rect.position.x - 1, floor_y, water_rect.size.x + 2, 1), STONE)
	if settled:
		world.fill_rect(water_rect, WATER)
	else:
		world.fill_rect(Rect2i(water_rect.position.x, water_rect.position.y, water_rect.size.x, maxi(1, water_rect.size.y / 2)), WATER)
	world.finalize_initialization()
	if not settled:
		for _tick in 8: world.step()
	var samples: Array[float] = []
	var bytes := 0
	for _sample in 24:
		var started := Time.get_ticks_usec()
		var page: Dictionary = world.get_fluid_render_page(page_chunks)
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		bytes = int(page.bytes)
	samples.sort()
	var expected_bytes := page_chunks.size.x * 64 * page_chunks.size.y * 64
	if bytes != expected_bytes:
		push_error("%s expected %d R8 bytes, got %d" % [label, expected_bytes, bytes])
		quit(1)
	print("phase7_render scenario=%s page=%dx%d_pixels r8_bytes=%d cpu_avg_ms=%.4f cpu_p95_ms=%.4f cpu_p99_ms=%.4f cpu_worst_ms=%.4f" % [
		label, page_chunks.size.x * 64, page_chunks.size.y * 64, bytes,
		_average(samples), _percentile(samples, 0.95), _percentile(samples, 0.99), samples[-1],
	])


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value in values: total += value
	return total / maxf(1.0, float(values.size()))


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)]
