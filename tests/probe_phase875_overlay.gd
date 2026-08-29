extends SceneTree

func _initialize() -> void:
	var world := NativeSandWorld.new()
	world.reset(1, 1)
	world.set_game_mode(1)
	world.allocate_chunk_rect(Rect2i(-4, -4, 8, 8))
	var id := world.place_subsurface_channel(0, Vector2i(-130, 30), Vector2i(-65, 30))
	var renderer := MapOverlayRenderer.new()
	root.add_child(renderer)
	renderer.initialize(world)
	renderer.set_mode(MapOverlayRenderer.Mode.UNDERGROUND_LOGISTICS)
	renderer.sync_visible(Rect2i(-5, -2, 7, 4))
	print("overlay_probe id=%d mode=%d routes=%d direct=%d" % [id, renderer.mode, renderer._routes.size(), world.get_visible_subsurface_routes(Rect2i(-320, -128, 448, 256)).size()])
	quit(0 if renderer._routes.size() == 10 else 1)
