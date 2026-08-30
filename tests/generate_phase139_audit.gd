extends SceneTree

func _initialize() -> void:
	var materials := MaterialRegistry.new()
	if materials.load_directory() != OK: quit(1); return
	var world := NativeSandWorld.new(); world.reset(139, 1)
	var blueprints := BlueprintLibrary.new(16); MvpExampleBlueprints.install(blueprints)
	var codex := PhysicsCodex.new(); codex.rebuild(materials, world, blueprints)
	var rows := PlayerFacingAudit.collect(materials, world, blueprints, codex)
	var error := PlayerFacingAudit.write_csv("res://artifacts/phase139/player-facing-audit.csv", rows)
	print("PHASE139_UX_AUDIT rows=%d error=%s" % [rows.size(), error_string(error)])
	quit(0 if error == OK else 1)
