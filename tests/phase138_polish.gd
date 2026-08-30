extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _run() -> void:
	_check(BuildInfo.VERSION == "0.1.0-playtest.3", "playtest.3 runtime version")
	_check(ProjectSettings.get_setting("application/config/version") == BuildInfo.VERSION, "project and runtime version agree")
	for path in ["res://PHASE138_POLISH.md", "res://scripts/capture_phase138.ps1", "res://scripts/create_phase138_contact_sheets.ps1"]:
		_check(FileAccess.file_exists(path), "%s exists" % path)
	var capture_script := FileAccess.get_file_as_string("res://scripts/capture_phase138.ps1")
	for name in ["main-menu", "new-game", "character", "character-jetpack", "character-hover", "character-cave", "character-factory", "factory", "factory-powered", "creative", "quickbar", "build-catalog", "build-ghost", "components", "research", "codex-material", "codex-component", "inspector-screen", "inspector-sluice", "inspector-furnace", "inspector-power", "blueprints", "custom-blueprint", "current-goal", "experiments", "map-character", "overview-factory", "temperature-overlay", "production-overlay", "power-overlay", "planning-pause", "tree", "fire", "water", "steam", "save-browser", "settings", "pause", "full-game-character", "full-game-factory", "realistic-max-factory"]:
		_check(capture_script.contains("'%s'=" % name), "capture contract includes %s" % name)
	_check(capture_script.contains("-MuteAudio"), "capture pipeline is explicitly silent")
	var wrapper := FileAccess.get_file_as_string("res://scripts/godot.ps1")
	_check(wrapper.contains("--audio-driver") and wrapper.contains("Dummy"), "Godot wrapper supports Dummy audio")
	for bus: String in AudioEventMixer.DEFAULT_BUS_DB:
		_check(float(AudioEventMixer.DEFAULT_BUS_DB[bus]) <= -9.0, "%s retains safe headroom" % bus)
	_check(ProceduralSfx.SAMPLE_RATE == 32000, "procedural audio sample rate bounded")
	var stream := ProceduralSfx.build(&"furnace", true)
	_check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "procedural loops use 16-bit PCM")
	var panel := PanelContainer.new()
	root.add_child(panel)
	KoalaSandTheme.reduced_motion = true
	KoalaSandTheme.show_panel(panel, true)
	_check(panel.visible and is_equal_approx(panel.modulate.a, 1.0), "reduced-motion panel appears immediately")
	var close_state := [false]
	KoalaSandTheme.hide_panel(panel, func() -> void: close_state[0] = true)
	_check(not panel.visible and bool(close_state[0]), "reduced-motion panel closes immediately")
	KoalaSandTheme.reduced_motion = false
	KoalaSandTheme.show_panel(panel, true)
	await create_timer(KoalaSandTheme.MOTION_EMPHASIS + 0.04).timeout
	var animated_close_state := [false]
	KoalaSandTheme.hide_panel(panel, func() -> void: animated_close_state[0] = true)
	await create_timer(KoalaSandTheme.MOTION_FAST + 0.04).timeout
	_check(not panel.visible and bool(animated_close_state[0]), "animated panel closes and invokes completion")
	_check(panel.scale == Vector2.ONE and is_equal_approx(panel.modulate.a, 1.0), "animated panel resets reusable visual state")
	panel.queue_free()
	if failures.is_empty():
		print("PASS: %d Phase 13.8 player-experience polish checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("PHASE138: " + failure)
		print("FAIL: %d of %d Phase 13.8 checks" % [failures.size(), checks])
		quit(1)
