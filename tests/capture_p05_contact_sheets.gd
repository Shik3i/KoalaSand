extends SceneTree

const SEEDS := [3,41,2965,8191,15508,18076,33191,45613,71317,99173,120011,144013,177019,233021,377029,610031,987037,1597043,2584081,8675309]
const TILE := Vector2i(300,180)
const GRID := Vector2i(5,4)
const GUTTER := 6

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var target := ProjectSettings.globalize_path("res://artifacts/p05-world-quality/contact-sheets")
	DirAccess.make_dir_recursive_absolute(target)
	for category in ["surface-shallow","underground-caves","water-aquifers","start-regions"]:
		var sheet := Image.create_empty(GRID.x * TILE.x + (GRID.x + 1) * GUTTER,GRID.y * TILE.y + (GRID.y + 1) * GUTTER,false,Image.FORMAT_RGBA8)
		sheet.fill(Color("081117"))
		for index in SEEDS.size():
			var tile := _render_tile(SEEDS[index],category)
			var destination := Vector2i(GUTTER + (index % GRID.x) * (TILE.x + GUTTER),GUTTER + (index / GRID.x) * (TILE.y + GUTTER))
			sheet.blit_rect(tile,Rect2i(Vector2i.ZERO,TILE),destination)
		var output := target.path_join("%s-20-seeds.png" % category)
		var error := sheet.save_png(output)
		print("p05_contact_sheet category=%s seeds=%d path=%s error=%s" % [category,SEEDS.size(),output,error_string(error)])
	var manifest := FileAccess.open(target.path_join("manifest.json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"generation_version":4,"seeds":SEEDS,"viewport":TILE,"grid":GRID,"categories":["surface-shallow","underground-caves","water-aquifers","start-regions"]},"  "))
	manifest.close(); print("PASS: P0.5 contact sheets"); quit(0)

func _render_tile(seed: int, category: String) -> Image:
	var world := NativeSandWorld.new(); world.configure_world({"seed":seed,"generation_version":4},6)
	var center := Vector2i.ZERO
	if category == "underground-caves": center = _descriptor_center(world,false)
	elif category == "water-aquifers": center = _descriptor_center(world,true)
	var center_chunk := Vector2i(floori(center.x / 64.0),floori(center.y / 64.0))
	var area := Rect2i(center_chunk - Vector2i(3,2),Vector2i(6,4))
	world.request_chunk_region(area,1); world.flush_generation()
	var page: Dictionary = world.consume_dirty_render_page(area,true)
	var base := Image.create_empty(int(page.width),int(page.height),false,Image.FORMAT_RGBA8); base.fill(Color("10232b") if category in ["surface-shallow","start-regions"] else Color("17252a"))
	var material := Image.create_from_data(int(page.width),int(page.height),false,Image.FORMAT_RGBA8,page.pixels)
	base.blend_rect(material,Rect2i(Vector2i.ZERO,material.get_size()),Vector2i.ZERO)
	var fluid: Dictionary = world.get_fluid_render_page(area)
	if not fluid.is_empty():
		var mass: PackedByteArray = fluid.pixels
		for y in int(fluid.height):
			for x in int(fluid.width):
				var amount := mass[y * int(fluid.width) + x]
				if amount > 0:
					var depth := float(amount) / 255.0
					base.set_pixel(x,y,Color(0.05,0.48 + depth * 0.24,0.68 + depth * 0.18,1.0))
	if category == "start-regions":
		var marker := Vector2i(base.get_width()/2,base.get_height()/2)
		for d in range(-5,6):
			if marker.x + d >= 0 and marker.x + d < base.get_width(): base.set_pixel(marker.x + d,marker.y,Color("ffc65a"))
			if marker.y + d >= 0 and marker.y + d < base.get_height(): base.set_pixel(marker.x,marker.y + d,Color("ffc65a"))
	base.resize(TILE.x,TILE.y,Image.INTERPOLATE_NEAREST)
	return base

func _descriptor_center(world: Variant, water: bool) -> Vector2i:
	var sample: Dictionary = world.get_worldgen_debug_sample(Rect2i(-1536,64,3072,1536),8)
	var records: PackedInt32Array = sample.records; var stride := int(sample.record_stride)
	for index in range(0,records.size(),stride):
		var cave := int(records[index + 3]); var aquifer := bool(records[index + 4]); var depth := int(records[index + 2])
		if cave > 0 and depth > 120 and aquifer == water: return Vector2i(records[index],records[index + 1])
	return Vector2i(0,420 if not water else 620)
