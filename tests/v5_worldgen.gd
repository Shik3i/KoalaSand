extends SceneTree

# V5 world-generation correctness.
#
# The load-bearing claims are: the world is a deterministic function of seed and coordinate,
# generation order and worker count cannot influence it, negative coordinates behave, terrain
# publishes in equilibrium, and player action is still what wakes it up.

var checks := 0
var failures: Array[String] = []

const AREA := Rect2i(-4, -1, 9, 14)
const SEEDS := [3, 41, 2965, 8191, 15508, 18076, 33191, 45613, 71317, 99173, 120011, 8675309]

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_architecture()
	_test_determinism()
	_test_negative_coordinates()
	_test_content_and_equilibrium()
	_test_cave_topology()
	_test_hydrology()
	_test_start_region()
	_test_structures_and_scenes()
	_test_player_induced_chaos()
	_test_save_round_trip()
	_test_legacy_versions()
	if failures.is_empty():
		print("PASS: %d V5 worldgen checks" % checks); quit(0)
	else:
		for failure in failures: push_error("V5_WORLDGEN: " + failure)
		print("FAIL: %d of %d V5 checks" % [failures.size(), checks]); quit(1)

# ---------------------------------------------------------------------------------------

func _test_architecture() -> void:
	var world: Variant = _world(412, 5)
	var architecture: Dictionary = world.get_worldgen_v5_architecture()
	_equal(int(architecture.generation_version), 5, "new worlds use generation version 5")
	_check(bool(architecture.is_v5), "V5 architecture is reported for a V5 world")
	_check(bool(architecture.chunk_order_independent_descriptors), "descriptors are order independent")
	_check(bool(architecture.surface_biome_separate_from_geology), "surface biome is separate from geology")
	_check(bool(architecture.fractional_liquid_levels), "fractional liquid levels are supported")
	_check(bool(architecture.composition_provenance_on_stone), "stone carries composition provenance")
	for archetype in ["tunnel", "chamber", "fissure", "cavern", "entrance"]:
		_check(archetype in architecture.cave_archetypes, "cave archetype %s exposed" % archetype)
	var seed_domains: Array = architecture.seed_domains as Array
	_check(seed_domains.size() >= 20, "subsystem seed domains are separated")
	_equal(seed_domains.size(), _unique(seed_domains).size(), "seed domains are unique")

	var profiles: Dictionary = world.get_worldgen_v5_profiles()
	_equal(int(profiles.biomes.size()), 5, "five surface biome profiles")
	_equal(int(profiles.provinces.size()), 5, "five geological province profiles")
	_check(int(profiles.rocks.size()) >= 8, "rock profile table is data driven")
	var families: Array = []
	for rock: Dictionary in profiles.rocks: families.append(int(rock.family))
	_equal(families.size(), _unique(families).size(), "each rock family is uniquely identifiable from composition")

	# Stone must never claim gold it does not have: V4 tagged provenance with 0x8000, which
	# collided with the gold field of the profile packing.
	world.request_chunk_region(Rect2i(0, 4, 2, 2), 1); world.flush_generation()
	var gold_bearing := 0; var stone_cells := 0
	for y in range(256, 384, 3):
		for x in range(0, 128, 3):
			if world.get_cell(Vector2i(x, y)) != 1: continue
			stone_cells += 1
			if float(world.get_geology_profile_at(Vector2i(x, y)).gold_ppm) > 0.0: gold_bearing += 1
	_check(stone_cells > 0, "deep stone sampled")
	_check(gold_bearing < stone_cells / 2, "gold is a rare constituent, not a provenance artefact (%d of %d)" % [gold_bearing, stone_cells])

func _test_determinism() -> void:
	var coordinates := [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4)]
	var orders := [
		[0, 1, 2, 3, 4, 5], [5, 4, 3, 2, 1, 0], [2, 5, 0, 4, 1, 3], [3, 0, 5, 1, 4, 2],
	]
	var region := Rect2i(0, 3, 3, 2)
	var reference: String = ""
	for order_index in orders.size():
		var world: Variant = _world(99173, 5)
		for slot: int in orders[order_index]:
			world.request_chunk(coordinates[slot], 1)
			world.flush_generation()
		var digest := str(world.get_region_content_hash(region))
		if order_index == 0: reference = digest
		else: _equal(digest, reference, "generation order %d matches the reference order" % order_index)

	# Worker count must not reach the generated world either.
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(99173, 5, workers)
		world.request_chunk_region(region, 1); world.flush_generation()
		_equal(str(world.get_region_content_hash(region)), reference, "worker count %d matches" % workers)

	# A far jump must produce the chunk the player would eventually have streamed into.
	var traversed: Variant = _world(8191, 5)
	for chunk_x in range(-2, 9):
		traversed.request_chunk_region(Rect2i(chunk_x, 5, 1, 2), 1); traversed.flush_generation()
	var teleported: Variant = _world(8191, 5)
	teleported.request_chunk_region(Rect2i(7, 5, 1, 2), 1); teleported.flush_generation()
	_equal(str(teleported.get_region_content_hash(Rect2i(7, 5, 1, 2))),
		str(traversed.get_region_content_hash(Rect2i(7, 5, 1, 2))), "a far jump generates the traversal result")

func _test_negative_coordinates() -> void:
	# Floor division is the classic procedural-generation bug: a truncating divide mirrors the
	# world about zero and leaves a seam at x = 0.
	var world: Variant = _world(45613, 5)
	var area := Rect2i(-3, 2, 6, 3)
	world.request_chunk_region(area, 1); world.flush_generation()
	var left := str(world.get_region_content_hash(Rect2i(-3, 2, 3, 3)))
	var right := str(world.get_region_content_hash(Rect2i(0, 2, 3, 3)))
	_check(left != right, "left and right of the origin are not mirrored")

	var mirrored := 0
	for x in range(1, 400):
		if int(world.get_worldgen_v5_cell(Vector2i(-x, 0)).surface_y) == int(world.get_worldgen_v5_cell(Vector2i(x, 0)).surface_y):
			mirrored += 1
	_check(mirrored < 160, "the surface profile is not mirrored about x=0 (%d of 399)" % mirrored)

	# No discontinuity where the sign of the coordinate flips.
	var worst := 0
	var previous := int(world.get_worldgen_v5_cell(Vector2i(-40, 0)).surface_y)
	for x in range(-39, 41):
		var current := int(world.get_worldgen_v5_cell(Vector2i(x, 0)).surface_y)
		worst = maxi(worst, absi(current - previous))
		previous = current
	_check(worst <= 6, "no surface seam at world x=0 (largest step %d)" % worst)

	var negative: Variant = _world(45613, 5)
	negative.request_chunk_region(Rect2i(-40, 3, 2, 2), 1); negative.flush_generation()
	var stable: Dictionary = negative.get_generation_stability_report(Rect2i(-40, 3, 2, 2))
	_equal(int(stable.initially_active_dynamic_cells), 0, "far negative terrain publishes settled")

func _test_content_and_equilibrium() -> void:
	var totals: Dictionary = {"sand": 0, "water": 0, "coal": 0}
	var seeds_with_water := 0
	var seeds_with_sand := 0
	for seed_value in SEEDS:
		var world: Variant = _world(seed_value, 5)
		world.request_chunk_region(AREA, 1); world.flush_generation()
		var stable: Dictionary = world.get_generation_stability_report(AREA)
		var quality: Dictionary = world.get_worldgen_quality_report(AREA)
		var content: Dictionary = quality.content
		_equal(int(stable.initially_active_dynamic_cells), 0, "seed %d publishes in equilibrium" % seed_value)
		_equal(int(stable.unsupported_sand_cells), 0, "seed %d has no unsupported Sand" % seed_value)
		_equal(int(stable.water_vertical_drop_cells), 0, "seed %d has no Water above a void" % seed_value)
		_check(int(content.sand_cells) > 0, "seed %d contains physical Sand" % seed_value)
		# The budget is a regional aggregate. A single chunk inside a large cavern is
		# legitimately almost all void; capping per chunk is what fragmented V4 caves.
		_equal(str(stable.void_budget_applies_to), "region_aggregate", "seed %d uses an aggregate void budget" % seed_value)
		var limits: Array = stable.void_fraction_limits
		var fractions: Array = stable.void_fraction_by_depth_band
		for band in 3:
			_check(float(fractions[band]) <= float(limits[band]) + 0.0001,
				"seed %d band %d void %.4f within limit %.4f" % [seed_value, band, float(fractions[band]), float(limits[band])])
		totals.sand += int(content.sand_cells); totals.water += int(content.water_cells); totals.coal += int(content.ore_cells)
		seeds_with_water += 1 if int(content.water_cells) > 0 else 0
		seeds_with_sand += 1 if int(content.sand_cells) > 0 else 0
	print("v5_content seeds=%d sand=%d water=%d coal=%d wet_seeds=%d" % [SEEDS.size(), totals.sand, totals.water, totals.coal, seeds_with_water])
	_equal(seeds_with_sand, SEEDS.size(), "every sampled seed contains Sand")
	_check(seeds_with_water >= SEEDS.size() - 2, "Water is present in nearly every sampled seed")
	_check(totals.coal > 2000, "sample contains substantial ore")

func _test_cave_topology() -> void:
	# V4 counted descriptor grid keys and called them cave systems. This measures the real
	# thing: a generator can satisfy a void budget and still produce forty disconnected slits.
	var area := Rect2i(-6, 4, 12, 12)
	var isolated_total := 0
	var largest_total := 0.0
	var components_total := 0
	for seed_value in [3, 18076, 71317, 8675309]:
		var world: Variant = _world(seed_value, 5)
		world.request_chunk_region(area, 1); world.flush_generation()
		var report: Dictionary = world.get_cave_topology_report(area)
		var components := int(report.components)
		var isolated := int(report.isolated_small_components)
		print("v5_topology seed=%d components=%d void=%.4f largest=%.3f isolated=%d width_p50=%s flooded=%.3f" % [
			seed_value, components, float(report.void_fraction), float(report.largest_component_fraction),
			isolated, str(report.passage_width.p50), float(report.flooded_fraction)])
		_check(components > 0, "seed %d has cave components" % seed_value)
		_check(float(report.void_fraction) > 0.01, "seed %d has meaningful void volume" % seed_value)
		_check(float(report.void_fraction) < 0.30, "seed %d does not dissolve into void" % seed_value)
		_check(float(report.component_size.p50) >= 40.0,
			"seed %d median cave component is a system, not a slit (%.0f cells)" % [seed_value, float(report.component_size.p50)])
		_check(float(report.passage_width.p50) >= 3.0, "seed %d passages are traversable" % seed_value)
		_check(isolated <= components / 4 + 2, "seed %d isolated fragments stay a minority" % seed_value)
		isolated_total += isolated; largest_total += float(report.largest_component_fraction); components_total += components
	_check(largest_total / 4.0 > 0.04, "cave volume concentrates into large systems")
	_check(components_total > 0, "cave components measured")
	_test_no_chunk_boundary_truncation()
	_test_cross_chunk_agreement()


func _test_cross_chunk_agreement() -> void:
	# Two chunks whose padded halo both cover a cell must agree about that cell. A content
	# hash cannot detect a disagreement here, because each chunk still agrees with itself:
	# the feature is simply absent from one side and present on the other, and the seam only
	# shows up later as a capped shaft or a Sand cell with nothing under it.
	for seed_value in [8675309, 3, 41]:
		var world: Variant = _world(seed_value, 5)
		var mismatches := 0
		var checked := 0
		var carved := 0
		for chunk_x in range(104, 112):
			for chunk_y in range(-1, 5):
				var upper := Vector2i(chunk_x, chunk_y)
				var lower := Vector2i(chunk_x, chunk_y + 1)
				for offset in [10, 32, 54]:
					var cell := Vector2i(chunk_x * 64 + offset, (chunk_y + 1) * 64)
					var above: Dictionary = world.get_worldgen_debug_chunk_view(upper, cell)
					var below: Dictionary = world.get_worldgen_debug_chunk_view(lower, cell)
					if not bool(above.in_padded) or not bool(below.in_padded): continue
					checked += 1
					carved += 1 if int(below.carve) != 0 else 0
					if int(above.carve) != int(below.carve): mismatches += 1
		print("v5_agreement seed=%d checked=%d carved=%d mismatches=%d" % [seed_value, checked, carved, mismatches])
		_check(checked > 100, "seed %d sampled enough boundary cells" % seed_value)
		_check(carved > 0, "seed %d boundary sample includes carved cells" % seed_value)
		_equal(mismatches, 0, "seed %d neighbouring chunks agree on every boundary cell" % seed_value)

func _test_no_chunk_boundary_truncation() -> void:
	# A feature clipped by one chunk and not its neighbour leaves a one-cell plug exactly on
	# the boundary row. Comparing plug density on boundary rows against interior rows detects
	# that directly, which a content hash cannot: every chunk would still agree with itself.
	for seed_value in [167299, 8675309, 41]:
		var world: Variant = _world(seed_value, 5)
		var area := Rect2i(-4, -1, 9, 14)
		world.request_chunk_region(area, 1); world.flush_generation()
		var first := area.position * 64; var end := (area.position + area.size) * 64
		var boundary_plugs := 0; var boundary_rows := 0
		var interior_plugs := 0; var interior_rows := 0
		for y in range(first.y + 2, end.y - 2):
			var plugs := 0
			for x in range(first.x + 1, end.x - 1):
				var cell := Vector2i(x, y)
				if world.get_cell(cell) not in [1, 4]: continue
				if world.get_cell(cell + Vector2i.UP) != 0: continue
				if world.get_cell(cell + Vector2i.DOWN) != 0: continue
				plugs += 1
			if y % 64 == 0:
				boundary_plugs += plugs; boundary_rows += 1
			else:
				interior_plugs += plugs; interior_rows += 1
		var boundary_rate := float(boundary_plugs) / maxf(1.0, float(boundary_rows))
		var interior_rate := float(interior_plugs) / maxf(1.0, float(interior_rows))
		print("v5_boundary seed=%d boundary_rate=%.3f interior_rate=%.3f" % [seed_value, boundary_rate, interior_rate])
		_check(boundary_rate <= interior_rate * 3.0 + 1.0,
			"seed %d does not plug features at chunk boundaries (%.3f vs %.3f)" % [seed_value, boundary_rate, interior_rate])

func _test_hydrology() -> void:
	var found_partial: bool = false
	var found_flooded_cave: bool = false
	for seed_value in [3, 18076, 2965, 8675309, 41]:
		var world: Variant = _world(seed_value, 5)
		world.request_chunk_region(AREA, 1); world.flush_generation()
		var first := AREA.position * 64; var end := (AREA.position + AREA.size) * 64
		for y in range(first.y, end.y, 2):
			for x in range(first.x, end.x, 3):
				var cell := Vector2i(x, y)
				if world.get_cell(cell) != 3: continue
				var mass := int(world.get_liquid_mass(cell))
				if mass > 0 and mass < 255: found_partial = true
				if y > int(world.get_worldgen_v5_cell(cell).surface_y) + 60: found_flooded_cave = true
				if found_partial and found_flooded_cave: break
			if found_partial and found_flooded_cave: break
	_check(found_partial, "a generated waterline uses a fractional top cell")
	_check(found_flooded_cave, "cave systems below the local water table are flooded")

	# Water table geometry, not a drawn ellipse. A fully submerged cave has its top at its own
	# roof, so the invariant to check is the free surface: every water cell with air directly
	# above it must sit exactly on its region waterline.
	var world: Variant = _world(18076, 5)
	world.request_chunk_region(AREA, 1); world.flush_generation()
	var surfaces := 0
	var off_table := 0
	var first := AREA.position * 64; var end := (AREA.position + AREA.size) * 64
	for x in range(first.x, end.x):
		for y in range(first.y + 120, end.y):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) != 3: continue
			if world.get_cell(cell + Vector2i.UP) != 0: continue
			surfaces += 1
			if int(world.get_worldgen_v5_cell(cell).water_table_y) != y: off_table += 1
	_check(surfaces > 30, "underground free water surfaces sampled (%d)" % surfaces)
	_equal(off_table, 0, "every free water surface lies on its region waterline")

func _test_start_region() -> void:
	for seed_value in SEEDS:
		var world: Variant = _world(seed_value, 5)
		var report: Dictionary = world.get_worldgen_v5_start_report()
		_check(int(report.longest_buildable_run) >= 60, "seed %d offers a buildable start surface (%d)" % [seed_value, int(report.longest_buildable_run)])
		_check(int(report.sand_columns) >= 20, "seed %d has accessible Sand near spawn" % seed_value)
		_check(int(report.coal_seam_depth) > 0 and int(report.coal_seam_depth) < 90, "seed %d has a shallow starting coal seam" % seed_value)
		_check(int(report.nearest_wet_table_distance) >= 0, "seed %d has a reachable water table" % seed_value)

	# The protected build core stays solid, and the guaranteed features are not a visible
	# tutorial island: the start blends into the same fields as the rest of the world.
	var world: Variant = _world(8675309, 5)
	world.request_chunk_region(Rect2i(-2, -1, 4, 5), 1); world.flush_generation()
	var voids := 0
	for x in range(-96, 97):
		var surface := int(world.get_worldgen_v5_cell(Vector2i(x, 0)).surface_y)
		for y in range(surface, surface + 150):
			if world.get_cell(Vector2i(x, y)) == 0: voids += 1
	_check(voids == 0, "the protected build core contains no open void (%d cells)" % voids)

func _test_structures_and_scenes() -> void:
	var world: Variant = _world(120011, 5)
	var area := Rect2i(-6000, -200, 12000, 4000)
	var total := 0
	for structure_type in 3:
		var candidates: Array = world.get_structure_candidates(area, structure_type) as Array
		total += candidates.size()
		for candidate: Dictionary in candidates:
			_check(not (absi(int(candidate.cell.x)) < 140 and int(candidate.depth_below_surface) < 200),
				"structure candidates avoid the protected start core")
	_check(total > 0, "structure candidates are derivable from seed and region alone")
	# Candidate placement must be a pure function of the region, not of query extent.
	var narrow: Array = world.get_structure_candidates(Rect2i(0, 0, 3000, 2000), 1) as Array
	var wide: Array = world.get_structure_candidates(Rect2i(-6000, -200, 12000, 4000), 1) as Array
	var narrow_cells: Array = []
	for candidate: Dictionary in narrow: narrow_cells.append(candidate.cell)
	var wide_cells: Array = []
	for candidate: Dictionary in wide: wide_cells.append(candidate.cell)
	for cell: Vector2i in narrow_cells:
		_check(cell in wide_cells, "candidate %s is stable across query extents" % cell)
	var scenes: Array = world.get_natural_scene_candidates(area) as Array
	_check(scenes.size() > 0, "natural scene candidates exist")

func _test_player_induced_chaos() -> void:
	# World generation creates equilibrium. Player action creates chaos.
	var sand_world: Variant = _world(8675309, 5)
	sand_world.request_chunk_region(AREA, 0); sand_world.flush_generation()
	var sand: Vector2i = _find_supported(sand_world, 2)
	_check(sand.x < 900000, "a stable generated Sand deposit was found")
	if sand.x < 900000:
		var before := int(_count_material(sand_world, 2))
		sand_world.set_cell(sand + Vector2i.DOWN, 0)
		var moved := 0
		for tick in 120: sand_world.step(); moved += int(sand_world.get_statistics().cells_moved)
		_check(moved > 0, "removing support wakes and moves Sand")
		_equal(_count_material(sand_world, 2), before, "Sand cell count conserved after support removal")

	var water_world: Variant = _world(18076, 5)
	water_world.request_chunk_region(AREA, 0); water_world.flush_generation()
	var breach: Array = _find_water_wall(water_world)
	_check(not breach.is_empty(), "a stable generated reservoir wall was found")
	if not breach.is_empty():
		var water: Vector2i = breach[0]; var direction: Vector2i = breach[1]
		var mass_before := int(water_world.get_total_conserved_water_phase_mass())
		for offset in range(1, 9):
			var target := water + direction * offset
			if water_world.get_cell(target) != 3: water_world.set_cell(target, 0)
		var transfers := 0
		for tick in 180: water_world.step(); transfers += int(water_world.get_fluid_statistics().fluid_transfers)
		_check(transfers > 0, "breaching a reservoir wall wakes Water")
		_equal(int(water_world.get_total_conserved_water_phase_mass()), mass_before, "reservoir breach conserves Water-family mass")

func _test_save_round_trip() -> void:
	# Fractional waterlines are new in V5, so the amount plane has to survive a save. A
	# round trip that rounded a partial cell up would create Water out of nothing.
	var world: Variant = _world(18076, 5)
	var area := Rect2i(-2, -1, 5, 8)
	world.request_chunk_region(area, 1); world.flush_generation()
	# Dirty one chunk so it is written out rather than regenerated from the seed on load.
	var probe := Vector2i(-64, 0)
	world.set_cell(probe, 0)
	var before := int(world.get_total_conserved_water_phase_mass())
	var partial_before := _count_partial(world, area)
	var snapshot: Dictionary = world.serialize_world_snapshot()
	var restored: Variant = _world(18076, 5)
	_check(bool(restored.deserialize_world_snapshot(snapshot)), "a V5 world snapshot restores")
	# Streaming must still work after a load: reset() stops the generation workers, so a
	# restored world that cannot restart them deadlocks on the first new chunk.
	restored.request_chunk_region(area, 1)
	_check(int(restored.flush_generation()) >= 0, "a restored world can still stream new chunks")
	_equal(int(restored.get_total_conserved_water_phase_mass()), before, "save round trip conserves Water-family mass")
	_equal(_count_partial(restored, area), partial_before, "save round trip preserves fractional waterline cells")
	_check(partial_before > 0, "the sampled region contains fractional waterline cells (%d)" % partial_before)

func _count_partial(world: Variant, area: Rect2i) -> int:
	var result := 0
	var first := area.position * 64; var end := (area.position + area.size) * 64
	for y in range(first.y, end.y):
		for x in range(first.x, end.x):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) != 3: continue
			var mass := int(world.get_liquid_mass(cell))
			if mass > 0 and mass < 255: result += 1
	return result

func _test_legacy_versions() -> void:
	# Old saves keep their own generator. V5 must not silently rewrite an existing world.
	var region := Rect2i(0, 3, 2, 2)
	var digests: Array[String] = []
	for version in [2, 3, 4, 5]:
		var world: Variant = _world(99173, version)
		world.request_chunk_region(region, 1); world.flush_generation()
		digests.append(str(world.get_region_content_hash(region)))
		_equal(int(world.get_world_identity().generation_version), version, "version %d dispatches to its own generator" % version)
	_equal(digests.size(), _unique(digests).size(), "every generator version produces distinct content")

# ---------------------------------------------------------------------------------------

func _find_supported(world: Variant, material: int) -> Vector2i:
	var first := AREA.position * 64; var end := (AREA.position + AREA.size) * 64
	for y in range(first.y + 2, end.y - 2):
		for x in range(first.x + 2, end.x - 10):
			var cell := Vector2i(x, y)
			if world.get_cell(cell) == material and world.get_cell(cell + Vector2i.DOWN) in [1, 4, 5]: return cell
	return Vector2i(999999, 999999)

func _find_water_wall(world: Variant) -> Array:
	var first := AREA.position * 64; var end := (AREA.position + AREA.size) * 64
	for y in range(first.y + 10, end.y - 10):
		for x in range(first.x + 10, end.x - 10):
			var water := Vector2i(x, y)
			if world.get_cell(water) != 3: continue
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if world.get_cell(water + direction) in [1, 4, 5]: return [water, direction]
	return []

func _count_material(world: Variant, material: int) -> int:
	var result := 0; var first := AREA.position * 64; var end := (AREA.position + AREA.size) * 64
	for y in range(first.y, end.y):
		for x in range(first.x, end.x): result += int(world.get_cell(Vector2i(x, y)) == material)
	return result

func _unique(values: Array) -> Array:
	var seen: Array = []
	for value in values:
		if not (value in seen): seen.append(value)
	return seen

func _world(seed_value: int, version: int, workers: int = 6) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed_value, "generation_version": version}, workers)
	return world

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
