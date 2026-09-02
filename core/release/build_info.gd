class_name BuildInfo
extends RefCounted

const VERSION := "0.1.0-playtest.5"
const SAVE_SCHEMA := 1
const GENERATION_VERSION := 5

static func current() -> Dictionary:
	var manifest := {"version":VERSION, "build_id":"development", "source_manifest_sha256":"development", "build_timestamp_utc":"unpackaged"}
	if FileAccess.file_exists("res://BUILD_MANIFEST.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://BUILD_MANIFEST.json"))
		if parsed is Dictionary:
			manifest.merge(parsed, true)
	# The source constant is authoritative during development and after an
	# upgrade; a stale packaged manifest may supply build metadata, never an old
	# player-visible version.
	manifest.version = VERSION
	return manifest

static func display() -> String:
	var info := current()
	return "%s · %s" % [str(info.version), str(info.build_id)]
