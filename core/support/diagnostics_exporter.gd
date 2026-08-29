class_name DiagnosticsExporter
extends RefCounted

const ARCHIVE_PREFIX := "KoalaSand-diagnostics-"

var output_root := "user://diagnostics"

func _init(root := "user://diagnostics") -> void:
	output_root = root.trim_suffix("/")

func export_report(world: Variant, settings: Dictionary, performance: Dictionary, recent_errors: Array[String] = [], latest_log_path := "user://logs/godot.log") -> Dictionary:
	var report_id := _report_id()
	var stamp := Time.get_datetime_string_from_system(false, true).replace("-", "").replace(":", "").replace("T", "-")
	var filename := "%s%s.zip" % [ARCHIVE_PREFIX, stamp]
	var absolute_root := ProjectSettings.globalize_path(output_root)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_root)
	if mkdir_error != OK: return {"ok":false, "error":"CREATE_DIAGNOSTICS_DIRECTORY_FAILED", "code":mkdir_error}
	var path := output_root + "/" + filename
	var packer := ZIPPacker.new(); var open_error := packer.open(ProjectSettings.globalize_path(path))
	if open_error != OK: return {"ok":false, "error":"OPEN_DIAGNOSTICS_ZIP_FAILED", "code":open_error}
	var identity: Dictionary = world.get_world_identity() if world != null and world.has_method("get_world_identity") else {}
	var build := BuildInfo.current(); var memory := OS.get_memory_info()
	var diagnostics := {
		"report_id":report_id,
		"koalasand_version":build.version,
		"build_id":build.build_id,
		"godot_version":Engine.get_version_info().get("string", "unknown"),
		"os":OS.get_name(),
		"os_distribution":OS.get_distribution_name(),
		"cpu":OS.get_processor_name(),
		"logical_cores":OS.get_processor_count(),
		"gpu":RenderingServer.get_video_adapter_name(),
		"ram_physical_bytes":int(memory.get("physical", 0)),
		"renderer":RenderingServer.get_current_rendering_method(),
		"world_seed":int(identity.get("seed", 0)),
		"game_mode":int(world.get_game_mode()) if world != null and world.has_method("get_game_mode") else -1,
		"save_schema":BuildInfo.SAVE_SCHEMA,
		"generation_version":int(identity.get("generation_version", BuildInfo.GENERATION_VERSION)),
		"settings":_safe_settings(settings),
		"performance":performance.duplicate(true),
		"mods":[],
		"telemetry":false,
	}
	_write_entry(packer, "diagnostics.json", JSON.stringify(diagnostics, "  ") + "\n")
	_write_entry(packer, "recent-errors.txt", "\n".join(recent_errors.map(func(value: String) -> String: return _redact(value))) + "\n")
	_write_entry(packer, "performance.json", JSON.stringify(performance, "  ") + "\n")
	_write_entry(packer, "README.txt", "KoalaSand local diagnostics\nReport ID: %s\nNo telemetry or automatic upload. Review files before sharing.\n" % report_id)
	if FileAccess.file_exists(latest_log_path): _write_entry(packer, "latest-application.log", _redact(FileAccess.get_file_as_string(latest_log_path)).right(262144))
	packer.close()
	return {"ok":true, "path":path, "absolute_path":ProjectSettings.globalize_path(path), "filename":filename, "report_id":report_id, "contents":["diagnostics.json","recent-errors.txt","performance.json","README.txt"] + (["latest-application.log"] if FileAccess.file_exists(latest_log_path) else [])}

func _write_entry(packer: ZIPPacker, name: String, text: String) -> void:
	packer.start_file(name); packer.write_file(text.to_utf8_buffer()); packer.close_file()

func _safe_settings(settings: Dictionary) -> Dictionary:
	var allowed := ["autosave_minutes","ui_scale","reduced_motion","screen_shake","window_mode","master","ui","character","environment","machines","music","hover_toggle"]
	var result := {}
	for key in allowed:
		if settings.has(key): result[key] = settings[key]
	return result

func _redact(text: String) -> String:
	var normalized := text.replace("\\", "/")
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if not home.is_empty(): normalized = normalized.replace(home, "<USER_HOME>")
	return normalized

func _report_id() -> String:
	var random := Crypto.new().generate_random_bytes(12)
	return random.hex_encode()
