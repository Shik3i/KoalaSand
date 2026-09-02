extends SceneTree

# Deterministic V5 worldgen contact sheets, debug-field maps and single-seed inspection
# frames. Development artefacts only; none of this is player-facing UI.

const SEEDS := [3, 41, 2965, 8191, 15508, 18076, 33191, 45613, 71317, 99173,
	120011, 144013, 177019, 233021, 377029, 610031, 987037, 1597043, 2584081, 8675309]
const GRID := Vector2i(5, 4)
const GUTTER := 6
const OUTPUT := "res://artifacts/v5-worldgen"

# Frames are sampled well away from the origin except for the dedicated start sheets, so the
# guaranteed start features do not dominate every tile.
const AWAY := 5824

const SHEETS := {
	"surface": {"rect": Rect2i(AWAY - 960, -320, 1920, 720), "tile": Vector2i(384, 144), "stride": 3, "field": 0},
	"shallow": {"rect": Rect2i(AWAY - 480, -180, 960, 520), "tile": Vector2i(320, 174), "stride": 2, "field": 0},
	"deep": {"rect": Rect2i(AWAY - 640, 500, 1280, 700), "tile": Vector2i(320, 176), "stride": 3, "field": 0},
	"caves": {"rect": Rect2i(AWAY - 640, 220, 1280, 800), "tile": Vector2i(320, 200), "stride": 3, "field": 6},
	"cave-components": {"rect": Rect2i(AWAY - 512, 240, 1024, 640), "tile": Vector2i(320, 200), "stride": 2, "field": 12},
	"hydrology": {"rect": Rect2i(AWAY - 700, 140, 1400, 840), "tile": Vector2i(336, 200), "stride": 3, "field": 7},
	"biome": {"rect": Rect2i(AWAY - 2400, -300, 4800, 700), "tile": Vector2i(400, 58), "stride": 8, "field": 1},
	"province": {"rect": Rect2i(AWAY - 1600, -100, 3200, 2000), "tile": Vector2i(300, 188), "stride": 8, "field": 4},
	"strata": {"rect": Rect2i(AWAY - 500, -120, 1000, 660), "tile": Vector2i(320, 200), "stride": 2, "field": 5},
	"sediment": {"rect": Rect2i(AWAY - 700, -220, 1400, 500), "tile": Vector2i(350, 125), "stride": 3, "field": 8},
	"resources": {"rect": Rect2i(AWAY - 800, 0, 1600, 1400), "tile": Vector2i(320, 200), "stride": 4, "field": 9},
	"start": {"rect": Rect2i(-620, -260, 1240, 660), "tile": Vector2i(340, 180), "stride": 2, "field": 0},
	"start-constraints": {"rect": Rect2i(-900, -240, 1800, 740), "tile": Vector2i(360, 148), "stride": 4, "field": 10},
}

var _only := ""
var _detail := -1

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			_only = argument.substr(7)
		elif argument.begins_with("--detail="):
			_detail = int(argument.substr(9))
	call_deferred("_run")

func _run() -> void:
	if _detail >= 0:
		_render_detail(_detail)
		quit(0)
		return
	var target := ProjectSettings.globalize_path(OUTPUT + "/contact-sheets")
	DirAccess.make_dir_recursive_absolute(target)
	var written: Array[String] = []
	for category: String in SHEETS.keys():
		if _only != "" and category != _only:
			continue
		var spec: Dictionary = SHEETS[category]
		var tile: Vector2i = spec.tile
		var sheet := Image.create_empty(GRID.x * tile.x + (GRID.x + 1) * GUTTER,
			GRID.y * tile.y + (GRID.y + 1) * GUTTER, false, Image.FORMAT_RGBA8)
		sheet.fill(Color("06090d"))
		for index in SEEDS.size():
			var image := _render(SEEDS[index], spec)
			var destination := Vector2i(GUTTER + (index % GRID.x) * (tile.x + GUTTER),
				GUTTER + int(index / GRID.x) * (tile.y + GUTTER))
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), destination)
		var path := target.path_join("%s-20-seeds.png" % category)
		var error := sheet.save_png(path)
		written.append(path)
		print("v5_contact_sheet category=%s seeds=%d path=%s error=%s" % [category, SEEDS.size(), path, error_string(error)])

	# The climate-space diagnostic describes the biome table rather than a seed, so it is a
	# single artefact: it shows whether a parameter change has made a biome unreachable.
	if _only == "" or _only == "climate-space":
		var world := NativeSandWorld.new()
		world.configure_world({"seed": 1, "generation_version": 5}, 1)
		var page: Dictionary = world.get_worldgen_debug_field(Rect2i(0, 0, 640, 640), 11, 1)
		var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
		var path := target.path_join("climate-space.png")
		image.save_png(path)
		written.append(path)
		print("v5_climate_space panels=%s axes=%s path=%s" % [str(page.panels), str(page.axes), path])

	var manifest := FileAccess.open(target.path_join("manifest.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"generation_version": 5, "seeds": SEEDS, "grid": GRID, "sample_x": AWAY,
		"categories": SHEETS.keys(), "files": written}, "  "))
	manifest.close()
	print("PASS: V5 contact sheets")
	quit(0)

func _render(seed_value: int, spec: Dictionary) -> Image:
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed_value, "generation_version": 5}, 6)
	var rect: Rect2i = spec.rect
	var page: Dictionary = world.get_worldgen_debug_field(rect, int(spec.field), int(spec.stride))
	var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
	var tile: Vector2i = spec.tile
	var filter := Image.INTERPOLATE_NEAREST if int(spec.field) in [6, 12] else Image.INTERPOLATE_LANCZOS
	image.resize(tile.x, tile.y, filter)
	return image

func _render_detail(seed_value: int) -> void:
	var target := ProjectSettings.globalize_path(OUTPUT + "/detail")
	DirAccess.make_dir_recursive_absolute(target)
	var world := NativeSandWorld.new()
	world.configure_world({"seed": seed_value, "generation_version": 5}, 6)
	var frames := {
		"section": [Rect2i(AWAY - 700, -280, 1400, 1100), 0],
		"start": [Rect2i(-700, -280, 1400, 900), 0],
		"deep": [Rect2i(AWAY - 700, 900, 1400, 1100), 0],
		"cave-components": [Rect2i(AWAY - 700, 200, 1400, 900), 12],
		"strata": [Rect2i(AWAY - 700, -280, 1400, 1100), 5],
		"hydrology": [Rect2i(AWAY - 700, 100, 1400, 1100), 7],
	}
	for name: String in frames.keys():
		var spec: Array = frames[name]
		var page: Dictionary = world.get_worldgen_debug_field(spec[0], int(spec[1]), 1)
		var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
		var path := target.path_join("seed%d-%s.png" % [seed_value, name])
		image.save_png(path)
		print("v5_detail seed=%d frame=%s size=%dx%d path=%s" % [seed_value, name, int(page.width), int(page.height), path])
	var topology_area := Rect2i(int(AWAY / 64.0) - 8, -1, 16, 14)
	world.request_chunk_region(topology_area, 1)
	world.flush_generation()
	print("v5_topology seed=%d %s" % [seed_value, JSON.stringify(world.get_cave_topology_report(topology_area))])
	print("v5_start seed=%d %s" % [seed_value, JSON.stringify(world.get_worldgen_v5_start_report())])
	print("v5_cell seed=%d %s" % [seed_value, JSON.stringify(world.get_worldgen_v5_cell(Vector2i(AWAY, 420)))])
