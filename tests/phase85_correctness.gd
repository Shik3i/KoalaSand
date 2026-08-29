extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry := MaterialRegistry.new()
	_check(registry.load_directory() == OK, "material registry loads")
	for key in [&"stone", &"raw_sand", &"water", &"iron", &"glass"]:
		var definition: MaterialDefinition = registry.get_definition(registry.get_id(key))
		_check(definition.thermal_conductivity > 0, "%s conductivity" % key)
		_check(definition.specific_heat_units > 1, "%s heat capacity" % key)
	_check(registry.get_definition(registry.get_id(&"water")).thermal_mass_uses_cell_mass, "Water capacity uses liquid mass")

	var world := NativeSandWorld.new()
	world.reset(8501, 8)
	world.set_game_mode(1)
	world.fill_rect(Rect2i(-64, -64, 128, 128), 0)
	_check(world.place_pipe_line(Vector2i(-4, 0), Vector2i(4, 0)) == 9, "Pipe fixture placed")
	var before: Dictionary = world.get_infrastructure_render_page(Vector2i(-1, 0))
	_check(before.topology.size() == int(before.width) * int(before.height) * 4, "topology page is cropped RGBA8")
	_check(before.dynamic.size() == int(before.width) * int(before.height) * 4, "dynamic page is cropped RGBA8")
	_check(int(before.pipe_count) == 4, "negative page culls Pipe records")
	var topology_before: PackedByteArray = before.topology.duplicate()
	_check(world.set_pipe_mass(Vector2i(-2, 0), 32768, 1600) == OK, "Pipe dynamic state changed")
	var after: Dictionary = world.get_infrastructure_render_page(Vector2i(-1, 0))
	_check(after.topology == topology_before, "dynamic Pipe change preserves static topology page")
	_check(after.dynamic != before.dynamic, "dynamic Pipe change alters only dynamic page")
	_check(world.place_conveyor_line(Vector2i(-4, 8), Vector2i(4, 8), 1) == 9, "Conveyor fixture placed")
	var conveyor_page: Dictionary = world.get_infrastructure_render_page(Vector2i.ZERO)
	_check(int(conveyor_page.infrastructure_count) >= 10, "Pipe and Conveyor share dense page path")

	var temperature_page: Dictionary = world.get_temperature_render_page(Rect2i(Vector2i(-1, -1), Vector2i(2, 2)))
	_check(int(temperature_page.width) == 128 and int(temperature_page.height) == 128, "temperature page visible extent")
	_check(temperature_page.pixels.size() == 128 * 128 * 2, "temperature page is packed RG8")
	var ambient_low := 1173 & 255
	_check(temperature_page.pixels[0] == ambient_low, "temperature page stores explicit low byte")

	var renderer_source := FileAccess.get_file_as_string("res://rendering/structure_renderer.gd")
	_check(renderer_source.contains("InfrastructureRenderPages"), "paged renderer is canonical")
	_check(renderer_source.contains("dynamic_state"), "dynamic texture is shader visible")
	_check(renderer_source.contains("TIME * sign(flow)"), "Pipe flow animation is shader driven")
	_check(renderer_source.contains("_page_topology_bytes"), "static topology upload cache exists")
	_check(renderer_source.contains("_page_dynamic_bytes"), "dynamic dirty upload cache exists")
	_check(FileAccess.file_exists("res://native/core/thermal_prototype.cpp"), "isolated thermal prototype exists")
	_check(FileAccess.file_exists("res://native/core/thermal_benchmark.cpp"), "thermal benchmark exists")
	_check(FileAccess.file_exists("res://data/materials/steam.tres"), "Phase 9 Steam definition exists")
	_check(FileAccess.file_exists("res://data/materials/ice.tres"), "Phase 9 Ice definition exists")

	if failures.is_empty():
		print("PASS: %d checks across 7 Phase 8.5 architecture suites" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("FAIL: " + failure)
	print("FAIL: %d of %d Phase 8.5 checks failed" % [failures.size(), checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
