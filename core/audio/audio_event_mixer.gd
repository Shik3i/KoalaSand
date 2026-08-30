class_name AudioEventMixer
extends Node

const CATEGORIES := ["Master", "UI", "Character", "Environment", "Machines", "Music"]
const MAX_UI_VOICES := 6
const MAX_WORLD_ONESHOTS := 12
const MAX_AGGREGATED_LOOPS := 8
const DEFAULT_BUS_DB := {"UI":-9.0, "Character":-10.0, "Environment":-14.0, "Machines":-16.0, "Music":-18.0}
const EVENT_MATRIX := [
	["hover", "UI", false, false, "pointer focus", 1, 1], ["click", "UI", false, false, "activation", 3, 2], ["confirm", "UI", false, false, "accepted action", 5, 2], ["cancel", "UI", false, false, "cancelled action", 4, 2], ["invalid", "UI", false, false, "rejection", 8, 2], ["place", "UI", false, false, "placed Components", 6, 3], ["remove", "UI", false, false, "removed Components", 6, 3], ["rotate", "UI", false, false, "orientation", 4, 2], ["undo", "UI", false, false, "history action", 6, 2], ["redo", "UI", false, false, "history action", 6, 2], ["research_unlock", "UI", false, false, "authoritative unlock", 9, 1], ["milestone_complete", "UI", false, false, "authoritative milestone", 10, 1], ["save_complete", "UI", false, false, "atomic save result", 8, 1], ["save_error", "UI", false, false, "save failure", 10, 1],
	["dig", "Character", false, true, "removed material", 7, 4], ["cut", "Character", false, true, "Wood cut", 7, 4], ["tree_crack", "Environment", false, true, "fall progress", 8, 3], ["tree_impact", "Environment", false, true, "physical impact", 9, 3], ["jetpack", "Character", true, true, "actual thrust", 7, 1], ["hover_active", "Character", true, true, "actual Hover state", 5, 1], ["igniter", "Character", false, true, "accepted ignition", 7, 3], ["splash", "Environment", false, true, "Water contact", 5, 4],
	["sand", "Environment", true, true, "cells moved", 2, 1], ["water", "Environment", true, true, "flow/transfers", 4, 2], ["steam", "Environment", true, true, "release/pressure", 7, 2], ["fire", "Environment", true, true, "combustion intensity", 6, 2], ["conveyor", "Machines", true, true, "belt moves/load", 3, 2], ["vibration", "Machines", true, true, "actual vibration", 5, 1], ["pump", "Machines", true, true, "actual flow/load", 6, 2], ["turbine", "Machines", true, true, "real RPM/load", 8, 1], ["generator", "Machines", true, true, "electrical load", 7, 1],
]

var requested_voices := 0
var actual_voices := 0
var aggregated_loops := 0
var dropped_low_priority := 0
var last_mix_ms := 0.0
var _ui_players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer2D] = []
var _loop_players: Array[AudioStreamPlayer2D] = []
var _streams: Dictionary = {}
var _loop_assignments: Dictionary = {}
var _planning_paused := false
var _presentation_counter := 0

func _ready() -> void:
	_ensure_buses()
	# Build the tiny procedural loop set once at mixer creation, outside gameplay
	# aggregation timing. No file I/O and no per-Component players.
	for record: Array in EVENT_MATRIX:
		if bool(record[2]): _stream(StringName(record[0]), true)
	for _index in MAX_UI_VOICES:
		var player := AudioStreamPlayer.new(); player.bus = "UI"; add_child(player); _ui_players.append(player)
	for _index in MAX_WORLD_ONESHOTS:
		var player := AudioStreamPlayer2D.new(); player.bus = "Environment"; player.max_distance = 1800.0; player.attenuation = 1.35; add_child(player); _world_players.append(player)
	for _index in MAX_AGGREGATED_LOOPS:
		var player := AudioStreamPlayer2D.new(); player.bus = "Machines"; player.max_distance = 2200.0; player.attenuation = 1.1; add_child(player); _loop_players.append(player)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	# Audio playback keeps a reference to its stream until explicitly detached.
	# Release every pooled voice before AudioServer teardown so benchmark exits,
	# scene changes, and packaged shutdowns do not retain procedural resources.
	for player in _ui_players:
		player.stop()
		player.stream = null
	for player in _world_players:
		player.stop()
		player.stream = null
	for player in _loop_players:
		player.stop()
		player.stream = null
	_streams.clear()
	_loop_assignments.clear()

func set_category_volumes(values: Dictionary) -> void:
	for category in CATEGORIES:
		var linear := clampf(float(values.get(category.to_lower(), values.get(category, 1.0))), 0.0, 1.0)
		var index := AudioServer.get_bus_index(category)
		if index >= 0:
			var headroom := 0.0 if category == "Master" else float(DEFAULT_BUS_DB.get(category, -12.0))
			AudioServer.set_bus_volume_db(index, headroom + linear_to_db(maxf(linear, 0.0001)))

func play_ui(event_id: StringName, intensity := 1.0) -> bool:
	requested_voices += 1
	for player in _ui_players:
		if not player.playing:
			_presentation_counter += 1; player.stream = _stream(event_id, false); player.volume_db = linear_to_db(clampf(intensity, 0.02, 1.0)) - 11.0; player.pitch_scale = _variation(event_id, _presentation_counter, 0.025); player.play(); actual_voices += 1; return true
	dropped_low_priority += 1; return false

func play_world(event_id: StringName, world_position: Vector2, intensity := 1.0, category := "Environment") -> bool:
	requested_voices += 1
	for player in _world_players:
		if not player.playing:
			_presentation_counter += 1; player.bus = category; player.position = world_position; player.stream = _stream(event_id, false); player.volume_db = linear_to_db(clampf(intensity, 0.02, 1.0)) - 12.0; player.pitch_scale = _variation(event_id, _presentation_counter, 0.04); player.play(); actual_voices += 1; return true
	dropped_low_priority += 1; return false

func update_aggregated_loops(sources: Array[Dictionary], camera_position: Vector2, zoom: float) -> void:
	var started := Time.get_ticks_usec(); requested_voices += sources.size(); var grouped: Dictionary = {}
	for source: Dictionary in sources:
		var intensity := clampf(float(source.get("intensity", 0.0)), 0.0, 1.0)
		if intensity <= 0.01: continue
		var event_id := str(source.get("event", "")); var position := Vector2(source.get("position", Vector2.ZERO)); var distance := camera_position.distance_to(position); var relevance := intensity / maxf(1.0, distance / 320.0) / maxf(1.0, zoom * 0.55)
		var key := "%s:%d:%d" % [event_id, floori(position.x / 640.0), floori(position.y / 640.0)]
		if not grouped.has(key): grouped[key] = {"event":event_id, "position":position, "intensity":0.0, "weight":0.0, "relevance":0.0, "parameter":0.0, "category":str(source.get("category", "Machines"))}
		var aggregate: Dictionary = grouped[key]; aggregate.position = (Vector2(aggregate.position) * float(aggregate.weight) + position * intensity) / maxf(0.001, float(aggregate.weight) + intensity); aggregate.weight = float(aggregate.weight) + intensity; aggregate.intensity = minf(1.0, float(aggregate.intensity) + intensity * 0.22); aggregate.relevance = maxf(float(aggregate.relevance), relevance); aggregate.parameter = maxf(float(aggregate.parameter), float(source.get("parameter", intensity))); grouped[key] = aggregate
	var candidates: Array[Dictionary] = []; for key: String in grouped: var item: Dictionary = grouped[key]; item["key"] = key; candidates.append(item)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.relevance) > float(b.relevance))
	if candidates.size() > MAX_AGGREGATED_LOOPS: dropped_low_priority += candidates.size() - MAX_AGGREGATED_LOOPS; candidates.resize(MAX_AGGREGATED_LOOPS)
	var keep: Dictionary = {}; aggregated_loops = candidates.size(); actual_voices = 0
	for index in candidates.size():
		var item := candidates[index]; var player := _loop_players[index]; var key := str(item.key); keep[key] = true
		var target_db := linear_to_db(maxf(0.001, float(item.intensity))) - 18.0 + (-24.0 if _planning_paused else 0.0)
		var is_new := str(_loop_assignments.get(index, "")) != key or not player.playing
		player.bus = str(item.category); player.position = Vector2(item.position); player.pitch_scale = clampf(0.90 + float(item.parameter) * 0.18, 0.84, 1.12)
		if is_new:
			player.volume_db = -60.0
			player.stream = _stream(StringName(item.event), true)
			player.play()
			_loop_assignments[index] = key
		player.volume_db = lerpf(player.volume_db, target_db, 0.18)
		actual_voices += 1
	for index in range(candidates.size(), _loop_players.size()):
		# Muting a loop gradually avoids a discontinuity at the AudioServer mix
		# boundary. The bounded pool may keep inaudible streams alive.
		if _loop_players[index].playing: _loop_players[index].volume_db = lerpf(_loop_players[index].volume_db, -60.0, 0.24)
		_loop_assignments.erase(index)
	last_mix_ms = float(Time.get_ticks_usec() - started) / 1000.0

func set_planning_paused(paused: bool) -> void:
	_planning_paused = paused
	for player in _loop_players:
		if player.playing:
			var target := -36.0 if paused else minf(player.volume_db + 24.0, -6.0)
			create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(player, "volume_db", target, 0.16)

func statistics() -> Dictionary:
	return {"requested_voices":requested_voices, "actual_voices":actual_voices, "aggregated_loops":aggregated_loops, "dropped_low_priority":dropped_low_priority, "audio_cpu_ms":last_mix_ms, "ui_pool":MAX_UI_VOICES, "world_pool":MAX_WORLD_ONESHOTS, "loop_pool":MAX_AGGREGATED_LOOPS}

static func event_matrix() -> Array:
	return EVENT_MATRIX.duplicate(true)

func _stream(event_id: StringName, looped: bool) -> AudioStreamWAV:
	var key := "%s:%s" % [event_id, str(looped)]
	if not _streams.has(key): _streams[key] = ProceduralSfx.build(event_id, looped)
	return _streams[key]

func _ensure_buses() -> void:
	for category in CATEGORIES:
		if AudioServer.get_bus_index(category) >= 0: continue
		AudioServer.add_bus(); AudioServer.set_bus_name(AudioServer.bus_count - 1, category)
		if category != "Master": AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for category: String in DEFAULT_BUS_DB:
		var index := AudioServer.get_bus_index(category)
		if index >= 0: AudioServer.set_bus_volume_db(index, float(DEFAULT_BUS_DB[category]))

func _variation(event_id: StringName, ordinal: int, amount: float) -> float:
	var hash := int(str(event_id).hash()) ^ (ordinal * 1103515245)
	var unit := float(abs(hash) % 1000) / 999.0
	return 1.0 + (unit * 2.0 - 1.0) * amount
