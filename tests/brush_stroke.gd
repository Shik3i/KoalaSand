extends SceneTree

# Brush strokes.
#
# A stroke replaced roughly 4,700 per-cell commands a frame with one. That is only allowed to be
# a performance change: the cells it covers, the provenance it writes and the simulation it wakes
# have to be what the per-cell path produced, and it has to stay a deterministic function of its
# arguments.

var checks := 0
var failures: Array[String] = []

const SAND := 2
const STONE := 1
const EMPTY := 0
const COAL := 4
const COAL_CHUNK := 14

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_geometry_matches_per_cell_stamps()
	_test_determinism()
	_test_rejects_impossible_strokes()
	_test_erase_and_harvest()
	_test_stroke_wakes_the_simulation()
	_test_command_round_trip()
	_test_log_is_bounded()
	if failures.is_empty():
		print("PASS: %d brush stroke checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("BRUSH_STROKE: " + failure)
	print("FAIL: %d of %d brush stroke checks" % [failures.size(), checks]); quit(1)

# ---------------------------------------------------------------------------------------

func _test_geometry_matches_per_cell_stamps() -> void:
	# The old brush stamped a disc at every interpolated point along the line. The union of
	# those discs is a capsule, and that is what the stroke sweeps. Anything else would change
	# how the brush feels, which is not a change a performance fix is allowed to make.
	for radius in [0, 1, 3, 7]:
		for pair in [[Vector2i(-40, 300), Vector2i(-40, 300)], [Vector2i(-60, 310), Vector2i(20, 310)],
					 [Vector2i(-30, 290), Vector2i(30, 340)], [Vector2i(40, 350), Vector2i(-50, 300)]]:
			var stroke_world: Variant = _world()
			var stamped_world: Variant = _world()
			var from_cell: Vector2i = pair[0]
			var to_cell: Vector2i = pair[1]
			stroke_world.paint_stroke(from_cell, to_cell, radius, STONE)
			for point in _line_points(from_cell, to_cell):
				for offset_y in range(-radius, radius + 1):
					for offset_x in range(-radius, radius + 1):
						if offset_x * offset_x + offset_y * offset_y > radius * radius: continue
						stamped_world.set_cell(point + Vector2i(offset_x, offset_y), STONE)
			var mismatches := 0
			var painted := 0
			for y in range(270, 380):
				for x in range(-90, 70):
					var cell := Vector2i(x, y)
					var in_stroke: bool = stroke_world.get_cell(cell) == STONE
					var in_stamps: bool = stamped_world.get_cell(cell) == STONE
					if in_stroke: painted += 1
					if in_stroke != in_stamps: mismatches += 1
			_equal(mismatches, 0, "radius %d stroke %s->%s covers the per-stamp cells" % [radius, from_cell, to_cell])
			if radius > 0:
				_check(painted > 0, "radius %d stroke %s->%s painted something" % [radius, from_cell, to_cell])


func _test_determinism() -> void:
	# Two worlds hold the same region and take the same stroke. One generates the region first
	# and paints into chunks that already exist; the other paints first, so the stroke pulls
	# the chunks into being as it goes. The edit has to be the same either way.
	var region := Rect2i(-2, 4, 4, 2)
	var first: Variant = _world()
	var second: Variant = _world()
	first.paint_stroke(Vector2i(-70, 300), Vector2i(70, 330), 4, STONE)
	first.request_chunk_region(region, 0)
	first.flush_generation()
	second.request_chunk_region(region, 0)
	second.flush_generation()
	second.paint_stroke(Vector2i(-70, 300), Vector2i(70, 330), 4, STONE)
	_equal(first.get_region_content_hash(region), second.get_region_content_hash(region),
		"a stroke is the same edit whether or not the chunks it covers existed first")

	var repeated: Variant = _world()
	repeated.request_chunk_region(region, 0)
	repeated.flush_generation()
	repeated.paint_stroke(Vector2i(-70, 300), Vector2i(70, 330), 4, STONE)
	repeated.paint_stroke(Vector2i(-70, 300), Vector2i(70, 330), 4, STONE)
	_equal(repeated.get_region_content_hash(region), second.get_region_content_hash(region),
		"painting the same stroke twice changes nothing the second time")

	# The stamp path is anchored at the point the drag started from, so a diagonal drag is very
	# slightly direction-dependent -- it always has been, and matching the old brush exactly is
	# worth more than smoothing that out. An axis-aligned drag has no such freedom, and there
	# reversal has to be exact.
	var forward_axis: Variant = _world()
	var reverse_axis: Variant = _world()
	forward_axis.paint_stroke(Vector2i(-70, 310), Vector2i(70, 310), 4, STONE)
	reverse_axis.paint_stroke(Vector2i(70, 310), Vector2i(-70, 310), 4, STONE)
	_equal(forward_axis.material_and_provenance_hash(), reverse_axis.material_and_provenance_hash(),
		"an axis-aligned stroke covers the same cells in both directions")

	# The two directions are compared against each other over identical terrain, so every
	# difference is a difference in the stroke rather than in the world underneath it.
	var baseline: Variant = _world()
	var reversed_stroke: Variant = _world()
	baseline.request_chunk_region(region, 0)
	baseline.flush_generation()
	reversed_stroke.request_chunk_region(region, 0)
	reversed_stroke.flush_generation()
	reversed_stroke.paint_stroke(Vector2i(70, 330), Vector2i(-70, 300), 4, STONE)
	var differing := 0
	var painted := 0
	for y in range(290, 340):
		for x in range(-80, 80):
			var cell := Vector2i(x, y)
			var forward_material: int = second.get_cell(cell)
			var reverse_material: int = reversed_stroke.get_cell(cell)
			if forward_material != baseline.get_cell(cell): painted += 1
			if forward_material != reverse_material: differing += 1
	_check(painted > 300, "the diagonal stroke painted enough cells to compare (%d)" % painted)
	_check(differing * 50 <= painted, "reversing a diagonal stroke only moves fringe cells (%d of %d)" % [differing, painted])


func _test_rejects_impossible_strokes() -> void:
	var world: Variant = _world()
	_check(world.paint_stroke(Vector2i(0, 300), Vector2i(10, 300), -1, STONE) < 0, "negative radius rejected")
	_check(world.paint_stroke(Vector2i(0, 300), Vector2i(10, 300), 65, STONE) < 0, "radius past the brush limit rejected")
	_check(world.paint_stroke(Vector2i(0, 300), Vector2i(10, 300), 3, 9999) < 0, "unknown material rejected")
	_check(world.paint_stroke(Vector2i(0, 300), Vector2i(10, 300), 3, -1) < 0, "negative material rejected")
	# A stroke that would sweep the whole world is a malformed command, not a brush gesture.
	_check(world.paint_stroke(Vector2i(-2000000, 300), Vector2i(2000000, 300), 3, STONE) < 0,
		"implausibly long stroke rejected instead of sweeping the world")
	_check(world.harvest_stroke(Vector2i(0, 300), Vector2i(10, 300), 65) < 0, "harvest radius limit enforced")
	var untouched: Variant = _world()
	_equal(world.material_and_provenance_hash(), untouched.material_and_provenance_hash(),
		"a rejected stroke leaves the world untouched")


func _test_erase_and_harvest() -> void:
	var world: Variant = _world()
	world.request_chunk_region(Rect2i(-1, 4, 2, 2), 0)
	world.flush_generation()
	world.paint_stroke(Vector2i(-20, 300), Vector2i(20, 300), 5, STONE)
	var erased: int = world.paint_stroke(Vector2i(-20, 300), Vector2i(20, 300), 5, EMPTY)
	_check(erased > 0, "erase is a stroke with the empty material")
	var solid := 0
	for x in range(-20, 21):
		if world.get_cell(Vector2i(x, 300)) != EMPTY: solid += 1
	_equal(solid, 0, "erasing a stroke leaves nothing behind on its centre line")

	var harvest_world: Variant = _world()
	harvest_world.set_cell(Vector2i(4, 300), COAL)
	harvest_world.set_cell(Vector2i(5, 300), STONE)
	var harvested: int = harvest_world.harvest_stroke(Vector2i(0, 300), Vector2i(10, 300), 2)
	_equal(harvested, 1, "harvest converts only the coal it swept")
	_equal(harvest_world.get_cell(Vector2i(4, 300)), COAL_CHUNK, "harvested coal becomes a coal chunk")
	_equal(harvest_world.get_cell(Vector2i(5, 300)), STONE, "harvest leaves other materials alone")


func _test_stroke_wakes_the_simulation() -> void:
	# World generation creates equilibrium; player action creates chaos. A stroke has to count
	# as player action, or painted sand would hang in the air until something else woke it.
	var world: Variant = _world()
	world.request_chunk_region(Rect2i(-1, 4, 2, 2), 0)
	world.flush_generation()
	var spawn: Vector2i = world.get_character_spawn()
	world.paint_stroke(Vector2i(spawn.x - 6, spawn.y - 40), Vector2i(spawn.x + 6, spawn.y - 40), 3, SAND)
	_check(world.active_chunk_count() > 0, "a stroke leaves the affected chunks active")
	var before: String = world.material_state_hash()
	for _tick in range(8): world.step()
	_check(world.material_state_hash() != before, "painted sand falls once the world steps")


func _test_command_round_trip() -> void:
	var payload := {"x0": -10, "y0": 300, "x1": 30, "y1": 320, "radius": 3, "material_id": STONE}
	var command := WorldCommand.new(WorldCommand.Type.PAINT_STROKE, payload, 7)
	var restored := WorldCommand.deserialize(command.serialize())
	_check(restored != null, "a stroke command survives serialisation")
	if restored != null:
		_equal(int(restored.type), int(WorldCommand.Type.PAINT_STROKE), "stroke command keeps its type")
		_equal(restored.payload, payload, "stroke command keeps its payload")

	var world: Variant = _world()
	var bus := WorldCommandBus.new()
	_check(bus.apply(world, command), "the bus applies a stroke command")
	_check(int(bus.last_result) > 0, "the bus reports the cells a stroke wrote")
	_check(not bus.apply(world, WorldCommand.new(WorldCommand.Type.PAINT_STROKE, {"x0": 0, "y0": 0}, 7)),
		"a stroke command missing its endpoints is rejected")


func _test_log_is_bounded() -> void:
	# The command log is a diagnostic tail. It used to grow for as long as the session lasted.
	var world: Variant = _world()
	var bus := WorldCommandBus.new()
	for index in range(WorldCommandBus.LOG_CAPACITY * 3):
		bus.submit(world, WorldCommand.new(WorldCommand.Type.CREATIVE_PAINT,
			{"x": index % 200 - 100, "y": 300 + int(index / 200.0), "material_id": STONE}, 1))
	_check(bus.serialize_log().size() <= WorldCommandBus.LOG_CAPACITY + WorldCommandBus.LOG_TRIM_SLACK,
		"the command log stops growing at its capacity")

# ---------------------------------------------------------------------------------------

func _world() -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": 8675309, "generation_version": 5}, 4)
	return world


func _line_points(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var delta := to_cell - from_cell
	var steps := maxi(absi(delta.x), absi(delta.y))
	var points: Array[Vector2i] = []
	if steps == 0:
		points.append(to_cell)
		return points
	for index in range(steps + 1):
		var fraction := float(index) / float(steps)
		points.append(Vector2i(roundi(lerpf(from_cell.x, to_cell.x, fraction)), roundi(lerpf(from_cell.y, to_cell.y, fraction))))
	return points


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
