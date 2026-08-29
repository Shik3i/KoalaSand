extends SceneTree

const EMPTY := 0
const STONE := 1
const WATER := 3
const COAL_CHUNK := 14
const ASH := 15
const STEAM := 17
const WOOD := 21
const LEAVES := 22
const CHARCOAL := 23
const SMOKE := 24
const RAW_FOOD := 25
const COOKED_FOOD := 26
const BURNT_FOOD := 27

var checks := 0
var suites := 0
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _world(seed := 12001, workers := 4) -> Variant:
	var world := NativeSandWorld.new()
	world.reset(seed, workers)
	world.set_game_mode(1)
	world.allocate_chunk_rect(Rect2i(-4, -4, 8, 8))
	return world


func _v2_world(seed := 12002, workers := 4) -> Variant:
	var world := NativeSandWorld.new()
	world.configure_world({
		"seed": seed, "width": 16384, "depth": 4096, "sky": 512,
		"surface_baseline": 0, "surface_amplitude": 72, "sediment_depth": 18,
		"cave_density": 0.52, "coal_frequency": 0.73, "water_frequency": 0.72,
		"geology_scale": 512, "generation_version": 2,
	}, workers)
	return world


func _run() -> void:
	_material_contract()
	_worldgen_and_modes()
	_tree_cut_fall_and_replay()
	_optional_state_and_moisture()
	_combustion_and_blocking()
	_pyrolysis_and_fuels()
	_commands_and_factory_clear()
	_cookware_and_conductivity()
	_cooking()
	_worker_parity_and_hashing()
	if failed:
		print("FAIL: Phase 12 correctness")
		quit(1)
	else:
		print("PASS: %d checks across %d Phase 12 suites" % [checks, suites])
		quit(0)


func _material_contract() -> void:
	suites += 1
	var registry := MaterialRegistry.new()
	_check_equal(registry.load_directory(), OK, "Phase 12 registry loads")
	_check_equal(registry.size(), 28, "stable material registry size")
	for pair in [[&"wood", WOOD], [&"leaves", LEAVES], [&"charcoal", CHARCOAL], [&"smoke", SMOKE], [&"raw_food", RAW_FOOD], [&"cooked_food", COOKED_FOOD], [&"burnt_food", BURNT_FOOD]]:
		_check_equal(registry.get_id(pair[0]), pair[1], "stable ID %s" % pair[0])
	var world: Variant = _world()
	var definitions: Array = world.get_organic_material_definitions()
	_check_equal(definitions.size(), 7, "seven organic material definitions")
	_check_equal(world.get_fuel_definitions().size(), 3, "Coal/Wood/Charcoal generic fuels")
	_check(int(world.get_fuel_definitions()[2].energy_per_mass) > int(world.get_fuel_definitions()[1].energy_per_mass), "Charcoal energy density exceeds Wood")
	var architecture: Dictionary = world.get_organic_architecture()
	_check_equal(architecture.base_cell_bytes, 9, "base cell remains 9 bytes")
	_check_equal(architecture.standing_tree_metadata_bytes, 0, "standing Trees allocate no entity record")
	_check(bool(architecture.implicit_ambient_air), "ambient air remains implicit")
	_check_equal(world.get_memory_layout().maximum_material_id, 27, "native material range includes Phase 12")


func _worldgen_and_modes() -> void:
	suites += 1
	var anchors_world: Variant = _v2_world(12002, 2)
	var anchors: Array = anchors_world.get_world_feature_anchors(Rect2i(-32, 0, 64, 1))
	var trees: Array = anchors.filter(func(anchor: Dictionary) -> bool: return int(anchor.get("template_index", -1)) == 4)
	_check(not trees.is_empty(), "deterministic surface Tree anchors exist")
	for anchor: Dictionary in trees:
		_check(absi((anchor.world_cell as Vector2i).x) >= 160, "Tree anchor respects spawn factory exclusion")
		_check_equal(anchor.template_id, "basic_tree.v1", "Tree uses versioned WorldFeatureTemplate")
	var area := Rect2i(-8, -4, 16, 10)
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _v2_world(12002, workers)
		world.request_chunk_region(area, 1)
		world.flush_generation()
		hashes.append(world.get_region_content_hash(area))
	for value in hashes: _check_equal(value, hashes[0], "organic WorldGen worker parity")
	var factory: Variant = _v2_world(12002, 2)
	var creative: Variant = _v2_world(12002, 2)
	creative.set_game_mode(1)
	for world in [factory, creative]:
		world.request_chunk_region(area, 1); world.flush_generation()
	_check_equal(factory.get_region_content_hash(area), creative.get_region_content_hash(area), "same Trees across modes")
	print("phase12_worldgen_hash workers=[1,2,4,8] hash=%s trees=%d" % [hashes[0], trees.size()])


func _build_test_tree(world: Variant) -> int:
	for x in range(-20, 21): world.set_material_state(Vector2i(x, 12), STONE, 255, 1172)
	var cells := 0
	for y in range(2, 11):
		world.set_material_state(Vector2i(0, y), WOOD, 255, 1172)
		world.set_organic_moisture(Vector2i(0, y), 32)
		cells += 1
	for cell in [Vector2i(-1, 2), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, 2)]:
		world.set_material_state(cell, LEAVES, 255, 1172)
		cells += 1
	return cells


func _tree_cut_fall_and_replay() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 8]:
		var world: Variant = _world(12003, workers)
		var source_cells := _build_test_tree(world)
		var cut: Dictionary = world.character_cut_cell(Vector2i(0, 10))
		_check(bool(cut.accepted), "Cut creates a FellableCluster")
		_check_equal(int(cut.cells), source_cells, "connected Tree captured exactly")
		_check_equal(world.get_organic_statistics().active_clusters, 1, "one detached cluster")
		for tick in 90: world.step()
		_check_equal(world.get_organic_statistics().active_clusters, 0, "Tree settles back into grid matter")
		var settled_cells := 0
		var settled_mass := 0
		for y in range(-10, 20):
			for x in range(-24, 25):
				if int(world.get_cell(Vector2i(x, y))) in [WOOD, LEAVES]:
					settled_cells += 1
					settled_mass += int(world.get_material_amount(Vector2i(x, y)))
		_check_equal(settled_cells, source_cells, "Tree placement has no duplication/loss")
		_check_equal(settled_mass, source_cells * 255, "Tree organic mass conserved")
		hashes.append(world.organic_state_hash())
	_check_equal(hashes[0], hashes[1], "Tree fall worker replay parity")
	print("phase12_tree_replay workers=[1,8] hash=%s" % hashes[0])


func _optional_state_and_moisture() -> void:
	suites += 1
	var world: Variant = _world(12004)
	var before: Dictionary = world.get_memory_layout()
	_check_equal(before.organic_moisture_plane_chunks, 0, "untouched world has no moisture planes")
	_check_equal(before.oxidizer_plane_chunks, 0, "untouched atmosphere has no plane")
	_check_equal(before.organic_reaction_plane_chunks, 0, "untouched world has no reaction plane")
	var cell := Vector2i.ZERO
	world.set_material_state(cell, WOOD, 255, 1700)
	world.set_organic_moisture(cell, 20)
	for neighbor in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]: world.set_material_state(neighbor, STONE, 255, 1172)
	var initial_family: int = world.get_total_phase_family_mass(1)
	for tick in 8: world.step()
	var moisture := int(world.get_organic_moisture(cell))
	var released := int(world.get_total_phase_family_mass(1)) - initial_family
	_check(moisture < 20, "hot wet Wood dries")
	_check_equal(moisture + released, 20, "Wood moisture becomes conserved Water/Steam mass")
	_check(world.get_temperature(cell) < 1700, "drying consumes latent energy")
	var layout: Dictionary = world.get_memory_layout()
	_check(layout.organic_moisture_plane_chunks > 0 and layout.organic_reaction_plane_chunks > 0, "organic planes allocate lazily on use")
	_check_equal(layout.simulation_bytes_per_cell, 9, "optional state does not bloat every cell")


func _combustion_and_blocking() -> void:
	suites += 1
	var world: Variant = _world(12005)
	world.set_material_state(Vector2i.ZERO, WOOD, 40, 2300)
	var initial_temperature := int(world.get_temperature(Vector2i.ZERO))
	for tick in 8: world.step()
	var stats: Dictionary = world.get_organic_statistics()
	_check(int(stats.wood_burned) > 0, "hot dry Wood burns in oxygen")
	_check(int(stats.oxygen_consumed) > 0, "combustion consumes local oxygen")
	_check(int(stats.combustion_energy) > 0, "combustion releases real thermal energy")
	_check(int(stats.ash_produced) > 0 and int(stats.smoke_produced) > 0, "combustion emits physical Ash and Smoke")
	_check_equal(int(stats.ash_produced) + int(stats.smoke_produced), int(stats.wood_burned) + int(stats.oxygen_consumed), "combustion mass balance exact")
	_check(world.get_temperature(Vector2i.ZERO) >= initial_temperature or int(world.get_cell(Vector2i.ZERO)) == EMPTY, "burning heats fuel before exhaustion")
	var blocked: Variant = _world(12006)
	blocked.set_material_state(Vector2i.ZERO, WOOD, 20, 2300)
	for y in range(-2, 3):
		for x in range(-2, 3):
			if x != 0 or y != 0: blocked.set_material_state(Vector2i(x, y), STONE, 255, 1172)
	for tick in 6: blocked.step()
	_check_equal(blocked.get_cell(Vector2i.ZERO), WOOD, "blocked byproducts prevent hidden fuel deletion")
	_check_equal(blocked.get_material_amount(Vector2i.ZERO), 20, "blocked combustion preserves fuel mass")


func _pyrolysis_and_fuels() -> void:
	suites += 1
	var world: Variant = _world(12007)
	world.set_material_state(Vector2i.ZERO, WOOD, 255, 2300)
	for neighbor in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]: world.set_material_state(neighbor, STONE, 255, 1172)
	for tick in 60: world.step()
	_check_equal(world.get_cell(Vector2i.ZERO), CHARCOAL, "low-oxygen heating produces Charcoal")
	_check_equal(world.get_material_amount(Vector2i.ZERO), 96, "Charcoal yield is fixed-point mass")
	_check(world.get_temperature(Vector2i.ZERO) > 1800, "Charcoal retains hot source temperature")
	var stats: Dictionary = world.get_organic_statistics()
	_check_equal(int(stats.charcoal_produced) + int(stats.smoke_produced), 255, "pyrolysis mass conserved")
	var fuel_defs: Array = world.get_fuel_definitions()
	_check_equal(fuel_defs.map(func(value: Dictionary) -> int: return int(value.material_id)), [COAL_CHUNK, WOOD, CHARCOAL], "generic fuel order stable")
	_check(int(fuel_defs[2].burn_rate) < int(fuel_defs[1].burn_rate), "Charcoal burns slower than Wood")
	var leaves: Variant = _world(12014)
	leaves.set_material_state(Vector2i.ZERO, LEAVES, 255, 2100)
	for neighbor in [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]: leaves.set_material_state(neighbor, STONE, 255, 1172)
	for tick in 60: leaves.step()
	_check_equal(leaves.get_cell(Vector2i.ZERO), CHARCOAL, "Leaves pyrolysis uses configured nonzero Charcoal yield")
	_check_equal(int(leaves.get_organic_statistics().charcoal_produced), 16, "Leaves fixed-point Charcoal yield is data-driven")


func _commands_and_factory_clear() -> void:
	suites += 1
	var world: Variant = _world(12008)
	_build_test_tree(world)
	var bus := WorldCommandBus.new()
	var cut := WorldCommand.new(WorldCommand.Type.CUT_ORGANIC, {"x":0, "y":10}, 3, 1, 7)
	var restored := WorldCommand.deserialize(cut.serialize())
	_check(restored != null and restored.type == WorldCommand.Type.CUT_ORGANIC, "CUT WorldCommand serializes")
	_check(bus.submit(world, restored), "CUT WorldCommand applies")
	var ignite := WorldCommand.new(WorldCommand.Type.IGNITE, {"x":0, "y":10, "energy":24000000}, 4, 2, 7)
	_check(WorldCommand.deserialize(ignite.serialize()) != null, "IGNITE WorldCommand serializes")
	var clear_world: Variant = _world(12009)
	for x in [0, 8]:
		for y in range(2, 7): clear_world.set_material_state(Vector2i(x, y), WOOD, 255, 1172)
	var clear := WorldCommand.new(WorldCommand.Type.CLEAR_VEGETATION_RECT, {"x":-2, "y":0, "width":14, "height":10})
	_check(WorldCommandBus.new().submit(clear_world, clear), "Factory vegetation batch applies")
	_check_equal(clear_world.get_organic_statistics().active_clusters, 2, "Factory batch creates two physical clusters")


func _cookware_and_conductivity() -> void:
	suites += 1
	var world: Variant = _world(12010)
	var research_ids: Array = world.get_research_definitions().map(func(value: Dictionary) -> String: return str(value.id))
	_check(research_ids.has("organic.wood_processing"), "Wood Processing research boundary exists")
	_check(research_ids.has("thermal.cookware"), "Cookware research unlock exists")
	_check(not research_ids.has("organic.combustion_control"), "Combustion Control deferred without Vent/Fan/Grate infrastructure")
	var iron_origin := Vector2i(-20, 0)
	var ceramic_origin := Vector2i(20, 0)
	_check(int(world.place_structure(35, iron_origin, 0)) > 0, "Iron Pot places")
	_check(int(world.place_structure(36, ceramic_origin, 0)) > 0, "test-only Ceramic vessel places")
	for x in range(1, 8):
		world.set_material_state(iron_origin + Vector2i(x, 4), WATER, 255, 1172)
		world.set_material_state(ceramic_origin + Vector2i(x, 4), WATER, 255, 1172)
		world.set_material_state(iron_origin + Vector2i(x, 6), STONE, 255, 5000)
		world.set_material_state(ceramic_origin + Vector2i(x, 6), STONE, 255, 5000)
	_check(int(world.remove_structure_at(iron_origin)) <= 0, "Pot removal rejected while contents remain")
	for tick in 2: world.step()
	var iron_temperature := int(world.get_temperature(iron_origin + Vector2i(4, 4)))
	var ceramic_temperature := int(world.get_temperature(ceramic_origin + Vector2i(4, 4)))
	print("phase12_vessel_temperature iron=%d ceramic=%d" % [iron_temperature, ceramic_temperature])
	_check(iron_temperature > ceramic_temperature, "Iron vessel conducts faster than Ceramic fixture")
	_check(iron_temperature > 1172, "Pot Water heats through vessel wall")
	_check_equal(world.get_total_phase_family_mass(1), 14 * 255, "vessel heating conserves Water family mass")
	var definition: Dictionary = world.get_thermal_vessel_definition(35)
	_check(bool(definition.open_top) and bool(definition.contents_are_world_cells), "Iron Pot is open and inventory-free")
	_check_equal(definition.removal_policy, "CONTENTS_PRESENT_REJECTED", "Pot removal policy explicit")


func _cooking() -> void:
	suites += 1
	var world: Variant = _world(12011)
	world.set_material_state(Vector2i.ZERO, RAW_FOOD, 255, 1600)
	for tick in 60: world.step()
	_check_equal(world.get_cell(Vector2i.ZERO), COOKED_FOOD, "temperature-time exposure cooks Raw Food")
	_check(int(world.get_organic_statistics().food_cooked) > 0, "cooking statistic increments")
	world.set_material_state(Vector2i(4, 0), RAW_FOOD, 255, 2300)
	for tick in 30: world.step()
	_check_equal(world.get_cell(Vector2i(4, 0)), BURNT_FOOD, "excess heat creates Burnt Food")
	_check(int(world.get_organic_statistics().food_burned) > 0, "burnt-food statistic increments")
	var cooking_hash: String = world.authoritative_physical_hash()
	var replay: Variant = _world(12011)
	replay.set_material_state(Vector2i.ZERO, RAW_FOOD, 255, 1600)
	for tick in 60: replay.step()
	replay.set_material_state(Vector2i(4, 0), RAW_FOOD, 255, 2300)
	for tick in 30: replay.step()
	_check_equal(replay.authoritative_physical_hash(), cooking_hash, "cooking temperature-time replay hash stable")
	print("phase12_cooking_replay hash=%s" % cooking_hash)


func _worker_parity_and_hashing() -> void:
	suites += 1
	var hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var world: Variant = _world(12012, workers)
		world.set_material_state(Vector2i.ZERO, CHARCOAL, 80, 3000)
		for tick in 40: world.step()
		hashes.append(world.authoritative_physical_hash())
	for value in hashes: _check_equal(value, hashes[0], "organic reaction worker parity")
	_check(not hashes[0].is_empty(), "authoritative hash includes organic state")
	print("phase12_worker_parity workers=[1,2,4,8] hash=%s" % hashes[0])
	var smoke_hashes: Array[String] = []
	for workers in [1, 2, 4, 8]:
		var smoke_world: Variant = _world(12013, workers)
		smoke_world.fill_pattern_state(Rect2i(0, 0, 32, 32), SMOKE, 128, 128, 2100, 2100)
		for tick in 20: smoke_world.step()
		smoke_hashes.append(smoke_world.authoritative_physical_hash())
	for value in smoke_hashes: _check_equal(value, smoke_hashes[0], "Smoke gas worker parity")
	print("phase12_smoke_worker_parity workers=[1,2,4,8] hash=%s" % smoke_hashes[0])


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failed = true
		push_error("%s expected=%s actual=%s" % [message, expected, actual])
