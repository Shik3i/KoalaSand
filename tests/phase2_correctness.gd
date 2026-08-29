extends SceneTree

const DEFAULT_SETTINGS := {
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

var _checks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_provenance_transport()
	_test_world_bounds_and_validation()
	_test_generation_determinism()
	_test_generation_content_and_continuity()
	_test_geology_profiles()
	_test_eviction_and_regeneration()
	_test_golden_seeds()
	if _failures.is_empty():
		print("PASS: %d checks across 7 Phase 2 suites" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d Phase 2 checks failed" % [_failures.size(), _checks])
	quit(1)


func _test_provenance_transport() -> void:
	var world := NativeSandWorld.new()
	world.reset(1001, 2)
	_check_equal(world.set_cell_with_provenance(Vector2i(0, 0), 2, 12345), OK, "set custom provenance")
	_check_equal(world.step(), 1, "provenance particle moves")
	_check_equal(world.get_cell(Vector2i(0, 1)), 2, "moved sand material")
	_check_equal(world.get_provenance(Vector2i(0, 1)), 12345, "provenance follows moved sand")
	_check_equal(world.get_provenance(Vector2i.ZERO), 0, "source provenance clears")

	var mixed := NativeSandWorld.new()
	mixed.reset(1002, 1)
	mixed.set_cell_with_provenance(Vector2i(-4, 0), 2, 111)
	mixed.set_cell_with_provenance(Vector2i(4, 0), 2, 222)
	for _tick in 12:
		mixed.step()
	var seen: Dictionary = {}
	for y in range(0, 16):
		for x in range(-8, 9):
			if mixed.get_cell(Vector2i(x, y)) == 2:
				seen[mixed.get_provenance(Vector2i(x, y))] = true
	_check(seen.has(111) and seen.has(222), "mixed provenance survives independent movement")
	_check(mixed.material_and_provenance_hash() != mixed.material_state_hash(), "provenance participates in state hash")


func _test_world_bounds_and_validation() -> void:
	var world: Variant = _new_world(2001, 2)
	var settings: Dictionary = world.get_world_settings()
	_check_equal(settings["min_x"], -8192, "default world min x")
	_check_equal(settings["max_x"], 8191, "default world max x")
	_check_equal(settings["max_y"], 4095, "default world max y")
	_check_equal(world.get_cell(Vector2i(0, -513)), 0, "sky above finite world is empty")
	_check_equal(world.get_cell(Vector2i(-8193, 0)), 5, "left finite boundary is bedrock")
	_check_equal(world.get_cell(Vector2i(8192, 0)), 5, "right finite boundary is bedrock")
	_check_equal(world.get_cell(Vector2i(0, 4096)), 5, "bottom finite boundary is bedrock")
	_check_equal(world.get_cell(Vector2i(0, 0)), -1, "ungenerated in-bounds cell is guarded")
	_check(world.request_chunk(Vector2i.ZERO, 0), "valid chunk request accepted")
	_check_equal(world.get_generation_state(Vector2i.ZERO), 1, "queued/generated-not-published state")
	world.flush_generation()
	_check_equal(world.get_generation_state(Vector2i.ZERO), 2, "published generation state")
	var neighbor_before: int = world.get_cell(Vector2i(1, 0))
	var replacement := 1 if world.get_cell(Vector2i.ZERO) == 0 else 0
	world.fill_rect(Rect2i(0, 0, 1, 1), replacement)
	_check_equal(world.get_cell(Vector2i(1, 0)), neighbor_before, "bulk edit preserves generated chunk neighbors")
	_check(not bool(world.get_chunk_state(Vector2i.ZERO)["pristine"]), "bulk edit marks generated chunk modified")
	_check(not world.request_chunk(Vector2i(500, 0), 1), "out-of-bounds chunk request rejected")

	var clamped := NativeSandWorld.new()
	clamped.configure_world({"seed": 9, "width": 1, "depth": 1, "sky": -5, "cave_density": 4.0}, 99)
	var validated: Dictionary = clamped.get_world_settings()
	_check_equal(validated["width"], 64, "world width validation")
	_check_equal(validated["depth"], 64, "world depth validation")
	_check_equal(validated["sky"], 0, "sky validation")
	_check_equal(validated["cave_density"], 0.95, "cave density validation")
	_check(int(clamped.get_generation_statistics()["workers"]) <= 8, "generation worker count bounded")


func _test_generation_determinism() -> void:
	var region := Rect2i(-2, -1, 4, 7)
	var expected_hash := ""
	for workers in [1, 2, 4]:
		var world: Variant = _new_world(3001, workers)
		if workers == 2:
			var end := region.position + region.size
			for y in range(end.y - 1, region.position.y - 1, -1):
				for x in range(end.x - 1, region.position.x - 1, -1):
					world.request_chunk(Vector2i(x, y), (x + y) & 3)
		else:
			world.request_chunk_region(region, 1)
		world.flush_generation()
		var content_hash: String = world.get_region_content_hash(region)
		if expected_hash.is_empty():
			expected_hash = content_hash
		else:
			_check_equal(content_hash, expected_hash, "generation independent of workers/order workers=%d" % workers)
	var different: Variant = _new_world(3002, 3)
	different.request_chunk_region(region, 1)
	different.flush_generation()
	_check(different.get_region_content_hash(region) != expected_hash, "different seed changes generated content")
	var high_seed: Variant = _new_world(3001 + (1 << 32), 2)
	high_seed.request_chunk_region(region, 1)
	high_seed.flush_generation()
	_check(high_seed.get_region_content_hash(region) != expected_hash, "upper 32 seed bits affect generated content")


func _test_generation_content_and_continuity() -> void:
	var world: Variant = _new_world(4001, 2)
	var region := Rect2i(-3, -1, 6, 12)
	world.request_chunk_region(region, 1)
	world.flush_generation()
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for y in range(region.position.y * 64, (region.position.y + region.size.y) * 64):
		for x in range(region.position.x * 64, (region.position.x + region.size.x) * 64):
			var material: int = world.get_cell(Vector2i(x, y))
			if counts.has(material):
				counts[material] += 1
	_check(counts[0] > 0, "generated region contains open air/caves")
	_check(counts[1] > 0, "generated region contains stone")
	_check(counts[2] > 0, "generated region contains raw sand")
	_check(counts[3] > 0, "generated region contains static water pockets")
	_check(counts[4] > 0, "generated region contains coal deposits")

	var previous_surface := 0
	var initialized := false
	var worst_step := 0
	for x in range(-160, 161):
		var surface := -64
		while surface < 96 and world.get_cell(Vector2i(x, surface)) == 0:
			surface += 1
		if initialized:
			worst_step = maxi(worst_step, absi(surface - previous_surface))
		previous_surface = surface
		initialized = true
	_check(worst_step <= 3, "surface is continuous across chunk seams worst_step=%d" % worst_step)


func _test_geology_profiles() -> void:
	var world: Variant = _new_world(5001, 2)
	var near_equal := 0
	var samples := 0
	var gold_regions := 0
	var maximum_gold := 0.0
	for y in range(0, 2048, 64):
		for x in range(-8000, 8001, 64):
			var profile_id: int = world.geology_profile_id_at(Vector2i(x, y))
			var profile: Dictionary = world.get_geology_profile(profile_id)
			var total := float(profile["silica_fraction"]) + float(profile["iron_fraction"]) + float(profile["heavy_minerals_fraction"]) + float(profile["other_fraction"])
			_check(absf(total - 1.0) < 0.000001, "profile fractions sum to one id=%d" % profile_id)
			var gold := float(profile["gold_ppm"])
			gold_regions += 1 if gold > 0.01 else 0
			maximum_gold = maxf(maximum_gold, gold)
			near_equal += 1 if profile_id == world.geology_profile_id_at(Vector2i(x + 1, y)) else 0
			samples += 1
	_check(float(near_equal) / samples > 0.90, "adjacent cells have regionally coherent geology")
	_check(gold_regions > 0, "gold anomaly exists in broad deterministic sample")
	_check(float(gold_regions) / samples < 0.08, "gold anomalies remain uncommon")
	_check(maximum_gold >= 0.25, "gold anomaly reaches measurable trace ppm")


func _test_eviction_and_regeneration() -> void:
	var world: Variant = _new_world(6001, 2)
	var coordinate := Vector2i(0, 12)
	world.request_chunk(coordinate, 1)
	world.flush_generation()
	var original_hash: String = world.get_chunk_content_hash(coordinate)
	_check(not original_hash.is_empty(), "generated chunk has content hash")
	_check_equal(world.evict_pristine_outside(Rect2i(20, 20, 1, 1), 1), 1, "pristine sleeping chunk evicted")
	_check_equal(world.consume_evicted_chunks(), [coordinate], "eviction notification emitted")
	world.request_chunk(coordinate, 1)
	world.flush_generation()
	_check_equal(world.get_chunk_content_hash(coordinate), original_hash, "evicted chunk regenerates identically")
	var edit_cell := Vector2i(1, coordinate.y * 64 + 1)
	var replacement := 1 if world.get_cell(edit_cell) == 0 else 0
	world.set_cell(edit_cell, replacement)
	_check_equal(world.evict_pristine_outside(Rect2i(20, 20, 1, 1), 1), 0, "modified chunk is retained")
	_check(world.is_chunk_generated(coordinate), "modified chunk remains allocated")


func _test_golden_seeds() -> void:
	var region := Rect2i(-1, -1, 3, 5)
	var golden := {
		17: "8e4d5543",
		8675309: "86dee9f0",
		323: "1715bf2a",
	}
	for seed: int in golden:
		var world: Variant = _new_world(seed, 2)
		world.request_chunk_region(region, 1)
		world.flush_generation()
		var actual: String = world.get_region_content_hash(region)
		print("golden seed=%d region=%s hash=%s" % [seed, region, actual])
		_check_equal(actual, golden[seed], "golden generated world seed=%d" % seed)


func _new_world(seed: int, workers: int) -> Variant:
	var settings := DEFAULT_SETTINGS.duplicate()
	settings["seed"] = seed
	var world := NativeSandWorld.new()
	world.configure_world(settings, workers)
	return world


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
