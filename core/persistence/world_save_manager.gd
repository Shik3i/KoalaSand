class_name WorldSaveManager
extends RefCounted

const FILE_MAGIC := "KOALASAND_SAVE"
const SAVE_SCHEMA_VERSION := 1
const GAME_VERSION := BuildInfo.VERSION
const SAVE_EXTENSION := ".ksave"
const MAX_SAVE_BYTES := 256 * 1024 * 1024
const MAX_WORLD_NAME_LENGTH := 128
const RESERVED_WINDOWS_STEMS := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]

var save_root := "user://saves"
var last_capture_usec := 0
var last_write_usec := 0
var last_load_usec := 0
var _async_thread: Thread
var _async_started_usec := 0
var _io_mutex := Mutex.new()


func _init(root := "user://saves") -> void:
	save_root = root.trim_suffix("/")


func save_world(world_name: String, native_world: Variant, context: Dictionary = {}) -> Dictionary:
	var capture_started := Time.get_ticks_usec()
	var payload := _capture_payload(world_name, native_world, context)
	last_capture_usec = Time.get_ticks_usec() - capture_started
	if payload.is_empty():
		return {"ok": false, "error": "CAPTURE_FAILED"}
	var write_started := Time.get_ticks_usec()
	var result := _write_payload_atomic(world_name, payload)
	last_write_usec = Time.get_ticks_usec() - write_started
	result["capture_usec"] = last_capture_usec
	result["write_usec"] = last_write_usec
	return result


func save_world_async(world_name: String, native_world: Variant, context: Dictionary = {}) -> Dictionary:
	if _async_thread != null:
		return {"ok": false, "error": "SAVE_ALREADY_RUNNING"}
	var capture_started := Time.get_ticks_usec()
	var payload := _capture_payload(world_name, native_world, context)
	last_capture_usec = Time.get_ticks_usec() - capture_started
	if payload.is_empty():
		return {"ok": false, "error": "CAPTURE_FAILED"}
	_async_thread = Thread.new()
	_async_started_usec = Time.get_ticks_usec()
	var start_error := _async_thread.start(_write_payload_atomic.bind(world_name, payload))
	if start_error != OK:
		_async_thread = null
		return {"ok": false, "error": "THREAD_START_FAILED", "code": start_error}
	return {"ok": true, "pending": true, "capture_usec": last_capture_usec}


func poll_async_save() -> Dictionary:
	if _async_thread == null:
		return {"pending": false}
	if _async_thread.is_alive():
		return {"pending": true}
	var result: Dictionary = _async_thread.wait_to_finish()
	last_write_usec = Time.get_ticks_usec() - _async_started_usec
	_async_thread = null
	result["pending"] = false
	result["write_usec"] = last_write_usec
	return result


func finish_async_save() -> Dictionary:
	if _async_thread == null:
		return {"ok": true, "pending": false}
	var result: Dictionary = _async_thread.wait_to_finish()
	last_write_usec = Time.get_ticks_usec() - _async_started_usec
	_async_thread = null
	result["pending"] = false
	result["write_usec"] = last_write_usec
	return result


func load_world(world_name: String) -> Dictionary:
	finish_async_save()
	_io_mutex.lock()
	var started := Time.get_ticks_usec()
	var primary := _read_envelope(_save_path(world_name))
	if not bool(primary.get("ok", false)):
		var backup := _read_envelope(_backup_path(world_name))
		if not bool(backup.get("ok", false)):
			_io_mutex.unlock()
			return {"ok": false, "error": str(primary.get("error", "SAVE_NOT_FOUND")), "backup_error": str(backup.get("error", "BACKUP_NOT_FOUND"))}
		primary = backup
		primary["recovered_from_backup"] = true
	var payload: Dictionary = primary.payload
	payload = _migrate_payload(payload)
	if payload.is_empty():
		_io_mutex.unlock()
		return {"ok": false, "error": "UNSUPPORTED_SAVE_SCHEMA"}
	last_load_usec = Time.get_ticks_usec() - started
	_io_mutex.unlock()
	return {"ok": true, "payload": payload, "metadata": payload.metadata, "recovered_from_backup": bool(primary.get("recovered_from_backup", false)), "load_usec": last_load_usec}


func restore_world(world_name: String, native_world: Variant) -> Dictionary:
	var loaded := load_world(world_name)
	if not bool(loaded.get("ok", false)):
		return loaded
	var payload: Dictionary = loaded.payload
	var validation_world := NativeSandWorld.new()
	if not validation_world.deserialize_world_snapshot(payload.world):
		return {"ok": false, "error": "WORLD_SNAPSHOT_VALIDATION_FAILED"}
	if not native_world.deserialize_world_snapshot(payload.world):
		return {"ok": false, "error": "WORLD_DESERIALIZE_FAILED"}
	loaded["context"] = Dictionary(payload.get("context", {})).duplicate(true)
	return loaded


func list_worlds() -> Array[Dictionary]:
	finish_async_save()
	var result: Array[Dictionary] = []
	var absolute_root := ProjectSettings.globalize_path(save_root)
	var directory := DirAccess.open(absolute_root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(SAVE_EXTENSION):
			var entry := _read_envelope(save_root + "/" + file_name)
			if bool(entry.get("ok", false)):
				var metadata: Dictionary = Dictionary(entry.payload.get("metadata", {})).duplicate(true)
				metadata["file_name"] = file_name
				result.append(metadata)
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("timestamp_unix", 0)) > int(b.get("timestamp_unix", 0)))
	return result


func inspect_worlds() -> Array[Dictionary]:
	finish_async_save()
	var result: Array[Dictionary] = []
	var absolute_root := ProjectSettings.globalize_path(save_root)
	var directory := DirAccess.open(absolute_root)
	if directory == null:
		return result
	var stems: Dictionary = {}
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(SAVE_EXTENSION) or file_name.ends_with(SAVE_EXTENSION + ".bak")):
			var stem := file_name.trim_suffix(".bak").trim_suffix(SAVE_EXTENSION)
			stems[stem] = true
		file_name = directory.get_next()
	directory.list_dir_end()
	for stem: String in stems:
		var primary := _read_envelope(save_root + "/" + stem + SAVE_EXTENSION)
		var backup := _read_envelope(save_root + "/" + stem + SAVE_EXTENSION + ".bak")
		var source: Dictionary = primary if bool(primary.get("ok", false)) else backup
		var metadata: Dictionary = Dictionary(source.get("payload", {}).get("metadata", {})).duplicate(true) if bool(source.get("ok", false)) else {"world_name":stem.replace("_", " ")}
		metadata["primary_valid"] = bool(primary.get("ok", false))
		metadata["backup_valid"] = bool(backup.get("ok", false))
		metadata["recoverable"] = not bool(primary.get("ok", false)) and bool(backup.get("ok", false))
		metadata["primary_error"] = str(primary.get("error", ""))
		metadata["backup_error"] = str(backup.get("error", ""))
		metadata["file_stem"] = stem
		result.append(metadata)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("timestamp_unix", 0)) > int(b.get("timestamp_unix", 0)))
	return result


func restore_backup(world_name: String) -> Dictionary:
	finish_async_save()
	var backup := _read_envelope(_backup_path(world_name))
	if not bool(backup.get("ok", false)):
		return {"ok":false, "error":str(backup.get("error", "BACKUP_NOT_FOUND"))}
	var payload: Dictionary = _migrate_payload(Dictionary(backup.payload))
	if payload.is_empty():
		return {"ok":false, "error":"UNSUPPORTED_SAVE_SCHEMA"}
	var result := _write_payload_atomic(world_name, payload)
	result["restored_backup"] = bool(result.get("ok", false))
	return result


func delete_world(world_name: String, confirmed: bool) -> Dictionary:
	if not confirmed:
		return {"ok": false, "error": "CONFIRMATION_REQUIRED"}
	finish_async_save()
	_io_mutex.lock()
	var removed := 0
	for path in [_save_path(world_name), _backup_path(world_name), _temporary_path(world_name)]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			var error := DirAccess.remove_absolute(absolute)
			if error != OK:
				_io_mutex.unlock()
				return {"ok": false, "error": "DELETE_FAILED", "code": error, "path": path}
			removed += 1
	_io_mutex.unlock()
	return {"ok": true, "removed_files": removed}


func rename_world(old_name: String, new_name: String) -> Dictionary:
	var loaded := load_world(old_name)
	if not bool(loaded.get("ok", false)):
		return loaded
	var payload: Dictionary = loaded.payload
	payload.metadata.world_name = new_name.strip_edges()
	var written := _write_payload_atomic(new_name, payload)
	if not bool(written.get("ok", false)):
		return written
	var deleted := delete_world(old_name, true)
	return {"ok": bool(deleted.get("ok", false)), "write": written, "delete": deleted}


func _capture_payload(world_name: String, native_world: Variant, context: Dictionary) -> Dictionary:
	if native_world == null or not native_world.has_method("serialize_world_snapshot") or world_name.strip_edges().is_empty() or world_name.length() > MAX_WORLD_NAME_LENGTH:
		return {}
	var identity: Dictionary = native_world.get_world_identity() if native_world.has_method("get_world_identity") else {}
	var metadata := {
		"world_name": world_name.strip_edges(),
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"playtime_seconds": int(context.get("playtime_seconds", 0)),
		"seed": int(identity.get("seed", context.get("seed", 0))),
		"generation_version": int(identity.get("generation_version", 0)),
		"mode": int(context.get("mode", 0)),
		"game_version": GAME_VERSION,
		"save_schema_version": SAVE_SCHEMA_VERSION,
	}
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"metadata": metadata,
		"world": native_world.serialize_world_snapshot(),
		"context": context.duplicate(true),
	}


func _write_payload_atomic(world_name: String, payload: Dictionary) -> Dictionary:
	_io_mutex.lock()
	var result := _write_payload_atomic_unlocked(world_name, payload)
	_io_mutex.unlock()
	return result


func _write_payload_atomic_unlocked(world_name: String, payload: Dictionary) -> Dictionary:
	var absolute_root := ProjectSettings.globalize_path(save_root)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_root)
	if mkdir_error != OK:
		return {"ok": false, "error": "CREATE_SAVE_DIRECTORY_FAILED", "code": mkdir_error}
	var payload_bytes := var_to_bytes(payload)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_SAVE_BYTES:
		return {"ok": false, "error": "SAVE_PAYLOAD_TOO_LARGE", "bytes": payload_bytes.size(), "maximum": MAX_SAVE_BYTES}
	var magic_bytes := FILE_MAGIC.to_utf8_buffer()
	var payload_hash := _hash(payload_bytes)
	var temporary := _temporary_path(world_name)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "OPEN_TEMPORARY_FAILED", "code": FileAccess.get_open_error()}
	file.store_32(magic_bytes.size())
	file.store_buffer(magic_bytes)
	file.store_32(SAVE_SCHEMA_VERSION)
	file.store_64(payload_bytes.size())
	file.store_buffer(payload_hash)
	file.store_buffer(payload_bytes)
	file.flush()
	var file_error := file.get_error()
	file.close()
	if file_error != OK:
		return {"ok": false, "error": "WRITE_FAILED", "code": file_error}
	var validation := _read_envelope(temporary)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "TEMPORARY_VALIDATION_FAILED", "detail": validation}
	var final_path := _save_path(world_name)
	var backup_path := _backup_path(world_name)
	var absolute_final := ProjectSettings.globalize_path(final_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	if FileAccess.file_exists(absolute_backup):
		var remove_error := DirAccess.remove_absolute(absolute_backup)
		if remove_error != OK:
			return {"ok": false, "error": "OLD_BACKUP_REMOVE_FAILED", "code": remove_error}
	if FileAccess.file_exists(absolute_final):
		var backup_error := DirAccess.rename_absolute(absolute_final, absolute_backup)
		if backup_error != OK:
			return {"ok": false, "error": "BACKUP_RENAME_FAILED", "code": backup_error}
	var replace_error := DirAccess.rename_absolute(absolute_temporary, absolute_final)
	if replace_error != OK:
		if FileAccess.file_exists(absolute_backup) and not FileAccess.file_exists(absolute_final):
			DirAccess.rename_absolute(absolute_backup, absolute_final)
		return {"ok": false, "error": "ATOMIC_REPLACE_FAILED", "code": replace_error}
	return {"ok": true, "path": final_path, "bytes": FileAccess.get_file_as_bytes(final_path).size(), "sha256": _sha256(payload_bytes)}


func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "SAVE_NOT_FOUND"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "OPEN_FAILED", "code": FileAccess.get_open_error()}
	var file_length := file.get_length()
	if file_length > MAX_SAVE_BYTES + 256:
		file.close()
		return {"ok": false, "error": "SAVE_FILE_TOO_LARGE"}
	if file_length < 4 + FILE_MAGIC.length() + 4 + 8 + 32:
		file.close()
		return {"ok": false, "error": "TRUNCATED_SAVE"}
	var magic_length := file.get_32()
	if magic_length < 1 or magic_length > 64 or file_length < 4 + magic_length + 4 + 8 + 32:
		file.close()
		return {"ok": false, "error": "INVALID_HEADER"}
	var magic := file.get_buffer(magic_length).get_string_from_utf8()
	var envelope_schema := file.get_32()
	var payload_length := file.get_64()
	var expected_hash := file.get_buffer(32)
	if magic != FILE_MAGIC or envelope_schema < 1 or envelope_schema > SAVE_SCHEMA_VERSION or payload_length <= 0 or payload_length > MAX_SAVE_BYTES or payload_length != file_length - file.get_position():
		file.close()
		return {"ok": false, "error": "INVALID_HEADER"}
	var payload_bytes := file.get_buffer(payload_length)
	var read_error := file.get_error()
	file.close()
	if read_error != OK or payload_bytes.size() != payload_length:
		return {"ok": false, "error": "READ_FAILED", "code": read_error}
	if _hash(payload_bytes) != expected_hash:
		return {"ok": false, "error": "CHECKSUM_MISMATCH"}
	var payload_value: Variant = bytes_to_var(payload_bytes)
	if not payload_value is Dictionary:
		return {"ok": false, "error": "INVALID_PAYLOAD"}
	var payload: Dictionary = payload_value
	if not payload.get("metadata", null) is Dictionary or not payload.get("world", null) is Dictionary or not payload.get("context", null) is Dictionary:
		return {"ok": false, "error": "INVALID_PAYLOAD_SHAPE"}
	return {"ok": true, "payload": payload_value}


func _migrate_payload(payload: Dictionary) -> Dictionary:
	var schema := int(payload.get("schema_version", 0))
	if schema == SAVE_SCHEMA_VERSION:
		return payload
	# Future migrations are chained here without mutating the only on-disk copy.
	return {}


func _sha256(bytes: PackedByteArray) -> String:
	return _hash(bytes).hex_encode()


func _hash(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


func _safe_stem(world_name: String) -> String:
	var source := world_name.strip_edges().left(MAX_WORLD_NAME_LENGTH)
	var stem := ""
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var code := character.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or character in ["-", "_"]:
			stem += character
		elif character == " ":
			stem += "_"
	if stem.is_empty():
		stem = "World-" + source.sha256_text().left(8)
	stem = stem.trim_suffix(".").trim_suffix(" ")
	if stem.to_upper() in RESERVED_WINDOWS_STEMS:
		stem = "_" + stem
	if stem != source.replace(" ", "_"):
		stem = stem.left(54) + "-" + source.sha256_text().left(8)
	return stem.left(64)


func _save_path(world_name: String) -> String:
	return save_root + "/" + _safe_stem(world_name) + SAVE_EXTENSION


func _backup_path(world_name: String) -> String:
	return _save_path(world_name) + ".bak"


func _temporary_path(world_name: String) -> String:
	return _save_path(world_name) + ".tmp"
