extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _run() -> void:
	_check(BuildInfo.VERSION == "0.1.0-playtest.4", "playtest.4 runtime version")
	_check(ProjectSettings.get_setting("application/config/version") == BuildInfo.VERSION, "project and runtime version agree")
	for path in ["res://DESIGN_SYSTEM.md", "res://PHASE136_POLISH.md", "res://OWNER_FIRST_PLAYTEST.md", "res://scripts/capture_phase136.ps1", "res://scripts/create_phase136_contact_sheets.ps1"]:
		_check(FileAccess.file_exists(path), "%s exists" % path)
	for color in [KoalaSandTheme.COLOR_PANEL, KoalaSandTheme.COLOR_PANEL_ELEVATED, KoalaSandTheme.COLOR_ACCENT, KoalaSandTheme.COLOR_WARNING, KoalaSandTheme.COLOR_DANGER, KoalaSandTheme.COLOR_SUCCESS, KoalaSandTheme.COLOR_INFO, KoalaSandTheme.COLOR_STATE_UNKNOWN, KoalaSandTheme.COLOR_STATE_STALE, KoalaSandTheme.COLOR_STATE_LIVE]:
		_check(color.a > 0.0, "canonical semantic color is visible")
	_check(KoalaSandTheme.SPACE_1 < KoalaSandTheme.SPACE_2 and KoalaSandTheme.SPACE_2 < KoalaSandTheme.SPACE_4, "spacing scale ordered")
	_check(KoalaSandTheme.RADIUS_SMALL < KoalaSandTheme.RADIUS_LARGE, "radius scale ordered")
	_check(KoalaSandTheme.ICON_SMALL < KoalaSandTheme.ICON_MEDIUM and KoalaSandTheme.ICON_MEDIUM < KoalaSandTheme.ICON_LARGE, "icon scale ordered")
	_check(KoalaSandTheme.MOTION_FAST >= 0.08 and KoalaSandTheme.MOTION_EMPHASIS <= 0.18, "motion stays in 80-180 ms contract")
	for scale in [1.0, 1.25, 1.5]:
		var theme := KoalaSandTheme.build(scale)
		for variation in ["HudPanel", "ElevatedPanel", "ModalPanel", "PrimaryButton", "QuietButton", "DisplayLabel", "ScreenTitleLabel", "SectionTitleLabel", "NumericLabel"]:
			_check(not theme.get_type_variation_base(variation).is_empty(), "%s exists at %.0f%% UI scale" % [variation, scale * 100.0])
	var mixer := AudioEventMixer.new()
	root.add_child(mixer)
	await process_frame
	_check(AudioEventMixer.event_matrix().size() >= 30, "audio event coverage retained")
	_check(mixer.get_child_count() == AudioEventMixer.MAX_UI_VOICES + AudioEventMixer.MAX_WORLD_ONESHOTS + AudioEventMixer.MAX_AGGREGATED_LOOPS, "audio pools remain bounded")
	var loop_stream := ProceduralSfx.build(&"conveyor", true)
	_check(loop_stream.format == AudioStreamWAV.FORMAT_16_BITS, "procedural audio uses 16-bit PCM")
	_check(loop_stream.mix_rate == ProceduralSfx.SAMPLE_RATE, "procedural audio uses canonical sample rate")
	_check(loop_stream.loop_end * 2 == loop_stream.data.size(), "loop bounds cover complete 16-bit sample data")
	var first_sample := int(loop_stream.data[0]) | (int(loop_stream.data[1]) << 8)
	var last_offset := loop_stream.data.size() - 2
	var last_sample := int(loop_stream.data[last_offset]) | (int(loop_stream.data[last_offset + 1]) << 8)
	if first_sample >= 32768: first_sample -= 65536
	if last_sample >= 32768: last_sample -= 65536
	_check(absi(first_sample - last_sample) < 2048, "procedural loop seam has no audible discontinuity")
	mixer.queue_free()
	if failures.is_empty():
		print("PASS: %d Phase 13.6 polish correctness checks" % checks)
		quit(0)
	else:
		for failure in failures: push_error("PHASE136: " + failure)
		print("FAIL: %d of %d Phase 13.6 checks" % [failures.size(), checks])
		quit(1)
