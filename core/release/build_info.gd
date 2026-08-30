class_name BuildInfo
extends RefCounted

const VERSION := "0.1.0-playtest.3"
const SAVE_SCHEMA := 1
const GENERATION_VERSION := 2

static func current() -> Dictionary:
	var manifest := {"version":VERSION, "build_id":"development", "source_manifest_sha256":"development", "build_timestamp_utc":"unpackaged"}
	if FileAccess.file_exists("res://BUILD_MANIFEST.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://BUILD_MANIFEST.json"))
		if parsed is Dictionary:
			manifest.merge(parsed, true)
	return manifest

static func display() -> String:
	var info := current()
	return "%s · %s" % [str(info.version), str(info.build_id)]
