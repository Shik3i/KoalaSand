class_name KoalaCharacterController
extends Node2D

signal discovery_updated
signal movement_state_changed

const SCHEMA_VERSION := 1
const VISIBILITY_OWNER_ID := 1
const BODY_SIZE := Vector2i(3, 6)
const INTERACTION_RANGE_CELLS := 18
const DIG_TIME_SECONDS := 0.35
const CUT_TIME_SECONDS := 0.25
const IGNITION_ENERGY := 24000000
const WALK_SPEED := 320
const SPRINT_SPEED := 500
const HOVER_SPEED := 180
const JUMP_IMPULSE := 520
const JUMP_BUFFER_TICKS := 5
const COYOTE_TICKS := 5
const JETPACK_ACCELERATION := 42
const JETPACK_MAX_ASCENT_SPEED := 680
const MAX_FALL_SPEED := 760
const VISIBILITY_RADIUS := 72
const SOLID_SHELL_DEPTH := 8
const MAX_CAMERA_OFFSET_CELLS := 52.0
const INPUT_LEFT := 1 << 0
const INPUT_RIGHT := 1 << 1
const INPUT_JUMP := 1 << 2
const INPUT_JETPACK := 1 << 3
const INPUT_SPRINT := 1 << 4
const INPUT_HOVER := 1 << 5
const MILLI := 1000

var world: Variant
var command_bus: WorldCommandBus
var follow_camera: Camera2D
var cell_pixel_size := 2.0
var position_milli := Vector2i.ZERO
var velocity_milli := Vector2i.ZERO
var jetpack_unlocked := true
var sprint_unlocked := false
var hover_unlocked := false
var hover_active := false
var hover_toggle := true
var reduced_motion := false
var jetpack_active := false
var debug_input_override := -1
var interaction_target := Vector2i.ZERO
var dig_progress := 0.0
enum Tool { DIG, CUT, IGNITER }
var active_tool: Tool = Tool.DIG
var last_collision_ms := 0.0
var last_visibility_ms := 0.0
var collision_queries := 0
var collision_cells_sampled := 0
var _last_visibility_cell := Vector2i(2147483647, 2147483647)
var _last_hover_pressed := false
var _last_jump_pressed := false
var _jump_buffer_remaining := 0
var _coyote_remaining := 0
var _camera_velocity_look := Vector2.ZERO
var simulation_paused := false


func initialize(next_world: Variant, camera: Camera2D, spawn_cell: Vector2i, pixels_per_cell := 2.0, next_command_bus: WorldCommandBus = null) -> void:
	world = next_world
	command_bus = next_command_bus if next_command_bus != null else WorldCommandBus.new()
	follow_camera = camera
	cell_pixel_size = pixels_per_cell
	position_milli = spawn_cell * MILLI
	velocity_milli = Vector2i.ZERO
	position = Vector2(spawn_cell) * cell_pixel_size
	interaction_target = spawn_cell
	_refresh_unlocks()
	_update_visibility(true)
	queue_redraw()


func apply_accessibility_preferences(preferences: CharacterAccessibilityPreferences) -> void:
	hover_toggle = preferences.hover_toggle
	reduced_motion = preferences.reduced_motion


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	if simulation_paused:
		jetpack_active = false
		return
	_refresh_unlocks()
	_simulate_tick(_read_input_mask() if debug_input_override < 0 else debug_input_override)
	_update_camera()
	_update_visibility(false)
	_update_tool_selection()
	_update_primary_tool(1.0 / 60.0)
	if Input.is_action_just_pressed(&"character_cut"):
		cut_immediate_for_test(interaction_target)
	if Input.is_action_just_pressed(&"ignite"):
		ignite_immediate_for_test(interaction_target)

func set_simulation_paused(paused: bool) -> void:
	simulation_paused = paused
	if paused:
		jetpack_active = false


func replay_step(input_mask: int, update_visibility := true) -> void:
	_simulate_tick(input_mask)
	if update_visibility:
		_update_visibility(false)


func _read_input_mask() -> int:
	var mask := 0
	if Input.is_action_pressed(&"move_left"): mask |= INPUT_LEFT
	if Input.is_action_pressed(&"move_right"): mask |= INPUT_RIGHT
	if Input.is_action_pressed(&"jump"): mask |= INPUT_JUMP
	if Input.is_action_pressed(&"jetpack"): mask |= INPUT_JETPACK
	if Input.is_action_pressed(&"sprint"): mask |= INPUT_SPRINT
	if Input.is_action_pressed(&"hover"): mask |= INPUT_HOVER
	return mask


func _simulate_tick(mask: int) -> void:
	var horizontal := int(bool(mask & INPUT_RIGHT)) - int(bool(mask & INPUT_LEFT))
	var sprinting := sprint_unlocked and bool(mask & INPUT_SPRINT) and horizontal != 0
	var ground_speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var on_ground := _body_blocked(position_milli + Vector2i(0, MILLI))
	var jetting := jetpack_unlocked and bool(mask & INPUT_JETPACK)
	jetpack_active = jetting
	var jump_pressed := bool(mask & INPUT_JUMP)
	if jump_pressed and not _last_jump_pressed:
		_jump_buffer_remaining = JUMP_BUFFER_TICKS
	_last_jump_pressed = jump_pressed
	if on_ground:
		_coyote_remaining = COYOTE_TICKS
	else:
		_coyote_remaining = maxi(0, _coyote_remaining - 1)
	var hover_pressed := bool(mask & INPUT_HOVER)
	if hover_unlocked and hover_pressed and not _last_hover_pressed and hover_toggle:
		hover_active = not hover_active
		movement_state_changed.emit()
	_last_hover_pressed = hover_pressed
	if not hover_toggle:
		hover_active = hover_unlocked and hover_pressed

	var target_x := horizontal * (HOVER_SPEED if hover_active and hover_unlocked else ground_speed)
	var horizontal_acceleration := 110 if hover_active and hover_unlocked else (76 if on_ground else 48)
	if horizontal == 0:
		horizontal_acceleration = 125 if hover_active and hover_unlocked else (92 if on_ground else 54)
	velocity_milli.x = move_toward(velocity_milli.x, target_x, horizontal_acceleration)
	if _jump_buffer_remaining > 0 and _coyote_remaining > 0:
		velocity_milli.y = -JUMP_IMPULSE
		_jump_buffer_remaining = 0
		_coyote_remaining = 0
	elif _jump_buffer_remaining > 0:
		_jump_buffer_remaining -= 1
	if jetting:
		velocity_milli.y = maxi(velocity_milli.y - JETPACK_ACCELERATION, -JETPACK_MAX_ASCENT_SPEED)
	elif hover_active and hover_unlocked:
		velocity_milli.y = move_toward(velocity_milli.y, 0, 125)
	else:
		velocity_milli.y = mini(velocity_milli.y + 20, MAX_FALL_SPEED)
	var feet_material := int(world.get_cell(world_cell()))
	if feet_material == 3:
		velocity_milli = Vector2i(int(velocity_milli.x * 0.82), int(velocity_milli.y * 0.82))

	_move_axis(Vector2i(velocity_milli.x, 0))
	_move_axis(Vector2i(0, velocity_milli.y))
	position = Vector2(position_milli) / MILLI * cell_pixel_size
	queue_redraw()


func _move_axis(delta_milli: Vector2i) -> void:
	if delta_milli == Vector2i.ZERO:
		return
	var candidate := position_milli + delta_milli
	if _body_blocked(candidate):
		if delta_milli.x != 0:
			velocity_milli.x = 0
		else:
			velocity_milli.y = 0
		return
	position_milli = candidate


func _body_blocked(candidate_milli: Vector2i) -> bool:
	var feet := Vector2i(floori(float(candidate_milli.x) / MILLI), floori(float(candidate_milli.y) / MILLI))
	var body := Rect2i(feet - Vector2i(1, BODY_SIZE.y - 1), BODY_SIZE)
	var started := Time.get_ticks_usec()
	var result: Dictionary = world.query_character_collision(body)
	last_collision_ms = float(Time.get_ticks_usec() - started) / 1000.0
	collision_queries += 1
	collision_cells_sampled += int(result.get("cells_sampled", 0))
	return bool(result.get("blocked", false))


func world_cell() -> Vector2i:
	return Vector2i(floori(float(position_milli.x) / MILLI), floori(float(position_milli.y) / MILLI))


func set_interaction_target(target: Vector2i) -> void:
	if target != interaction_target:
		interaction_target = target
		dig_progress = 0.0


func can_interact(target: Vector2i) -> bool:
	return interaction_reason(target) == "VALID"


func interaction_reason(target: Vector2i) -> String:
	var origin := world_cell() - Vector2i(0, 2)
	if origin.distance_squared_to(target) > INTERACTION_RANGE_CELLS * INTERACTION_RANGE_CELLS:
		return "OUT_OF_RANGE"
	if world.has_method("is_cell_live_visible") and not world.is_cell_live_visible(VISIBILITY_OWNER_ID, target):
		return "UNKNOWN_AREA"
	var delta := target - origin
	var steps := maxi(absi(delta.x), absi(delta.y))
	var solid_run := 0
	for step in range(1, maxi(1, steps)):
		var sample := Vector2i(roundi(lerpf(origin.x, target.x, float(step) / steps)), roundi(lerpf(origin.y, target.y, float(step) / steps)))
		if int(world.get_cell(sample)) in [1, 4, 5, 16]:
			solid_run += 1
			if solid_run >= 2:
				return "BLOCKED_INTERACTION"
		else:
			solid_run = 0
	return "VALID"


func build_validation(target: Vector2i, tech_unlocked := true) -> String:
	if not tech_unlocked:
		return "TECH_LOCKED"
	var access := interaction_reason(target)
	if access != "VALID":
		return access
	var material := int(world.get_cell(target))
	if material in [1, 4, 5, 16]:
		return "COLLIDES_WITH_TERRAIN"
	if material != 0:
		return "COLLIDES_WITH_MATERIAL"
	return "VALID"


func can_build_cells(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if build_validation(cell) != "VALID":
			return false
	return true


func classify_build_cells(cells: Array[Vector2i], tech_unlocked := true) -> Dictionary:
	var result := {}
	for cell in cells:
		result[cell] = build_validation(cell, tech_unlocked)
	return result


func _update_tool_selection() -> void:
	if Input.is_action_just_pressed(&"quickbar_1"): active_tool = Tool.DIG
	elif Input.is_action_just_pressed(&"quickbar_2"): active_tool = Tool.CUT
	elif Input.is_action_just_pressed(&"quickbar_3"): active_tool = Tool.IGNITER


func _update_primary_tool(delta: float) -> void:
	if not Input.is_action_pressed(&"dig") or not can_interact(interaction_target):
		dig_progress = 0.0
		return
	dig_progress += delta
	var duration := CUT_TIME_SECONDS if active_tool == Tool.CUT else DIG_TIME_SECONDS
	if dig_progress >= duration:
		match active_tool:
			Tool.DIG:
				world.character_dig_cell(interaction_target)
			Tool.CUT:
				command_bus.submit(world, WorldCommand.new(WorldCommand.Type.CUT_ORGANIC, {"x": interaction_target.x, "y": interaction_target.y}))
			Tool.IGNITER:
				command_bus.submit(world, WorldCommand.new(WorldCommand.Type.IGNITE, {"x": interaction_target.x, "y": interaction_target.y, "energy": IGNITION_ENERGY}))
		dig_progress = 0.0
		_update_visibility(true)


func dig_immediate_for_test(target: Vector2i) -> Dictionary:
	var access := interaction_reason(target)
	if access != "VALID":
		return {"changed": false, "reason": access, "conserved": true, "position": target}
	var result: Dictionary = world.character_dig_cell(target)
	_update_visibility(true)
	return result


func cut_immediate_for_test(target: Vector2i) -> Dictionary:
	var access := interaction_reason(target)
	if access != "VALID": return {"accepted": false, "reason": access}
	var command := WorldCommand.new(WorldCommand.Type.CUT_ORGANIC, {"x": target.x, "y": target.y})
	command_bus.submit(world, command)
	_update_visibility(true)
	return Dictionary(command_bus.last_result)


func ignite_immediate_for_test(target: Vector2i) -> Dictionary:
	var access := interaction_reason(target)
	if access != "VALID": return {"accepted": false, "reason": access}
	var command := WorldCommand.new(WorldCommand.Type.IGNITE, {"x": target.x, "y": target.y, "energy": IGNITION_ENERGY})
	command_bus.submit(world, command)
	return Dictionary(command_bus.last_result)


func active_tool_name() -> String:
	return ["DIG", "CUT", "IGNITER"][active_tool]


func _update_visibility(force: bool) -> void:
	var cell := world_cell()
	if not force and cell == _last_visibility_cell:
		return
	var started := Time.get_ticks_usec()
	world.update_character_visibility(VISIBILITY_OWNER_ID, cell - Vector2i(0, 2), VISIBILITY_RADIUS, SOLID_SHELL_DEPTH)
	last_visibility_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_last_visibility_cell = cell
	discovery_updated.emit()


func _update_camera() -> void:
	if follow_camera == null:
		return
	var target := position
	var maximum_offset := MAX_CAMERA_OFFSET_CELLS * cell_pixel_size
	var mouse_delta := get_global_mouse_position() - position
	var look := Vector2.ZERO if mouse_delta.length() < 12.0 else mouse_delta.limit_length(maximum_offset) * 0.42
	var vertical_look := clampf(float(velocity_milli.y) / MAX_FALL_SPEED, -1.0, 1.0) * 8.0 * cell_pixel_size
	_camera_velocity_look = Vector2(0.0, vertical_look)
	target += look + _camera_velocity_look
	if reduced_motion:
		follow_camera.position = target
	else:
		follow_camera.position = follow_camera.position.lerp(target, 0.36)


func center_camera() -> void:
	if follow_camera != null:
		follow_camera.position = position


func _refresh_unlocks() -> void:
	if world == null:
		return
	var sprint: Dictionary = world.get_research_state("mobility.sprint")
	var hover: Dictionary = world.get_research_state("mobility.hover")
	sprint_unlocked = bool(sprint.get("unlocked", false))
	hover_unlocked = bool(hover.get("unlocked", false))
	if not hover_unlocked:
		hover_active = false


func serialize_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"position_milli": position_milli,
		"velocity_milli": velocity_milli,
		"jetpack_unlocked": jetpack_unlocked,
		"sprint_unlocked": sprint_unlocked,
		"hover_unlocked": hover_unlocked,
		"hover_active": hover_active,
		"active_tool": int(active_tool),
	}


func deserialize_state(state: Dictionary) -> bool:
	if int(state.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	position_milli = state.get("position_milli", Vector2i.ZERO)
	velocity_milli = state.get("velocity_milli", Vector2i.ZERO)
	jetpack_unlocked = bool(state.get("jetpack_unlocked", true))
	sprint_unlocked = bool(state.get("sprint_unlocked", false))
	hover_unlocked = bool(state.get("hover_unlocked", false))
	hover_active = bool(state.get("hover_active", false)) and hover_unlocked
	active_tool = clampi(int(state.get("active_tool", Tool.DIG)), Tool.DIG, Tool.IGNITER)
	position = Vector2(position_milli) / MILLI * cell_pixel_size
	_update_visibility(true)
	return true


func replay_hash() -> String:
	return "%08x" % [hash([position_milli, velocity_milli, jetpack_unlocked, sprint_unlocked, hover_unlocked, hover_active,
		_jump_buffer_remaining, _coyote_remaining, active_tool]) & 0xffffffff]


func movement_profile() -> Dictionary:
	return {
		"walk_speed_milli_per_tick": WALK_SPEED,
		"sprint_speed_milli_per_tick": SPRINT_SPEED,
		"jump_impulse_milli_per_tick": JUMP_IMPULSE,
		"jump_buffer_ticks": JUMP_BUFFER_TICKS,
		"coyote_ticks": COYOTE_TICKS,
		"jetpack_acceleration_milli_per_tick2": JETPACK_ACCELERATION,
		"jetpack_max_ascent_milli_per_tick": JETPACK_MAX_ASCENT_SPEED,
		"hover_speed_milli_per_tick": HOVER_SPEED,
		"hover_vertical_damping_milli_per_tick": 125,
		"interaction_range_cells": INTERACTION_RANGE_CELLS,
		"camera_offset_cells": MAX_CAMERA_OFFSET_CELLS,
		"visibility_radius": VISIBILITY_RADIUS,
		"solid_shell_depth": SOLID_SHELL_DEPTH,
	}


func _draw() -> void:
	# Compact readable character silhouette; no per-cell physics Nodes.
	draw_circle(Vector2(0, -13), 5.0, Color("d6e5ce"))
	draw_circle(Vector2(-2, -14), 1.2, Color("27323a"))
	draw_rect(Rect2(-5, -9, 10, 11), Color("4fbb62"), true)
	draw_rect(Rect2(-7, -7, 3, 7), Color("889aa3"), true)
	draw_line(Vector2(-3, 2), Vector2(-4, 7), Color("313d45"), 2.0)
	draw_line(Vector2(3, 2), Vector2(4, 7), Color("313d45"), 2.0)
	if hover_active:
		draw_arc(Vector2.ZERO, 9.0, 0.15, PI - 0.15, 18, Color("f5c84b"), 1.5)
	if jetpack_active:
		var flame_length := 4.0 if reduced_motion else 8.0
		draw_line(Vector2(-6, -2), Vector2(-8, -2 + flame_length), Color("58d7ef"), 2.0)
		draw_line(Vector2(-4, -1), Vector2(-5, -1 + flame_length * 0.7), Color("f5c84b"), 2.0)
	if dig_progress > 0.0:
		draw_arc(Vector2(0, -10), 8.0, -PI * 0.5, -PI * 0.5 + TAU * dig_progress / DIG_TIME_SECONDS, 16, Color("f1d16d"), 2.0)
