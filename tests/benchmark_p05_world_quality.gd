extends SceneTree

func _init() -> void:
	var v3 := _traversal(3); var v4 := _traversal(4)
	print("p05_before_after v3_avg_ms=%.4f v4_avg_ms=%.4f v3_worst_ms=%.4f v4_worst_ms=%.4f v3_wall_ms=%.3f v4_wall_ms=%.3f v3_first_tick_ms=%.4f v4_first_tick_ms=%.4f v3_active=%d v4_active=%d v4_sand=%d v4_water=%d" % [v3.avg,v4.avg,v3.worst,v4.worst,v3.wall,v4.wall,v3.tick,v4.tick,v3.active,v4.active,v4.sand,v4.water])
	_seed_sample(100)
	if int(v4.active) == 0 and float(v4.avg) < 12.0 and float(v4.worst) < 25.0:
		print("PASS: P0.5 world-quality benchmark"); quit(0); return
	push_error("P05_BENCHMARK: V4 stability/performance budget failed"); quit(1)

func _traversal(version: int) -> Dictionary:
	var world := NativeSandWorld.new(); world.configure_world({"seed":8675309,"generation_version":version},8)
	var started := Time.get_ticks_usec(); var requests := 0; var resident_peak := 0
	for chunk_x in range(-30,31,5):
		var region := Rect2i(chunk_x - 4,-1,9,13); requests += world.request_chunk_region(region,1); world.flush_generation()
		world.evict_pristine_outside(Rect2i(chunk_x - 7,-2,15,16),256); resident_peak = maxi(resident_peak,world.chunk_count())
	var wall := (Time.get_ticks_usec() - started) / 1000.0
	var inspect := Rect2i(26,-1,9,13); world.request_chunk_region(inspect,0); world.flush_generation()
	var stability: Dictionary = world.get_generation_stability_report(inspect)
	var quality: Dictionary = world.get_worldgen_quality_report(inspect)
	started = Time.get_ticks_usec(); world.step(); var tick := (Time.get_ticks_usec() - started) / 1000.0
	var generation: Dictionary = world.get_generation_statistics()
	print("p05_traversal version=%d requests=%d wall_ms=%.3f resident_peak=%d resident_final=%d avg_ms=%.4f worst_ms=%.4f first_tick_ms=%.4f active=%d sand=%d water=%d" % [version,requests,wall,resident_peak,world.chunk_count(),generation.generation_usec_average/1000.0,generation.generation_usec_worst/1000.0,tick,stability.initially_active_dynamic_cells,quality.content.sand_cells,quality.content.water_cells])
	return {"wall":wall,"avg":generation.generation_usec_average/1000.0,"worst":generation.generation_usec_worst/1000.0,"tick":tick,"active":stability.initially_active_dynamic_cells,"sand":quality.content.sand_cells,"water":quality.content.water_cells}

func _seed_sample(count: int) -> void:
	var sand: Array[float] = []; var water: Array[float] = []; var caves: Array[float] = []; var ore: Array[float] = []; var slopes: Array[float] = []; var flat: Array[float] = []; var generation: Array[float] = []
	var unstable := 0; var dry := 0; var empty_sand := 0
	var area := Rect2i(-3,-1,7,12)
	for index in count:
		var world := NativeSandWorld.new(); world.configure_world({"seed":1000 + index * 7919,"generation_version":4},6)
		world.request_chunk_region(area,1); world.flush_generation()
		var stable: Dictionary = world.get_generation_stability_report(area); var quality: Dictionary = world.get_worldgen_quality_report(area)
		if int(stable.initially_active_dynamic_cells) > 0:
			unstable += 1
			print("p05_unstable seed=%d sand=%d water=%d sand_sample=%s water_sample=%s" % [1000 + index * 7919,stable.unsupported_sand_cells,stable.initially_active_water_cells,str(stable.unsupported_sand_sample_xy),str(stable.active_water_sample_xy)])
		dry += 1 if int(quality.content.water_cells) == 0 else 0; empty_sand += 1 if int(quality.content.sand_cells) == 0 else 0
		sand.append(quality.content.sand_cells); water.append(quality.content.water_cells); caves.append(quality.content.cave_systems); ore.append(quality.content.ore_veins)
		slopes.append(float(quality.structure.surface_slope.mean)); flat.append(quality.structure.longest_flat_run_cells)
		generation.append(float(world.get_generation_statistics().generation_usec_average) / 1000.0)
	print("p05_seed_sample seeds=%d unstable=%d dry=%d empty_sand=%d sand=%s water=%s caves=%s ore=%s slope=%s longest_flat=%s generation_ms=%s" % [count,unstable,dry,empty_sand,str(_dist(sand)),str(_dist(water)),str(_dist(caves)),str(_dist(ore)),str(_dist(slopes)),str(_dist(flat)),str(_dist(generation))])

func _dist(values: Array[float]) -> Dictionary:
	values.sort(); var total := 0.0
	for value in values: total += value
	return {"mean":total/values.size(),"p50":values[int((values.size()-1)*0.50)],"p90":values[int((values.size()-1)*0.90)],"p99":values[int((values.size()-1)*0.99)],"min":values[0],"max":values[-1]}
