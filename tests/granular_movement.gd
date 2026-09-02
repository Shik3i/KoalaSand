extends SceneTree

# What a falling cell has to carry with it.
#
# The granular hot loop used to hand every single move to the serial barrier so that
# reactive_cells_ could be re-derived for both the cell that left and the cell that arrived.
# For plain Sand that is a provable no-op -- a cell only enters reactive_cells_ if its material
# is reactive or it carries bound water -- but it cost two hash-set erases and two chunk-map
# lookups per move on the one part of the tick that cannot be parallel. A million falling Sand
# cells meant four million serial map operations that nothing ever read, and that was most of
# why Sand cost roughly five times what the same number of Water cells cost.
#
# The loop now skips the notification when neither the material leaving nor the material
# arriving can be reactive. These are the cases that must still be tracked, and the case that
# must not be.

var checks := 0
var failures: Array[String] = []

const EMPTY := 0
const STONE := 1
const SAND := 2
const WATER := 3
const COAL_CHUNK := 14

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	_test_wet_sediment_keeps_its_moisture_while_falling()
	_test_dry_sand_registers_nothing_reactive()
	_test_burning_material_stays_tracked_while_falling()
	_test_falling_conserves_material()
	if failures.is_empty():
		print("PASS: %d granular movement checks" % checks)
		quit(0)
		return
	for failure in failures: push_error("GRANULAR_MOVEMENT: " + failure)
	print("FAIL: %d of %d granular movement checks" % [failures.size(), checks])
	quit(1)

# ---------------------------------------------------------------------------------------

func _test_wet_sediment_keeps_its_moisture_while_falling() -> void:
	var world: Variant = _world()
	var top := Vector2i(4, 4)
	world.set_cell(top, SAND)
	world.set_cell(Vector2i(5, 4), WATER)
	var bound: Dictionary = world.bind_water_to_sediment(top, Vector2i(5, 4), 40)
	_equal(int(bound.get("accepted", 0)), 40, "water binds to the sediment cell")
	_check(int(world.get_organic_moisture(top)) > 0, "the sediment starts wet")
	_check(int(world.get_organic_statistics().reactive_cells) > 0, "a wet cell is tracked as reactive")

	var landed := _fall(world, top, SAND)
	_check(landed != top, "the wet sediment actually moved")
	_equal(int(world.get_organic_moisture(landed)), 40, "bound water travels with the cell that carries it")
	_equal(int(world.get_organic_moisture(top)), 0, "the cell it left keeps no moisture")
	_equal(int(world.get_bound_water_mass()), 40, "no bound water is created or lost by the fall")


func _test_dry_sand_registers_nothing_reactive() -> void:
	# This is the premise the optimisation rests on. If dry Sand ever becomes reactive, the
	# notification it no longer sends would start to matter and this check is what says so.
	var world: Variant = _world()
	for x in range(0, 12):
		world.set_cell(Vector2i(x, 4), SAND)
	_equal(int(world.get_organic_statistics().reactive_cells), 0, "dry Sand starts with nothing reactive")
	for _tick in range(30):
		world.step()
	_equal(int(world.get_organic_statistics().reactive_cells), 0, "falling dry Sand registers nothing reactive")
	var settled := 0
	for y in range(0, 41):
		for x in range(0, 12):
			if world.get_cell(Vector2i(x, y)) == SAND: settled += 1
	_equal(settled, 12, "every dry Sand cell is still there after it falls")


func _test_burning_material_stays_tracked_while_falling() -> void:
	# Coal chunks are both reactive and able to fall, which is the combination the notification
	# exists for. Cold material is dropped from reactive_cells_ by process_reactions() every
	# tick whether it moves or not, so the observable question is whether a cell that is
	# genuinely reacting keeps reacting across a move.
	var world: Variant = _world()
	var top := Vector2i(4, 4)
	world.set_cell(top, COAL_CHUNK)
	var ignition: Dictionary = world.ignite_cell(top, 24000000)
	_check(bool(ignition.get("accepted", false)), "the coal chunk ignites")
	_check(int(world.get_organic_statistics().reactive_cells) > 0, "an ignited cell is reacting")

	var landed := _fall(world, top, COAL_CHUNK)
	_check(landed != top, "the burning material actually moved")
	_check(int(world.get_organic_statistics().reactive_cells) > 0,
		"a burning cell is still reacting after it falls")
	_check(int(world.get_temperature(landed)) > int(world.get_temperature(Vector2i(30, 39))),
		"the heat travelled with the cell rather than staying behind")


func _test_falling_conserves_material() -> void:
	# The same-chunk fast path resolves the destination without the chunk map. A mistake there
	# would duplicate or drop cells, so count them across a chunk boundary as well as inside one.
	var world: Variant = _world()
	var placed := 0
	for x in range(60, 70):
		for y in range(2, 6):
			world.set_cell(Vector2i(x, y), SAND)
			placed += 1
	var before: String = world.material_state_hash()
	for _tick in range(60):
		world.step()
	_check(world.material_state_hash() != before, "the pile moved")
	var remaining := 0
	for y in range(0, 41):
		for x in range(45, 85):
			if world.get_cell(Vector2i(x, y)) == SAND: remaining += 1
	_equal(remaining, placed, "no Sand is created or lost falling across a chunk boundary")

# ---------------------------------------------------------------------------------------

func _world() -> Variant:
	# A bare world, so nothing but the cells placed here is in play.
	var world := NativeSandWorld.new()
	world.reset(7, 4)
	world.allocate_chunk_rect(Rect2i(0, 0, 3, 2))
	# A floor, so falling material settles instead of leaving the allocated chunks.
	for x in range(0, 192):
		world.set_cell(Vector2i(x, 40), STONE)
	return world


func _fall(world: Variant, from_cell: Vector2i, material_id: int) -> Vector2i:
	for _tick in range(60):
		world.step()
		if world.get_cell(from_cell) != material_id:
			break
	for y in range(from_cell.y, 40):
		for x in range(from_cell.x - 3, from_cell.x + 4):
			var cell := Vector2i(x, y)
			if cell == from_cell: continue
			if world.get_cell(cell) == material_id: return cell
	return from_cell


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected: failures.append("%s expected=%s actual=%s" % [label, expected, actual])
