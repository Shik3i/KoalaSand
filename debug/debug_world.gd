extends Node2D

const WORLD_SEED := 0x4b53414e44
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 12.0, 16.0, 24.0]
const GENERATION_WORKERS := 2
const MAX_CHUNKS_PUBLISHED_PER_FRAME := 4
const STREAM_PREFETCH_MARGIN := 2
const STREAM_EVICTION_MARGIN := 7

enum BrushMode {
	RAW_SAND,
	STONE,
	ERASE,
	HARVEST,
	CLEAR_VEGETATION,
	IGNITE,
}

@onready var renderer: DebugCellRenderer = $DebugCellRenderer
@onready var structure_renderer: StructureRenderer = $StructureRenderer
@onready var automation_renderer: AutomationRenderer = $AutomationRenderer
@onready var map_overlay_renderer: MapOverlayRenderer = $MapOverlayRenderer
@onready var overlay: ShowcaseOverlay = $ForegroundOverlay
@onready var minimal_label: Label = $HUD/MinimalPanel/Margin/MinimalStatus
@onready var diagnostics_panel: PanelContainer = $HUD/DiagnosticsPanel
@onready var diagnostics_label: Label = $HUD/DiagnosticsPanel/Margin/Diagnostics
@onready var camera: Camera2D = $Camera2D
@onready var seed_input: LineEdit = $HUD/SeedPanel/SeedControls/SeedInput
@onready var regenerate_button: Button = $HUD/SeedPanel/SeedControls/Regenerate
@onready var copy_seed_button: Button = $HUD/SeedPanel/SeedControls/CopySeed
@onready var reserve_label: Label = $HUD/ResearchHUD/Row/Reserves
@onready var research_button: Button = $HUD/ResearchHUD/Row/OpenResearch
@onready var research_tree: ResearchTreePanel = $HUD/ResearchTree
@onready var automation_inspector: PanelContainer = $HUD/AutomationInspector
@onready var automation_details: Label = $HUD/AutomationInspector/Margin/Details
@onready var factory_hud: FactoryHUD = $HUD/FactoryHUD

var materials := MaterialRegistry.new()
var world: Variant
var clock := SimulationClock.new(60)
var brush_mode := BrushMode.RAW_SAND
var _creative_material_id := 0
var build_structure_type := 0
var build_structure_orientation := 0
var remove_structure_mode := false
var _subsurface_depth := -1
var _subsurface_dragging := false
var _info_mode := false
var _blueprints := BlueprintLibrary.new(16)
var _blueprint_turns := 0
var _blueprint_flip_h := false
var _blueprint_flip_v := false
var _blueprint_selection_active := false
var _blueprint_selection_anchor := Vector2i.ZERO
var _construction_history := ConstructionHistory.new(64)
var _alert_manager := FactoryAlertManager.new()
var brush_radius: int = 3
var diagnostics_visible: bool = false
var zoom_index: int = 1
var _painting: bool = false
var _panning: bool = false
var _last_painted_cell := Vector2i.ZERO
var _capture_path: String = ""
var _capture_tick: int = -1
var _capture_queued: bool = false
var _simulation_latest_ms := 0.0
var _simulation_total_ms := 0.0
var _simulation_worst_ms := 0.0
var _simulation_samples := 0
var _render_total_ms := 0.0
var _render_samples := 0
var _runtime_benchmark_ticks := -1
var _runtime_benchmark_start_usec := 0
var _runtime_benchmark_frames := 0
var _runtime_benchmark_delta_seconds := 0.0
var _runtime_benchmark_finished := false
var _runtime_benchmark_started := false
var _runtime_benchmark_start_tick := 0
var _runtime_frame_samples: Array[float] = []
var _runtime_sim_samples: Array[float] = []
var _runtime_water_upload_total_ms := 0.0
var _runtime_water_upload_total_bytes := 0
var _runtime_water_upload_samples := 0
var _runtime_logistics_total_usec := 0
var _runtime_logistics_samples := 0
var _runtime_belts_considered_total := 0
var _runtime_belts_considered_peak := 0
var _runtime_belt_moves_total := 0
var _runtime_machine_total_usec := 0
var _runtime_machine_samples := 0
var _runtime_bank_total_usec := 0
var _runtime_bank_samples := 0
var _runtime_ui_total_ms := 0.0
var _runtime_ui_samples := 0
var _runtime_automation_total_ms := 0.0
var _runtime_automation_samples := 0
var _runtime_structure_visibility_ms := 0.0
var _runtime_structure_prepare_ms := 0.0
var _runtime_structure_upload_ms := 0.0
var _runtime_structure_upload_bytes := 0
var _runtime_structure_samples := 0
var _runtime_thermal_total_ms := 0.0
var _runtime_thermal_samples := 0
var _runtime_phase9_thermal_ms: Array[float] = []
var _runtime_phase9_gas_ms: Array[float] = []
var _runtime_phase9_fluid_ms: Array[float] = []
var _runtime_phase9_pipe_ms: Array[float] = []
var _world_seed: int = WORLD_SEED
var _streaming_frame: int = 0
var _visible_chunk_rect := Rect2i()
var _geology_visible: bool = false
var _structure_dragging := false
var _structure_drag_start := Vector2i.ZERO
var _structure_definitions: Dictionary = {}
var _showcase_enabled := true
var _phase4_view := ""
var _phase5_view := "primitive"
var _phase6_view := ""
var _phase65_view := ""
var _phase7_view := ""
var _phase8_view := ""
var _dense_factory_benchmark := false
var _dense_progression_benchmark := false
var _dense_automation_benchmark := false
var _dense_physical_benchmark := false
var _dense_water_benchmark := false
var _dense_phase8_benchmark := false
var _phase85_render_benchmark := ""
var _phase85_temperature_overlay := false
var _phase85_renderer_mode := 0
var _phase85_thermal_load := false
var _phase875_view := ""
var _phase9_view := ""
var _phase10_view := ""
var _phase11_view := ""
var _phase12_view := ""
var _phase13_view := ""
var _phase135_view := ""
var _phase136_view := ""
var _realistic_max_factory_benchmark := false
var _owner_package_smoke := false
var _validate_seeds := 0
var _validate_seed_start := 1
var _creative_fixture := false
var _unlock_notice := ""
var _benchmark_bank_origins: Array[Vector2i] = []
var _command_bus := WorldCommandBus.new()
var _game_session := GameSession.new()
var _character: KoalaCharacterController
var _visibility_renderer: VisibilityRenderer
var _new_game_screen: NewGameScreen
var _pause_menu: PauseMenu
var _save_manager := WorldSaveManager.new()
var _world_name := "New World"
var _player_session_active := false
var _playtime_seconds := 0.0
var _autosave_elapsed := 0.0
var _world_map_panel: WorldMapPanel
var _phase11_character_cell := Vector2i.ZERO
var _character_hud_label: Label
var _organic_renderer: OrganicRenderer
var _physics_codex := PhysicsCodex.new()
var _codex_panel: CodexPanel
var _experiment_tracker := ExperimentTracker.new()
var _experiments_panel: ExperimentsPanel
var _blueprint_panel: BlueprintLibraryPanel
var _audio_mixer: AudioEventMixer
var _feedback_renderer: PhysicalFeedbackRenderer
var _diagnostics_exporter := DiagnosticsExporter.new()
var _planning_paused := false
var _pause_menu_was_planning := false
var _last_milestones: Dictionary = {}
var _phase135_capture_inspector: Dictionary = {}


func _ready() -> void:
	var error := materials.load_directory()
	if error != OK:
		push_error("Material registry failed to load: %s" % error_string(error))
		get_tree().quit(1)
		return
	_parse_capture_arguments()
	_game_session.apply_preset(_phase11_preset_for_view())
	_alert_manager.alert_emitted.connect(_on_factory_alert)
	_alert_manager.focus_requested.connect(_focus_world_cell)
	world = NativeSandWorld.new()
	# Eight simulation workers leave main/render-thread headroom on desktop while
	# preserving the single-thread fallback selected by NativeSandWorld on Web.
	world.reset(_world_seed, clampi(OS.get_processor_count() - 1, 1, 8))
	_configure_procedural_world()
	if _validate_seeds > 0:
		var validation_report: Dictionary = world.validate_world_seeds(_validate_seed_start, _validate_seeds)
		print("phase11_seed_validation_json=%s" % JSON.stringify(validation_report))
		get_tree().quit(0 if int(validation_report.validation_failures) == 0 else 1)
		return
	if _creative_fixture or _dense_factory_benchmark or _realistic_max_factory_benchmark or _dense_progression_benchmark or _dense_automation_benchmark or _dense_physical_benchmark or _dense_water_benchmark or _dense_phase8_benchmark or not _phase85_render_benchmark.is_empty() or not _phase875_view.is_empty() or not _phase9_view.is_empty() or not _phase10_view.is_empty() or not _phase11_view.is_empty() or not _phase12_view.is_empty() or not _phase13_view.is_empty() or not _phase135_view.is_empty() or not _phase136_view.is_empty() or not _phase4_view.is_empty() or not _phase6_view.is_empty() or not _phase65_view.is_empty() or not _phase7_view.is_empty() or not _phase8_view.is_empty():
		world.set_game_mode(1)
	if _game_session.progression_mode == GameModeCapabilities.ProgressionMode.CREATIVE:
		world.set_game_mode(1)
	_cache_structure_definitions()
	MvpExampleBlueprints.install(_blueprints)
	_physics_codex.rebuild(materials, world, _blueprints)
	if _showcase_enabled:
		_build_showcase()
	renderer.initialize(world)
	structure_renderer.render_mode = _phase85_renderer_mode
	structure_renderer.initialize(world)
	automation_renderer.initialize(world)
	map_overlay_renderer.initialize(world)
	_organic_renderer = OrganicRenderer.new()
	_organic_renderer.name = "OrganicRenderer"
	_organic_renderer.z_index = 24
	add_child(_organic_renderer)
	_organic_renderer.initialize(world, renderer.cell_pixel_size)
	_visibility_renderer = VisibilityRenderer.new()
	_visibility_renderer.name = "VisibilityRenderer"
	add_child(_visibility_renderer)
	_visibility_renderer.initialize(world, KoalaCharacterController.VISIBILITY_OWNER_ID, renderer.cell_pixel_size)
	_visibility_renderer.set_discovery_enabled(_game_session.visibility_policy == GameModeCapabilities.VisibilityPolicy.DISCOVERED)
	if _phase85_temperature_overlay:
		map_overlay_renderer.set_mode(MapOverlayRenderer.Mode.TEMPERATURE)
	if _phase85_thermal_load:
		world.configure_thermal_candidate(1024, 512, 8)
	overlay.initialize(world)
	seed_input.text = str(_world_seed)
	seed_input.text_submitted.connect(_on_seed_submitted)
	regenerate_button.pressed.connect(_regenerate_from_seed_input)
	copy_seed_button.pressed.connect(_copy_seed)
	_connect_build_toolbar()
	factory_hud.initialize(world)
	factory_hud.configure_mode(_game_session.preset_id)
	factory_hud.tool_selected.connect(_on_factory_tool_selected)
	factory_hud.research_requested.connect(_toggle_research)
	factory_hud.overlay_selected.connect(_on_overlay_selected)
	factory_hud.map_requested.connect(_toggle_world_map)
	factory_hud.codex_requested.connect(_open_codex)
	factory_hud.experiments_requested.connect(_toggle_experiments)
	factory_hud.blueprints_requested.connect(_toggle_blueprint_library)
	factory_hud.diagnostics_requested.connect(_export_diagnostics)
	_create_phase135_player_ui()
	_create_pause_menu()
	research_tree.initialize(world)
	research_tree.theme = factory_hud.theme
	if _phase6_view == "research":
		research_tree.select_research("automation.logic_control")
	research_tree.unlock_requested.connect(_on_unlock_requested)
	research_button.pressed.connect(_toggle_research)
	if _phase5_view == "tree":
		research_tree.visible = true
	_configure_phase65_view()
	_configure_phase7_view()
	_configure_phase8_view()
	_configure_phase875_view()
	_configure_phase9_view()
	_configure_phase10_view()
	_configure_phase11_view()
	_configure_phase12_view()
	_configure_phase13_view()
	_runtime_benchmark_start_usec = Time.get_ticks_usec()
	_set_camera_zoom_index(zoom_index)
	_request_camera_streaming()
	if _game_session.control_mode == GameModeCapabilities.ControlMode.CHARACTER:
		_create_character()
	if _phase11_view in ["new-game", "world-preview"]:
		_show_new_game_screen()
	elif _is_normal_player_launch():
		_show_new_game_screen()
	_configure_phase135_view()
	_configure_phase136_view()
	if _owner_package_smoke:
		call_deferred("_run_owner_package_smoke")
	_update_brush_preview()
	_update_status()
	_maybe_queue_capture()


func _process(delta: float) -> void:
	var async_result := _save_manager.poll_async_save()
	if async_result.has("ok") and not bool(async_result.get("pending", false)) and factory_hud != null:
		factory_hud.show_notification("Autosave complete" if bool(async_result.get("ok", false)) else "Autosave failed: %s" % str(async_result.get("error", "UNKNOWN")))
	if _player_session_active and clock.speed_multiplier > 0:
		_playtime_seconds += delta
		_autosave_elapsed += delta
		var autosave_minutes := int(_pause_menu.settings().get("autosave_minutes", 5)) if _pause_menu != null else 5
		if _autosave_elapsed >= autosave_minutes * 60.0:
			_autosave_elapsed = 0.0
			_save_current_world(true)
	_streaming_frame += 1
	if _streaming_frame % 8 == 1:
		_request_camera_streaming()
	var chunks_changed: bool = world.pump_generation(MAX_CHUNKS_PUBLISHED_PER_FRAME) > 0
	if _character != null:
		_character.set_interaction_target(_mouse_world_cell())
		_update_character_hud()
	if _streaming_frame % 12 == 0:
		_update_phase135_feedback()
	if _runtime_benchmark_started:
		_runtime_benchmark_frames += 1
		_runtime_benchmark_delta_seconds += delta
		_runtime_frame_samples.append(delta * 1000.0)
		_runtime_ui_total_ms += research_tree.last_update_ms + factory_hud.last_update_ms
		_runtime_ui_samples += 1
	var due_ticks := clock.advance(delta)
	for _tick in due_ticks:
		if _dense_progression_benchmark:
			_maintain_progression_bank_feeds()
		var simulation_start := Time.get_ticks_usec()
		world.step()
		if _runtime_benchmark_started:
			var phase9_thermal: Dictionary = world.get_thermal_statistics()
			var phase9_gas: Dictionary = world.get_gas_statistics()
			var phase9_fluid: Dictionary = world.get_fluid_statistics()
			var phase9_pipe: Dictionary = world.get_pipe_statistics()
			_runtime_phase9_thermal_ms.append(float(phase9_thermal.get("thermal_usec", 0)) / 1000.0)
			_runtime_phase9_gas_ms.append(float(phase9_gas.get("gas_usec", 0)) / 1000.0)
			_runtime_phase9_fluid_ms.append(float(phase9_fluid.get("fluid_usec", 0)) / 1000.0)
			_runtime_phase9_pipe_ms.append(float(phase9_pipe.get("pipe_usec", 0)) / 1000.0)
		if _phase85_thermal_load and int(world.get_statistics().get("tick", 0)) % 2 == 0:
			var thermal: Dictionary = world.step_thermal_candidate(2)
			if _runtime_benchmark_started:
				_runtime_thermal_total_ms += float(thermal.get("thermal_usec", 0)) / 1000.0
				_runtime_thermal_samples += 1
		if _runtime_benchmark_started:
			var logistics: Dictionary = world.get_structure_statistics()
			var considered := int(logistics.get("belts_considered", 0))
			_runtime_logistics_total_usec += int(logistics.get("logistics_usec", 0))
			_runtime_logistics_samples += 1
			_runtime_belts_considered_total += considered
			_runtime_belts_considered_peak = maxi(_runtime_belts_considered_peak, considered)
			_runtime_belt_moves_total += int(logistics.get("belt_moves", 0))
			var processing: Dictionary = world.get_processing_statistics()
			_runtime_machine_total_usec += int(processing.get("machine_processing_usec", 0))
			_runtime_machine_samples += 1
			var banks: Dictionary = world.get_bank_statistics()
			_runtime_bank_total_usec += int(banks.get("bank_usec", 0))
			_runtime_bank_samples += 1
			var automation: Dictionary = world.get_automation_statistics()
			_runtime_automation_total_ms += float(automation.get("circuit_ms", 0.0))
			_runtime_automation_samples += 1
		_simulation_latest_ms = float(Time.get_ticks_usec() - simulation_start) / 1000.0
		_simulation_total_ms += _simulation_latest_ms
		_simulation_worst_ms = maxf(_simulation_worst_ms, _simulation_latest_ms)
		_simulation_samples += 1
		if _runtime_benchmark_started:
			_runtime_sim_samples.append(_simulation_latest_ms)
	if _streaming_frame % 30 == 0:
		var keep_rect := _expanded_chunk_rect(_visible_chunk_rect, STREAM_EVICTION_MARGIN)
		chunks_changed = world.evict_pristine_outside(keep_rect, 12) > 0 or chunks_changed
		_alert_manager.observe(world, _expanded_chunk_rect(_visible_chunk_rect, 1))
	if due_ticks > 0 or chunks_changed:
		if _phase875_view not in ["overview", "underground-benchmark", "info-benchmark"] and _phase9_view != "overview" and _phase10_view != "overview":
			renderer.render_dirty_chunks(_expanded_chunk_rect(_visible_chunk_rect, 1))
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		if _organic_renderer != null:
			_organic_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		if _visibility_renderer != null:
			_visibility_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		_render_total_ms += renderer.last_update_ms
		_render_samples += 1
		if _runtime_benchmark_started:
			_runtime_structure_visibility_ms += structure_renderer.last_visibility_ms
			_runtime_structure_prepare_ms += structure_renderer.last_cpu_prepare_ms
			_runtime_structure_upload_ms += structure_renderer.last_upload_ms
			_runtime_structure_upload_bytes += structure_renderer.last_upload_bytes
			_runtime_structure_samples += 1
			_runtime_water_upload_total_ms += renderer.last_water_upload_ms
			_runtime_water_upload_total_bytes += renderer.last_water_upload_bytes
			_runtime_water_upload_samples += 1
		if _info_mode:
			overlay.set_info_mode(true, _expanded_chunk_rect(_visible_chunk_rect, 1))
		if overlay.show_chunk_debug or overlay.show_geology_heatmap or _info_mode:
			overlay.queue_redraw()
		_update_status()
	_maybe_queue_capture()
	_maybe_start_runtime_benchmark()
	_maybe_finish_runtime_benchmark()


func _unhandled_input(event: InputEvent) -> void:
	if _new_game_screen != null and _new_game_screen.visible:
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_key(event: InputEventKey) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"planning_pause"):
		_set_planning_paused(not _planning_paused)
		return
	if event.is_action_pressed(&"open_codex"):
		_open_codex("")
		return
	if event.is_action_pressed(&"open_experiments"):
		_toggle_experiments()
		return
	if event.is_action_pressed(&"cancel"):
		if _pause_menu != null and _pause_menu.visible:
			_resume_from_pause()
			return
		if _blueprint_selection_active:
			_cancel_blueprint_selection()
			return
		if build_structure_type > 0 or remove_structure_mode or _subsurface_depth >= 0:
			build_structure_type = 0
			remove_structure_mode = false
			_subsurface_depth = -1
			_structure_dragging = false
			factory_hud.show_notification("Cancelled placement")
			_update_structure_preview()
			return
		if _world_map_panel != null and _world_map_panel.visible:
			_toggle_world_map()
			return
		if research_tree.visible:
			_toggle_research()
			return
		if factory_hud.close_top_modal():
			return
		if _player_session_active:
			_open_pause_menu()
		else:
			clock.set_speed(1 if clock.speed_multiplier == 0 else 0)
			factory_hud.show_notification("Paused" if clock.speed_multiplier == 0 else "Resumed")
		return
	if event.is_action_pressed(&"map"):
		_toggle_world_map()
		return
	if event.is_action_pressed(&"toggle_wiring"):
		automation_renderer.set_wiring_mode(not automation_renderer.wiring_mode)
		automation_inspector.visible = automation_renderer.wiring_mode
		_update_automation_inspector()
		return
	if event.is_action_pressed(&"statistics"):
		factory_hud.toggle_statistics()
		return
	if event.is_action_pressed(&"info_mode"):
		_info_mode = not _info_mode
		factory_hud.set_info_mode(_info_mode)
		overlay.set_info_mode(_info_mode, _expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	if event.is_action_pressed(&"blueprint"):
		if _blueprint_selection_active:
			_cancel_blueprint_selection()
		else:
			_begin_blueprint_selection()
		return
	if event.keycode == KEY_ESCAPE and _blueprint_selection_active:
		_cancel_blueprint_selection()
		return
	if event.is_action_pressed(&"pipette"):
		if _character != null and not world.is_cell_live_visible(KoalaCharacterController.VISIBILITY_OWNER_ID, _mouse_world_cell()):
			factory_hud.show_context_hint("pipette_unknown", "Pipette requires a live-visible structure.")
			return
		var copied := ConstructionPlanner.pipette(world, _mouse_world_cell())
		if not copied.is_empty():
			build_structure_orientation = int(copied.orientation)
			_select_structure(int(copied.type_id))
		return
	if event.is_action_pressed(&"rotate"):
		build_structure_orientation = posmod(build_structure_orientation + 1, 4)
		_blueprint_turns = posmod(_blueprint_turns + 1, 4)
		_update_structure_preview()
		if _audio_mixer != null: _audio_mixer.play_ui(&"rotate")
		return
	if event.is_action_pressed(&"flip_horizontal"):
		_blueprint_flip_h = not _blueprint_flip_h
		return
	if event.is_action_pressed(&"flip_vertical"):
		_blueprint_flip_v = not _blueprint_flip_v
		return
	if event.is_action_pressed(&"copy") or event.is_action_pressed(&"cut"):
		_copy_blueprint_selection(event.is_action_pressed(&"cut"))
		return
	if event.is_action_pressed(&"paste"):
		_paste_blueprint()
		return
	if event.is_action_pressed(&"undo"):
		var undo_result: Dictionary = _construction_history.undo(world, _command_bus)
		if int(undo_result.get("rejected", 1)) == 0:
			factory_hud.show_notification("Undid: construction action")
			if _audio_mixer != null: _audio_mixer.play_ui(&"undo")
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
		return
	if event.is_action_pressed(&"redo"):
		var redo_result: Dictionary = _construction_history.redo(world, _command_bus)
		if int(redo_result.get("rejected", 1)) == 0:
			factory_hud.show_notification("Redid: construction action")
			if _audio_mixer != null: _audio_mixer.play_ui(&"redo")
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
		return
	if automation_renderer.wiring_mode:
		if event.keycode == KEY_ESCAPE:
			automation_renderer.pending_source_id = 0
			automation_renderer.queue_redraw()
			return
		if event.keycode == KEY_DELETE and automation_renderer.selected_component_id > 0:
			_submit_world_command(WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, {"component_id": automation_renderer.selected_component_id})
			automation_renderer.select_component(0)
			automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
			_update_automation_inspector()
			return
		if event.keycode == KEY_ENTER and automation_renderer.selected_component_id > 0:
			var selected_state: Dictionary = world.get_automation_component_state(automation_renderer.selected_component_id)
			if int(selected_state.get("type_id", 0)) == 1:
				_submit_world_command(WorldCommand.Type.SET_MANUAL_SWITCH, {"component_id": automation_renderer.selected_component_id, "enabled": not bool(selected_state.get("enabled", false))})
			_update_automation_inspector()
			return
		if event.shift_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var type_id := int(event.keycode - KEY_1) + 1
			var component_cell := _mouse_world_cell()
			var component_id := 0
			if _submit_world_command(WorldCommand.Type.CREATE_AUTOMATION_COMPONENT, {"type_id": type_id, "x": component_cell.x, "y": component_cell.y, "configuration": _default_automation_config(type_id, component_cell)}):
				component_id = int(_command_bus.last_result)
			if component_id > 0:
				automation_renderer.select_component(component_id)
				automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
				_update_automation_inspector()
			return
	if not event.ctrl_pressed and not event.alt_pressed:
		for number in range(10):
			if event.is_action_pressed(StringName("quickbar_%d" % number)):
				factory_hud.activate_slot(number)
				return
	if event.is_action_pressed(&"build_catalog"):
		factory_hud.toggle_catalog()
		return
	if event.is_action_pressed(&"open_research"):
		_toggle_research()
		return
	if event.is_action_pressed(&"overlay_selector"):
		_on_overlay_selected(0 if map_overlay_renderer.mode != MapOverlayRenderer.Mode.NONE else MapOverlayRenderer.Mode.MAGNETIC_FIELD)
		return
	match event.keycode:
		KEY_SPACE:
			if _game_session.control_mode != GameModeCapabilities.ControlMode.CHARACTER:
				_set_planning_paused(not _planning_paused)
		KEY_R:
			_select_terrain(BrushMode.RAW_SAND)
		KEY_S:
			_select_terrain(BrushMode.STONE)
		KEY_E:
			_select_terrain(BrushMode.ERASE)
		KEY_H:
			_select_terrain(BrushMode.HARVEST)
		KEY_Q:
			_select_structure(1)
		KEY_W:
			_select_structure(2)
		KEY_A:
			_select_structure(3)
		KEY_D:
			_select_structure(4)
		KEY_G:
			_select_structure(8)
		KEY_F:
			_select_structure(40)
		KEY_V:
			_select_structure(45)
		KEY_M:
			_select_structure(46)
		KEY_X:
			_select_remove()
		KEY_MINUS:
			brush_radius = maxi(1, brush_radius - 1)
		KEY_EQUAL:
			brush_radius = mini(12, brush_radius + 1)
		KEY_PAGEUP:
			factory_hud.change_page(-1)
		KEY_PAGEDOWN:
			factory_hud.change_page(1)
		KEY_F2:
			overlay.set_chunk_debug(not overlay.show_chunk_debug)
		KEY_F3:
			if _phase11_view in ["diagnostics", "worldgen-debug"] or _phase11_view.is_empty():
				diagnostics_visible = not diagnostics_visible
				diagnostics_panel.visible = diagnostics_visible
			else:
				factory_hud.show_notification("Developer diagnostics are disabled in player modes")
		KEY_F4:
			if _game_session.visibility_policy == GameModeCapabilities.VisibilityPolicy.OMNISCIENT:
				_geology_visible = not _geology_visible
				overlay.set_geology_heatmap(_geology_visible)
			else:
				factory_hud.show_context_hint("geology_locked", "Hidden geology needs a future survey capability.")
		KEY_F5:
			_regenerate_from_seed_input()
		KEY_F6:
			_world_seed += 1
			seed_input.text = str(_world_seed)
			_regenerate_world()
		KEY_F7:
			_copy_seed()
	_update_brush_preview()
	_update_status()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed and bool(_game_session.capabilities.get("free_camera", true)) and not _pointer_over_ui()
		return
	if _pointer_over_ui():
		return
	if _character != null and not _character.can_interact(_mouse_world_cell()):
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return
	if automation_renderer.wiring_mode and event.pressed and not _pointer_over_ui():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var wire_id := automation_renderer.pick_connection(_mouse_world_cell())
			if wire_id > 0:
				_submit_world_command(WorldCommand.Type.REMOVE_AUTOMATION_CONNECTION, {"connection_id": wire_id})
			else:
				automation_renderer.pending_source_id = 0
			automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_wiring_click(_mouse_world_cell())
			return
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_camera_zoom_index(zoom_index + 1)
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_camera_zoom_index(zoom_index - 1)
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not _pointer_over_ui():
		var remove_cell := _mouse_world_cell()
		_submit_world_command(WorldCommand.Type.REMOVE_STRUCTURE, {"x": remove_cell.x, "y": remove_cell.y})
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
		_update_structure_preview()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _character != null and build_structure_type == 0 and not remove_structure_mode and _subsurface_depth < 0:
		# Physical Dig is handled by the Character controller's InputMap action.
		return
	if _subsurface_depth >= 0:
		if event.pressed and not _pointer_over_ui():
			_subsurface_dragging = true
			_structure_drag_start = _mouse_world_cell()
		elif not event.pressed and _subsurface_dragging:
			_place_subsurface_drag(_mouse_world_cell())
		return
	if build_structure_type > 0:
		if build_structure_type <= 2 or build_structure_type == 10:
			_structure_dragging = event.pressed and not _pointer_over_ui()
			if _structure_dragging:
				_structure_drag_start = _mouse_world_cell()
			elif not event.pressed:
				if build_structure_type == 10: _place_pipe_drag(_mouse_world_cell())
				else: _place_conveyor_drag(_mouse_world_cell())
		else:
			if event.pressed and not _pointer_over_ui():
				var placement_cell := _mouse_world_cell()
				if _character != null and not _character.can_interact(placement_cell):
					return
				_submit_world_command(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": build_structure_type, "x": placement_cell.x, "y": placement_cell.y, "orientation": build_structure_orientation})
				structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
				_update_structure_preview()
		return
	if remove_structure_mode:
		if event.pressed and not _pointer_over_ui():
			var remove_cell := _mouse_world_cell()
			_submit_world_command(WorldCommand.Type.REMOVE_STRUCTURE, {"x": remove_cell.x, "y": remove_cell.y})
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
			_update_structure_preview()
		return
	_painting = event.pressed and not _pointer_over_ui()
	if _painting:
		_last_painted_cell = _mouse_world_cell()
		_paint_line(_last_painted_cell, _last_painted_cell)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		camera.position -= event.relative / camera.zoom
		_snap_camera_to_screen_pixel()
	if automation_renderer.wiring_mode:
		automation_renderer.set_preview(_mouse_world_cell(), automation_renderer.pick_component(_mouse_world_cell()) == 0)
	_update_brush_preview()
	_update_structure_preview()
	if _structure_dragging:
		return
	if not _painting or _pointer_over_ui():
		_update_status()
		return
	var current_cell := _mouse_world_cell()
	_paint_line(_last_painted_cell, current_cell)
	_last_painted_cell = current_cell


func _paint_line(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var delta := to_cell - from_cell
	var steps := maxi(absi(delta.x), absi(delta.y))
	if steps == 0:
		_paint_stamp(to_cell)
	else:
		for step_index in range(steps + 1):
			var fraction := float(step_index) / float(steps)
			_paint_stamp(Vector2i(
				roundi(lerpf(from_cell.x, to_cell.x, fraction)),
				roundi(lerpf(from_cell.y, to_cell.y, fraction))
			))
	renderer.render_dirty_chunks()
	_update_status()


func _handle_wiring_click(cell: Vector2i) -> void:
	var component_id := automation_renderer.pick_component(cell)
	if component_id <= 0:
		automation_renderer.invalid_target = true
		automation_renderer.queue_redraw()
		return
	if automation_renderer.pending_source_id <= 0:
		var ports: Array = world.get_automation_component_ports(component_id)
		for port: Dictionary in ports:
			if int(port.direction) == 1:
				automation_renderer.pending_source_id = component_id
				automation_renderer.select_component(component_id)
				_update_automation_inspector()
				return
		automation_renderer.invalid_target = true
		return
	var target_port := -1
	for port: Dictionary in world.get_automation_component_ports(component_id):
		if int(port.direction) == 0 and not bool(port.connected):
			target_port = int(port.port_id)
			break
	var wire_id: int = 0
	if target_port >= 0 and component_id != automation_renderer.pending_source_id:
		if _submit_world_command(WorldCommand.Type.CREATE_AUTOMATION_CONNECTION, {"source_component": automation_renderer.pending_source_id, "source_port": 0, "target_component": component_id, "target_port": target_port}):
			wire_id = int(_command_bus.last_result)
	automation_renderer.invalid_target = wire_id <= 0
	if wire_id > 0:
		automation_renderer.pending_source_id = 0
		automation_renderer.select_component(component_id)
	automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	_update_automation_inspector()


func _default_automation_config(type_id: int, cell: Vector2i) -> Dictionary:
	match type_id:
		2:
			return {"material_id": 2, "mode": 0, "probe_size": Vector2i(3, 1), "target_position": cell + Vector2i(0, 1)}
		3:
			return {"mode": 1, "probe_size": Vector2i(6, 7), "target_position": cell + Vector2i(0, 1), "threshold": 800}
		7:
			return {"operator": 1, "threshold": 800}
		8:
			return {"mode": 4, "target_position": cell + Vector2i(0, 1)}
		9:
			return {"mode": 2, "period_ticks": 300, "on_ticks": 60}
		_:
			return {}


func _update_automation_inspector() -> void:
	if not automation_renderer.wiring_mode:
		return
	var component_id := automation_renderer.selected_component_id
	if component_id <= 0:
		automation_details.text = "AUTOMATION / WIRING MODE\n\nShift+1…9 place components\nClick output → click input\nRight-click wire: delete\nEsc: cancel   Y: close"
		return
	var state: Dictionary = world.get_automation_component_state(component_id)
	var definitions: Array = world.get_automation_definitions()
	var name := "Component"
	for definition: Dictionary in definitions:
		if int(definition.type_id) == int(state.type_id):
			name = str(definition.display_name)
			break
	automation_details.text = "AUTOMATION / %s  #%d\n\nIN A: %d   IN B: %d   OUT: %d\nmode %d   threshold %d\nprobe %s   target %s\n\nEnter toggles Manual Switch\nDelete removes component   Y closes" % [
		name, component_id, state.input_a, state.input_b, state.output, state.mode, state.threshold, state.probe_size, state.target_position
	]
func _paint_stamp(center: Vector2i) -> void:
	if brush_mode == BrushMode.CLEAR_VEGETATION:
		_submit_world_command(WorldCommand.Type.CLEAR_VEGETATION_RECT, {
			"x": center.x - brush_radius, "y": center.y - brush_radius,
			"width": brush_radius * 2 + 1, "height": brush_radius * 2 + 1,
		})
		return
	if brush_mode == BrushMode.IGNITE:
		_submit_world_command(WorldCommand.Type.IGNITE, {"x": center.x, "y": center.y, "energy": 24000000})
		return
	if brush_mode == BrushMode.HARVEST:
		for offset_y in range(-brush_radius, brush_radius + 1):
			for offset_x in range(-brush_radius, brush_radius + 1):
				if offset_x * offset_x + offset_y * offset_y <= brush_radius * brush_radius:
					var harvest_cell := center + Vector2i(offset_x, offset_y)
					_submit_world_command(WorldCommand.Type.HARVEST, {"x": harvest_cell.x, "y": harvest_cell.y})
		return
	var material_id := _current_brush_material()
	for offset_y in range(-brush_radius, brush_radius + 1):
		for offset_x in range(-brush_radius, brush_radius + 1):
			if offset_x * offset_x + offset_y * offset_y > brush_radius * brush_radius:
				continue
			var paint_cell := center + Vector2i(offset_x, offset_y)
			var command_type := WorldCommand.Type.CREATIVE_ERASE if material_id == 0 else WorldCommand.Type.CREATIVE_PAINT
			_submit_world_command(command_type, {"x": paint_cell.x, "y": paint_cell.y, "material_id": material_id})


func _current_brush_material() -> int:
	if _creative_material_id > 0:
		return _creative_material_id
	match brush_mode:
		BrushMode.STONE:
			return materials.get_id(&"stone")
		BrushMode.ERASE:
			return MaterialRegistry.EMPTY_ID
		BrushMode.HARVEST, BrushMode.CLEAR_VEGETATION, BrushMode.IGNITE:
			return MaterialRegistry.EMPTY_ID
		_:
			return materials.get_id(&"raw_sand")


func _current_brush_name() -> String:
	if _subsurface_depth >= 0:
		return "SUBSURFACE CHANNEL %s" % ["I", "II", "III"][_subsurface_depth]
	if remove_structure_mode:
		return "REMOVE STRUCTURE"
	if build_structure_type > 0:
		var definition: Dictionary = _structure_definitions.get(build_structure_type, {})
		return str(definition.get("display_name", "STRUCTURE")).to_upper()
	if _creative_material_id > 0:
		var material_definition := materials.get_definition(_creative_material_id)
		return str(material_definition.display_name if material_definition != null else "MATERIAL").to_upper()
	match brush_mode:
		BrushMode.STONE:
			return "STONE"
		BrushMode.ERASE:
			return "ERASE"
		BrushMode.HARVEST:
			return "HARVEST COAL"
		BrushMode.CLEAR_VEGETATION:
			return "CLEAR VEGETATION"
		BrushMode.IGNITE:
			return "IGNITER"
		_:
			return "RAW SAND"


func _cache_structure_definitions() -> void:
	_structure_definitions.clear()
	for definition: Dictionary in world.get_structure_definitions():
		_structure_definitions[int(definition["type_id"])] = definition


func _connect_build_toolbar() -> void:
	var tools := $HUD/BuildToolbar/Margin/Tools
	tools.get_node("RawSand").pressed.connect(_select_terrain.bind(BrushMode.RAW_SAND))
	tools.get_node("Stone").pressed.connect(_select_terrain.bind(BrushMode.STONE))
	tools.get_node("Erase").pressed.connect(_select_terrain.bind(BrushMode.ERASE))
	tools.get_node("Harvest").pressed.connect(_select_terrain.bind(BrushMode.HARVEST))
	tools.get_node("BeltLeft").pressed.connect(_select_structure.bind(1))
	tools.get_node("BeltRight").pressed.connect(_select_structure.bind(2))
	tools.get_node("Funnel").pressed.connect(_select_structure.bind(3))
	tools.get_node("Bin").pressed.connect(_select_structure.bind(4))
	tools.get_node("Bank").pressed.connect(_select_structure.bind(8))
	tools.get_node("Furnace").pressed.connect(_select_structure.bind(5))
	tools.get_node("Sieve").pressed.connect(_select_structure.bind(6))
	tools.get_node("Magnetic").pressed.connect(_select_structure.bind(7))
	tools.get_node("Remove").pressed.connect(_select_remove)


func _on_factory_tool_selected(tool: Dictionary) -> void:
	match str(tool.get("kind", "")):
		"select":
			build_structure_type = 0; remove_structure_mode = false; _subsurface_depth = -1
		"pipette":
			_pipette_at_cursor()
		"blueprint_select":
			_begin_blueprint_selection()
		"structure":
			_select_structure(int(tool.id))
		"subsurface":
			_subsurface_depth = int(tool.depth)
			build_structure_type = 0
			remove_structure_mode = false
		"terrain":
			_select_terrain(int(tool.id))
		"material":
			_select_creative_material(int(tool.id))
		"organic_clear":
			_select_terrain(BrushMode.CLEAR_VEGETATION)
		"ignite":
			_select_terrain(BrushMode.IGNITE)
		"remove":
			_select_remove()
		"wiring", "automation":
			automation_renderer.set_wiring_mode(true)
			automation_inspector.visible = true
	_update_status()

func _place_subsurface_drag(end_cell: Vector2i) -> void:
	if not _subsurface_dragging:
		return
	var delta := end_cell - _structure_drag_start
	var end := Vector2i(_structure_drag_start.x, end_cell.y) if absi(delta.y) > absi(delta.x) else Vector2i(end_cell.x, _structure_drag_start.y)
	if _character != null and (not _character.can_interact(_structure_drag_start) or not _character.can_interact(end)):
		_subsurface_dragging = false
		return
	_submit_world_command(WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL, {
		"depth": _subsurface_depth,
		"x0": _structure_drag_start.x,
		"y0": _structure_drag_start.y,
		"x1": end.x,
		"y1": end.y,
	})
	_subsurface_dragging = false
	structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
	_update_structure_preview()

func _begin_blueprint_selection() -> void:
	_blueprint_selection_active = true
	_blueprint_selection_anchor = _mouse_world_cell()
	build_structure_type = 0
	remove_structure_mode = false
	_subsurface_depth = -1
	_painting = false
	_structure_dragging = false
	_unlock_notice = "BLUEPRINT SELECT · CTRL+C COPY · CTRL+X CUT · U/ESC CANCEL"
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


func _cancel_blueprint_selection() -> void:
	_blueprint_selection_active = false
	if _unlock_notice.begins_with("BLUEPRINT SELECT"):
		_unlock_notice = ""
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


static func blueprint_selection_rect(anchor: Vector2i, cursor: Vector2i) -> Rect2i:
	var minimum := Vector2i(mini(anchor.x, cursor.x), mini(anchor.y, cursor.y))
	var maximum := Vector2i(maxi(anchor.x, cursor.x), maxi(anchor.y, cursor.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _blueprint_selection_preview(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if rect.get_area() <= 4096:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		return cells
	for x in range(rect.position.x, rect.end.x):
		cells.append(Vector2i(x, rect.position.y))
		if rect.size.y > 1:
			cells.append(Vector2i(x, rect.end.y - 1))
	for y in range(rect.position.y + 1, rect.end.y - 1):
		cells.append(Vector2i(rect.position.x, y))
		if rect.size.x > 1:
			cells.append(Vector2i(rect.end.x - 1, y))
	return cells


func _automation_blueprint_configuration(state: Dictionary, selection_origin: Vector2i) -> Dictionary:
	var configuration := {}
	for key in ["orientation", "mode", "material_id", "probe_size", "threshold", "operator", "period_ticks", "on_ticks", "enabled"]:
		if state.has(key):
			configuration[key] = state[key]
	if state.has("target_position"):
		configuration.target_position = Vector2i(state.target_position) - selection_origin
	return configuration


func _capture_blueprint_region(selection: Rect2i) -> Dictionary:
	var blueprint := BlueprintDefinition.new(
		"clipboard-%d" % Time.get_ticks_usec(),
		"Clipboard",
		"Region %dx%d" % [selection.size.x, selection.size.y]
	)
	var next_relative_id := 1
	var structure_origins: Array[Vector2i] = []
	var seen_structures := {}
	for y in range(selection.position.y, selection.end.y):
		for x in range(selection.position.x, selection.end.x):
			var cell := Vector2i(x, y)
			var type_id := int(world.get_structure(cell))
			if type_id <= 0 or type_id in [18, 19, 20, 21, 22, 23]:
				continue
			var sampled := ConstructionPlanner.pipette(world, cell)
			if sampled.is_empty():
				continue
			var origin := Vector2i(sampled.get("origin", cell))
			var key := "%d:%d:%d" % [origin.x, origin.y, type_id]
			if seen_structures.has(key):
				continue
			seen_structures[key] = true
			structure_origins.append(origin)
			blueprint.add_structure(next_relative_id, type_id, origin - selection.position, int(sampled.orientation), Dictionary(sampled.configuration))
			next_relative_id += 1

	var component_ids: Array[int] = []
	var component_relative_ids := {}
	var component_records: PackedInt32Array = world.get_visible_automation_components(selection)
	for index in range(0, component_records.size(), 7):
		var component_id := int(component_records[index])
		var state: Dictionary = world.get_automation_component_state(component_id)
		if state.is_empty():
			continue
		component_ids.append(component_id)
		component_relative_ids[component_id] = next_relative_id
		blueprint.add_automation_component(
			next_relative_id,
			int(state.type_id),
			Vector2i(state.position) - selection.position,
			_automation_blueprint_configuration(state, selection.position)
		)
		next_relative_id += 1

	var automation_state: Dictionary = world.serialize_automation_state()
	for connection_value: Variant in Array(automation_state.get("connections", [])):
		var connection: Dictionary = connection_value
		var source_id := int(connection.get("source", 0))
		var target_id := int(connection.get("target", 0))
		if component_relative_ids.has(source_id) and component_relative_ids.has(target_id):
			blueprint.add_connection(
				int(component_relative_ids[source_id]), int(connection.get("source_port", 0)),
				int(component_relative_ids[target_id]), int(connection.get("target_port", 0))
			)

	var channel_ids: Array[int] = []
	var route_records: PackedInt32Array = world.get_visible_subsurface_routes(selection)
	for index in range(0, route_records.size(), 10):
		var entrance := Vector2i(route_records[index + 3], route_records[index + 4])
		var exit := Vector2i(route_records[index + 5], route_records[index + 6])
		if not selection.has_point(entrance) or not selection.has_point(exit):
			continue
		var channel_id := (int(route_records[index + 1]) << 32) | (int(route_records[index]) & 0xffffffff)
		channel_ids.append(channel_id)
		blueprint.add_subsurface_channel(next_relative_id, int(route_records[index + 2]), entrance - selection.position, exit - selection.position)
		next_relative_id += 1
	return {
		"blueprint": blueprint,
		"structure_origins": structure_origins,
		"component_ids": component_ids,
		"channel_ids": channel_ids,
	}


func _copy_blueprint_selection(cut: bool) -> void:
	var cursor := _mouse_world_cell()
	var selection := blueprint_selection_rect(_blueprint_selection_anchor, cursor) if _blueprint_selection_active else Rect2i(cursor, Vector2i.ONE)
	var captured := _capture_blueprint_region(selection)
	var blueprint: BlueprintDefinition = captured.blueprint
	if blueprint.entries.is_empty() and blueprint.subsurface_channels.is_empty():
		return
	_blueprints.copy_to_clipboard(blueprint)
	_blueprint_turns = 0
	_blueprint_flip_h = false
	_blueprint_flip_v = false
	if cut:
		_cut_blueprint_region(selection, blueprint, captured)
	_cancel_blueprint_selection()


func _cut_blueprint_region(selection: Rect2i, blueprint: BlueprintDefinition, captured: Dictionary) -> void:
	for channel_id: int in captured.channel_ids:
		var channel: Dictionary = world.get_subsurface_channel_state(channel_id)
		if channel.is_empty() or int(channel.get("occupied_packets", 0)) > 0:
			_unlock_notice = "CUT BLOCKED · SUBSURFACE CHANNEL MUST DRAIN"
			_update_status()
			return
	var sequence := Time.get_ticks_usec()
	var forward := CommandBatch.new("cut:%d" % sequence, 0, sequence, "Cut region", CommandBatch.ValidationMode.ATOMIC)
	for component_id: int in captured.component_ids:
		forward.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, {"component_id": component_id}))
	for channel_id: int in captured.channel_ids:
		forward.add(WorldCommand.new(WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL, {"channel_id": channel_id, "removal_policy": ConstructionPlanner.RemovalPolicy.MUST_DRAIN}))
	for origin: Vector2i in captured.structure_origins:
		forward.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": origin.x, "y": origin.y}))
	var inverse := blueprint.instantiate(selection.position, 0, sequence, "Undo cut region")
	var result := _construction_history.execute(world, _command_bus, forward, inverse)
	if int(result.get("rejected", 0)) > 0:
		_unlock_notice = "CUT REJECTED · WORLD CHANGED"
	structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))

func _paste_blueprint() -> void:
	var blueprint := _blueprints.clipboard()
	if blueprint == null:
		return
	var origin := _mouse_world_cell()
	var sequence := Time.get_ticks_usec()
	var transformed := blueprint.transformed(_blueprint_turns, _blueprint_flip_h, _blueprint_flip_v)
	if _character != null:
		var required_cells: Array[Vector2i] = []
		for entry: Dictionary in transformed.entries:
			required_cells.append(origin + Vector2i(entry.position))
		for channel: Dictionary in transformed.subsurface_channels:
			required_cells.append(origin + Vector2i(channel.entrance))
			required_cells.append(origin + Vector2i(channel.exit))
		if not _character.can_build_cells(required_cells):
			_unlock_notice = "BLUEPRINT OUT OF CHARACTER BUILD RANGE"
			return
	var forward := transformed.instantiate(origin, 0, sequence, "Paste")
	var result := _command_bus.submit_batch(world, forward)
	if int(result.get("rejected", 0)) > 0 or int(result.get("applied", 0)) != forward.commands.size():
		return
	var relative_ids: Dictionary = result.get("relative_id_map", {})
	var inverse := CommandBatch.new("undo-paste:%d" % sequence, 0, sequence, "Undo paste", CommandBatch.ValidationMode.ATOMIC)
	for entry: Dictionary in transformed.entries:
		if str(entry.get("kind", "structure")) == "automation":
			var component_id := int(relative_ids.get(int(entry.relative_id), 0))
			if component_id > 0:
				inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, {"component_id": component_id}))
	for channel: Dictionary in transformed.subsurface_channels:
		var channel_id := int(relative_ids.get(int(channel.relative_id), 0))
		if channel_id > 0:
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL, {"channel_id": channel_id, "removal_policy": ConstructionPlanner.RemovalPolicy.MUST_DRAIN}))
	for entry: Dictionary in transformed.entries:
		if str(entry.get("kind", "structure")) == "structure":
			var cell: Vector2i = origin + Vector2i(entry.position)
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": cell.x, "y": cell.y}))
	_construction_history.record(forward, inverse)
	structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))


func _on_overlay_selected(mode: int) -> void:
	if _game_session.visibility_policy == GameModeCapabilities.VisibilityPolicy.DISCOVERED and mode == MapOverlayRenderer.Mode.GEOLOGY:
		factory_hud.show_context_hint("overlay_geology", "Hidden geology needs a future survey capability.")
		return
	map_overlay_renderer.set_mode(mode)
	_geology_visible = mode == MapOverlayRenderer.Mode.GEOLOGY
	overlay.set_geology_heatmap(_geology_visible)
	map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))

func _on_factory_alert(alert: Dictionary) -> void:
	if not _phase136_view.is_empty():
		return
	if _character != null:
		var cell: Vector2i = alert.get("world_cell", alert.get("cell", Vector2i(2147483647, 2147483647)))
		if cell.x != 2147483647 and not world.is_cell_live_visible(KoalaCharacterController.VISIBILITY_OWNER_ID, cell):
			return
	factory_hud.show_alert(str(alert.message))

func _focus_world_cell(world_cell: Vector2i) -> void:
	if _character != null and not world.is_cell_live_visible(KoalaCharacterController.VISIBILITY_OWNER_ID, world_cell):
		factory_hud.show_context_hint("remote_focus", "Remote live focus needs a future observation capability.")
		return
	camera.position = Vector2(world_cell) * renderer.cell_pixel_size
	_snap_camera_to_screen_pixel()


func _submit_world_command(type: int, payload: Dictionary) -> bool:
	var tick := int(world.get_statistics().get("tick", 0)) if world != null else 0
	var sequence := Time.get_ticks_usec()
	var forward := CommandBatch.new("action:%d" % sequence, 0, sequence, "Construction action", CommandBatch.ValidationMode.ATOMIC)
	var forward_payload := payload.duplicate(true)
	if type in [WorldCommand.Type.CREATE_AUTOMATION_COMPONENT, WorldCommand.Type.CREATE_AUTOMATION_CONNECTION, WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL]:
		forward_payload.relative_id = 1
	forward.add(WorldCommand.new(type, forward_payload, tick))
	var inverse := _inverse_before_command(type, payload, sequence, tick)
	var result := _command_bus.submit_batch(world, forward)
	if int(result.get("rejected", 0)) > 0:
		if _audio_mixer != null: _audio_mixer.play_ui(&"invalid")
		if _feedback_renderer != null and payload.has("x") and payload.has("y"): _feedback_renderer.emit(&"invalid", Vector2i(payload.x, payload.y))
		return false
	if inverse == null:
		inverse = _inverse_after_command(type, payload, result, sequence, tick)
	if inverse != null and not inverse.commands.is_empty():
		_construction_history.record(forward, inverse)
	var allocated := int(Dictionary(result.get("relative_id_map", {})).get(1, 0))
	if allocated > 0:
		_command_bus.last_result = allocated
	if payload.has("x") and payload.has("y"):
		var cell := Vector2i(payload.x, payload.y)
		if type in [WorldCommand.Type.PLACE_STRUCTURE, WorldCommand.Type.PLACE_CONVEYOR_LINE, WorldCommand.Type.PLACE_PIPE_LINE]:
			if _audio_mixer != null: _audio_mixer.play_world(&"place", Vector2(cell) * renderer.cell_pixel_size, 0.7, "UI")
			if _feedback_renderer != null: _feedback_renderer.emit(&"place", cell)
		elif type == WorldCommand.Type.REMOVE_STRUCTURE:
			if _audio_mixer != null: _audio_mixer.play_world(&"remove", Vector2(cell) * renderer.cell_pixel_size, 0.7, "UI")
			if _feedback_renderer != null: _feedback_renderer.emit(&"remove", cell)
		elif type == WorldCommand.Type.IGNITE:
			if _audio_mixer != null: _audio_mixer.play_world(&"igniter", Vector2(cell) * renderer.cell_pixel_size, 0.8, "Character")
			if _feedback_renderer != null: _feedback_renderer.emit(&"ignite", cell)
	return true

func _inverse_before_command(type: int, payload: Dictionary, sequence: int, tick: int) -> CommandBatch:
	var inverse := CommandBatch.new("undo:%d" % sequence, 0, sequence, "Undo construction action", CommandBatch.ValidationMode.ATOMIC)
	match type:
		WorldCommand.Type.PLACE_STRUCTURE:
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": payload.x, "y": payload.y}, tick))
		WorldCommand.Type.REMOVE_STRUCTURE:
			var sampled := ConstructionPlanner.pipette(world, Vector2i(payload.x, payload.y))
			if sampled.is_empty(): return null
			var origin := Vector2i(sampled.get("origin", Vector2i(payload.x, payload.y)))
			inverse.add(WorldCommand.new(WorldCommand.Type.PLACE_STRUCTURE, {"type_id": sampled.type_id, "x": origin.x, "y": origin.y, "orientation": sampled.orientation, "configuration": sampled.configuration}, tick))
		WorldCommand.Type.PLACE_CONVEYOR_LINE:
			for x in range(mini(int(payload.x0), int(payload.x1)), maxi(int(payload.x0), int(payload.x1)) + 1):
				inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": x, "y": payload.y}, tick))
		WorldCommand.Type.PLACE_PIPE_LINE:
			var start := Vector2i(payload.x0, payload.y0)
			var finish := Vector2i(payload.x1, payload.y1)
			var direction := (finish - start).sign()
			var distance := absi(finish.x - start.x) + absi(finish.y - start.y)
			for offset in distance + 1:
				var cell := start + direction * offset
				inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_STRUCTURE, {"x": cell.x, "y": cell.y}, tick))
		WorldCommand.Type.SET_MANUAL_SWITCH:
			var state: Dictionary = world.get_automation_component_state(int(payload.component_id))
			if state.is_empty(): return null
			inverse.add(WorldCommand.new(type, {"component_id": payload.component_id, "enabled": state.get("enabled", false)}, tick))
		WorldCommand.Type.SET_PIPE_DEVICE:
			var pipe: Dictionary = world.get_pipe_state(Vector2i(payload.x, payload.y))
			if pipe.is_empty(): return null
			inverse.add(WorldCommand.new(type, {"x": payload.x, "y": payload.y, "enabled": pipe.enabled, "valve": payload.get("valve", false)}, tick))
		_:
			return null
	return inverse

func _inverse_after_command(type: int, payload: Dictionary, result: Dictionary, sequence: int, tick: int) -> CommandBatch:
	var allocated := int(Dictionary(result.get("relative_id_map", {})).get(1, 0))
	if allocated <= 0:
		return null
	var inverse := CommandBatch.new("undo:%d" % sequence, 0, sequence, "Undo allocated construction action", CommandBatch.ValidationMode.ATOMIC)
	match type:
		WorldCommand.Type.CREATE_AUTOMATION_COMPONENT:
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_COMPONENT, {"component_id": allocated}, tick))
		WorldCommand.Type.CREATE_AUTOMATION_CONNECTION:
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_AUTOMATION_CONNECTION, {"connection_id": allocated}, tick))
		WorldCommand.Type.PLACE_SUBSURFACE_CHANNEL:
			inverse.add(WorldCommand.new(WorldCommand.Type.REMOVE_SUBSURFACE_CHANNEL, {"channel_id": allocated, "removal_policy": ConstructionPlanner.RemovalPolicy.MUST_DRAIN}, tick))
		_:
			return null
	return inverse


func _select_terrain(mode: BrushMode) -> void:
	brush_mode = mode
	_creative_material_id = 0
	build_structure_type = 0
	remove_structure_mode = false
	_subsurface_depth = -1
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


func _select_creative_material(material_id: int) -> void:
	brush_mode = BrushMode.RAW_SAND
	_creative_material_id = material_id
	build_structure_type = 0
	remove_structure_mode = false
	_subsurface_depth = -1
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


func _select_structure(type_id: int) -> void:
	_subsurface_depth = -1
	if not world.is_structure_unlocked(type_id):
		build_structure_type = 0
		remove_structure_mode = false
		_unlock_notice = "LOCKED · OPEN RESEARCH TO UNLOCK"
		research_tree.visible = true
		research_tree.queue_redraw()
		_update_status()
		return
	build_structure_type = type_id
	remove_structure_mode = false
	_painting = false
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


func _toggle_research() -> void:
	research_tree.toggle()
	factory_hud.set_external_modal("research", research_tree.visible)
	_update_status()


func _toggle_world_map() -> void:
	if _world_map_panel == null:
		_world_map_panel = WorldMapPanel.new()
		_world_map_panel.name = "WorldMapPanel"
		$HUD.add_child(_world_map_panel)
		_world_map_panel.center_requested.connect(func() -> void:
			if _character != null:
				_character.center_camera()
		)
		_world_map_panel.initialize(world, _game_session.preset_id)
		_world_map_panel.visible = false
	_world_map_panel.visible = not _world_map_panel.visible
	factory_hud.set_external_modal("map", _world_map_panel.visible)
	if _world_map_panel.visible:
		_world_map_panel.refresh(_expanded_chunk_rect(_visible_chunk_rect, 1))


func _on_unlock_requested(research_id: String) -> void:
	if world.try_unlock_research(research_id):
		var name := research_id
		for definition: Dictionary in world.get_research_definitions():
			if definition.id == research_id:
				name = definition.display_name
				break
		_unlock_notice = "UNLOCKED · %s" % name.to_upper()
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	else:
		_unlock_notice = "RESEARCH REQUIREMENTS NOT MET"
	research_tree.queue_redraw()
	_update_status()


func _select_remove() -> void:
	build_structure_type = 0
	remove_structure_mode = true
	_subsurface_depth = -1
	_painting = false
	_update_brush_preview()
	_update_structure_preview()
	_update_status()


func _structure_preview_cells(origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if build_structure_type <= 0:
		return cells
	if (build_structure_type <= 2 or build_structure_type == 10) and _structure_dragging:
		if build_structure_type == 10 and absi(origin.y - _structure_drag_start.y) > absi(origin.x - _structure_drag_start.x):
			for y in range(mini(_structure_drag_start.y, origin.y), maxi(_structure_drag_start.y, origin.y) + 1): cells.append(Vector2i(_structure_drag_start.x, y))
		else:
			for x in range(mini(_structure_drag_start.x, origin.x), maxi(_structure_drag_start.x, origin.x) + 1): cells.append(Vector2i(x, _structure_drag_start.y))
		return cells
	var definition: Dictionary = _structure_definitions.get(build_structure_type, {})
	for local: Vector2i in definition.get("occupied_cells", []):
		cells.append(origin + local)
	return cells


func _update_structure_preview() -> void:
	if _blueprint_selection_active:
		var selection := blueprint_selection_rect(_blueprint_selection_anchor, _mouse_world_cell())
		overlay.set_structure_preview(_blueprint_selection_preview(selection), true)
		return
	if _subsurface_depth >= 0:
		if not _subsurface_dragging or _capture_path.is_empty() == false or _pointer_over_ui():
			overlay.set_structure_preview([], false)
			return
		var target := _mouse_world_cell()
		var delta := target - _structure_drag_start
		var end := Vector2i(_structure_drag_start.x, target.y) if absi(delta.y) > absi(delta.x) else Vector2i(target.x, _structure_drag_start.y)
		var direction := (end - _structure_drag_start).sign()
		var distance := absi(end.x - _structure_drag_start.x) + absi(end.y - _structure_drag_start.y)
		var cells: Array[Vector2i] = []
		for offset in distance + 1:
			cells.append(_structure_drag_start + direction * offset)
		overlay.set_structure_preview(cells, world.can_place_subsurface_channel(_subsurface_depth, _structure_drag_start, end))
		return
	if build_structure_type <= 0 or not _capture_path.is_empty() or _pointer_over_ui():
		overlay.set_structure_preview([], false)
		return
	var origin := _mouse_world_cell()
	var cells := _structure_preview_cells(origin)
	var valid := false
	if (build_structure_type <= 2 or build_structure_type == 10) and _structure_dragging:
		if build_structure_type == 10:
			valid = not cells.is_empty()
			for cell in cells: valid = valid and world.can_place_structure(10, cell, 0)
		else:
			valid = world.can_place_conveyor_line(_structure_drag_start, Vector2i(origin.x, _structure_drag_start.y), -1 if build_structure_type == 1 else 1)
	else:
		valid = world.can_place_structure(build_structure_type, origin, build_structure_orientation)
	if _character != null:
		var reasons := _character.classify_build_cells(cells, world.is_structure_unlocked(build_structure_type))
		for reason: String in reasons.values():
			if reason != "VALID":
				valid = false
				factory_hud.show_alert(reason.replace("_", " ").capitalize())
				break
	var presentation := ComponentPresentation.describe(build_structure_type, _structure_definitions.get(build_structure_type, {}))
	overlay.set_structure_preview(cells, valid, build_structure_type, build_structure_orientation, Array(presentation.ports))


func _place_conveyor_drag(end_cell: Vector2i) -> void:
	if not _structure_dragging:
		return
	var end := Vector2i(end_cell.x, _structure_drag_start.y)
	if _character != null:
		var cells: Array[Vector2i] = []
		for x in range(mini(_structure_drag_start.x, end.x), maxi(_structure_drag_start.x, end.x) + 1):
			cells.append(Vector2i(x, end.y))
		if not _character.can_build_cells(cells):
			_structure_dragging = false
			return
	_submit_world_command(WorldCommand.Type.PLACE_CONVEYOR_LINE, {
		"x0": _structure_drag_start.x, "x1": end.x, "y": end.y,
		"direction": -1 if build_structure_type == 1 else 1,
	})
	_structure_dragging = false
	structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	_update_structure_preview()


func _place_pipe_drag(end_cell: Vector2i) -> void:
	if not _structure_dragging:
		return
	var delta := end_cell - _structure_drag_start
	var end := Vector2i(end_cell.x, _structure_drag_start.y) if absi(delta.x) >= absi(delta.y) else Vector2i(_structure_drag_start.x, end_cell.y)
	if _character != null and (not _character.can_interact(_structure_drag_start) or not _character.can_interact(end)):
		_structure_dragging = false
		return
	_submit_world_command(WorldCommand.Type.PLACE_PIPE_LINE, {"x0": _structure_drag_start.x, "y0": _structure_drag_start.y, "x1": end.x, "y1": end.y})
	_structure_dragging = false
	structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	_update_structure_preview()
	_update_status()


func _current_brush_color() -> Color:
	if brush_mode == BrushMode.ERASE or brush_mode == BrushMode.HARVEST:
		return Color(0.78, 0.88, 0.92, 0.62)
	var definition := materials.get_definition(_current_brush_material())
	var color := definition.visual_surface_color
	color.a = 0.72
	return color


func _mouse_world_cell() -> Vector2i:
	var world_position := get_global_mouse_position()
	return Vector2i(
		floori(world_position.x / renderer.cell_pixel_size),
		floori(world_position.y / renderer.cell_pixel_size)
	)


func _update_brush_preview() -> void:
	overlay.set_brush_preview(
		_mouse_world_cell(),
		brush_radius,
		_current_brush_color(),
		not _pointer_over_ui() and _capture_path.is_empty() and build_structure_type == 0 and not remove_structure_mode and not _blueprint_selection_active
	)


func _pointer_over_ui() -> bool:
	if factory_hud != null and factory_hud.modal_open():
		return true
	var control := get_viewport().gui_get_hovered_control()
	return control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _set_camera_zoom_index(next_index: int) -> void:
	zoom_index = clampi(next_index, 0, ZOOM_LEVELS.size() - 1)
	camera.zoom = Vector2.ONE * ZOOM_LEVELS[zoom_index]
	structure_renderer.set_overview_mode(zoom_index == 0)
	_snap_camera_to_screen_pixel()
	_update_status()


func _snap_camera_to_screen_pixel() -> void:
	camera.position = (camera.position * camera.zoom).round() / camera.zoom


func _configure_procedural_world() -> void:
	world.configure_world({
		"seed": _world_seed,
		"width": 16384,
		"depth": 4096,
		"sky": 512,
		"surface_baseline": 0,
		"surface_amplitude": 72,
		"sediment_depth": 18,
		"cave_density": 0.52,
		"coal_frequency": 0.73,
		"water_frequency": 0.72,
		"geology_scale": 512,
		"generation_version": 2 if not _phase11_view.is_empty() or not _phase12_view.is_empty() or not _phase13_view.is_empty() or _validate_seeds > 0 else 1,
	}, GENERATION_WORKERS)


func _build_showcase() -> void:
	if _realistic_max_factory_benchmark:
		_build_realistic_max_factory()
		return
	if not _phase13_view.is_empty():
		_build_phase13_showcase()
		return
	if not _phase12_view.is_empty():
		_build_phase12_showcase()
		return
	if not _phase11_view.is_empty():
		_build_phase11_showcase()
		return
	if not _phase10_view.is_empty():
		_build_phase10_showcase()
		return
	if not _phase9_view.is_empty():
		_build_phase9_showcase()
		return
	if not _phase875_view.is_empty():
		_build_phase875_showcase()
		return
	if not _phase85_render_benchmark.is_empty():
		_build_phase85_render_benchmark()
		return
	if _dense_phase8_benchmark:
		_build_dense_phase8_benchmark()
		return
	if not _phase8_view.is_empty():
		_build_phase8_showcase()
		return
	if _dense_water_benchmark:
		_build_dense_water_benchmark()
		return
	if not _phase7_view.is_empty():
		_build_phase7_showcase()
		return
	if _dense_physical_benchmark:
		_build_dense_physical_benchmark()
		return
	if _dense_automation_benchmark:
		_build_dense_automation_benchmark()
		return
	if not _phase6_view.is_empty():
		_build_phase6_showcase()
		return
	if not _phase65_view.is_empty():
		_build_phase65_showcase()
		return
	if _dense_progression_benchmark:
		_build_dense_factory_benchmark()
		_add_dense_progression_banks()
		return
	if _dense_factory_benchmark or not _phase4_view.is_empty():
		_build_phase4_showcase()
		return
	_build_phase5_showcase()


func _phase11_preset_for_view() -> GameModeCapabilities.Preset:
	if not _phase13_view.is_empty():
		return GameModeCapabilities.Preset.CREATIVE
	if _phase12_view == "character-sandbox":
		return GameModeCapabilities.Preset.CHARACTER
	if _phase12_view.begins_with("creative"):
		return GameModeCapabilities.Preset.CREATIVE
	if _phase11_view.begins_with("character") or _phase11_view in ["jetpack", "hover", "discovered-map"]:
		return GameModeCapabilities.Preset.CHARACTER
	if _phase11_view in ["creative-mode", "creative-normal"]:
		return GameModeCapabilities.Preset.CREATIVE
	return GameModeCapabilities.Preset.FACTORY


func _place_mvp_blueprint(blueprint: BlueprintDefinition, origin: Vector2i) -> void:
	for entry: Dictionary in blueprint.entries:
		world.place_structure(int(entry.type_id), origin + Vector2i(entry.position), int(entry.orientation))


func _build_phase13_showcase() -> void:
	world.fill_rect(Rect2i(-128, -72, 256, 112), MaterialRegistry.EMPTY_ID)
	world.fill_rect(Rect2i(-128, 34, 256, 3), 1)
	match _phase13_view:
		"screen":
			_place_mvp_blueprint(MvpExampleBlueprints.basic_screen(), Vector2i(-3, 16))
			for x in range(-7, 11):
				world.set_material_state(Vector2i(x, 14), 2, 190, 1172)
		"wet-sluice":
			_place_mvp_blueprint(MvpExampleBlueprints.basic_wet_sluice(), Vector2i(-4, 14))
			for x in [-3, -1, 1, 3]: world.set_water_mass(Vector2i(x, 15), 225, 1172)
			for x in [-2, 0, 2]: world.set_material_state(Vector2i(x, 14), 2, 140, 1172)
		"furnace":
			_place_mvp_blueprint(MvpExampleBlueprints.basic_furnace(), Vector2i(-4, 12))
			for x in range(-1, 3):
				world.set_material_state(Vector2i(x, 15), 23, 180, 3600)
				world.set_material_state(Vector2i(x, 14), 2, 190, 3100)
		"vessels":
			_place_mvp_blueprint(MvpExampleBlueprints.basic_metal_vessel(), Vector2i(-13, 11))
			_place_mvp_blueprint(MvpExampleBlueprints.basic_steam_boiler(), Vector2i(7, 10))
			for x in range(-12, -7): world.set_material_state(Vector2i(x, 13), 18, 220, 2800)
			for x in range(9, 14): world.set_material_state(Vector2i(x, 13), 3, 255, 3400)
		_:
			var origins := [Vector2i(-34, 8), Vector2i(-19, 8), Vector2i(-3, 8), Vector2i(15, 8), Vector2i(30, 8), Vector2i(45, 8)]
			var examples := MvpExampleBlueprints.all()
			for index in examples.size():
				_place_mvp_blueprint(examples[index], origins[index])
	world.finalize_initialization()
	camera.position = Vector2(0, 12) * renderer.cell_pixel_size
	zoom_index = 8 if _phase13_view != "components" else 5


func _phase12_add_tree(base: Vector2i, height: int, crown_radius: int) -> void:
	for y in range(height):
		var trunk := base - Vector2i(0, y)
		world.set_material_state(trunk, 21, 255, 1172)
		world.set_organic_moisture(trunk, 36)
	var crown := base - Vector2i(0, height - 1)
	for y in range(-crown_radius, crown_radius + 1):
		for x in range(-crown_radius, crown_radius + 1):
			if x * x * 3 + y * y * 4 > crown_radius * crown_radius * 4:
				continue
			var leaf := crown + Vector2i(x, y)
			if world.get_cell(leaf) == 0:
				world.set_material_state(leaf, 22, 180, 1172)
				world.set_organic_moisture(leaf, 18)


func _phase12_fill_pot(origin: Vector2i, temperature: int, food_material: int = 25) -> void:
	world.place_structure(35, origin, 0)
	for x in range(1, 8):
		world.set_material_state(origin + Vector2i(x, 4), 3, 255, maxi(1172, temperature - 500))
	world.set_material_state(origin + Vector2i(4, 3), food_material, 255, maxi(1172, temperature - 300))
	for x in range(1, 8):
		world.set_material_state(origin + Vector2i(x, 6), 1, 255, temperature)


func _build_phase12_showcase() -> void:
	world.fill_rect(Rect2i(-128, -72, 256, 108), 0)
	world.fill_rect(Rect2i(-128, 32, 256, 3), 1)
	_phase12_add_tree(Vector2i(-72, 31), 25, 6)
	_phase12_add_tree(Vector2i(-45, 31), 18, 5)
	_phase12_add_tree(Vector2i(-22, 31), 22, 6)
	_phase11_character_cell = Vector2i(-94, 26)

	# A physical organic/factory vignette: conveyors, exposed fuel, kiln and open cookware.
	world.place_conveyor_line(Vector2i(-10, 30), Vector2i(104, 30), 1)
	for x in range(-8, 7):
		world.set_material_state(Vector2i(x, 29), 21 if x % 3 else 23, 160, 1172)
	world.place_structure(6, Vector2i(10, 24), 0)
	world.place_structure(7, Vector2i(28, 24), 0)
	world.place_structure(8, Vector2i(94, 24), 0)

	# Restricted-air Stone kiln. Heat and oxygen determine Charcoal; no recipe/machine state.
	for x in range(38, 51):
		world.set_material_state(Vector2i(x, 18), 1, 255, 1172)
	for y in range(8, 19):
		world.set_material_state(Vector2i(38, y), 1, 255, 1172)
		world.set_material_state(Vector2i(50, y), 1, 255, 1172)
	for x in range(38, 51):
		if x != 43:
			world.set_material_state(Vector2i(x, 8), 1, 255, 1172)
	for x in range(40, 49):
		world.set_material_state(Vector2i(x, 17), 21, 220, 2250)

	var pot_temperature := 1172
	if _phase12_view in ["pot-heating", "cooking", "factory-organic", "character-sandbox", "temperature-overlay", "diagnostics"]:
		pot_temperature = 4200
	elif _phase12_view in ["pot-boiling", "pot-steam", "burnt-food"]:
		pot_temperature = 8200
	var food_material := 27 if _phase12_view == "burnt-food" else (26 if _phase12_view == "cooking" else 25)
	_phase12_fill_pot(Vector2i(66, 21), pot_temperature, food_material)
	if _phase12_view == "pot-steam":
		for y in range(12, 20):
			world.set_material_state(Vector2i(70 + (y % 3) - 1, y), 14, 180, 4100)

	if _phase12_view in ["tree-cut", "tree-falling", "fallen-wood", "character-sandbox"]:
		world.character_cut_cell(Vector2i(-72, 31))
	if _phase12_view in ["wood-burning", "smoke", "factory-organic", "character-sandbox", "temperature-overlay", "diagnostics"]:
		for x in range(0, 13):
			world.set_material_state(Vector2i(x, 16), 1, 255, 1172)
			world.set_material_state(Vector2i(x, 15), 21, 220, 2500)
			if x % 2 == 0:
				world.set_material_state(Vector2i(x, 14), 23, 140, 2900)
			world.ignite_cell(Vector2i(x, 15), 24000000)
	if _phase12_view == "smoke":
		for y in range(-2, 14):
			for x in range(-2, 3):
				if (x + y) % 3 == 0:
					world.set_material_state(Vector2i(6 + x, y), 24, 140, 2600)
	if _phase12_view == "oxygen-starved":
		for x in range(-2, 15):
			world.set_material_state(Vector2i(x, 16), 1, 255, 1172)
		world.set_material_state(Vector2i(-2, 17), 1, 255, 1172)
		world.set_material_state(Vector2i(14, 17), 1, 255, 1172)
		for x in range(0, 13):
			world.set_material_state(Vector2i(x, 17), 21, 220, 2300)
	if _phase12_view in ["charcoal", "charcoal-kiln"]:
		for x in range(40, 49):
			world.set_material_state(Vector2i(x, 17), 23, 96, 2100)

	camera.position = Vector2(0, 5) * renderer.cell_pixel_size
	zoom_index = 4


func _configure_phase12_view() -> void:
	if _phase12_view.is_empty():
		return
	if _phase12_view == "temperature-overlay":
		_on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
	if _phase12_view == "diagnostics":
		diagnostics_visible = true
		diagnostics_panel.visible = true
		overlay.set_chunk_debug(true)
	if _phase12_view == "factory-organic":
		factory_hud.toggle_statistics()


func _configure_phase13_view() -> void:
	if _phase13_view.is_empty():
		return
	if _phase13_view == "pause-menu":
		_player_session_active = true
		_world_name = "Phase 13 Verification"
		_open_pause_menu()
	elif _phase13_view == "components" and _phase136_view.is_empty():
		factory_hud.show_notification("Six editable physical blueprints · no recipe identity")


func _configure_phase135_capture_source() -> void:
	match _phase135_view:
		"main-menu", "new-game", "save-browser": _phase11_view = "new-game"
		"character-gameplay", "full-character-factory": _phase11_view = "character-factory"
		"creative-gameplay": _phase11_view = "creative-normal"
		"diagnostic-furnace": _phase13_view = "furnace"
		"diagnostic-sluice": _phase13_view = "wet-sluice"
		"diagnostic-screen": _phase13_view = "screen"
		"temperature-overlay": _phase12_view = "temperature-overlay"
		"power-overlay": _phase10_view = "power-factory-wide"
		"settings": _phase13_view = "pause-menu"
		"components", "component-ghosts": _phase13_view = "components"
		_: _phase13_view = "full-game"


func _configure_phase136_capture_source() -> void:
	match _phase136_view:
		"main-menu", "main-menu-continue", "new-game", "mode-factory", "mode-character", "mode-creative", "save-browser":
			_phase11_view = "new-game"
		"character-spawn": _phase11_view = "character-spawn"
		"character-exploration": _phase11_view = "character-cave"
		"character-jetpack": _phase11_view = "jetpack"
		"character-hover-build": _phase11_view = "character-hover"
		"character-factory", "full-game-character": _phase11_view = "character-normal"
		"factory-start", "quickbar": _phase11_view = "factory-normal"
		"factory-midgame", "full-game-factory", "production-flow": _phase11_view = "full-game"
		"factory-powered", "inspector-power", "power-overlay": _phase10_view = "first-grid"
		"creative": _phase11_view = "creative-normal"
		"build-catalog": _phase11_view = "build-catalog"
		"build-ghosts", "component-world": _phase13_view = "components"
		"research": _phase11_view = "research"
		"codex-material", "codex-component": _phase13_view = "full-game"
		"inspector-screen": _phase13_view = "screen"
		"inspector-furnace", "physical-furnace": _phase13_view = "furnace"
		"blueprints", "custom-blueprint", "current-goal", "experiments", "planning-pause", "pause-menu", "settings": _phase13_view = "full-game"
		"map-character": _phase11_view = "character-stale-map"
		"map-factory": _phase11_view = "factory-normal"
		"temperature": _phase12_view = "temperature-overlay"
		"tree-world": _phase12_view = "tree-falling"
		"fire": _phase12_view = "wood-burning"
		"water": _phase7_view = "waterfall"
		"steam": _phase9_view = "steam-render"
		"wet-separation": _phase13_view = "wet-sluice"
		"diagnostics": _phase11_view = "diagnostics"
		"full-game-megafactory": _realistic_max_factory_benchmark = true
		_: _phase13_view = "full-game"


func _configure_phase135_view() -> void:
	if _phase135_view.is_empty():
		return
	match _phase135_view:
		"main-menu", "new-game":
			if _new_game_screen != null:
				_new_game_screen.set_saved_worlds([])
		"save-browser":
			if _new_game_screen != null:
				_new_game_screen.set_saved_worlds([{"world_name":"Riverside Works", "timestamp_utc":"2026-08-29T10:42:00Z", "primary_valid":true, "recoverable":false, "playtime_seconds":3278, "seed":8675309, "mode":1, "save_schema_version":3, "game_version":BuildInfo.VERSION}, {"world_name":"Old Foundry", "timestamp_utc":"2026-08-29T09:12:00Z", "primary_valid":false, "recoverable":true, "primary_error":"CHECKSUM_MISMATCH", "playtime_seconds":1880, "seed":13575, "mode":0, "save_schema_version":3, "game_version":BuildInfo.VERSION}])
		"codex-material": _open_codex("material:raw_sand")
		"codex-component": _open_codex("component:41")
		"diagnostic-screen": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-2, 16))
		"diagnostic-furnace": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-5, 15))
		"diagnostic-sluice": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-2, 15))
		"planning-pause": _set_planning_paused(true)
		"blueprint-library": _toggle_blueprint_library()
		"custom-blueprint":
			_blueprints.copy_to_clipboard(MvpExampleBlueprints.basic_furnace())
			_save_clipboard_blueprint("My Furnace")
			_toggle_blueprint_library()
		"current-milestone": factory_hud.set_current_goal("Establish a Powered Factory", ["Generate Steam", "Drive a shaft", "Supply stable electrical power"])
		"experiments": _toggle_experiments()
		"temperature-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
		"production-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.PRODUCTION)
		"power-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.POWER)
		"diagnostics-export":
			_export_diagnostics()
			factory_hud.show_notification("Local diagnostics ZIP created · nothing uploaded")
		"settings":
			if _pause_menu != null and not _pause_menu.visible: _open_pause_menu()
		"component-ghosts":
			var cells: Array[Vector2i] = []
			for x in range(8): cells.append(Vector2i(-4 + x, 3))
			overlay.set_structure_preview(cells, true, 14, 1, ["Fluid input", "Fluid output", "Automation"])


func _phase136_saved_worlds() -> Array[Dictionary]:
	return [{"world_name":"Riverside Works", "timestamp_utc":"2026-08-29T10:42:00Z", "primary_valid":true, "recoverable":false, "playtime_seconds":3278, "seed":8675309, "mode":1, "save_schema_version":3, "game_version":BuildInfo.VERSION}, {"world_name":"Old Foundry", "timestamp_utc":"2026-08-29T09:12:00Z", "primary_valid":false, "recoverable":true, "primary_error":"CHECKSUM_MISMATCH", "playtime_seconds":1880, "seed":13575, "mode":0, "save_schema_version":3, "game_version":BuildInfo.VERSION}]


func _configure_phase136_view() -> void:
	if _phase136_view.is_empty():
		return
	match _phase136_view:
		"main-menu", "new-game":
			if _new_game_screen != null: _new_game_screen.set_saved_worlds([])
		"main-menu-continue", "save-browser":
			if _new_game_screen != null: _new_game_screen.set_saved_worlds(_phase136_saved_worlds())
		"mode-factory":
			if _new_game_screen != null: _new_game_screen.select_preset(GameModeCapabilities.Preset.FACTORY)
		"mode-character":
			if _new_game_screen != null: _new_game_screen.select_preset(GameModeCapabilities.Preset.CHARACTER)
		"mode-creative":
			if _new_game_screen != null: _new_game_screen.select_preset(GameModeCapabilities.Preset.CREATIVE)
		"character-spawn", "character-exploration", "character-jetpack", "character-hover-build", "character-factory", "full-game-character":
			_set_camera_zoom_index(6)
		"codex-material": _open_codex("material:raw_sand")
		"codex-component": _open_codex("component:41")
		"inspector-screen": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-2, 16))
		"inspector-furnace": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-5, 15))
		"inspector-power": _phase135_capture_inspector = PhysicalInspector.inspect(world, materials, Vector2i(-43, -2))
		"build-ghosts":
			var cells: Array[Vector2i] = []
			for x in range(8): cells.append(Vector2i(-4 + x, 3))
			overlay.set_structure_preview(cells, true, 14, 1, ["Fluid input", "Fluid output", "Automation"])
		"blueprints": _toggle_blueprint_library()
		"custom-blueprint":
			_blueprints.copy_to_clipboard(MvpExampleBlueprints.basic_furnace())
			_save_clipboard_blueprint("Compact Furnace")
			_toggle_blueprint_library()
		"current-goal": factory_hud.set_current_goal("Establish powered production", ["Generate steam", "Drive a shaft", "Supply stable power"])
		"experiments": _toggle_experiments()
		"map-factory": _toggle_world_map()
		"temperature": _on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
		"production-flow": _on_overlay_selected(MapOverlayRenderer.Mode.PRODUCTION)
		"power-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.POWER)
		"planning-pause": _set_planning_paused(true)
		"pause-menu", "settings":
			_player_session_active = true
			_world_name = "Riverside Works"
			_open_pause_menu()
		"diagnostics":
			diagnostics_visible = true
			diagnostics_panel.visible = true
	factory_hud.show_alert("")


func _build_phase11_showcase() -> void:
	var center := Vector2i(world.get_character_spawn())
	match _phase11_view:
		"surface", "factory-mode", "factory-normal", "creative-normal", "character-spawn", "character-normal", "character-vision", "jetpack", "hover", "character-hover", "character-factory", "character-building", "character-map", "character-stale-map", "character-overview", "full-game", "build-catalog", "research", "blueprint-preview", "info-mode", "statistics", "overlay", "overview", "diagnostics", "new-game", "world-preview":
			center = world.get_character_spawn()
		"character-cave", "character-cave-reveal", "cavern":
			center = Vector2i(520, 740)
		"aquifer", "discovered-map":
			center = Vector2i(-650, 980)
		"deep-thermal":
			center = Vector2i(1050, 1900)
		"worldgen-debug":
			center = Vector2i(320, 620)
		"feature-ruin":
			center = Vector2i(760, 520)
	_phase11_character_cell = center
	var center_chunk := Vector2i(floori(center.x / 64.0), floori(center.y / 64.0))
	world.request_chunk_region(Rect2i(center_chunk - Vector2i(6, 4), Vector2i(13, 9)), 0)
	world.flush_generation()
	if _phase11_view in ["factory-mode", "factory-normal", "creative-normal", "character-factory", "character-normal", "character-building", "character-map", "character-stale-map", "full-game", "build-catalog", "research", "blueprint-preview", "info-mode", "statistics", "overlay", "overview", "character-overview", "diagnostics"]:
		var previous_mode: int = int(world.get_game_mode())
		world.set_game_mode(1)
		var floor_y := center.y + 12
		world.fill_rect(Rect2i(center.x - 86, floor_y, 172, 2), 1)
		world.place_conveyor_line(Vector2i(center.x - 70, floor_y - 2), Vector2i(center.x + 70, floor_y - 2), 1)
		for entry in [[6, -42], [7, -6], [5, 34], [8, 64]]:
			world.place_structure(int(entry[0]), Vector2i(center.x + int(entry[1]), floor_y - 8), 0)
		world.place_structure(29, Vector2i(center.x + 18, floor_y - 12), 0)
		world.place_structure(34, Vector2i(center.x + 25, floor_y - 10), 0)
		world.set_game_mode(previous_mode)
	if _phase11_view == "feature-ruin":
		var previous_mode: int = int(world.get_game_mode())
		world.set_game_mode(1)
		world.fill_rect(Rect2i(center - Vector2i(42, 24), Vector2i(84, 48)), 0)
		for x in range(center.x - 34, center.x + 35):
			world.set_cell(Vector2i(x, center.y + 18), 1)
		world.place_pipe_line(center + Vector2i(-30, 8), center + Vector2i(14, 8))
		world.damage_pipe(center + Vector2i(-4, 8), 1000, 3)
		world.place_structure(29, center + Vector2i(22, 5), 0)
		world.set_game_mode(previous_mode)
	world.finalize_initialization()
	camera.position = Vector2(center) * renderer.cell_pixel_size
	zoom_index = 3 if _phase11_view not in ["character-overview", "overview", "worldgen-debug"] else 1


func _build_phase10_showcase() -> void:
	world.fill_rect(Rect2i(-180, -90, 360, 180), MaterialRegistry.EMPTY_ID)
	for x in range(-170, 171):
		world.set_material_state(Vector2i(x, 58), 1, 255, 1173)
	_build_phase10_power_train(Vector2i(-72, -12), false)
	_build_phase10_power_train(Vector2i(-72, 22), _phase10_view == "backpressure")
	# A switched low-priority wing: separate pole components joined only by the switch.
	world.place_structure(29, Vector2i(-43, -2), 0)
	world.place_structure(30, Vector2i(-31, -2), 0)
	world.place_structure(29, Vector2i(-17, -2), 0)
	world.place_structure(34, Vector2i(-14, -5), 0)
	world.configure_power_structure(Vector2i(-14, -5), {"priority": 3})
	world.configure_power_structure(Vector2i(-31, -2), {"closed": _phase10_view not in ["brownout", "load-shedding"]})
	var power_sensor := int(world.create_automation_component(22, Vector2i(12, -18), {"mode": 0, "target_position": Vector2i(-43, -2)}))
	var shaft_sensor := int(world.create_automation_component(23, Vector2i(24, -18), {"target_position": Vector2i(-64, -10)}))
	var comparator := int(world.create_automation_component(5, Vector2i(36, -18), {"threshold": 750}) )
	var switch_control := int(world.create_automation_component(24, Vector2i(48, -18), {"target_position": Vector2i(-31, -2)}))
	world.create_automation_connection(power_sensor, 0, comparator, 0)
	world.create_automation_connection(comparator, 0, switch_control, 0)
	world.create_automation_connection(shaft_sensor, 0, comparator, 1)
	if _phase10_view in ["factory", "power-factory-wide", "closed-steam-cycle"]:
		for row in 3:
			var y := 62 + row * 4
			world.place_conveyor_line(Vector2i(-145, y), Vector2i(145, y), 1 if row % 2 == 0 else -1)
		for x in range(15, 116, 8):
			world.place_structure([6, 7, 14][int(x / 8) % 3], Vector2i(x, 20 + (x % 4)), 0)
			world.configure_power_structure(Vector2i(x, 20 + (x % 4)), {"electric_drive": true, "priority": 2})
		for x in range(0, 121, 20): world.place_structure(29, Vector2i(x, 16), 0)
	world.finalize_initialization()
	camera.position = Vector2(-15, 12) * renderer.cell_pixel_size
	zoom_index = 5 if _phase10_view not in ["overview", "power-factory-wide"] else 2


func _build_phase10_power_train(origin: Vector2i, blocked_exhaust: bool) -> void:
	world.place_structure(27, origin, 0)
	world.place_pipe_line(origin + Vector2i(-1, 1), origin + Vector2i(-1, 1))
	world.set_pipe_fluid(origin + Vector2i(-1, 1), 17, 30000, 2200)
	world.place_pipe_line(origin + Vector2i(6, 1), origin + Vector2i(6, 1))
	if blocked_exhaust: world.set_pipe_fluid(origin + Vector2i(6, 1), 17, 65000, 3000)
	world.place_mechanical_shaft_line(origin + Vector2i(6, 2), origin + Vector2i(13, 2))
	if origin.y > 0: world.place_structure(33, origin + Vector2i(9, 3), 1)
	world.place_structure(28, origin + Vector2i(14, 0), 0)
	world.place_structure(29, origin + Vector2i(20, 2), 0)
	world.place_structure(31, origin + Vector2i(24, 0), 0)
	world.place_structure(34, origin + Vector2i(29, 0), 0)
	world.configure_power_structure(origin + Vector2i(29, 0), {"priority": 1})
	for x in range(origin.x - 2, origin.x + 34): world.set_material_state(Vector2i(x, origin.y + 7), 1, 255, 1173)


func _configure_phase10_view() -> void:
	if _phase10_view.is_empty(): return
	if _phase10_view in ["power-overlay", "first-grid", "brownout", "load-shedding", "power-factory-wide"]:
		_on_overlay_selected(MapOverlayRenderer.Mode.POWER)
	if _phase10_view in ["automation", "load-shedding"]: automation_renderer.set_wiring_mode(true)
	if _phase10_view in ["factory", "power-factory-wide"]: factory_hud.toggle_statistics()
	if _phase10_view == "diagnostics":
		diagnostics_visible = true
		diagnostics_panel.visible = true
	if _phase10_view == "overview":
		structure_renderer.set_overview_mode(true)
		renderer.visible = false
		overlay.visible = false
		automation_renderer.visible = false


func _configure_phase11_view() -> void:
	if _phase11_view.is_empty():
		return
	if _phase11_view in ["worldgen-debug", "diagnostics"]:
		diagnostics_visible = true
		diagnostics_panel.visible = true
		overlay.set_chunk_debug(true)
	if _phase11_view == "worldgen-debug":
		overlay.set_geology_heatmap(true)
	if _phase11_view in ["character-overview", "discovered-map"]:
		structure_renderer.set_overview_mode(true)
	if _phase11_view in ["hover", "character-hover"]:
		world.set_game_mode(1)
		world.credit_research_material_for_test(10, 10000)
		world.credit_research_material_for_test(11, 1000)
		world.credit_research_material_for_test(12, 10)
		world.set_game_mode(0)
		world.try_unlock_research("mobility.sprint")
		world.try_unlock_research("automation.basic_sensing")
		world.try_unlock_research("mobility.hover")
	if _phase11_view in ["factory-mode", "character-factory"]:
		factory_hud.toggle_statistics()
	if _phase11_view == "build-catalog":
		factory_hud.toggle_catalog()
	if _phase11_view == "research":
		_toggle_research()
	if _phase11_view == "statistics":
		factory_hud.toggle_statistics()
	if _phase11_view == "info-mode":
		_info_mode = true
		factory_hud.set_info_mode(true)
		overlay.set_info_mode(true, _expanded_chunk_rect(_visible_chunk_rect, 1))
	if _phase11_view == "overlay":
		_on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
	if _phase11_view in ["overview", "character-overview"]:
		structure_renderer.set_overview_mode(true)
	if _phase11_view in ["character-building", "blueprint-preview"]:
		var preview_origin := _phase11_character_cell + Vector2i(8, -5)
		var preview_cells: Array[Vector2i] = []
		for x in range(9): preview_cells.append(preview_origin + Vector2i(x, 0))
		overlay.set_structure_preview(preview_cells, true)


func _create_character() -> void:
	if _character != null:
		_character.queue_free()
	_character = KoalaCharacterController.new()
	_character.name = "Character"
	_character.z_index = 34
	add_child(_character)
	_character.initialize(world, camera, _phase11_character_cell, renderer.cell_pixel_size, _command_bus)
	if _phase11_view in ["jetpack", "hover", "character-hover"]:
		_character.position_milli -= Vector2i(0, 22 * KoalaCharacterController.MILLI)
		_character.position = Vector2(_character.position_milli) / KoalaCharacterController.MILLI * renderer.cell_pixel_size
	if _phase11_view in ["hover", "character-hover"]:
		_character._refresh_unlocks()
		_character.hover_active = true
		_character.debug_input_override = 0
	elif _phase11_view == "jetpack":
		_character.debug_input_override = KoalaCharacterController.INPUT_JETPACK | KoalaCharacterController.INPUT_RIGHT
	_character.discovery_updated.connect(func() -> void:
		if _visibility_renderer != null:
			_visibility_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1), true)
	)
	_create_character_hud()
	if _phase11_view == "character-stale-map":
		world.update_character_visibility(
			KoalaCharacterController.VISIBILITY_OWNER_ID,
			_phase11_character_cell + Vector2i(80, -2),
			KoalaCharacterController.VISIBILITY_RADIUS,
			KoalaCharacterController.SOLID_SHELL_DEPTH
		)
	if _phase11_view in ["character-map", "character-stale-map"]:
		call_deferred("_toggle_world_map")


func _create_character_hud() -> void:
	var existing := get_node_or_null("HUD/CharacterHUD") as Control
	if existing != null:
		existing.queue_free()
	var panel := PanelContainer.new()
	panel.name = "CharacterHUD"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(18, -130)
	panel.custom_minimum_size = Vector2(300, 52)
	panel.theme = KoalaSandTheme.build()
	panel.theme_type_variation = "HudPanel"
	var label := Label.new()
	_character_hud_label = label
	_update_character_hud()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("d8e5d6"))
	panel.add_child(label)
	$HUD.add_child(panel)


func _update_character_hud() -> void:
	if _character_hud_label == null or _character == null:
		return
	var mobility: Array[String] = []
	if _character.jetpack_active: mobility.append("JETPACK")
	if _character.hover_active: mobility.append("HOVER")
	if _character.sprint_unlocked: mobility.append("SPRINT")
	var mobility_text := " · ".join(mobility) if not mobility.is_empty() else "Mobility ready"
	_character_hud_label.text = "%s  ·  %s\n1 Dig   2 Cut   3 Build" % [_character.active_tool_name().capitalize(), mobility_text]


func _show_new_game_screen() -> void:
	if _new_game_screen != null:
		return
	_new_game_screen = NewGameScreen.new()
	_new_game_screen.name = "NewGameScreen"
	$HUD.add_child(_new_game_screen)
	_new_game_screen.set_seed(_world_seed)
	_new_game_screen.start_requested.connect(_start_phase11_game)
	_new_game_screen.continue_requested.connect(_continue_world)
	_new_game_screen.delete_requested.connect(_delete_world)
	_new_game_screen.recovery_requested.connect(_recover_world_backup)
	_new_game_screen.diagnostics_requested.connect(_export_diagnostics)
	_new_game_screen.set_saved_worlds(_save_manager.inspect_worlds())


func _start_phase11_game(preset_id: int, seed: int, world_name: String) -> void:
	_game_session.apply_preset(preset_id)
	_world_seed = seed
	_world_name = world_name
	_playtime_seconds = 0.0
	_autosave_elapsed = 0.0
	_player_session_active = true
	_phase11_view = ["factory-mode", "character-spawn", "creative-mode"][preset_id]
	if _new_game_screen != null:
		_new_game_screen.queue_free()
		_new_game_screen = null
	_regenerate_world()
	_visibility_renderer.initialize(world, KoalaCharacterController.VISIBILITY_OWNER_ID, renderer.cell_pixel_size)
	_visibility_renderer.set_discovery_enabled(_game_session.visibility_policy == GameModeCapabilities.VisibilityPolicy.DISCOVERED)
	if _game_session.control_mode == GameModeCapabilities.ControlMode.CHARACTER:
		_create_character()
	clock.set_speed(1)


func _create_pause_menu() -> void:
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	$HUD.add_child(_pause_menu)
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.save_requested.connect(_save_named_world)
	_pause_menu.return_to_menu_requested.connect(_save_and_return_to_menu)
	_pause_menu.exit_requested.connect(_save_and_exit)
	_pause_menu.diagnostics_requested.connect(_export_diagnostics)

func _create_phase135_player_ui() -> void:
	_codex_panel = CodexPanel.new(); _codex_panel.name = "PhysicsCodex"; $HUD.add_child(_codex_panel); _codex_panel.initialize(_physics_codex)
	_codex_panel.closed.connect(func(): factory_hud.set_external_modal("codex", false))
	_experiments_panel = ExperimentsPanel.new(); _experiments_panel.name = "Experiments"; $HUD.add_child(_experiments_panel); _experiments_panel.initialize(_experiment_tracker)
	_blueprint_panel = BlueprintLibraryPanel.new(); _blueprint_panel.name = "BlueprintLibrary"; $HUD.add_child(_blueprint_panel); _blueprint_panel.initialize(_blueprints)
	_blueprint_panel.blueprint_selected.connect(_select_library_blueprint)
	_blueprint_panel.save_clipboard_requested.connect(_save_clipboard_blueprint)
	_audio_mixer = AudioEventMixer.new(); _audio_mixer.name = "CentralAudioMixer"; add_child(_audio_mixer)
	_feedback_renderer = PhysicalFeedbackRenderer.new(); _feedback_renderer.name = "PhysicalFeedback"; _feedback_renderer.z_index = 45; _feedback_renderer.cell_pixel_size = renderer.cell_pixel_size; add_child(_feedback_renderer)


func _run_owner_package_smoke() -> void:
	var smoke := {"new_character":false, "build":false, "save":false, "exit":false, "continue":false, "codex":false, "settings":false, "planning_pause":false, "factory":false, "creative":false, "diagnostics":false}
	_start_phase11_game(GameModeCapabilities.Preset.CHARACTER, 13602, "Owner Smoke")
	smoke.new_character = _character != null and _game_session.preset_id == GameModeCapabilities.Preset.CHARACTER
	world.set_game_mode(1)
	smoke.build = world.place_structure(37, _phase11_character_cell + Vector2i(5, 0), 0) > 0
	world.set_game_mode(0)
	var save_result := _save_current_world(false)
	smoke.save = bool(save_result.get("ok", false))
	smoke.exit = _save_manager.inspect_worlds().any(func(metadata: Dictionary) -> bool: return str(metadata.get("world_name", "")) == "Owner Smoke" and bool(metadata.get("primary_valid", false)))
	_continue_world("Owner Smoke")
	smoke.continue = _world_name == "Owner Smoke" and _player_session_active
	_open_codex("material:raw_sand")
	smoke.codex = _codex_panel != null and _codex_panel.visible
	_set_planning_paused(true)
	smoke.planning_pause = _planning_paused and clock.speed_multiplier == 0
	_open_pause_menu()
	smoke.settings = _pause_menu != null and _pause_menu.visible
	_game_session.apply_preset(GameModeCapabilities.Preset.FACTORY)
	factory_hud.configure_mode(_game_session.preset_id)
	smoke.factory = _game_session.preset_id == GameModeCapabilities.Preset.FACTORY
	_game_session.apply_preset(GameModeCapabilities.Preset.CREATIVE)
	factory_hud.configure_mode(_game_session.preset_id)
	smoke.creative = _game_session.preset_id == GameModeCapabilities.Preset.CREATIVE
	var diagnostic := _diagnostics_exporter.export_report(world, _pause_menu.settings(), {"smoke":true}, [])
	smoke.diagnostics = bool(diagnostic.get("ok", false))
	_save_manager.delete_world("Owner Smoke", true)
	var ok := smoke.values().all(func(value: Variant) -> bool: return bool(value))
	print("owner_package_smoke %s" % " ".join(smoke.keys().map(func(key: Variant) -> String: return "%s=%d" % [key, 1 if bool(smoke[key]) else 0])))
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	if _audio_mixer != null:
		_audio_mixer.shutdown()
		_audio_mixer.queue_free()
		_audio_mixer = null
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if ok else 1)

func _open_codex(entry_id := "") -> void:
	if _codex_panel == null: return
	_codex_panel.open_entry(entry_id)
	factory_hud.set_external_modal("codex", true)
	_audio_mixer.play_ui(&"click")

func _toggle_experiments() -> void:
	if _experiments_panel == null: return
	_experiments_panel.visible = not _experiments_panel.visible
	if _experiments_panel.visible: _experiments_panel.refresh()
	factory_hud.set_external_modal("experiments", _experiments_panel.visible)

func _toggle_blueprint_library() -> void:
	if _blueprint_panel == null: return
	_blueprint_panel.visible = not _blueprint_panel.visible
	if _blueprint_panel.visible: _blueprint_panel.refresh()
	factory_hud.set_external_modal("blueprints", _blueprint_panel.visible)

func _select_library_blueprint(blueprint: BlueprintDefinition) -> void:
	_blueprints.copy_to_clipboard(blueprint)
	_blueprint_turns = 0; _blueprint_flip_h = false; _blueprint_flip_v = false
	_blueprint_panel.visible = false; factory_hud.set_external_modal("blueprints", false)
	factory_hud.show_notification("Blueprint ready: %s · %d Components" % [blueprint.display_name, blueprint.entries.size()])

func _save_clipboard_blueprint(display_name: String) -> void:
	var source := _blueprints.clipboard()
	if source == null or display_name.is_empty():
		factory_hud.show_notification("Copy Components, then enter a Blueprint name")
		return
	var custom := BlueprintDefinition.deserialize(source.serialize())
	custom.blueprint_id = "player_%s_%s" % [display_name.to_snake_case(), custom.content_hash().left(8)]
	custom.display_name = display_name
	custom.description = "Player Blueprint · editable ordinary Components"
	_blueprints.save(custom); _physics_codex.rebuild(materials, world, _blueprints); _codex_panel.initialize(_physics_codex); _blueprint_panel.refresh()
	factory_hud.show_notification("Saved Blueprint: %s" % display_name)
	_audio_mixer.play_ui(&"confirm")

func _set_planning_paused(paused: bool) -> void:
	_planning_paused = paused
	clock.set_paused(paused)
	if _character != null: _character.set_simulation_paused(paused)
	factory_hud.set_planning_paused(paused)
	if _audio_mixer != null: _audio_mixer.set_planning_paused(paused)
	factory_hud.show_notification("Planning Pause · physics frozen" if paused else "Simulation resumed")

func _pipette_at_cursor() -> void:
	var cell := _mouse_world_cell()
	if _character != null and not world.is_cell_live_visible(KoalaCharacterController.VISIBILITY_OWNER_ID, cell):
		factory_hud.show_context_hint("pipette_unknown", "Pipette requires a live-visible Component.")
		return
	var copied := ConstructionPlanner.pipette(world, cell)
	if copied.is_empty():
		factory_hud.show_notification("No Component to Pipette")
		return
	build_structure_orientation = int(copied.orientation)
	_select_structure(int(copied.type_id))
	factory_hud.show_notification("Pipette: %s" % str(ComponentPresentation.describe(int(copied.type_id), _structure_definitions.get(int(copied.type_id), {})).name))

func _export_diagnostics() -> void:
	var performance := {"simulation_latest_ms":_simulation_latest_ms, "render_ms":renderer.last_update_ms, "hud_ms":factory_hud.last_update_ms, "audio":_audio_mixer.statistics() if _audio_mixer != null else {}, "vfx_ms":_feedback_renderer.last_update_ms if _feedback_renderer != null else 0.0}
	var result := _diagnostics_exporter.export_report(world, _pause_menu.settings() if _pause_menu != null else {}, performance, [])
	if factory_hud != null: factory_hud.show_notification("Diagnostics exported: %s" % str(result.get("filename", result.get("error", "FAILED"))))
	if _audio_mixer != null: _audio_mixer.play_ui(&"confirm" if bool(result.get("ok", false)) else &"save_error")

func _update_phase135_feedback() -> void:
	if _audio_mixer == null: return
	var structure: Dictionary = world.get_structure_statistics()
	var physical: Dictionary = world.get_physical_processing_statistics()
	var fluid: Dictionary = world.get_fluid_statistics()
	var gas: Dictionary = world.get_gas_statistics()
	var organic: Dictionary = world.get_organic_statistics()
	var pipe: Dictionary = world.get_pipe_statistics()
	var power: Dictionary = world.get_power_statistics()
	var wet: Dictionary = world.get_wet_processing_statistics()
	var machine: Dictionary = world.get_processing_statistics()
	var center := camera.position
	var sources: Array[Dictionary] = [
		{"event":"conveyor", "position":center, "intensity":clampf(float(structure.get("belt_moves", 0)) / 600.0, 0.0, 1.0), "parameter":clampf(float(structure.get("belt_moves", 0)) / 1200.0, 0.0, 1.0), "category":"Machines"},
		{"event":"vibration", "position":center, "intensity":clampf(float(physical.get("vibration_cells", 0)) / 64.0, 0.0, 1.0), "category":"Machines"},
		{"event":"pump", "position":center, "intensity":clampf(float(pipe.get("pump_work", 0)) / 10000.0, 0.0, 1.0), "category":"Machines"},
		{"event":"turbine", "position":center, "intensity":clampf(float(power.get("turbine_output", 0)) / 10000.0, 0.0, 1.0), "category":"Machines"},
		{"event":"generator", "position":center, "intensity":clampf(float(power.get("generation", power.get("electrical_output", 0))) / 10000.0, 0.0, 1.0), "category":"Machines"},
		{"event":"water", "position":center, "intensity":clampf(float(fluid.get("transfers", fluid.get("fluid_cells_moved", 0))) / 2000.0, 0.0, 1.0), "category":"Environment"},
		{"event":"steam", "position":center, "intensity":clampf(float(gas.get("transfers", 0)) / 1000.0, 0.0, 1.0), "category":"Environment"},
		{"event":"fire", "position":center, "intensity":clampf(float(organic.get("reactive_cells", 0)) / 128.0, 0.0, 1.0), "category":"Environment"},
		{"event":"sand", "position":center, "intensity":clampf(float(world.get_statistics().get("cells_moved", 0)) / 3000.0, 0.0, 1.0), "category":"Environment"},
	]
	_audio_mixer.update_aggregated_loops(sources, center, camera.zoom.x)
	var authoritative := {"wet_then_dry_events":wet.get("dried_grains", 0), "heavy_captured":wet.get("heavy_captured", 0), "charcoal_produced":organic.get("charcoal_produced", 0), "vessel_steam_generated":gas.get("steam_generated", 0), "vessel_material_comparisons":machine.get("vessel_material_comparisons", 0), "oxygen_starved_events":organic.get("oxygen_starved", organic.get("oxygen_limited_cells", 0)), "pipe_steam_mass":pipe.get("steam_mass", 0), "modified_furnace_temperature_gain":physical.get("improved_furnace_temperature_gain", 0)}
	for experiment_id: String in _experiment_tracker.observe(authoritative):
		if _phase136_view.is_empty():
			factory_hud.show_notification("Experiment complete: %s" % experiment_id.replace("_", " ").capitalize())
			_audio_mixer.play_ui(&"milestone_complete")
	var milestones: Dictionary = world.get_milestone_state()
	var order := ["first_material_moved", "first_separation", "first_iron", "first_gold", "first_automation", "first_water", "first_steam", "first_power", "stable_power", "powered_factory_established"]
	var labels := ["Move physical material", "Separate by physical properties", "Recover Iron", "Recover Gold", "Build Automation", "Route Water", "Produce Steam", "Generate Power", "Stabilize the grid", "Establish a Powered Factory"]
	for index in order.size():
		if not bool(milestones.get(order[index], false)):
			factory_hud.set_current_goal(labels[index], ["Build", "Observe", "Improve"])
			break
	_last_milestones = milestones


func _open_pause_menu() -> void:
	_pause_menu_was_planning = _planning_paused
	clock.set_paused(true)
	if _character != null: _character.set_simulation_paused(true)
	_pause_menu.open(_world_name)


func _resume_from_pause() -> void:
	_pause_menu.close()
	clock.set_paused(_pause_menu_was_planning)
	if _character != null: _character.set_simulation_paused(_pause_menu_was_planning)
	if _audio_mixer != null:
		_audio_mixer.set_category_volumes(_pause_menu.settings())
		_audio_mixer.set_planning_paused(_pause_menu_was_planning)
	if _feedback_renderer != null: _feedback_renderer.reduced_motion = bool(_pause_menu.settings().get("reduced_motion", false))


func _save_context() -> Dictionary:
	return {
		"playtime_seconds": int(_playtime_seconds),
		"seed": _world_seed,
		"mode": _game_session.preset_id,
		"session": _game_session.serialize(),
		"character": _character.serialize_state() if _character != null else {},
		"hud": factory_hud.serialize_session_state(),
		"blueprints": _blueprints.serialize(),
		"experiments": _experiment_tracker.serialize(),
		"settings": _pause_menu.settings() if _pause_menu != null else {},
		"objectives": world.get_milestone_state(),
		"camera_position": camera.position,
		"zoom_index": zoom_index,
	}


func _save_current_world(background := false) -> Dictionary:
	if not _player_session_active:
		return {"ok": false, "error": "NO_ACTIVE_WORLD"}
	if factory_hud != null: factory_hud.show_notification("Saving…")
	return _save_manager.save_world_async(_world_name, world, _save_context()) if background else _save_manager.save_world(_world_name, world, _save_context())


func _save_named_world(next_name: String) -> void:
	if next_name.is_empty():
		factory_hud.show_notification("World name required")
		return
	_world_name = next_name
	var result := _save_current_world(false)
	factory_hud.show_notification("Saved %s" % _world_name if bool(result.get("ok", false)) else "Save failed: %s" % str(result.get("error", "UNKNOWN")))


func _continue_world(saved_world_name: String) -> void:
	var restored := _save_manager.restore_world(saved_world_name, world)
	if not bool(restored.get("ok", false)):
		return
	var context: Dictionary = restored.context
	if not _game_session.deserialize(Dictionary(context.get("session", {}))):
		return
	_world_name = saved_world_name
	_world_seed = int(restored.metadata.get("seed", _world_seed))
	_playtime_seconds = float(context.get("playtime_seconds", 0))
	_autosave_elapsed = 0.0
	_player_session_active = true
	if context.get("blueprints", null) is PackedByteArray:
		_blueprints.deserialize_state(context.blueprints)
	if context.get("experiments", null) is Dictionary:
		_experiment_tracker.deserialize(context.experiments)
	_physics_codex.rebuild(materials, world, _blueprints)
	_codex_panel.initialize(_physics_codex)
	_blueprint_panel.initialize(_blueprints)
	_experiments_panel.initialize(_experiment_tracker)
	factory_hud.configure_mode(_game_session.preset_id)
	factory_hud.initialize(world)
	if context.get("hud", null) is Dictionary:
		factory_hud.deserialize_session_state(context.hud)
	if context.get("settings", null) is Dictionary:
		_pause_menu.apply_settings(context.settings)
	camera.position = context.get("camera_position", camera.position)
	zoom_index = clampi(int(context.get("zoom_index", zoom_index)), 0, ZOOM_LEVELS.size() - 1)
	_set_camera_zoom_index(zoom_index)
	if _character != null:
		_character.queue_free()
		_character = null
	if _game_session.control_mode == GameModeCapabilities.ControlMode.CHARACTER:
		_create_character()
		if context.get("character", null) is Dictionary:
			_character.deserialize_state(context.character)
	_cache_structure_definitions()
	renderer.initialize(world)
	structure_renderer.initialize(world)
	automation_renderer.initialize(world)
	if _new_game_screen != null:
		_new_game_screen.queue_free()
		_new_game_screen = null
	clock.set_speed(1)
	if bool(restored.get("recovered_from_backup", false)):
		factory_hud.show_notification("Recovered world from backup")


func _delete_world(saved_world_name: String) -> void:
	_save_manager.delete_world(saved_world_name, true)
	if _new_game_screen != null:
		_new_game_screen.set_saved_worlds(_save_manager.inspect_worlds())

func _recover_world_backup(saved_world_name: String) -> void:
	var result := _save_manager.restore_backup(saved_world_name)
	if _new_game_screen != null: _new_game_screen.set_saved_worlds(_save_manager.inspect_worlds())
	if factory_hud != null: factory_hud.show_notification("Backup restored: %s" % saved_world_name if bool(result.get("ok", false)) else "Recovery failed: %s" % str(result.get("error", "UNKNOWN")))


func _save_and_return_to_menu() -> void:
	var result := _save_current_world(false)
	if not bool(result.get("ok", false)):
		factory_hud.show_notification("Save failed: %s" % str(result.get("error", "UNKNOWN")))
		return
	_player_session_active = false
	_pause_menu.close()
	clock.set_paused(true)
	_show_new_game_screen()


func _save_and_exit() -> void:
	var result := _save_current_world(false)
	if not bool(result.get("ok", false)):
		factory_hud.show_notification("Save failed: %s" % str(result.get("error", "UNKNOWN")))
		return
	_save_manager.finish_async_save()
	if _audio_mixer != null:
		_audio_mixer.shutdown()
		_audio_mixer.queue_free()
		_audio_mixer = null
		# Let the audio server consume the stopped voices before engine teardown.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _is_normal_player_launch() -> bool:
	return _capture_path.is_empty() and _runtime_benchmark_ticks < 0 and _validate_seeds == 0 and not _owner_package_smoke and not _creative_fixture and not _dense_factory_benchmark and not _realistic_max_factory_benchmark and not _dense_progression_benchmark and not _dense_automation_benchmark and not _dense_physical_benchmark and not _dense_water_benchmark and not _dense_phase8_benchmark and _phase85_render_benchmark.is_empty() and _phase875_view.is_empty() and _phase4_view.is_empty() and _phase5_view == "primitive" and _phase6_view.is_empty() and _phase65_view.is_empty() and _phase7_view.is_empty() and _phase8_view.is_empty() and _phase9_view.is_empty() and _phase10_view.is_empty() and _phase11_view.is_empty() and _phase12_view.is_empty() and _phase13_view.is_empty() and _phase135_view.is_empty() and _phase136_view.is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _player_session_active:
			_save_current_world(false)
		_save_manager.finish_async_save()
		get_tree().quit(0)

func _build_phase9_showcase() -> void:
	world.fill_rect(Rect2i(-160, -100, 320, 210), MaterialRegistry.EMPTY_ID)
	for x in range(-150, 151): world.set_material_state(Vector2i(x, 80), 1, 255, 1173)
	match _phase9_view:
		"ice-melt":
			for y in range(10, 48):
				for x in range(-55, -35): world.set_material_state(Vector2i(x, y), 16, 255, 700)
			for y in range(10, 48): world.set_material_state(Vector2i(-34, y), 1, 255, 9000)
			for x in range(-56, 18): world.set_material_state(Vector2i(x, 55 + (x + 56) / 8), 1, 255, 1173)
			camera.position = Vector2(-25, 35) * renderer.cell_pixel_size; zoom_index = 3
		"steam-cycle":
			for x in range(-55, 56):
				world.set_material_state(Vector2i(x, 60), 1, 255, 8500)
				world.set_material_state(Vector2i(x, -35), 1, 255, 400)
			for y in range(35, 60):
				for x in range(-50, 51): world.set_material_state(Vector2i(x, y), 3, 255, 1300)
			camera.position = Vector2(0, 15) * renderer.cell_pixel_size; zoom_index = 2
		"steam-render":
			# Phase-9.5 rendering fixture: genuinely active Steam covers the 1080p view.
			world.allocate_chunk_rect(Rect2i(-8, -5, 16, 10))
			world.fill_pattern_state(Rect2i(-512, -288, 1024, 576), 17, 96, 192, 6000, 6000)
			camera.position = Vector2.ZERO; zoom_index = 1
		"steam-pipe":
			world.place_pipe_line(Vector2i(-75, 15), Vector2i(75, 15))
			for x in range(-75, 76): world.set_pipe_fluid(Vector2i(x, 15), 17, 24000 + ((x + 75) % 3) * 8000, 1900)
			world.remove_structure_at(Vector2i(35, 15)); world.place_structure(15, Vector2i(35, 15), 0)
			world.create_automation_component(19, Vector2i(-25, 5), {"target_position": Vector2i(-25, 15)})
			world.create_automation_component(20, Vector2i(10, 5), {"target_position": Vector2i(10, 15)})
			camera.position = Vector2(0, 15) * renderer.cell_pixel_size; zoom_index = 2
		"pipe-failure":
			world.place_pipe_line(Vector2i(-60, 10), Vector2i(60, 10))
			for x in range(-60, 61): world.set_pipe_fluid(Vector2i(x, 10), 17, 65535, 3000)
			camera.position = Vector2(0, 5) * renderer.cell_pixel_size; zoom_index = 2
		"molten-glass", "molten-iron":
			var molten := 18 if _phase9_view == "molten-glass" else 19
			for x in range(-70, 35): world.set_material_state(Vector2i(x, 58 + (x + 70) / 10), 1, 255, 1173)
			for y in range(5, 45):
				for x in range(-65, -35): world.set_material_state(Vector2i(x, y), molten, 255, 8500)
			for y in range(55, 75):
				for x in range(20, 55): world.set_material_state(Vector2i(x, y), 1, 255, 400)
			camera.position = Vector2(-10, 35) * renderer.cell_pixel_size; zoom_index = 2
		"water-molten":
			for y in range(40, 70):
				for x in range(-60, 1): world.set_material_state(Vector2i(x, y), 3, 255, 1300)
			for y in range(5, 50):
				for x in range(10, 45): world.set_material_state(Vector2i(x, y), 19, 255, 9500)
			camera.position = Vector2(-5, 35) * renderer.cell_pixel_size; zoom_index = 2
		"automation":
			world.set_material_state(Vector2i(-12, 25), 1, 255, 8500)
			world.set_material_state(Vector2i(-10, 25), 1, 255, 600)
			world.place_structure(24, Vector2i(-11, 25))
			var sensor := int(world.create_automation_component(18, Vector2i(-20, 5), {"target_position": Vector2i(-12, 25)}))
			var comparator := int(world.create_automation_component(5, Vector2i(-5, 5), {"threshold": 4000}))
			var control := int(world.create_automation_component(21, Vector2i(10, 5), {"target_position": Vector2i(-11, 25)}))
			world.create_automation_connection(sensor, 0, comparator, 0)
			world.create_automation_connection(comparator, 0, control, 0)
			camera.position = Vector2(-5, 15) * renderer.cell_pixel_size; zoom_index = 3
		_:
			_build_phase9_factory()
	world.finalize_initialization()

func _build_phase9_factory() -> void:
	for x in range(-130, 131): world.set_material_state(Vector2i(x, 70), 1, 255, 1173)
	for y in range(40, 70):
		for x in range(-125, -85): world.set_material_state(Vector2i(x, y), 3, 255, 1300)
	for y in range(25, 60):
		for x in range(-78, -55): world.set_material_state(Vector2i(x, y), 16, 255, 700)
	for y in range(-10, 28):
		for x in range(-45, -10): world.set_material_state(Vector2i(x, y), 17, 128, 1850)
	for y in range(35, 65):
		for x in range(8, 30): world.set_material_state(Vector2i(x, y), 18, 192, 8000)
	for y in range(28, 65):
		for x in range(38, 60): world.set_material_state(Vector2i(x, y), 19, 192, 9000)
	for row in 4: world.place_conveyor_line(Vector2i(-120, 74 + row), Vector2i(120, 74 + row), 1 if row % 2 == 0 else -1)
	for row in 4:
		var pipe_y := -30 + row * 5
		world.place_pipe_line(Vector2i(-120, pipe_y), Vector2i(120, pipe_y))
		for x in range(-120, 121): world.set_pipe_fluid(Vector2i(x, pipe_y), 17 if row > 1 else 3, 18000 + ((x + 120) % 4) * 7000, 1900 if row > 1 else 1300)
	for entry in [[3, Vector2i(-125, 8)], [4, Vector2i(-95, 8)], [5, Vector2i(-65, 62)], [6, Vector2i(65, 52)], [7, Vector2i(88, 52)], [8, Vector2i(112, 52)], [17, Vector2i(75, 38)], [25, Vector2i(65, 18)]]:
		world.place_structure(int(entry[0]), entry[1], 0)
	world.place_subsurface_channel(0, Vector2i(-115, 35), Vector2i(-65, 35))
	world.place_subsurface_channel(1, Vector2i(75, 28), Vector2i(75, 62))
	var sensor := int(world.create_automation_component(18, Vector2i(70, -5), {"target_position": Vector2i(45, 45)}))
	var comparator := int(world.create_automation_component(5, Vector2i(88, -5), {"threshold": 6500}))
	var control := int(world.create_automation_component(13, Vector2i(106, -5), {"target_position": Vector2i(105, 52)}))
	world.create_automation_connection(sensor, 0, comparator, 0)
	world.create_automation_connection(comparator, 0, control, 0)
	camera.position = Vector2(0, 25) * renderer.cell_pixel_size; zoom_index = 1

func _configure_phase9_view() -> void:
	if _phase9_view == "factory": factory_hud.toggle_statistics()
	if _phase9_view == "temperature": _on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
	if _phase9_view == "overview":
		zoom_index = 0
		structure_renderer.set_overview_mode(true)
		renderer.visible = false
		overlay.visible = false
		automation_renderer.visible = false
	if _phase9_view in ["automation", "factory"]: automation_renderer.set_wiring_mode(true)

func _build_phase875_showcase() -> void:
	if _phase875_view == "megafactory":
		_phase85_render_benchmark = "megafactory"
		_build_phase85_render_benchmark()
		# Exercise the actual Phase-8.75 construction path inside the full gate.
		world.remove_structure_at(Vector2i(0, -50))
		world.place_structure(14, Vector2i(0, -50), 0)
		world.place_structure(8, Vector2i(110, 145), 0)
		var benchmark_blueprint := BlueprintDefinition.new("megafactory-section", "Megafactory section", "Benchmark-built Conveyor bank")
		for x in 32:
			benchmark_blueprint.add_structure(x + 1, 2, Vector2i(x, 0), 0)
		_command_bus.submit_batch(world, benchmark_blueprint.instantiate(Vector2i(-100, 184), 0, 875, "Megafactory Blueprint section"))
		world.place_subsurface_channel(0, Vector2i(-100, 110), Vector2i(-35, 110))
		world.place_subsurface_channel(1, Vector2i(-70, 105), Vector2i(-70, 170))
		world.place_subsurface_channel(2, Vector2i(20, 112), Vector2i(85, 112))
		for index in 128:
			world.record_production_event_for_test([2, 6, 7, 8, 10, 11][index % 6], 1 + index % 9, index % 2 == 0)
		world.finalize_initialization()
		return
	if _phase875_view == "info-benchmark":
		for index in 4000:
			world.place_structure(4, Vector2i(-320 + (index % 80) * 8, -400 + (index / 80) * 8), index % 2)
		world.finalize_initialization()
		camera.position = Vector2(0, -200) * renderer.cell_pixel_size
		zoom_index = 0
		return
	if _phase875_view == "underground-benchmark":
		for lane in 200:
			for mouth in [Vector2i(-400, -100 + lane), Vector2i(-335, -100 + lane), Vector2i(-200 + lane, -130), Vector2i(-200 + lane, -65), Vector2i(60, -100 + lane), Vector2i(125, -100 + lane)]:
				world.set_cell(mouth, MaterialRegistry.EMPTY_ID)
			world.place_subsurface_channel(0, Vector2i(-400, -100 + lane), Vector2i(-335, -100 + lane))
			world.place_subsurface_channel(1, Vector2i(-200 + lane, -130), Vector2i(-200 + lane, -65))
			world.place_subsurface_channel(2, Vector2i(60, -100 + lane), Vector2i(125, -100 + lane))
		world.finalize_initialization()
		camera.position = Vector2(-100, 0) * renderer.cell_pixel_size
		zoom_index = 0
		return
	if _phase875_view == "overview" or _phase9_view == "overview":
		world.fill_rect(Rect2i(-216, -144, 432, 288), MaterialRegistry.EMPTY_ID)
		for row in 250:
			world.place_conveyor_line(Vector2i(-200, row - 125), Vector2i(199, row - 125), 1 if row % 2 == 0 else -1)
		world.finalize_initialization()
		camera.position = Vector2.ZERO
		zoom_index = 0
		return
	world.fill_rect(Rect2i(-210, -90, 430, 250), MaterialRegistry.EMPTY_ID)
	for x in range(-200, 201): world.set_cell(Vector2i(x, 140), 1)
	for row in 8:
		var y := 90 + row * 6
		world.place_conveyor_line(Vector2i(-190, y), Vector2i(190, y), 1 if row % 2 == 0 else -1)
	for row in 4:
		world.place_pipe_line(Vector2i(-190, 48 + row * 5), Vector2i(190, 48 + row * 5))
	for index in 12:
		world.place_structure([3, 4, 5, 6, 7, 8][index % 6], Vector2i(-180 + index * 31, 70), index % 2)
	var tunnel_i := int(world.place_subsurface_channel(0, Vector2i(-130, 30), Vector2i(-65, 30)))
	var tunnel_ii := 0
	if _phase875_view != "tunnel-I":
		tunnel_ii = int(world.place_subsurface_channel(1, Vector2i(-100, -20), Vector2i(-100, 45)))
	var tunnel_iii := int(world.place_subsurface_channel(2, Vector2i(20, 18), Vector2i(85, 18)))
	for lane_index in 64:
		if lane_index % 3 == 0: world.seed_subsurface_packet_for_test(tunnel_i, lane_index, 2, 1173 + lane_index, 2386, lane_index * 97)
	if tunnel_ii > 0:
		for lane_index in 64:
			if lane_index % 4 == 0: world.seed_subsurface_packet_for_test(tunnel_ii, lane_index, 7, 1300, 64848, lane_index * 131)
	for lane_index in 64:
		if lane_index % 5 == 0: world.seed_subsurface_packet_for_test(tunnel_iii, lane_index, 8, 1500, 64848, lane_index * 173)
	var production_materials := [2, 6, 7, 8, 10, 11]
	for index in 24:
		world.record_production_event_for_test(production_materials[index % production_materials.size()], 5 + index, index % 2 == 0)
	world.finalize_initialization()
	camera.position = Vector2(-20, 60) * renderer.cell_pixel_size
	zoom_index = 2
	if _phase875_view == "tunnel-I": camera.position = Vector2(-100, 30) * renderer.cell_pixel_size; zoom_index = 5
	if _phase875_view == "tunnel-crossing": camera.position = Vector2(-100, 30) * renderer.cell_pixel_size; zoom_index = 5

func _configure_phase875_view() -> void:
	match _phase875_view:
		"info-mode":
			_info_mode = true
			factory_hud.set_info_mode(true)
			overlay.set_info_mode(true, _expanded_chunk_rect(_visible_chunk_rect, 1))
		"info-benchmark":
			_info_mode = true
			factory_hud.set_info_mode(true)
			overlay.set_info_mode(true, _expanded_chunk_rect(_visible_chunk_rect, 1))
		"blueprint-preview":
			var cells: Array[Vector2i] = []
			for y in 8:
				for x in 24:
					if y in [0, 7] or x in [0, 23] or (x + y) % 5 == 0: cells.append(Vector2i(-60 + x, 20 + y))
			overlay.set_structure_preview(cells, true)
		"build-catalog": factory_hud.toggle_catalog()
		"underground-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.UNDERGROUND_LOGISTICS)
		"underground-benchmark": _on_overlay_selected(MapOverlayRenderer.Mode.UNDERGROUND_LOGISTICS)
		"tunnel-I", "tunnel-crossing": _on_overlay_selected(MapOverlayRenderer.Mode.UNDERGROUND_LOGISTICS)
		"statistics": factory_hud.toggle_statistics()
		"overview": structure_renderer.set_overview_mode(true)
	if _phase875_view == "overview":
		renderer.visible = false
		overlay.visible = false
		automation_renderer.visible = false
	if _phase875_view == "info-benchmark":
		renderer.visible = false
		automation_renderer.visible = false
		map_overlay_renderer.visible = false
		map_overlay_renderer.visible = false
	if _phase875_view == "underground-benchmark":
		renderer.visible = false
		overlay.visible = false
		automation_renderer.visible = false


func _build_dense_phase8_benchmark() -> void:
	world.fill_rect(Rect2i(-112, -112, 224, 224), MaterialRegistry.EMPTY_ID)
	for row in 100:
		var y := row * 2 - 100
		world.place_pipe_line(Vector2i(-100, y), Vector2i(99, y))
	# Exact 20k batched instances; deterministic stripes communicate fill and flow.
	for row in range(0, 100, 2):
		var y := row * 2 - 100
		for x in range(-100, 100): world.set_pipe_mass(Vector2i(x, y), 16384, 1024 + (row & 255))
	for index in 300:
		var cell := Vector2i(-98 + (index % 75) * 2, 2 + (index / 75) * 4)
		world.remove_structure_at(cell)
		world.place_structure(14 if index % 3 != 0 else 15, cell, 0)
	world.finalize_initialization()
	camera.position = Vector2(0, 0) * renderer.cell_pixel_size
	zoom_index = 0


func _build_phase85_render_benchmark() -> void:
	var mode := _phase85_render_benchmark
	var width := 100
	var pipe_rows := 0
	var belt_rows := 0
	match mode:
		"pipes2k": pipe_rows = 20
		"pipes20k": width = 200; pipe_rows = 100
		"pipes50k": width = 250; pipe_rows = 200
		"belts20k": width = 200; belt_rows = 100
		"belts50k": width = 250; belt_rows = 200
		"combined40k": width = 200; pipe_rows = 100; belt_rows = 100
		"megafactory": width = 200; pipe_rows = 100; belt_rows = 100
		"cull100k2k": pipe_rows = 20
		_: pipe_rows = 20
	var left := -width / 2
	var top := -(pipe_rows + belt_rows) / 2
	if mode == "megafactory":
		world.fill_rect(Rect2i(-192, -112, 384, 304), MaterialRegistry.EMPTY_ID)
	else:
		world.fill_rect(Rect2i(left - 8, top - 8, width + 16, pipe_rows + belt_rows + 16), MaterialRegistry.EMPTY_ID)
	for row in pipe_rows:
		var y := top + row
		world.place_pipe_line(Vector2i(left, y), Vector2i(left + width - 1, y))
		if row % 3 == 0:
			for x in range(left, left + width, 3):
				world.set_pipe_mass(Vector2i(x, y), 16384 + (row % 4) * 12288, 1100 + row)
	for row in belt_rows:
		var y := top + pipe_rows + row
		world.place_conveyor_line(Vector2i(left, y), Vector2i(left + width - 1, y), 1 if row % 2 == 0 else -1)
	if mode == "cull100k2k":
		for row in 245:
			var y := 4096 + row
			world.place_pipe_line(Vector2i(4096, y), Vector2i(4495, y))
	if mode == "megafactory":
		for y in range(-80, 101):
			world.set_cell(Vector2i(120, y), 1)
			world.set_cell(Vector2i(183, y), 1)
			world.set_cell(Vector2i(-184, y), 1)
			world.set_cell(Vector2i(-121, y), 1)
		for x in range(120, 184):
			world.set_cell(Vector2i(x, 100), 1)
			world.set_cell(Vector2i(-184 + x - 120, 100), 1)
		for y in range(-16, 100):
			for x in range(121, 183):
				world.set_water_mass(Vector2i(x, y), 224, 1120 + ((x + y) & 31))
		for y in range(-60, 100, 2):
			for x in range(-183, -121, 2):
				world.set_cell_with_metadata(Vector2i(x, y), 2, 2386, (x * 3571 + y * 7919) & 0xffff)
		for index in 12:
			world.place_structure([3, 4, 5, 6, 7, 17][index % 6], Vector2i(-108 + index * 18, 124), index % 2)
		for index in 20:
			var switch_id: int = world.create_automation_component(1, Vector2i(-108 + index * 10, 162), {"enabled": index % 2 == 0})
			var gate_id: int = world.create_automation_component(6, Vector2i(-108 + index * 10, 170), {})
			world.create_automation_connection(switch_id, 0, gate_id, 0)
	world.finalize_initialization()
	camera.position = Vector2.ZERO
	zoom_index = 0


func _build_phase8_showcase() -> void:
	world.fill_rect(Rect2i(-230, -90, 470, 320), MaterialRegistry.EMPTY_ID)
	# Natural source reservoir: all stored mass remains ordinary world Water.
	for x in range(-210, -121): world.set_cell(Vector2i(x, 120), 1)
	for y in range(25, 121):
		world.set_cell(Vector2i(-210, y), 1)
		world.set_cell(Vector2i(-120, y), 1)
	for y in range(72, 120):
		for x in range(-209, -120): world.set_water_mass(Vector2i(x, y), 255, 1160)
	# Adjacent intake, local pipe route, finite-head pumps and automated valve.
	world.place_structure(12, Vector2i(-120, 92), 2)
	world.place_pipe_line(Vector2i(-119, 92), Vector2i(-72, 92))
	world.remove_structure_at(Vector2i(-96, 92))
	world.place_structure(14, Vector2i(-96, 92), 0)
	world.place_pipe_line(Vector2i(-72, 92), Vector2i(-72, 34))
	world.remove_structure_at(Vector2i(-72, 67))
	world.place_structure(14, Vector2i(-72, 67), 3)
	world.place_pipe_line(Vector2i(-72, 34), Vector2i(48, 34))
	world.remove_structure_at(Vector2i(-8, 34))
	world.place_structure(15, Vector2i(-8, 34), 0)
	# Industrial reservoir walls with real Water cavity and a physical outlet.
	for x in range(36, 112): world.place_structure(16, Vector2i(x, 104))
	for y in range(48, 105):
		world.place_structure(16, Vector2i(36, y))
		world.place_structure(16, Vector2i(111, y))
	world.place_pipe_line(Vector2i(48, 34), Vector2i(48, 58))
	world.place_structure(13, Vector2i(48, 59), 1)
	for y in range(86, 104):
		for x in range(37, 111): world.set_water_mass(Vector2i(x, y), 255, 1140)
	# Open physical Wash Sluice above a settling basin; grains stay in world cells.
	var sluice_origin := Vector2i(-18, 112)
	world.place_structure(17, sluice_origin, 0)
	for x in range(-26, 32): world.set_cell(Vector2i(x, 134), 1)
	for y in range(121, 134):
		world.set_cell(Vector2i(-26, y), 1)
		world.set_cell(Vector2i(31, y), 1)
	for x in range(-17, -1): world.set_water_mass(Vector2i(x, 116), 255, 1120)
	var profile := 2386
	for x in range(-13, -1, 2):
		world.set_cell_with_metadata(Vector2i(x, 115), 2, profile, (x * 3571) & 0xffff)
	# Upper basin intake returns actual settled Water through a second route.
	world.place_structure(12, Vector2i(30, 124), 2)
	world.place_pipe_line(Vector2i(31, 124), Vector2i(148, 124))
	world.remove_structure_at(Vector2i(70, 124))
	world.place_structure(14, Vector2i(70, 124), 0)
	world.place_pipe_line(Vector2i(148, 124), Vector2i(148, 78))
	world.place_pipe_line(Vector2i(112, 78), Vector2i(148, 78))
	world.place_structure(13, Vector2i(111, 78), 2)
	# Automation is local: Flow Meter -> Comparator -> Pump, level -> Valve.
	var flow: int = world.create_automation_component(16, Vector2i(-54, 28), {"target_position": Vector2i(-72, 34)})
	var flow_low: int = world.create_automation_component(7, Vector2i(-42, 28), {"operator": 2, "threshold": 64})
	var pump_control: int = world.create_automation_component(14, Vector2i(-30, 28), {"target_position": Vector2i(-72, 67)})
	world.create_automation_connection(flow, 0, flow_low, 0)
	world.create_automation_connection(flow_low, 0, pump_control, 0)
	var level: int = world.create_automation_component(3, Vector2i(76, 42), {"mode": 1, "probe_size": Vector2i(60, 48), "target_position": Vector2i(40, 54)})
	var high: int = world.create_automation_component(7, Vector2i(88, 42), {"operator": 1, "threshold": 900})
	var valve_control: int = world.create_automation_component(15, Vector2i(100, 42), {"target_position": Vector2i(-8, 34)})
	world.create_automation_connection(level, 0, high, 0)
	world.create_automation_connection(high, 0, valve_control, 0)
	# Existing dry route remains present beside the wet branch.
	world.place_conveyor_line(Vector2i(-200, 146), Vector2i(205, 146), 1)
	world.place_structure(6, Vector2i(-92, 142))
	world.place_structure(7, Vector2i(-52, 140))
	world.place_structure(5, Vector2i(118, 142))
	world.place_structure(8, Vector2i(166, 140))
	for row in range(1, 8):
		var belt_y := 146 + row * 9
		world.place_conveyor_line(Vector2i(-200, belt_y), Vector2i(205, belt_y), 1 if row % 2 == 0 else -1)
		world.place_structure(6, Vector2i(-176, belt_y - 4))
		world.place_structure(7, Vector2i(-104, belt_y - 6))
		world.place_structure(5, Vector2i(12, belt_y - 4))
		world.place_structure(8, Vector2i(112, belt_y - 6))
		world.place_structure(9, Vector2i(186, belt_y))
		for x in range(-150, 150, 24): world.set_cell_with_metadata(Vector2i(x, belt_y - 1), 2, profile, (row * 997 + x * 313) & 0xffff)
	world.finalize_initialization()
	zoom_index = 3
	match _phase8_view:
		"pipes": camera.position = Vector2(-72, 60) * renderer.cell_pixel_size
		"pump-uphill": camera.position = Vector2(-82, 62) * renderer.cell_pixel_size
		"valve-control": camera.position = Vector2(0, 38) * renderer.cell_pixel_size
		"physical-tank": camera.position = Vector2(74, 78) * renderer.cell_pixel_size
		"sluice-close": camera.position = Vector2(-3, 116) * renderer.cell_pixel_size; zoom_index = 6
		"sluice-wide": camera.position = Vector2(0, 116) * renderer.cell_pixel_size; zoom_index = 4
		"water-recycling": camera.position = Vector2(72, 108) * renderer.cell_pixel_size
		"research-tree": camera.position = Vector2(0, 78) * renderer.cell_pixel_size
		"diagnostics": camera.position = Vector2(0, 78) * renderer.cell_pixel_size
		_: camera.position = Vector2(0, 86) * renderer.cell_pixel_size; zoom_index = 2


func _configure_phase8_view() -> void:
	if _phase8_view == "research-tree":
		research_tree.visible = true
		research_tree.select_research("processing.wet_separation")
	if _phase8_view == "diagnostics":
		diagnostics_visible = true
		diagnostics_panel.visible = true
		overlay.set_chunk_debug(true)


func _build_dense_physical_benchmark() -> void:
	var profile := 64848
	var iron_signature := 0
	for signature in 65536:
		if world.get_hidden_constituent(profile, signature) == 1:
			iron_signature = signature
			break
	for index in 500:
		var origin := Vector2i(-480 + (index % 40) * 24, -470 + (index / 40) * 14)
		var type_id := 7 if index < 200 else (6 if index < 400 else 5)
		world.place_structure(type_id, origin, 0)
		var support_y := 6 if type_id == 7 else 4
		world.place_conveyor_line(origin + Vector2i(-2, support_y), origin + Vector2i(13, support_y), 1)
		var material_y := support_y - 1
		for x in [2, 5, 8]:
			world.set_cell_with_metadata(origin + Vector2i(x, material_y), 7 if type_id == 7 else 2, profile, iron_signature + x)
	world.finalize_initialization()
	camera.position = Vector2(0, -380) * renderer.cell_pixel_size
	zoom_index = 2


func _build_phase65_showcase() -> void:
	world.fill_rect(Rect2i(-52, 98, 108, 32), MaterialRegistry.EMPTY_ID)
	var profile := 64848
	var iron_signature := 0
	var nonmag_signature := 0
	var fine_signature := 0
	var coarse_signature := 0
	for signature in 65536:
		var constituent: int = world.get_hidden_constituent(profile, signature)
		if iron_signature == 0 and constituent == 1: iron_signature = signature
		if nonmag_signature == 0 and constituent == 0: nonmag_signature = signature
		if fine_signature == 0:
			world.set_cell_with_metadata(Vector2i(9000, 9000), 2, profile, signature)
			if world.get_grain_size_class(Vector2i(9000, 9000)) == 0: fine_signature = signature
		if coarse_signature == 0:
			world.set_cell_with_metadata(Vector2i(9000, 9000), 2, profile, signature)
			if world.get_grain_size_class(Vector2i(9000, 9000)) == 2: coarse_signature = signature
		if iron_signature > 0 and nonmag_signature > 0 and fine_signature > 0 and coarse_signature > 0: break
	world.set_cell(Vector2i(9000, 9000), 0)
	var screen_origin := Vector2i(-32, 112)
	world.place_structure(6, screen_origin, 0)
	world.place_conveyor_line(screen_origin + Vector2i(-2, 4), screen_origin + Vector2i(11, 4), 1)
	var magnet_origin := Vector2i(-5, 112)
	world.place_structure(7, magnet_origin, 0)
	world.place_conveyor_line(magnet_origin + Vector2i(-2, 6), magnet_origin + Vector2i(13, 6), 1)
	var furnace_origin := Vector2i(22, 114)
	world.place_structure(5, furnace_origin, 0)
	world.place_conveyor_line(furnace_origin + Vector2i(-2, 4), furnace_origin + Vector2i(11, 4), 1)
	for x in range(-42, 44): world.set_cell(Vector2i(x, 126), 1)
	world.finalize_initialization()
	# Seed after initialization so deterministic capture frames include initial matter and each physical move.
	for entry in [[1, 2, coarse_signature], [3, 2, fine_signature], [5, 4, fine_signature], [7, 2, coarse_signature]]:
		world.set_cell_with_metadata(screen_origin + Vector2i(entry[0], entry[1]), 2, profile, entry[2])
	for entry in [[1, 5, iron_signature], [4, 4, iron_signature], [7, 3, iron_signature], [10, 2, iron_signature]]:
		world.set_cell_with_metadata(magnet_origin + Vector2i(entry[0], entry[1]), 7, profile, entry[2])
	for x in [2, 5, 8, 11]: world.set_cell_with_metadata(magnet_origin + Vector2i(x, 5), 7, profile, nonmag_signature)
	for x in [1, 3, 5, 7]: world.set_cell_with_metadata(furnace_origin + Vector2i(x, 3), 6, profile, (fine_signature + x * 311) & 0xffff)
	camera.position = Vector2(-2, 117) * renderer.cell_pixel_size
	zoom_index = 9 if _phase65_view in ["screen-close", "magnet-close"] else 5
	if _phase65_view == "screen-close": camera.position = Vector2(screen_origin + Vector2i(5, 2)) * renderer.cell_pixel_size
	if _phase65_view in ["magnet-close", "magnetic-overlay"]: camera.position = Vector2(magnet_origin + Vector2i(6, 3)) * renderer.cell_pixel_size


func _configure_phase65_view() -> void:
	match _phase65_view:
		"catalog": factory_hud.toggle_catalog()
		"research": research_tree.visible = true
		"wiring":
			automation_renderer.set_wiring_mode(true)
			automation_inspector.visible = true
		"magnetic-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.MAGNETIC_FIELD)


func _build_phase7_showcase() -> void:
	world.fill_rect(Rect2i(-210, -110, 430, 270), MaterialRegistry.EMPTY_ID)
	for x in range(-200, 201): world.set_cell(Vector2i(x, 130), 1)
	for y in range(-80, 131):
		world.set_cell(Vector2i(-200, y), 1)
		world.set_cell(Vector2i(200, y), 1)
	for x in range(-190, -49): world.set_cell(Vector2i(x, 92), 1)
	for y in range(-72, 93):
		world.set_cell(Vector2i(-190, y), 1)
		if y != 78: world.set_cell(Vector2i(-50, y), 1)
	world.place_structure(9, Vector2i(-50, 78))
	for y in range(24, 92):
		for x in range(-189, -50):
			world.set_water_mass(Vector2i(x, y), 255, 1080 + ((x + y) & 63))
	for x in range(-28, 29): world.set_cell(Vector2i(x, 112), 1)
	for y in range(20, 112):
		world.set_cell(Vector2i(-28, y), 1)
		world.set_cell(Vector2i(28, y), 1)
	for y in range(-72, -20):
		for x in range(-5, 6): world.set_water_mass(Vector2i(x, y), 255, 1173)
	for x in range(38, 120): world.set_cell(Vector2i(x, 90), 1)
	for y in range(42, 91):
		world.set_cell(Vector2i(38, y), 1)
		world.set_cell(Vector2i(119, y), 1)
	for y in range(65, 90):
		for x in range(39, 119): world.set_water_mass(Vector2i(x, y), 255, 1120)
	for y in range(24, 46, 2):
		for x in range(42, 112, 2): world.set_cell_with_metadata(Vector2i(x, y), 2, 2386, (x * 313 + y * 17) & 0xffff)
	world.place_conveyor_line(Vector2i(48, 104), Vector2i(172, 104), 1)
	world.place_structure(6, Vector2i(62, 100))
	world.place_structure(7, Vector2i(92, 98))
	world.place_structure(5, Vector2i(126, 100))
	world.place_structure(8, Vector2i(156, 98))
	var level: int = world.create_automation_component(3, Vector2i(-174, 10), {"target_position": Vector2i(-120, 40), "probe_size": Vector2i(32, 32), "mode": 1})
	var comparator: int = world.create_automation_component(7, Vector2i(-146, 10), {"operator": 1, "threshold": 450})
	var gate: int = world.create_automation_component(13, Vector2i(-84, 72), {"target_position": Vector2i(-50, 78)})
	world.create_automation_connection(level, 0, comparator, 0)
	if _phase7_view not in ["dam-closed", "reservoir"]: world.create_automation_connection(comparator, 0, gate, 0)
	world.finalize_initialization()
	zoom_index = 4
	match _phase7_view:
		"waterfall": camera.position = Vector2(0, 32) * renderer.cell_pixel_size
		"reservoir": camera.position = Vector2(-145, 50) * renderer.cell_pixel_size
		"dam-closed", "dam-open": camera.position = Vector2(-105, 58) * renderer.cell_pixel_size
		"sand-water": camera.position = Vector2(62, 44) * renderer.cell_pixel_size
		"factory-water": camera.position = Vector2(92, 82) * renderer.cell_pixel_size
		"temperature-overlay": camera.position = Vector2(-110, 52) * renderer.cell_pixel_size
		"diagnostics": camera.position = Vector2(-20, 50) * renderer.cell_pixel_size
		_: camera.position = Vector2(-20, 50) * renderer.cell_pixel_size


func _build_dense_water_benchmark() -> void:
	_build_dense_physical_benchmark()
	for x in range(-520, 521): world.set_cell(Vector2i(x, -250), 1)
	for y in range(-540, -250):
		world.set_cell(Vector2i(-520, y), 1)
		world.set_cell(Vector2i(520, y), 1)
	for y in range(-540, -250): world.set_cell(Vector2i(-259, y), 1)
	world.set_cell(Vector2i(-259, -251), MaterialRegistry.EMPTY_ID)
	world.place_structure(9, Vector2i(-259, -251))
	# A large already-supported reservoir exercises storage/rendering while only
	# the narrow waterfall remains an active front during the runtime benchmark.
	for y in range(-500, -250):
		for x in range(-519, -260): world.set_water_mass(Vector2i(x, y), 255, 1173)
	for y in range(-520, -440):
		for x in range(-4, 5): world.set_water_mass(Vector2i(x, y), 255, 1173)
	var level: int = world.create_automation_component(3, Vector2i(-470, -520), {"target_position": Vector2i(-480, -480), "probe_size": Vector2i(32, 32), "mode": 1})
	var comparator: int = world.create_automation_component(7, Vector2i(-430, -520), {"operator": 1, "threshold": 1001})
	var gate: int = world.create_automation_component(13, Vector2i(-270, -270), {"target_position": Vector2i(-259, -251)})
	world.create_automation_connection(level, 0, comparator, 0)
	world.create_automation_connection(comparator, 0, gate, 0)
	world.finalize_initialization()
	camera.position = Vector2(0, -380) * renderer.cell_pixel_size
	zoom_index = 2


func _configure_phase7_view() -> void:
	if _phase7_view == "temperature-overlay": _on_overlay_selected(MapOverlayRenderer.Mode.TEMPERATURE)
	if _phase7_view == "diagnostics":
		diagnostics_visible = true
		diagnostics_panel.visible = true
		overlay.set_chunk_debug(true)


func _build_phase6_showcase() -> void:
	world.set_game_mode(1)
	world.fill_rect(Rect2i(-250, -60, 500, 210), MaterialRegistry.EMPTY_ID)
	var bin_origin := Vector2i(-82, 38)
	world.place_structure(4, bin_origin)
	world.place_conveyor_line(Vector2i(-132, 45), Vector2i(-83, 45), 1)
	world.fill_rect(Rect2i(bin_origin + Vector2i(1, 1), Vector2i(6, 5)), 2, 2)
	var level: int = world.create_automation_component(3, Vector2i(-100, 34), {"mode": 1, "probe_size": Vector2i(6, 7), "target_position": bin_origin + Vector2i(1, 0)})
	var high: int = world.create_automation_component(7, Vector2i(-111, 37), {"operator": 1, "threshold": 800})
	var invert: int = world.create_automation_component(4, Vector2i(-119, 40))
	var belt_control: int = world.create_automation_component(11, Vector2i(-126, 42), {"target_position": Vector2i(-126, 45)})
	world.create_automation_connection(level, 0, high, 0)
	world.create_automation_connection(high, 0, invert, 0)
	world.create_automation_connection(invert, 0, belt_control, 0)

	var furnace_origin := Vector2i(-35, 38)
	world.place_structure(5, furnace_origin)
	world.place_conveyor_line(Vector2i(-65, 42), Vector2i(-36, 42), 1)
	var machine_sensor: int = world.create_automation_component(8, Vector2i(-50, 34), {"mode": 4, "target_position": furnace_origin})
	var machine_not: int = world.create_automation_component(4, Vector2i(-57, 37))
	var machine_belt: int = world.create_automation_component(11, Vector2i(-62, 40), {"target_position": Vector2i(-62, 42)})
	world.create_automation_connection(machine_sensor, 0, machine_not, 0)
	world.create_automation_connection(machine_not, 0, machine_belt, 0)

	world.place_conveyor_line(Vector2i(8, 45), Vector2i(92, 45), 1)
	world.place_structure(9, Vector2i(48, 44))
	world.place_structure(9, Vector2i(64, 44))
	var gold_sensor: int = world.create_automation_component(2, Vector2i(18, 40), {"material_id": 12, "mode": 0, "probe_size": Vector2i(3, 1), "target_position": Vector2i(22, 44)})
	var gold_not: int = world.create_automation_component(4, Vector2i(34, 38))
	var gate_gold: int = world.create_automation_component(13, Vector2i(48, 40), {"target_position": Vector2i(48, 44)})
	var gate_normal: int = world.create_automation_component(13, Vector2i(64, 40), {"target_position": Vector2i(64, 44)})
	world.create_automation_connection(gold_sensor, 0, gate_gold, 0)
	world.create_automation_connection(gold_sensor, 0, gold_not, 0)
	world.create_automation_connection(gold_not, 0, gate_normal, 0)
	for x in range(10, 88, 6):
		world.set_cell(Vector2i(x, 44), 12 if x == 16 or x == 58 else 6)

	var low: int = world.create_automation_component(7, Vector2i(-104, 54), {"operator": 2, "threshold": 400})
	var latch: int = world.create_automation_component(10, Vector2i(-112, 57))
	world.create_automation_connection(level, 0, low, 0)
	world.create_automation_connection(high, 0, latch, 0)
	world.create_automation_connection(low, 0, latch, 1)

	var timer_switch: int = world.create_automation_component(1, Vector2i(104, 37), {"enabled": true})
	var timer: int = world.create_automation_component(9, Vector2i(112, 40), {"mode": 2, "period_ticks": 300, "on_ticks": 60})
	world.place_structure(9, Vector2i(124, 44))
	var timer_gate: int = world.create_automation_component(13, Vector2i(124, 40), {"target_position": Vector2i(124, 44)})
	world.create_automation_connection(timer_switch, 0, timer, 0)
	world.create_automation_connection(timer, 0, timer_gate, 0)
	world.finalize_initialization()
	for _tick in 8:
		world.step()
	automation_renderer.set_wiring_mode(_phase6_view in ["wiring", "level", "machine", "gold", "hysteresis"])
	automation_inspector.visible = automation_renderer.wiring_mode
	match _phase6_view:
		"level":
			camera.position = Vector2(-98, 44) * renderer.cell_pixel_size
			automation_renderer.select_component(level)
		"hysteresis":
			camera.position = Vector2(-98, 44) * renderer.cell_pixel_size
			automation_renderer.select_component(latch)
		"machine":
			camera.position = Vector2(-42, 43) * renderer.cell_pixel_size
			automation_renderer.select_component(machine_sensor)
		"gold":
			camera.position = Vector2(52, 43) * renderer.cell_pixel_size
			automation_renderer.select_component(gold_sensor)
		"wiring":
			camera.position = Vector2(-5, 44) * renderer.cell_pixel_size
			automation_renderer.select_component(timer)
		"research":
			research_tree.visible = true
			camera.position = Vector2.ZERO
		_:
			camera.position = Vector2(-5, 44) * renderer.cell_pixel_size
	zoom_index = 5 if _phase6_view in ["level", "machine", "gold", "hysteresis"] else 3


func _fixture_credit(glass: int, iron: int, gold: int = 0) -> void:
	world.set_game_mode(1)
	world.credit_research_material_for_test(10, glass)
	world.credit_research_material_for_test(11, iron)
	if gold > 0:
		world.credit_research_material_for_test(12, gold)
	world.set_game_mode(0)


func _build_phase5_showcase() -> void:
	world.fill_rect(Rect2i(-250, -50, 500, 180), MaterialRegistry.EMPTY_ID)
	match _phase5_view:
		"ready", "tree":
			_fixture_credit(2400, 40)
		"sieve":
			_fixture_credit(2400, 40)
			world.try_unlock_research("processing.dry_separation")
		"magnetic", "wide":
			_fixture_credit(5400, 220)
			world.try_unlock_research("processing.dry_separation")
			world.try_unlock_research("processing.ferrous_separation")
	_build_primitive_processing_line(Vector2i(-155, 35))
	world.place_structure(8, Vector2i(-88, 35))
	if _phase5_view in ["sieve", "magnetic", "wide"]:
		_build_sieve_processing_line(Vector2i(-35, 30))
		world.place_structure(8, Vector2i(48, 34))
	if _phase5_view in ["magnetic", "wide"]:
		_build_magnetic_processing_line(Vector2i(105, 30))
	world.finalize_initialization()
	match _phase5_view:
		"primitive", "ready", "tree":
			camera.position = Vector2(-105, 42) * renderer.cell_pixel_size
			zoom_index = 4
		"sieve":
			camera.position = Vector2(-35, 42) * renderer.cell_pixel_size
			zoom_index = 4
		"magnetic":
			camera.position = Vector2(108, 42) * renderer.cell_pixel_size
			zoom_index = 4
		_:
			camera.position = Vector2(-10, 45) * renderer.cell_pixel_size
			zoom_index = 3


func _build_phase3_showcase() -> void:
	# Creative setup only. Normal placement still rejects matter and never erases it.
	if _dense_factory_benchmark:
		_build_dense_factory_benchmark()
		return
	world.fill_rect(Rect2i(-230, 25, 390, 145), MaterialRegistry.EMPTY_ID)
	world.place_structure(3, Vector2i(-180, 75), 0)
	world.place_conveyor_line(Vector2i(-177, 85), Vector2i(-22, 85), 1)
	world.place_structure(3, Vector2i(-25, 92), 0)
	world.place_conveyor_line(Vector2i(-22, 102), Vector2i(79, 102), 1)
	world.place_structure(4, Vector2i(80, 102), 0)
	world.place_structure(5, Vector2i(120, 104), 0)
	world.fill_rect(Rect2i(-179, 42, 5, 29), 2)
	world.fill_rect(Rect2i(-155, 75, 38, 4), 2, 2)
	world.fill_rect(Rect2i(42, 72, 10, 20), 2, 2)
	world.finalize_initialization()
	match _phase4_view:
		"conveyor":
			camera.position = Vector2(-105, 80) * renderer.cell_pixel_size
			zoom_index = 4
		"funnel":
			camera.position = Vector2(-176, 76) * renderer.cell_pixel_size
			zoom_index = 4
		"storage":
			camera.position = Vector2(82, 102) * renderer.cell_pixel_size
			zoom_index = 4
		_:
			camera.position = Vector2(-25, 100) * renderer.cell_pixel_size
			zoom_index = 1


func _build_phase4_showcase() -> void:
	if _dense_factory_benchmark:
		_build_dense_factory_benchmark()
		return
	world.fill_rect(Rect2i(-250, -50, 500, 180), MaterialRegistry.EMPTY_ID)
	_build_primitive_processing_line(Vector2i(-155, 35))
	_build_sieve_processing_line(Vector2i(-35, 30))
	_build_magnetic_processing_line(Vector2i(105, 30))
	world.finalize_initialization()
	match _phase4_view:
		"primitive":
			camera.position = Vector2(-145, 40) * renderer.cell_pixel_size
			zoom_index = 5
		"sieve":
			camera.position = Vector2(-25, 38) * renderer.cell_pixel_size
			zoom_index = 5
		"magnetic":
			camera.position = Vector2(116, 38) * renderer.cell_pixel_size
			zoom_index = 5
		_:
			camera.position = Vector2(-10, 45) * renderer.cell_pixel_size
			zoom_index = 3


func _build_primitive_processing_line(origin: Vector2i) -> void:
	world.place_structure(5, origin)
	world.place_conveyor_line(origin + Vector2i(-24, 4), origin + Vector2i(-1, 4), 1)
	world.place_conveyor_line(origin + Vector2i(9, 4), origin + Vector2i(42, 4), 1)
	world.place_conveyor_line(origin + Vector2i(-18, 6), origin + Vector2i(-1, 6), -1)
	world.fill_rect(Rect2i(origin + Vector2i(4, -30), Vector2i(1, 30)), 2)
	for x in range(origin.x - 22, origin.x - 2, 4):
		world.set_cell(Vector2i(x, origin.y + 3), 14)
	var anomaly_profile := 16 | (10 << 5) | (7 << 10) | (7 << 13)
	var gold_written := false
	for offset in range(11, 40, 2):
		var signature := (offset * 3571) & 0xffff
		var output: int = world.process_material_for_test(2, anomaly_profile, signature, 303)
		world.set_cell_with_metadata(origin + Vector2i(offset, 3), output, anomaly_profile, signature)
		if output == 12:
			gold_written = true
	if not gold_written:
		for signature in 65536:
			if world.process_material_for_test(2, anomaly_profile, signature, 303) == 12:
				world.set_cell_with_metadata(origin + Vector2i(39, 3), 12, anomaly_profile, signature)
				break


func _build_sieve_processing_line(origin: Vector2i) -> void:
	world.place_structure(6, origin)
	world.place_conveyor_line(origin + Vector2i(-30, 5), origin + Vector2i(-1, 5), -1)
	world.place_conveyor_line(origin + Vector2i(7, 5), origin + Vector2i(34, 5), 1)
	world.fill_rect(Rect2i(origin + Vector2i(3, -30), Vector2i(1, 30)), 2)
	var profile: int = world.geology_profile_id_at(origin)
	for x in range(-28, -2, 2):
		world.set_cell_with_metadata(origin + Vector2i(x, 4), 6, profile, (x * 1201) & 0xffff)
	for x in range(9, 34, 2):
		world.set_cell_with_metadata(origin + Vector2i(x, 4), 7, profile, (x * 1877) & 0xffff)
	world.place_structure(5, origin + Vector2i(-42, 12))
	world.place_structure(5, origin + Vector2i(36, 12))
	world.set_cell(origin + Vector2i(-43, 15), 14)
	world.set_cell(origin + Vector2i(35, 15), 14)


func _build_magnetic_processing_line(origin: Vector2i) -> void:
	world.place_structure(7, origin)
	world.place_conveyor_line(origin + Vector2i(-32, 5), origin + Vector2i(-1, 5), -1)
	world.place_conveyor_line(origin + Vector2i(8, 5), origin + Vector2i(38, 5), 1)
	var profile: int = world.geology_profile_id_at(origin)
	for y in range(origin.y - 28, origin.y):
		world.set_cell_with_metadata(Vector2i(origin.x + 4, y), 7, profile, (y * 11939) & 0xffff)
	for x in range(-30, -2, 2):
		world.set_cell_with_metadata(origin + Vector2i(x, 4), 8, profile, (x * 2371) & 0xffff)
	for x in range(10, 38, 2):
		world.set_cell_with_metadata(origin + Vector2i(x, 4), 9, profile, (x * 421) & 0xffff)
	world.place_structure(5, origin + Vector2i(-44, 12))
	world.place_structure(5, origin + Vector2i(40, 12))
	world.set_cell(origin + Vector2i(-45, 15), 14)
	world.set_cell(origin + Vector2i(39, 15), 14)


func _build_dense_factory_benchmark() -> void:
	world.fill_rect(Rect2i(-430, -130, 860, 380), MaterialRegistry.EMPTY_ID)
	for line in 13:
		var belt_y := -90 + line * 18
		world.place_conveyor_line(Vector2i(-400, belt_y), Vector2i(399, belt_y), 1 if (line & 1) == 0 else -1)
		for row in 3:
			world.fill_rect(Rect2i(-398, belt_y - 1 - row, 796, 1), 2, 2)
	var processing_profile := 16 | (10 << 5) | (7 << 10) | (7 << 13)
	for index in 300:
		var type_id: int = [6, 7, 5][index % 3]
		var origin := Vector2i(-390 + (index % 30) * 27, 145 + (index / 30) * 10)
		if world.place_structure(type_id, origin, 0) <= 0:
			continue
		var input_x := 3 if type_id == 6 else 4
		var feed := 7 if type_id == 7 else 2
		world.set_cell_with_metadata(origin + Vector2i(input_x, -1), feed, processing_profile, (index * 3571) & 0xffff)
		if type_id == 6:
			world.set_cell(origin + Vector2i(-1, 4), 1)
			world.set_cell(origin + Vector2i(7, 4), 1)
		elif type_id == 7:
			world.set_cell(origin + Vector2i(-1, 4), 1)
			world.set_cell(origin + Vector2i(8, 4), 1)
		else:
			world.set_cell(origin + Vector2i(-1, 4), 1)
			world.set_cell(origin + Vector2i(-2, 4), 1)
			world.set_cell(origin + Vector2i(-1, 6), 1)
			world.set_cell(origin + Vector2i(-2, 6), 1)
			world.set_cell(origin + Vector2i(9, 3), 1)
			world.set_cell(origin + Vector2i(9, 4), 1)
			world.set_cell(origin + Vector2i(10, 4), 1)
			world.set_cell(origin + Vector2i(-1, 3), 14)
	world.finalize_initialization()
	camera.position = Vector2(0, 55) * renderer.cell_pixel_size
	zoom_index = 1


func _build_realistic_max_factory() -> void:
	# Deliberately busy but screen-legible upper bound for an intended MVP factory.
	# Unlike --dense-factory, this fixture does not stack 300 machines behind 13
	# near-full-width belts inside one viewport.
	world.fill_rect(Rect2i(-270, -100, 540, 260), MaterialRegistry.EMPTY_ID)
	for line in 7:
		var belt_y := -70 + line * 22
		world.place_conveyor_line(Vector2i(-240, belt_y), Vector2i(239, belt_y), 1 if (line & 1) == 0 else -1)
		for row in 2:
			world.fill_rect(Rect2i(-238, belt_y - 1 - row, 476, 1), 2, 2)
	var processing_profile := 16 | (10 << 5) | (7 << 10) | (7 << 13)
	for index in 96:
		var type_id: int = [6, 7, 5][index % 3]
		var origin := Vector2i(-230 + (index % 24) * 20, 98 + (index / 24) * 11)
		if world.place_structure(type_id, origin, index % 2) <= 0: continue
		var input_x := 3 if type_id == 6 else 4
		world.set_cell_with_metadata(origin + Vector2i(input_x, -1), 7 if type_id == 7 else 2, processing_profile, (index * 3571) & 0xffff)
	world.finalize_initialization()
	camera.position = Vector2(0, 34) * renderer.cell_pixel_size
	zoom_index = 1


func _add_dense_progression_banks() -> void:
	_benchmark_bank_origins.clear()
	world.fill_rect(Rect2i(-430, 260, 860, 90), MaterialRegistry.EMPTY_ID)
	for index in 200:
		var origin := Vector2i(-390 + (index % 40) * 20, 270 + (index / 40) * 12)
		if world.place_structure(8, origin) > 0:
			_benchmark_bank_origins.append(origin)
	world.finalize_initialization()


func _build_dense_automation_benchmark() -> void:
	_build_dense_factory_benchmark()
	var sensors: Array[int] = []
	var logic: Array[int] = []
	for index in 2000:
		var belt_x := -398 + (index % 798)
		var belt_y := -90 + (index % 13) * 18
		var sensor: int = world.create_automation_component(2, Vector2i(belt_x, belt_y - 5), {"material_id": 2, "mode": 0, "target_position": Vector2i(belt_x, belt_y - 1)})
		var gate_logic: int = world.create_automation_component(4 if index % 2 == 0 else 7, Vector2i(belt_x, belt_y - 3), {"operator": 0, "threshold": 0})
		var control: int = world.create_automation_component(11, Vector2i(belt_x, belt_y - 2), {"target_position": Vector2i(belt_x, belt_y)})
		world.create_automation_connection(sensor, 0, gate_logic, 0)
		world.create_automation_connection(gate_logic, 0, control, 0)
		sensors.append(sensor)
		logic.append(gate_logic)
	world.fill_rect(Rect2i(-420, 255, 840, 90), MaterialRegistry.EMPTY_ID)
	for index in 16:
		world.place_structure(4, Vector2i(-380 + index * 48, 270))
		world.place_structure(8, Vector2i(-376 + index * 48, 300))
	for index in 40:
		var gate_cell := Vector2i(-390 + index * 20, 248)
		world.place_structure(9, gate_cell)
		var source: int = world.create_automation_component(1, gate_cell + Vector2i(0, -6), {"enabled": true})
		var timer: int = world.create_automation_component(9, gate_cell + Vector2i(0, -4), {"mode": 2, "period_ticks": 120 + index, "on_ticks": 30})
		var gate: int = world.create_automation_component(13, gate_cell + Vector2i(0, -2), {"target_position": gate_cell})
		world.create_automation_connection(source, 0, timer, 0)
		world.create_automation_connection(timer, 0, gate, 0)
	world.finalize_initialization()
	camera.position = Vector2(0, 75) * renderer.cell_pixel_size
	zoom_index = 1


func _maintain_progression_bank_feeds() -> void:
	var tick := int(world.get_statistics().get("tick", 0))
	for index in _benchmark_bank_origins.size():
		var origin := _benchmark_bank_origins[index]
		var input := origin + Vector2i(3, -1)
		if world.get_cell(input) == 0:
			world.set_cell(input, [10, 11, 12, 13][(index + tick) % 4])
		var reject := origin + Vector2i(8, 4)
		if world.get_cell(reject) == 13:
			world.set_cell(reject, 0)


func _request_camera_streaming() -> void:
	if world == null:
		return
	if _phase875_view == "overview" or _phase9_view == "overview":
		# Overview is a deliberately aggregated structure-only LOD. It must not
		# allocate/render hundreds of material chunks merely because the camera
		# sees a large area at minimum zoom.
		_visible_chunk_rect = Rect2i(Vector2i(-4, -3), Vector2i(8, 6))
		if structure_renderer != null and structure_renderer._world != null:
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	if _phase875_view == "underground-benchmark":
		_visible_chunk_rect = Rect2i(Vector2i(-7, -3), Vector2i(9, 5))
		if structure_renderer != null and structure_renderer._world != null:
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		map_overlay_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	if _phase875_view == "info-benchmark":
		_visible_chunk_rect = Rect2i(Vector2i(-6, -8), Vector2i(12, 8))
		if structure_renderer != null and structure_renderer._world != null:
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	if not _phase85_render_benchmark.is_empty():
		# The fixture occupies at most four chunks on either axis. Keep the base
		# rectangle stable so this path and the per-tick renderer sync both request
		# the same six-by-six page window instead of oscillating between 6x6/8x8.
		_visible_chunk_rect = Rect2i(Vector2i(-2, -2), Vector2i(4, 4))
		if structure_renderer != null and structure_renderer._world != null:
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	if _dense_phase8_benchmark:
		_visible_chunk_rect = Rect2i(Vector2i(-3, -3), Vector2i(6, 6))
		if structure_renderer != null and structure_renderer._world != null:
			structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
		return
	var viewport_cells := get_viewport_rect().size / (renderer.cell_pixel_size * camera.zoom)
	var center_cell := camera.position / renderer.cell_pixel_size
	var first_cell := center_cell - viewport_cells * 0.5
	var last_cell := center_cell + viewport_cells * 0.5
	var first_chunk := Vector2i(floori(first_cell.x / 64.0), floori(first_cell.y / 64.0))
	var last_chunk := Vector2i(floori(last_cell.x / 64.0), floori(last_cell.y / 64.0))
	_visible_chunk_rect = Rect2i(first_chunk, last_chunk - first_chunk + Vector2i.ONE)
	var center_chunk := Vector2i(floori(center_cell.x / 64.0), floori(center_cell.y / 64.0))
	if _character != null:
		var character_chunk := Vector2i(floori(_character.world_cell().x / 64.0), floori(_character.world_cell().y / 64.0))
		var character_region := InterestRegion.new(1, 0, Rect2i(character_chunk - Vector2i(3, 3), Vector2i(7, 7)), InterestRegion.Purpose.CHARACTER, 64)
		character_region.request(world)
		var direction := Vector2i(signi(_character.velocity_milli.x), signi(_character.velocity_milli.y))
		var directional_prefetch := InterestRegion.new(2, 1, Rect2i(character_chunk + direction * 3 - Vector2i(2, 2), Vector2i(5, 5)), InterestRegion.Purpose.PREFETCH, 32)
		directional_prefetch.request(world)
	world.request_chunk(center_chunk, 0 if _character == null else 1)
	InterestRegion.new(3, 1, _visible_chunk_rect, InterestRegion.Purpose.GOD_CAMERA if _character == null else InterestRegion.Purpose.VISION_SOURCE, 128).request(world)
	InterestRegion.new(4, 2, _expanded_chunk_rect(_visible_chunk_rect, STREAM_PREFETCH_MARGIN), InterestRegion.Purpose.PREFETCH, 192).request(world)
	if structure_renderer != null and structure_renderer._world != null:
		structure_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))
	if automation_renderer != null and automation_renderer._world != null:
		automation_renderer.sync_visible(_expanded_chunk_rect(_visible_chunk_rect, 1))


func _expanded_chunk_rect(source: Rect2i, margin: int) -> Rect2i:
	return Rect2i(source.position - Vector2i.ONE * margin, source.size + Vector2i.ONE * margin * 2)


func _on_seed_submitted(_text: String) -> void:
	_regenerate_from_seed_input()


func _regenerate_from_seed_input() -> void:
	var candidate := seed_input.text.strip_edges()
	if not candidate.is_valid_int():
		seed_input.text = str(_world_seed)
		return
	_world_seed = candidate.to_int()
	_regenerate_world()


func _regenerate_world() -> void:
	_configure_procedural_world()
	if _creative_fixture or _dense_factory_benchmark or _dense_progression_benchmark or _dense_automation_benchmark or _dense_physical_benchmark or _dense_water_benchmark or _dense_phase8_benchmark or not _phase4_view.is_empty() or not _phase6_view.is_empty() or not _phase65_view.is_empty() or not _phase7_view.is_empty() or not _phase8_view.is_empty():
		world.set_game_mode(1)
	if _game_session.progression_mode == GameModeCapabilities.ProgressionMode.CREATIVE:
		world.set_game_mode(1)
	_cache_structure_definitions()
	if _showcase_enabled:
		_build_showcase()
	renderer.clear_chunks()
	structure_renderer.clear()
	structure_renderer.initialize(world)
	automation_renderer.clear()
	automation_renderer.initialize(world)
	map_overlay_renderer.initialize(world)
	factory_hud.initialize(world)
	factory_hud.configure_mode(_game_session.preset_id)
	research_tree.initialize(world)
	overlay.initialize(world)
	_streaming_frame = 0
	_request_camera_streaming()
	_update_status()


func _copy_seed() -> void:
	DisplayServer.clipboard_set(str(_world_seed))


func _update_status() -> void:
	if world == null:
		return
	var statistics: Dictionary = world.get_statistics()
	var speed_text := "PAUSED" if clock.speed_multiplier == 0 else "%d×" % clock.speed_multiplier
	var cursor := _mouse_world_cell()
	if absi(cursor.x) > 100000 or absi(cursor.y) > 100000:
		cursor = Vector2i(camera.position / renderer.cell_pixel_size)
	minimal_label.text = "%s   R%d   %s\n%s · %s · %s" % [
		_current_brush_name(), brush_radius, speed_text, InputGlyphs.hint(&"planning_pause", "Planning Pause"), InputGlyphs.hint(&"open_codex", "Codex"), InputGlyphs.hint(&"info_mode", "Inspect")
	]
	factory_hud.refresh(_current_brush_name(), speed_text)
	if not _phase135_capture_inspector.is_empty():
		factory_hud.show_physical_inspector(_phase135_capture_inspector)
	elif _info_mode:
		factory_hud.show_physical_inspector(PhysicalInspector.inspect(world, materials, cursor, _character != null, KoalaCharacterController.VISIBILITY_OWNER_ID))
	else:
		factory_hud.show_inspector("", [])
	if not _unlock_notice.is_empty():
		minimal_label.text += "\n" + _unlock_notice
	var progression: Dictionary = world.get_progression_state()
	reserve_label.text = "GLASS %d   IRON %d   GOLD %d" % [progression.glass, progression.iron, progression.gold]
	var toolbar := $HUD/BuildToolbar/Margin/Tools
	toolbar.get_node("Sieve").text = "[V] Sieve" if world.is_structure_unlocked(6) else "[V] LOCKED · Dry Separation"
	toolbar.get_node("Magnetic").text = "[M] Magnetic" if world.is_structure_unlocked(7) else "[M] LOCKED · Ferrous Separation"
	diagnostics_label.text = (
		"SIMULATION\n"
		+ "render FPS        %.1f\nframe ms          %.2f\ntick              %d\nsim latest/avg    %.3f / %.3f ms\nsim worst         %.3f ms\nsimulation Hz     %.1f\nactive chunks     %d\nactive rects      %d\nactive region     %d cells\nsleeping chunks   %d\nallocated chunks  %d\n"
		+ "last movements    %d\nvisited cells     %d\nskipped cells     %d\nworkers           %d\nworker use        %.0f%%\n\nRENDER\n"
		+ "cell scale        %.1f px × %.1f zoom = %.1f px\ndirty chunks      %d\ndirty pixels      %d\nupload pixels     %d\ntexture update     %.3f ms\n"
		+ "\nB chunk/activity overlay"
	) % [
		Engine.get_frames_per_second(),
		1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		statistics.get("tick", 0),
		_simulation_latest_ms,
		_simulation_total_ms / maxf(1.0, float(_simulation_samples)),
		_simulation_worst_ms,
		1000.0 / maxf(0.001, _simulation_total_ms / maxf(1.0, float(_simulation_samples))),
		statistics.get("active_chunks", 0),
		statistics.get("active_rectangles", 0),
		statistics.get("active_region_cells", 0),
		statistics.get("sleeping_chunks", 0),
		statistics.get("allocated_chunks", 0),
		statistics.get("cells_moved", 0),
		statistics.get("cells_visited", 0),
		statistics.get("cells_skipped", 0),
		statistics.get("worker_count", 1),
		statistics.get("worker_utilization_percent", 0.0),
		renderer.cell_pixel_size,
		camera.zoom.x,
		renderer.cell_pixel_size * camera.zoom.x,
		renderer.last_chunks_rendered,
		renderer.last_dirty_pixels,
		renderer.last_upload_pixels,
		renderer.last_update_ms,
	]
	if not _phase10_view.is_empty() and world.has_method("get_power_statistics"):
		var phase10_power: Dictionary = world.get_power_statistics()
		var phase10_mechanical: Dictionary = world.get_mechanical_statistics()
		diagnostics_label.text += "\n\nPOWER / MECHANICAL\ngrid networks/active %d / %d   poles/edges %d / %d\ngeneration/demand/delivered %d / %d / %d\nstorage %d / %d   power %.3f ms\nshaft networks/active %d / %d   segments %d\nrotational energy %d   inertia %d   mechanical %.3f ms" % [
			phase10_power.get("networks", 0), phase10_power.get("active_networks", 0), phase10_power.get("poles", 0), phase10_power.get("edges", 0),
			phase10_power.get("generation", 0), phase10_power.get("demand", 0), phase10_power.get("delivered", 0),
			phase10_power.get("storage", 0), phase10_power.get("storage_capacity", 0), float(phase10_power.get("power_usec", 0)) / 1000.0,
			phase10_mechanical.get("networks", 0), phase10_mechanical.get("active_networks", 0), phase10_mechanical.get("segments", 0),
			phase10_mechanical.get("rotational_energy", 0), phase10_mechanical.get("inertia", 0), float(phase10_mechanical.get("mechanical_usec", 0)) / 1000.0,
		]
	if _phase8_view == "diagnostics":
		var quick_pipe: Dictionary = world.get_pipe_statistics()
		var quick_wet: Dictionary = world.get_wet_processing_statistics()
		diagnostics_label.text += "\n\nPHASE 8 FLUID\nPipe active/total %d/%d   visited %d\nflow transfers %d   mass %d   %.3f ms\nPumps/Valves %d/%d   total leak %d\nSluice moved/captured %d/%d   %.3f ms" % [
			quick_pipe.segments_active, quick_pipe.segments_total, quick_pipe.segments_visited,
			quick_pipe.transfers, quick_pipe.mass_total, float(quick_pipe.pipe_usec) / 1000.0,
			quick_pipe.pumps, quick_pipe.valves, quick_pipe.leak_mass_total,
			quick_wet.grains_moved, quick_wet.heavy_captured, float(quick_wet.wet_usec) / 1000.0,
		]
	var generation: Dictionary = world.get_generation_statistics()
	var profile: Dictionary = world.get_geology_profile_at(cursor)
	diagnostics_label.text += (
		"\nSTREAMING / GEOLOGY\n"
		+ "seed %d   queue/in flight %d/%d\ncompleted/published %d/%d\ngen avg/worst %.3f/%.3f ms   evicted %d\n"
		+ "cursor material %d   profile %d\nSi %.2f%%   Fe %.2f%%\nheavy %.2f%%   other %.2f%%   Au %.3f ppm"
	) % [
		_world_seed,
		generation.get("queued", 0),
		generation.get("in_flight", 0),
		generation.get("completed", 0),
		generation.get("published_last_frame", 0),
		float(generation.get("generation_usec_average", 0.0)) / 1000.0,
		float(generation.get("generation_usec_worst", 0.0)) / 1000.0,
		generation.get("evicted_total", 0),
		world.get_cell(cursor),
		profile.get("profile_id", 0),
		float(profile.get("silica_fraction", 0.0)) * 100.0,
		float(profile.get("iron_fraction", 0.0)) * 100.0,
		float(profile.get("heavy_minerals_fraction", 0.0)) * 100.0,
		float(profile.get("other_fraction", 0.0)) * 100.0,
		profile.get("gold_ppm", 0.0),
	]
	var material_id: int = world.get_cell(cursor)
	var material_definition := materials.get_definition(material_id)
	var material_name := material_definition.display_name if material_definition != null else "Empty"
	var material_amount: int = world.get_material_amount(cursor) if world.has_method("get_material_amount") else (255 if material_id != 0 else 0)
	var material_temperature: int = world.get_temperature(cursor)
	var phase_progress: int = world.get_phase_energy(cursor) if world.has_method("get_phase_energy") else 0
	var provenance: int = world.get_provenance(cursor)
	var signature: int = world.get_mineral_signature(cursor)
	var constituent_names := ["SILICA", "IRON_BEARING", "HEAVY_MINERAL", "GOLD_BEARING", "OTHER"]
	var constituent: int = world.get_hidden_constituent(provenance, signature) if provenance > 0 else -1
	diagnostics_label.text += "\nmaterial %s (%d)   amount %d\ntemperature %.1f °C   phase progress %d\nprovenance/signature %d / %d\nhidden constituent %s" % [
		material_name, material_id, material_amount, float(material_temperature) * 0.25 - 273.15, phase_progress,
		provenance, signature, constituent_names[constituent] if constituent >= 0 else "n/a"
	]
	var structures: Dictionary = world.get_structure_statistics()
	var processing: Dictionary = world.get_processing_statistics()
	var bank_stats: Dictionary = world.get_bank_statistics()
	diagnostics_label.text += (
		"\n\nFACTORY LOGISTICS\n"
		+ "structures/chunks %d / %d\nbelts total/active %d / %d\nconsidered/skipped %d / %d\nmoves/blocked %d / %d\n"
		+ "machines %d   logistics %.3f ms\nrender tiles %d   update %.3f ms\n\nPROCESSING\n"
		+ "total/active/sleeping %d / %d / %d\nvisited %d   machine %.3f ms\ninputs/outputs %d / %d\nblocked/fuel-starved %d / %d\n"
		+ "Sieve/Magnetic/Furnace %d / %d / %d\nGlass/Iron/Gold/Residue/Ash %d / %d / %d / %d / %d"
	) % [
		structures.get("structures_allocated", 0), structures.get("structure_bearing_chunks", 0),
		structures.get("belts_total", 0), structures.get("belts_active", 0),
		structures.get("belts_considered", 0), structures.get("belts_skipped", 0),
		structures.get("belt_moves", 0), structures.get("blocked_belt_attempts", 0),
		structures.get("machine_entities", 0), float(structures.get("logistics_usec", 0)) / 1000.0,
		structure_renderer.last_render_tiles, structure_renderer.last_update_ms,
		processing.get("machines_total", 0), processing.get("machines_active", 0), processing.get("machines_sleeping", 0),
		processing.get("machines_visited", 0), float(processing.get("machine_processing_usec", 0)) / 1000.0,
		processing.get("inputs_consumed", 0), processing.get("outputs_emitted", 0),
		processing.get("blocked_machines", 0), processing.get("fuel_starved_furnaces", 0),
		processing.get("sieve_processed_total", 0), processing.get("magnetic_processed_total", 0), processing.get("furnace_processed_total", 0),
		processing.get("glass_total", 0), processing.get("iron_total", 0), processing.get("gold_total", 0), processing.get("residue_total", 0), processing.get("ash_total", 0),
	]
	diagnostics_label.text += "\n\nRESEARCH BANK\nreserves G/I/Au %d / %d / %d\nbanks total/active/visited %d / %d / %d\naccepted/rejected/blocked %d / %d / %d   %.3f ms" % [
		progression.glass, progression.iron, progression.gold,
		bank_stats.banks_total, bank_stats.banks_active, bank_stats.banks_visited,
		bank_stats.accepted_cells, bank_stats.rejected_cells, bank_stats.blocked_banks, float(bank_stats.bank_usec) / 1000.0,
	]
	var automation: Dictionary = world.get_automation_statistics()
	diagnostics_label.text += "\n\nAUTOMATION\ncomponents/awake %d / %d   wires %d\ndirty/changed %d / %d\nsensors/logic %d / %d   actuators %d\ncircuit %.3f ms   topology %.3f ms" % [
		automation.components_total, automation.components_awake, automation.wires_total,
		automation.dirty_nodes, automation.signals_changed, automation.sensor_evaluations,
		automation.logic_evaluations, automation.actuator_changes, automation.circuit_ms, automation.topology_rebuild_ms,
	]
	if world.has_method("get_power_statistics") and _phase10_view.is_empty():
		var power: Dictionary = world.get_power_statistics()
		var mechanical: Dictionary = world.get_mechanical_statistics()
		diagnostics_label.text += "\n\nPOWER / MECHANICAL\ngrid networks/active %d / %d   poles/edges %d / %d\ngeneration/demand/delivered %d / %d / %d\nstorage %d / %d   power %.3f ms\nshaft networks/active %d / %d   segments %d\nrotational energy %d   inertia %d   mechanical %.3f ms" % [
			power.get("networks", 0), power.get("active_networks", 0), power.get("poles", 0), power.get("edges", 0),
			power.get("generation", 0), power.get("demand", 0), power.get("delivered", 0),
			power.get("storage", 0), power.get("storage_capacity", 0), float(power.get("power_usec", 0)) / 1000.0,
			mechanical.get("networks", 0), mechanical.get("active_networks", 0), mechanical.get("segments", 0),
			mechanical.get("rotational_energy", 0), mechanical.get("inertia", 0), float(mechanical.get("mechanical_usec", 0)) / 1000.0,
		]
	if world.has_method("get_pipe_statistics"):
		var pipe_stats: Dictionary = world.get_pipe_statistics()
		var wet_stats: Dictionary = world.get_wet_processing_statistics()
		diagnostics_label.text += "\n\nFLUID LOGISTICS\nsegments active/total %d / %d   visited %d\ntransfers %d   mass %d   %.3f ms\npump/valve work %d / %d   leaks %d\nsluices active/total %d / %d   wet %.3f ms\ngrains moved/captured %d / %d" % [
			pipe_stats.segments_active, pipe_stats.segments_total, pipe_stats.segments_visited,
			pipe_stats.transfers, pipe_stats.mass_total, float(pipe_stats.pipe_usec) / 1000.0,
			pipe_stats.pump_work, pipe_stats.valve_work, pipe_stats.leak_mass_total,
			wet_stats.sluices_active, wet_stats.sluices_total, float(wet_stats.wet_usec) / 1000.0,
			wet_stats.grains_moved, wet_stats.heavy_captured,
		]
	if automation_renderer.wiring_mode:
		_update_automation_inspector()
	var machine: Dictionary = world.get_machine_state_at(cursor)
	if not machine.is_empty():
		var states := ["IDLE", "NO_INPUT", "NO_FUEL", "RUNNING", "OUTPUT_BLOCKED", "ASH_BLOCKED", "ACCEPTING", "REJECTING", "REJECT_BLOCKED", "INPUT_BLOCKED"]
		diagnostics_label.text += "\n\nMACHINE INSPECTOR\nstate %s   input %d   result %d\nprogress %d/%d   fuel %d   ash %s\nprocessed/emitted %d/%d   route %d" % [
			states[clampi(int(machine.state), 0, states.size() - 1)], machine.current_input, machine.result_waiting,
			machine.progress_ticks, machine.process_ticks, machine.fuel_remaining, str(machine.ash_waiting),
			machine.processed_cells, machine.emitted_cells, machine.last_output_route,
		]
	if world.has_method("get_pipe_state"):
		var pipe: Dictionary = world.get_pipe_state(cursor)
		if not pipe.is_empty():
			var fluid_definition := materials.get_definition(int(pipe.get("fluid_type", 0)))
			var fluid_name := fluid_definition.display_name if fluid_definition != null else "Empty"
			diagnostics_label.text += "\n\nFLUID INSPECTOR\n%s %d / 65535   fill %d/1000\nflow %d   temp %.1f °C   pressure %d\nhealth %d   %s" % [
				fluid_name, pipe.get("mass", 0), int(int(pipe.get("mass", 0)) * 1000 / 65535), pipe.get("flow", 0),
				float(pipe.get("temperature", 0)) * 0.25 - 273.15, pipe.get("pressure", 0), pipe.get("health", 0), pipe.get("state", "IDLE"),
			]
	if world.has_method("get_power_state_at"):
		var power_state: Dictionary = world.get_power_state_at(cursor)
		if not power_state.is_empty() and int(power_state.get("type_id", 0)) >= 26:
			diagnostics_label.text += "\n\nPOWER INSPECTOR\nmechanical/grid %d / %d   speed %d mRPM\nstate %d   throttle %d/1000\ngeneration/load %d / %d   satisfaction %d/1000" % [
				power_state.get("mechanical_network_id", 0), power_state.get("power_network_id", 0), power_state.get("speed_millirpm", 0),
				power_state.get("state", 0), power_state.get("throttle", 0),
				power_state.get("electrical_output", 0), power_state.get("requested_rate", 0), power_state.get("satisfaction", 0),
			]


func _parse_capture_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-showcase="):
			_capture_path = argument.trim_prefix("--capture-showcase=")
		elif argument.begins_with("--capture-tick="):
			_capture_tick = argument.trim_prefix("--capture-tick=").to_int()
		elif argument == "--capture-debug":
			diagnostics_visible = true
			diagnostics_panel.visible = true
			overlay.set_chunk_debug(true)
		elif argument == "--capture-geology":
			_geology_visible = true
			overlay.set_geology_heatmap(true)
		elif argument.begins_with("--world-seed="):
			_world_seed = argument.trim_prefix("--world-seed=").to_int()
		elif argument.begins_with("--capture-camera-x="):
			camera.position.x = argument.trim_prefix("--capture-camera-x=").to_float() * renderer.cell_pixel_size
		elif argument.begins_with("--capture-camera-y="):
			camera.position.y = argument.trim_prefix("--capture-camera-y=").to_float() * renderer.cell_pixel_size
		elif argument.begins_with("--benchmark-runtime-ticks="):
			_runtime_benchmark_ticks = argument.trim_prefix("--benchmark-runtime-ticks=").to_int()
		elif argument == "--empty-world":
			_showcase_enabled = false
		elif argument.begins_with("--phase3-view="):
			_phase4_view = argument.trim_prefix("--phase3-view=")
		elif argument.begins_with("--phase4-view="):
			_phase4_view = argument.trim_prefix("--phase4-view=")
		elif argument.begins_with("--phase5-view="):
			_phase5_view = argument.trim_prefix("--phase5-view=")
		elif argument.begins_with("--phase6-view="):
			_phase6_view = argument.trim_prefix("--phase6-view=")
		elif argument.begins_with("--phase65-view="):
			_phase65_view = argument.trim_prefix("--phase65-view=")
		elif argument.begins_with("--phase7-view="):
			_phase7_view = argument.trim_prefix("--phase7-view=")
		elif argument.begins_with("--phase8-view="):
			_phase8_view = argument.trim_prefix("--phase8-view=")
		elif argument.begins_with("--phase875-view="):
			_phase875_view = argument.trim_prefix("--phase875-view=")
		elif argument.begins_with("--phase9-view="):
			_phase9_view = argument.trim_prefix("--phase9-view=")
		elif argument.begins_with("--phase10-view="):
			_phase10_view = argument.trim_prefix("--phase10-view=")
		elif argument.begins_with("--phase11-view="):
			_phase11_view = argument.trim_prefix("--phase11-view=")
		elif argument.begins_with("--phase12-view="):
			_phase12_view = argument.trim_prefix("--phase12-view=")
		elif argument.begins_with("--phase13-view="):
			_phase13_view = argument.trim_prefix("--phase13-view=")
		elif argument.begins_with("--phase135-view="):
			_phase135_view = argument.trim_prefix("--phase135-view=")
		elif argument.begins_with("--phase136-view="):
			_phase136_view = argument.trim_prefix("--phase136-view=")
		elif argument.begins_with("--validate-seeds="):
			_validate_seeds = clampi(argument.trim_prefix("--validate-seeds=").to_int(), 1, 1000000)
		elif argument.begins_with("--validate-seed-start="):
			_validate_seed_start = argument.trim_prefix("--validate-seed-start=").to_int()
		elif argument == "--creative":
			_creative_fixture = true
		elif argument == "--capture-1080p":
			get_window().content_scale_size = Vector2i(1920, 1080)
			get_window().size = Vector2i(1920, 1080)
		elif argument.begins_with("--capture-size="):
			var dimensions := argument.trim_prefix("--capture-size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				var capture_size := Vector2i(dimensions[0].to_int(), dimensions[1].to_int())
				get_window().content_scale_size = capture_size
				get_window().size = capture_size
		elif argument == "--dense-factory":
			_dense_factory_benchmark = true
		elif argument == "--realistic-max-factory":
			_realistic_max_factory_benchmark = true
		elif argument == "--owner-package-smoke":
			_owner_package_smoke = true
		elif argument == "--dense-progression":
			_dense_progression_benchmark = true
		elif argument == "--dense-automation":
			_dense_automation_benchmark = true
		elif argument == "--dense-physical":
			_dense_physical_benchmark = true
		elif argument == "--dense-water":
			_dense_water_benchmark = true
		elif argument == "--dense-phase8":
			_dense_phase8_benchmark = true
		elif argument.begins_with("--phase85-render="):
			_phase85_render_benchmark = argument.trim_prefix("--phase85-render=")
		elif argument == "--phase85-temperature-overlay":
			_phase85_temperature_overlay = true
		elif argument == "--phase85-renderer=legacy-pipe":
			_phase85_renderer_mode = 1
		elif argument == "--phase85-renderer=legacy-double":
			_phase85_renderer_mode = 2
		elif argument == "--phase85-thermal-load":
			_phase85_thermal_load = true
	if not _phase135_view.is_empty():
		_configure_phase135_capture_source()
	if not _phase136_view.is_empty():
		_configure_phase136_capture_source()
	if not _capture_path.is_empty() and _capture_tick < 0:
		_capture_tick = 30
	if _runtime_benchmark_ticks >= 0:
		get_window().content_scale_size = Vector2i(1920, 1080)
		get_window().size = Vector2i(1920, 1080)
		print("runtime benchmark armed ticks=%d" % _runtime_benchmark_ticks)


func _maybe_queue_capture() -> void:
	if _capture_path.is_empty() or _capture_queued or world == null:
		return
	if int(world.get_statistics().get("tick", 0)) < _capture_tick:
		return
	_capture_queued = true
	call_deferred("_capture_runtime_frame")


func _capture_runtime_frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_capture_path)
	print("CAPTURE: %s error=%s" % [_capture_path, error_string(error)])
	get_tree().quit(0 if error == OK else 1)


func _maybe_finish_runtime_benchmark() -> void:
	if not _runtime_benchmark_started or _runtime_benchmark_finished:
		return
	var statistics: Dictionary = world.get_statistics()
	if int(statistics.get("tick", 0)) - _runtime_benchmark_start_tick < _runtime_benchmark_ticks:
		return
	_runtime_benchmark_finished = true
	var elapsed_seconds := float(Time.get_ticks_usec() - _runtime_benchmark_start_usec) / 1000000.0
	var average_sim_ms := _simulation_total_ms / maxf(1.0, float(_simulation_samples))
	var average_render_ms := _render_total_ms / maxf(1.0, float(_render_samples))
	_runtime_frame_samples.sort()
	_runtime_sim_samples.sort()
	var p95_ms := _percentile(_runtime_frame_samples, 0.95)
	var p99_ms := _percentile(_runtime_frame_samples, 0.99)
	var sim_p95_ms := _percentile(_runtime_sim_samples, 0.95)
	var sim_p99_ms := _percentile(_runtime_sim_samples, 0.99)
	var worst_frame_ms := _runtime_frame_samples[-1] if not _runtime_frame_samples.is_empty() else 0.0
	var processing: Dictionary = world.get_processing_statistics()
	var automation: Dictionary = world.get_automation_statistics()
	var physical: Dictionary = world.get_physical_processing_statistics()
	print(
		"runtime_1080p resolution=%dx%d renderer=%s frames=%d ticks=%d elapsed_s=%.3f fps=%.1f frame_avg_ms=%.3f frame_p95_ms=%.3f frame_p99_ms=%.3f frame_worst_ms=%.3f sim_latest_ms=%.3f sim_avg_ms=%.3f sim_worst_ms=%.3f simulation_hz=%.1f material_render_avg_ms=%.3f structure_render_update_ms=%.3f wire_topology_ms=%.3f wire_draw_ms=%.3f structure_tiles=%d machine_instances=%d logistics_avg_ms=%.3f machine_avg_ms=%.3f bank_avg_ms=%.3f automation_avg_ms=%.4f ui_avg_ms=%.4f overlay_update_ms=%.4f overlay_draw_ms=%.4f magnetic_ms=%.4f screen_ms=%.4f heat_ms=%.4f magnetic_cells=%d magnetic_moves=%d screen_grains=%d screen_passes=%d heated_cells=%d heat_reactions=%d automation_components=%d wires=%d awake=%d sensors=%d logic=%d signals_changed=%d actuator_changes=%d machines_total=%d machines_active=%d machines_visited=%d blocked=%d belts_considered_avg=%d belts_considered_peak=%d belt_moves_total=%d active_chunks=%d active_rectangles=%d active_region_cells=%d cells_visited=%d cells_moved=%d dirty_render_pixels=%d upload_pixels=%d workers=%d worker_utilization_percent=%.1f"
		% [
			get_viewport_rect().size.x,
			get_viewport_rect().size.y,
			RenderingServer.get_current_rendering_method(),
			_runtime_benchmark_frames,
			statistics.get("tick", 0),
			elapsed_seconds,
			float(_runtime_benchmark_frames) / maxf(0.001, elapsed_seconds),
			_runtime_benchmark_delta_seconds * 1000.0 / maxf(1.0, float(_runtime_benchmark_frames)), p95_ms, p99_ms, worst_frame_ms,
			_simulation_latest_ms,
			average_sim_ms,
			_simulation_worst_ms,
			1000.0 / maxf(0.001, average_sim_ms),
			average_render_ms, structure_renderer.last_update_ms, automation_renderer.last_topology_rebuild_ms, automation_renderer.last_wire_draw_ms, structure_renderer.last_render_tiles, structure_renderer.last_machine_instances,
			float(_runtime_logistics_total_usec) / maxf(1.0, float(_runtime_logistics_samples)) / 1000.0,
			float(_runtime_machine_total_usec) / maxf(1.0, float(_runtime_machine_samples)) / 1000.0,
			float(_runtime_bank_total_usec) / maxf(1.0, float(_runtime_bank_samples)) / 1000.0,
			_runtime_automation_total_ms / maxf(1.0, float(_runtime_automation_samples)),
			_runtime_ui_total_ms / maxf(1.0, float(_runtime_ui_samples)),
			map_overlay_renderer.last_update_ms, map_overlay_renderer.last_draw_ms,
			float(physical.magnetic_usec) / 1000.0, float(physical.screen_usec) / 1000.0, float(physical.heat_usec) / 1000.0,
			physical.magnetic_cells_tested, physical.magnetic_moves, physical.screen_grains_tested, physical.screen_passes,
			physical.heated_cells, physical.heat_reactions,
			automation.components_total, automation.wires_total, automation.components_awake, automation.sensor_evaluations,
			automation.logic_evaluations, automation.signals_changed, automation.actuator_changes,
			processing.get("machines_total", 0), processing.get("machines_active", 0), processing.get("machines_visited", 0), processing.get("blocked_machines", 0),
			_runtime_belts_considered_total / maxi(1, _runtime_logistics_samples), _runtime_belts_considered_peak, _runtime_belt_moves_total,
			statistics.get("active_chunks", 0),
			statistics.get("active_rectangles", 0),
			statistics.get("active_region_cells", 0),
			statistics.get("cells_visited", 0),
			statistics.get("cells_moved", 0),
			statistics.get("dirty_render_pixels", 0),
			statistics.get("render_upload_pixels", 0),
			statistics.get("worker_count", 1),
			statistics.get("worker_utilization_percent", 0.0),
		]
	)
	var fluid: Dictionary = world.get_fluid_statistics()
	print(
		"runtime_phase7 sim_p95_ms=%.3f sim_p99_ms=%.3f granular_ms=%.3f granular_barrier_ms=%.3f fluid_ms=%.3f fluid_barrier_ms=%.3f fluid_active=%d fluid_visited=%d fluid_transfers=%d fluid_mass=%d fluid_plane_chunks=%d fluid_plane_bytes=%d fluid_activity_bytes=%d water_upload_avg_ms=%.3f water_upload_avg_bytes=%d"
		% [
			sim_p95_ms, sim_p99_ms,
			float(statistics.get("granular_usec", 0)) / 1000.0,
			float(statistics.get("granular_barrier_usec", 0)) / 1000.0,
			float(fluid.get("fluid_usec", 0)) / 1000.0,
			float(fluid.get("fluid_barrier_usec", 0)) / 1000.0,
			fluid.get("fluid_cells_active", 0), fluid.get("fluid_cells_visited", 0), fluid.get("fluid_transfers", 0),
			fluid.get("fluid_mass_total", 0), fluid.get("fluid_plane_chunks", 0), fluid.get("fluid_plane_bytes", 0), fluid.get("fluid_activity_bytes", 0),
			_runtime_water_upload_total_ms / maxf(1.0, float(_runtime_water_upload_samples)),
			_runtime_water_upload_total_bytes / maxi(1, _runtime_water_upload_samples),
		]
	)
	if world.has_method("get_pipe_statistics"):
		var pipe: Dictionary = world.get_pipe_statistics()
		var wet: Dictionary = world.get_wet_processing_statistics()
		print(
			"runtime_phase8 pipe_ms=%.3f pipe_segments=%d pipe_active=%d pipe_visited=%d pipe_transfers=%d pumps=%d valves=%d intakes=%d outlets=%d breached=%d pump_work=%d valve_work=%d intake_mass=%d outlet_mass=%d leak_mass=%d pipe_mass=%d pipe_memory_bytes=%d pipe_scheduler_bytes=%d wet_ms=%.3f sluices=%d wet_cells_visited=%d wet_grains_moved=%d wet_heavy_captured=%d"
			% [
				float(pipe.get("pipe_usec", 0)) / 1000.0, pipe.get("segments_total", 0), pipe.get("segments_active", 0),
				pipe.get("segments_visited", 0), pipe.get("transfers", 0), pipe.get("pumps", 0), pipe.get("valves", 0), pipe.get("intakes", 0), pipe.get("outlets", 0), pipe.get("breached_segments", 0), pipe.get("pump_work", 0), pipe.get("valve_work", 0),
				pipe.get("intake_mass", 0), pipe.get("outlet_mass", 0), pipe.get("leak_mass_total", 0), pipe.get("mass_total", 0),
				pipe.get("record_bytes", 0), pipe.get("scheduler_key_bytes", 0), float(wet.get("wet_usec", 0)) / 1000.0,
				wet.get("sluices_total", 0), wet.get("cells_visited", 0), wet.get("grains_moved", 0), wet.get("heavy_captured", 0),
			]
		)
		var memory: Dictionary = world.get_memory_layout()
		print("runtime_phase8_memory base_cell_bytes=%d allocated_cells=%d base_backing_bytes=%d water_planes=%d water_plane_bytes=%d water_activity_bytes=%d structure_backing_bytes=%d pipe_record_bytes=%d pipe_records=%d pipe_backing_bytes=%d pipe_scheduler_bytes=%d render_batches=3" % [
			memory.simulation_bytes_per_cell, statistics.get("allocated_cells", 0), statistics.get("simulation_backing_bytes", 0),
			memory.liquid_mass_plane_chunks, memory.liquid_mass_backing_bytes, memory.liquid_activity_backing_bytes,
			memory.structure_backing_bytes, memory.pipe_segment_bytes, memory.pipe_segments, memory.pipe_fluid_backing_bytes, memory.pipe_scheduler_key_bytes,
		])
	var frame_average := _runtime_benchmark_delta_seconds * 1000.0 / maxf(1.0, float(_runtime_benchmark_frames))
	var structure_samples := maxf(1.0, float(_runtime_structure_samples))
	print("runtime_phase85_render fixture=%s pages=%d visible_pipes=%d fps=%.1f frame_avg_ms=%.3f frame_p95_ms=%.3f frame_p99_ms=%.3f frame_worst_ms=%.3f visibility_avg_ms=%.4f cpu_prepare_avg_ms=%.4f upload_avg_ms=%.4f upload_avg_bytes=%d render_residual_ms=%.3f draw_calls=%d objects=%d" % [
		_phase85_render_benchmark if not _phase85_render_benchmark.is_empty() else "representative",
		structure_renderer.last_page_count, structure_renderer.last_pipe_instances,
		float(_runtime_benchmark_frames) / maxf(0.001, elapsed_seconds), frame_average, p95_ms, p99_ms, worst_frame_ms,
		_runtime_structure_visibility_ms / structure_samples, _runtime_structure_prepare_ms / structure_samples,
		_runtime_structure_upload_ms / structure_samples, _runtime_structure_upload_bytes / maxi(1, _runtime_structure_samples),
		maxf(0.0, frame_average - average_sim_ms - average_render_ms - _runtime_ui_total_ms / maxf(1.0, float(_runtime_ui_samples))),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	])
	print("runtime_phase85_temperature overlay=%s visible_page_update_ms=%.4f upload_ms=%.4f upload_bytes=%d draw_ms=%.4f" % [
		"on" if _phase85_temperature_overlay or _phase9_view == "temperature" else "off", map_overlay_renderer.last_update_ms,
		map_overlay_renderer.last_upload_ms, map_overlay_renderer.last_upload_bytes, map_overlay_renderer.last_draw_ms,
	])
	var thermal: Dictionary = world.get_thermal_candidate_statistics() if _phase85_thermal_load else {}
	print("runtime_phase85_thermal enabled=%s cadence_hz=30 avg_ms=%.4f latest_ms=%.4f active=%d visited=%d exchanges=%d barrier_us=%d workers=%d activity_bytes=%d scratch_bytes=%d hash=%s" % [
		"true" if _phase85_thermal_load else "false", _runtime_thermal_total_ms / maxf(1.0, float(_runtime_thermal_samples)),
		float(thermal.get("thermal_usec", 0)) / 1000.0, thermal.get("active_cells", 0), thermal.get("visited_cells", 0),
		thermal.get("exchanges", 0), thermal.get("barrier_usec", 0), thermal.get("workers_used", 0),
		thermal.get("activity_bytes", 0), thermal.get("scratch_bytes", 0), thermal.get("hash", "none"),
	])
	_runtime_phase9_thermal_ms.sort(); _runtime_phase9_gas_ms.sort(); _runtime_phase9_fluid_ms.sort(); _runtime_phase9_pipe_ms.sort()
	var production_thermal: Dictionary = world.get_thermal_statistics()
	var production_gas: Dictionary = world.get_gas_statistics()
	var production_pipe: Dictionary = world.get_pipe_statistics()
	print("runtime_phase9 fixture=%s thermal_avg_ms=%.4f thermal_p99_ms=%.4f gas_avg_ms=%.4f gas_p99_ms=%.4f fluid_avg_ms=%.4f fluid_p99_ms=%.4f pipe_avg_ms=%.4f pipe_p99_ms=%.4f thermal_active=%d thermal_visited=%d thermal_exchanges=%d phase_changes=%d gas_active=%d gas_visited=%d gas_transfers=%d steam_generated=%d steam_condensed=%d pipe_steam_mass=%d pipe_water_mass=%d pipe_breaches=%d" % [
		_phase9_view if not _phase9_view.is_empty() else "none",
		_average_samples(_runtime_phase9_thermal_ms), _percentile(_runtime_phase9_thermal_ms, 0.99),
		_average_samples(_runtime_phase9_gas_ms), _percentile(_runtime_phase9_gas_ms, 0.99),
		_average_samples(_runtime_phase9_fluid_ms), _percentile(_runtime_phase9_fluid_ms, 0.99),
		_average_samples(_runtime_phase9_pipe_ms), _percentile(_runtime_phase9_pipe_ms, 0.99),
		production_thermal.get("active_cells", 0), production_thermal.get("visited_cells", 0), production_thermal.get("exchanges", 0), production_thermal.get("phase_changes_total", 0),
		production_gas.get("active_cells", 0), production_gas.get("visited_cells", 0), production_gas.get("transfers", 0), production_gas.get("steam_generated", 0), production_gas.get("steam_condensed", 0),
		production_pipe.get("steam_mass", 0), production_pipe.get("water_mass", 0), production_pipe.get("breached_segments", 0),
	])
	var power: Dictionary = world.get_power_statistics()
	var mechanical: Dictionary = world.get_mechanical_statistics()
	var energy: Dictionary = world.get_energy_accounting()
	print("runtime_phase10 fixture=%s mechanical_ms=%.4f mechanical_topology_ms=%.4f shaft_segments=%d shaft_networks=%d shaft_active=%d power_ms=%.4f power_topology_ms=%.4f power_networks=%d power_active=%d poles=%d edges=%d consumers=%d generators=%d accumulators=%d generation=%d demand=%d delivered=%d storage=%d storage_capacity=%d thermal_in=%d mechanical_produced=%d electrical_produced=%d electrical_consumed=%d turbine_losses=%d generator_losses=%d storage_losses=%d power_overlay_ms=%.4f" % [
		_phase10_view if not _phase10_view.is_empty() else "none",
		float(mechanical.get("mechanical_usec", 0)) / 1000.0, float(mechanical.get("topology_usec", 0)) / 1000.0,
		mechanical.get("segments", 0), mechanical.get("networks", 0), mechanical.get("active_networks", 0),
		float(power.get("power_usec", 0)) / 1000.0, float(power.get("topology_usec", 0)) / 1000.0,
		power.get("networks", 0), power.get("active_networks", 0), power.get("poles", 0), power.get("edges", 0), power.get("consumers", 0), power.get("generators", 0), power.get("accumulators", 0),
		power.get("generation", 0), power.get("demand", 0), power.get("delivered", 0), power.get("storage", 0), power.get("storage_capacity", 0),
		energy.get("thermal_into_turbines", 0), energy.get("mechanical_produced", 0), energy.get("electrical_produced", 0), energy.get("electrical_consumed", 0),
		energy.get("turbine_losses", 0), energy.get("generator_losses", 0), energy.get("storage_losses", 0), map_overlay_renderer.last_update_ms,
	])
	var generation: Dictionary = world.get_generation_statistics()
	var identity: Dictionary = world.get_world_identity()
	var vision: Dictionary = world.get_visibility_statistics(KoalaCharacterController.VISIBILITY_OWNER_ID)
	print("runtime_phase11 fixture=%s preset=%d control_mode=%d progression_mode=%d visibility_policy=%d seed=%d generation_version=%d settings_hash=%s resident_chunks=%d generated_total=%d evicted_total=%d queue_peak=%d generation_avg_ms=%.4f generation_worst_ms=%.4f publish_last_ms=%.4f character_cell=%s collision_ms=%.4f collision_cells=%d fov_ms=%.4f fov_cells=%d discovered_chunks=%d discovery_bytes=%d visibility_render_ms=%.4f visibility_upload_bytes=%d" % [
		_phase11_view if not _phase11_view.is_empty() else "none", _game_session.preset_id, _game_session.control_mode,
		_game_session.progression_mode, _game_session.visibility_policy, identity.get("seed", 0), identity.get("generation_version", 0),
		identity.get("generator_settings_hash", "none"), world.chunk_count(), generation.get("generated_total", 0), generation.get("evicted_total", 0),
		generation.get("queue_peak", 0), float(generation.get("generation_usec_average", 0)) / 1000.0,
		float(generation.get("generation_usec_worst", 0)) / 1000.0, float(generation.get("publish_usec_last_frame", 0)) / 1000.0,
		str(_character.world_cell()) if _character != null else "none", float(vision.get("collision_usec", 0)) / 1000.0,
		vision.get("collision_cells_sampled", 0), float(vision.get("visibility_usec", 0)) / 1000.0, vision.get("cells_sampled", 0),
		vision.get("discovered_chunks", 0), vision.get("total_bytes", 0), _visibility_renderer.last_update_ms if _visibility_renderer != null else 0.0,
		_visibility_renderer.last_upload_bytes if _visibility_renderer != null else 0,
	])
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	if _audio_mixer != null:
		_audio_mixer.shutdown()
		_audio_mixer.queue_free()
		_audio_mixer = null
		# Let the audio server consume the stopped voices before engine teardown.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _maybe_start_runtime_benchmark() -> void:
	if _runtime_benchmark_ticks < 0 or _runtime_benchmark_started:
		return
	var warmup_frames := 120 if _dense_factory_benchmark or _realistic_max_factory_benchmark or _dense_progression_benchmark or _dense_automation_benchmark or _dense_physical_benchmark or _dense_water_benchmark or _dense_phase8_benchmark or not _phase85_render_benchmark.is_empty() or not _phase9_view.is_empty() or not _phase10_view.is_empty() else 30
	if Engine.get_process_frames() < warmup_frames:
		return
	_runtime_benchmark_started = true
	_runtime_benchmark_start_tick = int(world.get_statistics().get("tick", 0))
	_runtime_benchmark_start_usec = Time.get_ticks_usec()
	_runtime_benchmark_frames = 0
	_runtime_benchmark_delta_seconds = 0.0
	_simulation_latest_ms = 0.0
	_simulation_total_ms = 0.0
	_simulation_worst_ms = 0.0
	_simulation_samples = 0
	_render_total_ms = 0.0
	_render_samples = 0
	_runtime_frame_samples.clear()
	_runtime_sim_samples.clear()
	_runtime_water_upload_total_ms = 0.0
	_runtime_water_upload_total_bytes = 0
	_runtime_water_upload_samples = 0
	_runtime_logistics_total_usec = 0
	_runtime_logistics_samples = 0
	_runtime_belts_considered_total = 0
	_runtime_belts_considered_peak = 0
	_runtime_belt_moves_total = 0
	_runtime_machine_total_usec = 0
	_runtime_machine_samples = 0
	_runtime_bank_total_usec = 0
	_runtime_bank_samples = 0
	_runtime_ui_total_ms = 0.0
	_runtime_ui_samples = 0
	_runtime_automation_total_ms = 0.0
	_runtime_automation_samples = 0
	_runtime_structure_visibility_ms = 0.0
	_runtime_structure_prepare_ms = 0.0
	_runtime_structure_upload_ms = 0.0
	_runtime_structure_upload_bytes = 0
	_runtime_structure_samples = 0
	_runtime_thermal_total_ms = 0.0
	_runtime_thermal_samples = 0
	_runtime_phase9_thermal_ms.clear()
	_runtime_phase9_gas_ms.clear()
	_runtime_phase9_fluid_ms.clear()
	_runtime_phase9_pipe_ms.clear()


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(ceili(float(values.size()) * fraction) - 1, 0, values.size() - 1)
	return values[index]

func _average_samples(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var total := 0.0
	for value in values: total += value
	return total / float(values.size())
