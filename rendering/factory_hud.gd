class_name FactoryHUD
extends Control

signal tool_selected(tool: Dictionary)
signal research_requested
signal overlay_selected(mode: int)
signal map_requested
signal codex_requested(entry_id: String)
signal experiments_requested
signal blueprints_requested
signal diagnostics_requested
signal planning_pause_requested

const PAGE_COUNT := 10
const SLOT_COUNT := 10
const CATALOG_NEW_MARKER := "NEW · "

var _world: Variant
var _pages: Array[Array] = []
var _slot_nodes: Array[ToolSlot] = []
var _active_page := 0
var _catalog: PanelContainer
var _catalog_grid: GridContainer
var _search: LineEdit
var _category_filter := "ALL"
var _status: Label
var _reserves: Label
var _overlay_menu: PopupMenu
var _statistics_panel: PanelContainer
var _statistics_text: Label
var _info_badge: Label
var _alert_text: Label
var _mode_badge: Label
var _page_label: Label
var _onboarding_hint: Label
var _inspector: PanelContainer
var _inspector_text: Label
var _inspector_advanced: Label
var _inspector_advanced_button: Button
var _inspector_codex_id := ""
var _planning_badge: Label
var _goal_title: Label
var _goal_criteria: Label
var _goal_help_id := "concept:construction"
var _action_row: HBoxContainer
var _ui_state := GameUIState.new()
var _onboarding := OnboardingState.new()
var _preset_id := GameModeCapabilities.Preset.FACTORY
var last_update_ms := 0.0
var _toast_tween: Tween
var _material_names: Dictionary = {}
var _tooltip_layer: ContextTooltipLayer
var _highlight_layer: GuidedHighlightLayer
var _toast_center: ToastCenter
var _controls_panel: PanelContainer
var _controls_text: Label
var _help_targets: Dictionary = {}
var _menu_visibility: Dictionary = {}
var _new_tool_keys: Dictionary = {}
var _top_bar: PanelContainer
var _bottom_dock: PanelContainer
var _action_group: VBoxContainer
var _quickbar_group: VBoxContainer
var _utility_group: VBoxContainer
var _catalog_scroll: ScrollContainer
var _goal_details: HBoxContainer
var _goal_button: Button
var _goal_help_button: Button
var _navigation_menu: PopupMenu
var _ui_scale := 1.0
var _category_buttons: Dictionary = {}
var _catalog_empty: Label
var _selected_tool_key := ""
var _goal_expanded := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = KoalaSandTheme.build()
	for page in PAGE_COUNT:
		_pages.append([])
	_build_hud()
	_install_help_layers()
	call_deferred("_relayout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		call_deferred("_relayout")


func apply_ui_scale(value: float) -> void:
	_ui_scale = clampf(value, 0.75, 2.0)
	call_deferred("_relayout")

func initialize(world: Variant) -> void:
	_world = world
	if _material_names.is_empty():
		var registry := MaterialRegistry.new()
		if registry.load_directory() == OK:
			for stable_id: int in registry.get_ids():
				var definition := registry.get_definition(stable_id)
				_material_names[stable_id] = definition.display_name if definition != null else "Material %d" % stable_id
	_build_tool_data()
	_refresh_slots()
	_refresh_catalog()
	refresh("SELECT TOOL", "1×")

func refresh(selected: String, speed: String) -> void:
	if _world == null:
		return
	var started := Time.get_ticks_usec()
	var progression: Dictionary = _world.get_progression_state()
	_reserves.text = "Glass %d  ·  Iron %d  ·  Gold %d" % [progression.glass, progression.iron, progression.gold]
	_status.text = "%s  ·  %s" % [selected, speed]
	last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0

func activate_slot(number: int) -> void:
	var slot := 9 if number == 0 else number - 1
	if slot < 0 or slot >= SLOT_COUNT:
		return
	var tool: Dictionary = _pages[_active_page][slot]
	if not tool.is_empty() and not bool(tool.get("locked", false)):
		tool_selected.emit(tool)

func toggle_catalog() -> void:
	_catalog.visible = not _catalog.visible
	if _catalog.visible:
		_close_internal_modals_except("build_catalog")
		_refresh_catalog()
		KoalaSandTheme.animate_in(_catalog)
		_ui_state.open_modal("build_catalog")
		_search.grab_focus()
		demonstrate_onboarding("OPEN_CATALOG")
	else:
		_ui_state.close_modal("build_catalog")
		if not _new_tool_keys.is_empty():
			_new_tool_keys.clear()
			_refresh_catalog()
	_sync_help_safe_regions()

func set_page(page: int) -> void:
	_active_page = wrapi(page, 0, PAGE_COUNT)
	if _page_label != null:
		_page_label.text = "QUICKBAR  %d / %d" % [_active_page + 1, PAGE_COUNT]
	_refresh_slots()

func change_page(delta: int) -> void:
	set_page(_active_page + delta)

func toggle_statistics() -> void:
	_statistics_panel.visible = not _statistics_panel.visible
	if _statistics_panel.visible:
		_close_internal_modals_except("statistics")
		KoalaSandTheme.animate_in(_statistics_panel)
		_ui_state.open_modal("statistics")
		_refresh_statistics()
	else:
		_ui_state.close_modal("statistics")
	_sync_help_safe_regions()

func set_info_mode(enabled: bool) -> void:
	_info_badge.visible = enabled

func show_alert(message: String) -> void:
	_alert_text.text = message
	_alert_text.visible = not message.is_empty()


func configure_mode(preset_id: int) -> void:
	_preset_id = clampi(preset_id, 0, 2)
	_onboarding.preset_id = _preset_id
	_mode_badge.text = ["FACTORY", "CHARACTER", "CREATIVE"][_preset_id]
	_mode_badge.add_theme_color_override("font_color", [KoalaSandTheme.COLOR_INFO, KoalaSandTheme.COLOR_SUCCESS, KoalaSandTheme.COLOR_ACCENT_BRIGHT][_preset_id])
	_overlay_menu.set_item_disabled(1, _preset_id == GameModeCapabilities.Preset.CHARACTER)
	_refresh_onboarding()


func set_onboarding_enabled(enabled: bool) -> void:
	_onboarding.enabled = enabled
	_refresh_onboarding()


func reset_onboarding() -> void:
	_onboarding.reset(_preset_id)
	_refresh_onboarding()


func complete_onboarding_goal(goal: String) -> void:
	_onboarding.complete(goal)
	_refresh_onboarding()


func demonstrate_onboarding(event_id: String) -> void:
	if _onboarding.demonstrate(event_id):
		_refresh_onboarding()


func onboarding_state() -> OnboardingState:
	return _onboarding


func refresh_unlocks() -> void:
	if _world == null or not has_meta("catalog_tools"):
		return
	var structure_definitions := {}
	for definition: Dictionary in _world.get_structure_definitions():
		structure_definitions[int(definition.type_id)] = definition
	var automation_definitions := {}
	for definition: Dictionary in _world.get_automation_definitions():
		automation_definitions[int(definition.type_id)] = definition
	var refreshed_by_key := {}
	var tools: Array = get_meta("catalog_tools")
	for tool: Dictionary in tools:
		var was_locked := bool(tool.get("locked", false))
		if str(tool.kind) == "structure":
			tool.locked = not _world.is_structure_unlocked(int(tool.id))
			tool.help = HelpCatalog.component(int(tool.id), Dictionary(structure_definitions.get(int(tool.id), {})), bool(tool.locked))
		elif str(tool.kind) == "automation":
			var definition: Dictionary = Dictionary(automation_definitions.get(int(tool.id), {}))
			tool.locked = not bool(definition.get("unlocked", false))
			var help_definition := definition.duplicate(true); help_definition.key = str(definition.get("id", ""))
			tool.help = HelpCatalog.automation(help_definition, bool(tool.locked))
		if was_locked and not bool(tool.get("locked", false)):
			_new_tool_keys[_tool_key(tool)] = true
		refreshed_by_key[_tool_key(tool)] = tool
	set_meta("catalog_tools", tools)
	for page in PAGE_COUNT:
		for index in SLOT_COUNT:
			var current: Dictionary = _pages[page][index]
			var key := _tool_key(current)
			if refreshed_by_key.has(key):
				_pages[page][index] = refreshed_by_key[key]
	_refresh_slots()
	_refresh_catalog()


func set_help_preferences(tooltip_delay: float, reduced_motion: bool) -> void:
	if _tooltip_layer != null: _tooltip_layer.delay_seconds = clampf(tooltip_delay, 0.0, 1.5)
	if _highlight_layer != null: _highlight_layer.reduced_motion = reduced_motion
	if _toast_center != null: _toast_center.reduced_motion = reduced_motion


func bind_help_root(root: Node) -> void:
	if _tooltip_layer != null:
		_tooltip_layer.bind_tree(root)


func set_gameplay_hud_visible(enabled: bool) -> void:
	if not enabled:
		if not _menu_visibility.is_empty():
			return
		for child: Node in get_children():
			if child == _tooltip_layer:
				continue
			if child is CanvasItem:
				_menu_visibility[child] = (child as CanvasItem).visible
				(child as CanvasItem).visible = false
		return
	for child: Variant in _menu_visibility:
		if is_instance_valid(child) and child is CanvasItem:
			(child as CanvasItem).visible = bool(_menu_visibility[child])
	_menu_visibility.clear()


func preview_onboarding_step(step_id: String) -> void:
	_onboarding.reset(_preset_id)
	for step: Dictionary in OnboardingState.STEPS[_preset_id]:
		if str(step.id) == step_id:
			break
		_onboarding.complete(str(step.id))
	_refresh_onboarding()


func preview_tooltip(spec: Dictionary, target_id := "catalog") -> void:
	call_deferred("_preview_tooltip_deferred", spec, target_id)


func _preview_tooltip_deferred(spec: Dictionary, target_id: String) -> void:
	var target := _help_targets.get(target_id) as Control
	if _tooltip_layer != null and is_instance_valid(target):
		_sync_help_safe_regions()
		_tooltip_layer.show_virtual(spec, target.get_global_rect())


func show_context_hint(id: String, message: String) -> void:
	var text := _onboarding.context_once(id, message)
	if not text.is_empty():
		show_alert(text)


func show_inspector(title: String, lines: Array[String]) -> void:
	var was_hidden := not _inspector.visible
	_inspector.visible = not title.is_empty()
	if was_hidden and _inspector.visible: KoalaSandTheme.animate_in(_inspector)
	_inspector_text.text = "" if title.is_empty() else "%s\n\n%s" % [title.to_upper(), "\n".join(lines)]
	_sync_help_safe_regions()

func show_physical_inspector(result: Dictionary) -> void:
	var title := str(result.get("title", ""))
	var was_hidden := not _inspector.visible
	_inspector.visible = not title.is_empty()
	if was_hidden and _inspector.visible: KoalaSandTheme.animate_in(_inspector)
	var lines: Array[String] = []
	var causes: Array = result.get("causes", [])
	if not causes.is_empty():
		lines.append("WHY IT IS NOT WORKING")
		for cause: String in causes:
			var help := HelpCatalog.failure(cause)
			lines.append("• %s" % str(help.title))
			lines.append("  %s" % str(help.description))
		lines.append("")
	lines.append("STATE")
	lines.append_array(Array(result.get("summary", [])))
	_inspector_text.text = "%s\n\n%s" % [title, "\n".join(lines)]
	_inspector_text.add_theme_color_override("font_color", KoalaSandTheme.COLOR_WARNING if not causes.is_empty() else KoalaSandTheme.COLOR_TEXT)
	_inspector_advanced.text = "\n".join(Array(result.get("advanced", [])))
	_inspector_advanced.visible = false
	_inspector_advanced_button.visible = not _inspector_advanced.text.is_empty()
	_inspector_codex_id = str(result.get("codex_id", ""))
	demonstrate_onboarding("INSPECT")
	if _highlight_layer != null: _highlight_layer.clear()
	_sync_help_safe_regions()

func set_planning_paused(paused: bool) -> void:
	_planning_badge.visible = paused

func set_current_goal(title: String, criteria: Array[String], help_id := "concept:construction") -> void:
	_goal_title.text = title
	if _goal_button != null:
		_goal_button.text = "GOAL · %s  %s" % [title, "▾" if _goal_expanded else "▸"]
	_goal_criteria.text = " · ".join(criteria.slice(0, 4))
	_goal_help_id = help_id


func show_notification(message: String, kind := "INFO") -> void:
	_ui_state.notify(message)
	if _toast_center != null:
		_toast_center.push(message, kind)
	else:
		show_alert(message)


func modal_open() -> bool:
	return _ui_state.world_input_blocked()


func close_top_modal() -> bool:
	var top := _ui_state.top_modal()
	if top.is_empty():
		return false
	match top:
		"build_catalog": _catalog.visible = false
		"statistics": _statistics_panel.visible = false
		"controls": _controls_panel.visible = false
	_ui_state.close_modal(top)
	_sync_help_safe_regions()
	return true


func set_external_modal(id: String, open: bool) -> void:
	if open:
		_close_internal_modals_except("")
		_ui_state.open_modal(id)
		if _highlight_layer != null: _highlight_layer.clear()
	else:
		_ui_state.close_modal(id)
		_refresh_onboarding()
	_sync_help_safe_regions()

func serialize_quickbars() -> Dictionary:
	return {"schema": 1, "active_page": _active_page, "pages": _pages.duplicate(true)}

func deserialize_quickbars(state: Dictionary) -> bool:
	if int(state.get("schema", 0)) != 1 or not state.get("pages", null) is Array or state.pages.size() != PAGE_COUNT:
		return false
	for page in state.pages:
		if not page is Array or page.size() != SLOT_COUNT:
			return false
	_pages = state.pages.duplicate(true)
	_active_page = clampi(int(state.get("active_page", 0)), 0, PAGE_COUNT - 1)
	_refresh_slots()
	return true

func serialize_session_state() -> Dictionary:
	return {"schema": 1, "quickbars": serialize_quickbars(), "onboarding": _onboarding.serialize(), "ui": _ui_state.serialize()}

func deserialize_session_state(state: Dictionary) -> bool:
	if int(state.get("schema", 0)) != 1:
		return false
	if not deserialize_quickbars(Dictionary(state.get("quickbars", {}))):
		return false
	if not _onboarding.deserialize(Dictionary(state.get("onboarding", {}))):
		return false
	_refresh_onboarding()
	return true

func _build_hud() -> void:
	_build_top_bar()
	_build_bottom_dock()
	_build_catalog_panel()
	_build_side_panels()
	_build_controls_panel()


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.theme_type_variation = "HudPanel"
	_top_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_top_bar.z_index = UILayoutPolicy.LAYER_HUD
	_top_bar.set_meta("layout_role", "top_safe_region")
	add_child(_top_bar)
	var column := VBoxContainer.new(); _top_bar.add_child(column)
	var primary := HBoxContainer.new(); column.add_child(primary)
	_mode_badge = Label.new(); _mode_badge.text = "FACTORY"; _mode_badge.theme_type_variation = "SectionTitleLabel"; primary.add_child(_mode_badge)
	_status = Label.new(); _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; primary.add_child(_status)
	_reserves = Label.new(); _reserves.theme_type_variation = "NumericLabel"; primary.add_child(_reserves)
	HelpCatalog.attach(_reserves, {"title":"Research materials", "description":"Glass, Iron and Gold currently available for unlocking Research."})
	var research := Button.new(); research.theme_type_variation = "PrimaryButton"; research.text = "Research"; research.tooltip_text = InputGlyphs.hint(&"open_research", "Open Research"); research.pressed.connect(func(): research_requested.emit()); primary.add_child(research)
	_help_targets.research = research; HelpCatalog.attach(research, HelpCatalog.control("research"))
	var planning := Button.new(); planning.theme_type_variation = "QuietButton"; planning.text = "Plan"; planning.pressed.connect(func(): planning_pause_requested.emit()); primary.add_child(planning)
	_help_targets.planning_pause = planning; HelpCatalog.attach(planning, HelpCatalog.control("planning_pause"))
	var explore := Button.new(); explore.theme_type_variation = "QuietButton"; explore.text = "More  ▾"; explore.pressed.connect(_show_navigation_menu.bind(explore)); primary.add_child(explore)
	HelpCatalog.attach(explore, {"title":"Explore", "description":"Open the Codex, experiment ideas, world map, or production statistics."})
	var overlay_button := Button.new(); overlay_button.theme_type_variation = "QuietButton"; overlay_button.text = "View  ▾"; overlay_button.pressed.connect(_show_overlay_menu.bind(overlay_button)); primary.add_child(overlay_button)
	HelpCatalog.attach(overlay_button, HelpCatalog.control("overlay"))
	var controls := Button.new(); controls.theme_type_variation = "QuietButton"; controls.text = "?"; controls.pressed.connect(toggle_controls); primary.add_child(controls)
	_help_targets.controls = controls; HelpCatalog.attach(controls, HelpCatalog.control("controls"))
	_info_badge = Label.new(); _info_badge.text = "I · INFO MODE"; _info_badge.visible = false; _info_badge.add_theme_color_override("font_color", KoalaSandTheme.COLOR_INFO); primary.add_child(_info_badge)
	_alert_text = Label.new(); _alert_text.visible = false; _alert_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _alert_text.add_theme_color_override("font_color", KoalaSandTheme.COLOR_DANGER); primary.add_child(_alert_text)
	_planning_badge = Label.new(); _planning_badge.text = "Ⅱ  PLANNING PAUSE"; _planning_badge.visible = false; _planning_badge.theme_type_variation = "WarningLabel"; primary.add_child(_planning_badge)

	_goal_details = HBoxContainer.new(); _goal_details.set_meta("layout_role", "current_goal"); column.add_child(_goal_details)
	_goal_button = Button.new(); _goal_button.theme_type_variation = "QuietButton"; _goal_button.text = "GOAL · Discover physical processing  ▸"; _goal_button.pressed.connect(_toggle_goal_details); _goal_details.add_child(_goal_button)
	_goal_title = Label.new(); _goal_title.text = "Discover physical processing"; _goal_title.visible = false; _goal_details.add_child(_goal_title)
	_goal_criteria = Label.new(); _goal_criteria.text = "Build · Observe · Iterate"; _goal_criteria.visible = false; _goal_criteria.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _goal_criteria.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _goal_criteria.add_theme_color_override("font_color", KoalaSandTheme.COLOR_TEXT_SECONDARY); _goal_details.add_child(_goal_criteria)
	_onboarding_hint = Label.new(); _onboarding_hint.text = _onboarding.current_hint(); _onboarding_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _onboarding_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _onboarding_hint.add_theme_color_override("font_color", Color("a9c3bd")); _goal_details.add_child(_onboarding_hint)
	_goal_help_button = Button.new(); _goal_help_button.theme_type_variation = "QuietButton"; _goal_help_button.text = "How?"; _goal_help_button.visible = false; _goal_help_button.pressed.connect(func(): codex_requested.emit(_goal_help_id)); _goal_details.add_child(_goal_help_button)
	_help_targets.goal_help = _goal_help_button; _help_targets.status = _goal_button
	HelpCatalog.attach(_goal_help_button, {"title":"Goal help", "description":"Opens a relevant physical principle. It explains the outcome without prescribing one exact factory design.", "codex_id":"concept:construction"})

	_navigation_menu = PopupMenu.new()
	for entry: Array in [["Codex",0], ["Ideas",1], ["Map",2], ["Statistics",3]]: _navigation_menu.add_item(str(entry[0]), int(entry[1]))
	_navigation_menu.id_pressed.connect(_on_navigation_selected); add_child(_navigation_menu)
	_overlay_menu = PopupMenu.new()
	var overlays := [["None",0], ["Geology",1], ["Temperature",4], ["Magnetic Field",5], ["Automation",8], ["Underground Logistics",9], ["Production Flow",12], ["Power",13]]
	for entry: Array in overlays: _overlay_menu.add_item(str(entry[0]), int(entry[1]))
	_overlay_menu.id_pressed.connect(func(id: int): overlay_selected.emit(id)); add_child(_overlay_menu)


func _build_bottom_dock() -> void:
	_bottom_dock = PanelContainer.new()
	_bottom_dock.name = "BottomDock"
	_bottom_dock.theme_type_variation = "HudPanel"
	_bottom_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_bottom_dock.z_index = UILayoutPolicy.LAYER_HUD
	_bottom_dock.set_meta("layout_role", "bottom_safe_region")
	add_child(_bottom_dock)
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", 8); margin.add_theme_constant_override("margin_top", 6); margin.add_theme_constant_override("margin_right", 8); margin.add_theme_constant_override("margin_bottom", 6); _bottom_dock.add_child(margin)
	var dock_row := HFlowContainer.new(); dock_row.alignment = FlowContainer.ALIGNMENT_CENTER; margin.add_child(dock_row)
	_action_group = VBoxContainer.new(); _action_group.set_meta("layout_role", "world_actions"); dock_row.add_child(_action_group)
	var action_caption := Label.new(); action_caption.text = "WORLD TOOLS"; action_caption.theme_type_variation = "CaptionLabel"; _action_group.add_child(action_caption)
	_action_row = HBoxContainer.new(); _action_group.add_child(_action_row)
	var actions: Array[Dictionary] = [
		{"name":"Select", "kind":"select", "id":0, "icon":"select"}, {"name":"Pick", "kind":"pipette", "id":0, "icon":"pipette"},
		{"name":"Dig", "kind":"terrain", "id":3, "icon":"dig"}, {"name":"Cut", "kind":"organic_clear", "id":0, "icon":"remove"},
		{"name":"Ignite", "kind":"ignite", "id":0, "icon":"furnace"}, {"name":"Remove", "kind":"remove", "id":0, "icon":"remove"},
		{"name":"Plan", "kind":"blueprint_select", "id":0, "icon":"blueprint"},
	]
	for action: Dictionary in actions:
		var button := Button.new(); button.theme_type_variation = "QuietButton"; button.text = str(action.name); button.pressed.connect(func(): tool_selected.emit(action)); _action_row.add_child(button)
		var help_id: String = str({"pipette":"pipette", "blueprint_select":"blueprint", "select":"info_mode"}.get(str(action.kind), ""))
		HelpCatalog.attach(button, HelpCatalog.control(help_id) if not help_id.is_empty() else {"title":str(action.name), "description":"Use this world tool to interact with physical cells and Components."})
		if str(action.kind) == "terrain": _help_targets.dig = button
		if str(action.kind) == "select": _help_targets.info = button

	var left_separator := VSeparator.new(); dock_row.add_child(left_separator)
	_quickbar_group = VBoxContainer.new(); _quickbar_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _quickbar_group.set_meta("layout_role", "quickbar"); dock_row.add_child(_quickbar_group)
	var slot_row := HBoxContainer.new(); slot_row.alignment = BoxContainer.ALIGNMENT_CENTER; slot_row.add_theme_constant_override("separation", 5); _quickbar_group.add_child(slot_row)
	for index in SLOT_COUNT:
		var slot := ToolSlot.new(); slot.custom_minimum_size = Vector2(54, 48); slot.index = index
		slot.pressed.connect(_activate_visible_slot.bind(index)); slot.slot_drop.connect(_on_slot_drop); slot.slot_clear.connect(_on_slot_clear)
		slot_row.add_child(slot); _slot_nodes.append(slot)
	_help_targets.quickbar = slot_row
	var page_row := HBoxContainer.new(); page_row.alignment = BoxContainer.ALIGNMENT_CENTER; _quickbar_group.add_child(page_row)
	var previous_page := Button.new(); previous_page.theme_type_variation = "QuietButton"; previous_page.text = "◀"; previous_page.pressed.connect(change_page.bind(-1)); page_row.add_child(previous_page)
	HelpCatalog.attach(previous_page, HelpCatalog.control("quickbar_previous"))
	_page_label = Label.new(); _page_label.text = "QUICKBAR  1 / %d" % PAGE_COUNT; _page_label.theme_type_variation = "CaptionLabel"; page_row.add_child(_page_label)
	var next_page := Button.new(); next_page.theme_type_variation = "QuietButton"; next_page.text = "▶"; next_page.pressed.connect(change_page.bind(1)); page_row.add_child(next_page)
	HelpCatalog.attach(next_page, HelpCatalog.control("quickbar_next"))

	var right_separator := VSeparator.new(); dock_row.add_child(right_separator)
	_utility_group = VBoxContainer.new(); _utility_group.set_meta("layout_role", "dock_utilities"); dock_row.add_child(_utility_group)
	var utility_caption := Label.new(); utility_caption.text = "BUILD"; utility_caption.theme_type_variation = "CaptionLabel"; _utility_group.add_child(utility_caption)
	var utility_row := HBoxContainer.new(); _utility_group.add_child(utility_row)
	var catalog_button := Button.new(); catalog_button.theme_type_variation = "PrimaryButton"; catalog_button.text = "Catalog  [%s]" % InputGlyphs.action(&"build_catalog"); catalog_button.pressed.connect(toggle_catalog); utility_row.add_child(catalog_button)
	_help_targets.catalog = catalog_button; HelpCatalog.attach(catalog_button, HelpCatalog.control("catalog"))
	var blueprint_button := Button.new(); blueprint_button.theme_type_variation = "QuietButton"; blueprint_button.text = "Blueprints"; blueprint_button.pressed.connect(func(): blueprints_requested.emit()); utility_row.add_child(blueprint_button)
	_help_targets.blueprints = blueprint_button; HelpCatalog.attach(blueprint_button, HelpCatalog.control("blueprint"))


func _build_catalog_panel() -> void:
	_catalog = PanelContainer.new(); _catalog.name = "BuildCatalog"; _catalog.theme_type_variation = "ElevatedPanel"; _catalog.visible = false; _catalog.mouse_filter = Control.MOUSE_FILTER_STOP; _catalog.z_index = UILayoutPolicy.LAYER_MODAL; _catalog.set_meta("layout_role", "modal_catalog"); add_child(_catalog)
	var catalog_margin := MarginContainer.new(); catalog_margin.add_theme_constant_override("margin_left", 16); catalog_margin.add_theme_constant_override("margin_top", 14); catalog_margin.add_theme_constant_override("margin_right", 16); catalog_margin.add_theme_constant_override("margin_bottom", 14); _catalog.add_child(catalog_margin)
	var catalog_column := VBoxContainer.new(); catalog_margin.add_child(catalog_column)
	var title_row := HBoxContainer.new(); catalog_column.add_child(title_row)
	var title := Label.new(); title.text = "Build catalog"; title.theme_type_variation = "ScreenTitleLabel"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(title)
	var close_catalog := Button.new(); close_catalog.theme_type_variation = "QuietButton"; close_catalog.text = "Close  [%s]" % InputGlyphs.action(&"build_catalog"); close_catalog.pressed.connect(toggle_catalog); title_row.add_child(close_catalog)
	_search = LineEdit.new(); _search.placeholder_text = "Search by name or purpose…"; _search.text_changed.connect(func(_text: String): _refresh_catalog()); catalog_column.add_child(_search)
	var category_row := HFlowContainer.new(); catalog_column.add_child(category_row)
	for category in ["ALL", "LOGISTICS", "PROCESSING", "FLUIDS", "THERMAL", "POWER", "AUTOMATION", "STRUCTURES"]:
		var category_button := Button.new(); category_button.theme_type_variation = "QuietButton"; category_button.toggle_mode = true; category_button.text = category.capitalize(); category_button.pressed.connect(func(): _category_filter = category; _refresh_catalog()); category_row.add_child(category_button); _category_buttons[category] = category_button
	_catalog_scroll = ScrollContainer.new(); _catalog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; catalog_column.add_child(_catalog_scroll)
	_catalog_grid = GridContainer.new(); _catalog_grid.columns = 3; _catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _catalog_scroll.add_child(_catalog_grid)
	_catalog_empty = Label.new(); _catalog_empty.text = "No Components match this search.\nTry a category, a physical purpose, or clear the search."; _catalog_empty.theme_type_variation = "SecondaryLabel"; _catalog_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _catalog_empty.visible = false; catalog_column.add_child(_catalog_empty)
	var hint := Label.new(); hint.text = "Select or drag to quickbar · right-click a quickbar slot to clear"; hint.theme_type_variation = "CaptionLabel"; catalog_column.add_child(hint)


func _build_side_panels() -> void:
	_statistics_panel = PanelContainer.new(); _statistics_panel.name = "StatisticsPanel"; _statistics_panel.visible = false; _statistics_panel.mouse_filter = Control.MOUSE_FILTER_STOP; _statistics_panel.z_index = UILayoutPolicy.LAYER_MODAL; add_child(_statistics_panel)
	var statistics_margin := MarginContainer.new(); statistics_margin.add_theme_constant_override("margin_left", 16); statistics_margin.add_theme_constant_override("margin_top", 14); statistics_margin.add_theme_constant_override("margin_right", 16); statistics_margin.add_theme_constant_override("margin_bottom", 14); _statistics_panel.add_child(statistics_margin)
	_statistics_text = Label.new(); _statistics_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP; statistics_margin.add_child(_statistics_text)
	_inspector = PanelContainer.new(); _inspector.name = "InspectorPanel"; _inspector.theme_type_variation = "ElevatedPanel"; _inspector.visible = false; _inspector.mouse_filter = Control.MOUSE_FILTER_STOP; _inspector.z_index = UILayoutPolicy.LAYER_PANEL; add_child(_inspector)
	var inspector_margin := MarginContainer.new(); inspector_margin.add_theme_constant_override("margin_left", 16); inspector_margin.add_theme_constant_override("margin_top", 14); inspector_margin.add_theme_constant_override("margin_right", 16); inspector_margin.add_theme_constant_override("margin_bottom", 14); _inspector.add_child(inspector_margin)
	var inspector_column := VBoxContainer.new(); inspector_margin.add_child(inspector_column)
	_inspector_text = Label.new(); _inspector_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; inspector_column.add_child(_inspector_text)
	_inspector_advanced_button = Button.new(); _inspector_advanced_button.text = "ADVANCED DETAILS"; _inspector_advanced_button.visible = false; _inspector_advanced_button.pressed.connect(func(): _inspector_advanced.visible = not _inspector_advanced.visible); inspector_column.add_child(_inspector_advanced_button)
	_inspector_advanced = Label.new(); _inspector_advanced.visible = false; _inspector_advanced.add_theme_color_override("font_color", KoalaSandTheme.COLOR_TEXT_DISABLED); inspector_column.add_child(_inspector_advanced)
	var inspector_codex := Button.new(); inspector_codex.text = "OPEN IN CODEX"; inspector_codex.pressed.connect(func(): if not _inspector_codex_id.is_empty(): codex_requested.emit(_inspector_codex_id)); inspector_column.add_child(inspector_codex)


func _relayout() -> void:
	if _top_bar == null or _bottom_dock == null:
		return
	var viewport_size := size
	if viewport_size.x < 100.0 or viewport_size.y < 100.0:
		viewport_size = get_viewport_rect().size
	var margin := 14.0
	var top_height := clampf(maxf(84.0 * _ui_scale, _top_bar.get_combined_minimum_size().y), 84.0, viewport_size.y * 0.22)
	_top_bar.position = Vector2(margin, margin)
	_top_bar.size = Vector2(viewport_size.x - margin * 2.0, top_height)
	var dock_width := minf(viewport_size.x - margin * 2.0, maxf(viewport_size.x * 0.82, 1160.0 * _ui_scale))
	var responsive_dock_height := 214.0 if _ui_scale >= 1.3 and viewport_size.x <= 1700.0 else 92.0 * _ui_scale
	var dock_height := clampf(maxf(responsive_dock_height, _bottom_dock.get_combined_minimum_size().y), 92.0, viewport_size.y * 0.28)
	_bottom_dock.position = Vector2((viewport_size.x - dock_width) * 0.5, viewport_size.y - dock_height - margin)
	_bottom_dock.size = Vector2(dock_width, dock_height)
	for slot: ToolSlot in _slot_nodes:
		slot.custom_minimum_size = Vector2(54.0 * _ui_scale, 48.0 * _ui_scale)
	var top_end := _top_bar.position.y + _top_bar.size.y
	var available_height := maxf(360.0, _bottom_dock.position.y - top_end - 34.0)
	var catalog_width := minf(viewport_size.x - margin * 2.0, maxf(viewport_size.x * 0.58, 720.0 * _ui_scale))
	_catalog.position = Vector2(margin, top_end + 12.0)
	_catalog.size = Vector2(catalog_width, available_height)
	_catalog_grid.columns = UILayoutPolicy.catalog_columns(maxf(480.0, catalog_width - 48.0), _ui_scale)
	for card: Node in _catalog_grid.get_children():
		if card is CatalogCard: (card as CatalogCard).apply_ui_scale(_ui_scale)
	var side_width := minf(420.0 * _ui_scale, viewport_size.x * 0.42)
	var side_height := minf(560.0 * _ui_scale, available_height)
	_statistics_panel.position = Vector2(viewport_size.x - side_width - margin, top_end + 12.0)
	_statistics_panel.size = Vector2(side_width, side_height)
	var inspector_width := minf(390.0 * _ui_scale, viewport_size.x * 0.40)
	var inspector_height := minf(440.0 * _ui_scale, available_height)
	_inspector.position = Vector2(viewport_size.x - inspector_width - margin, top_end + 12.0)
	_inspector.size = Vector2(inspector_width, inspector_height)
	if _controls_panel != null:
		var controls_size := Vector2(minf(660.0 * _ui_scale, viewport_size.x - 48.0), minf(600.0 * _ui_scale, viewport_size.y - 64.0))
		_controls_panel.position = (viewport_size - controls_size) * 0.5
		_controls_panel.size = controls_size
	_sync_help_safe_regions()


func layout_metrics() -> Dictionary:
	var cards: Array[Dictionary] = []
	if _catalog_grid != null:
		for node: Node in _catalog_grid.get_children():
			if node is CatalogCard: cards.append((node as CatalogCard).layout_rects())
	return {
		"viewport":Rect2(Vector2.ZERO, size), "top":_top_bar.get_global_rect(), "bottom":_bottom_dock.get_global_rect(),
		"actions":_action_group.get_global_rect(), "quickbar":_quickbar_group.get_global_rect(), "utilities":_utility_group.get_global_rect(),
		"goal":_goal_details.get_global_rect(), "catalog":_catalog.get_global_rect(), "catalog_columns":_catalog_grid.columns, "catalog_cards":cards,
	}


func layout_surfaces() -> Dictionary:
	return {"top":_top_bar, "bottom":_bottom_dock, "catalog":_catalog, "statistics":_statistics_panel, "controls":_controls_panel, "inspector":_inspector}


func workspace_rect() -> Rect2:
	if _top_bar == null or _bottom_dock == null:
		return Rect2(Vector2(12, 12), size - Vector2(24, 24))
	var top_end := _top_bar.position.y + _top_bar.size.y + 12.0
	return Rect2(Vector2(14.0, top_end), Vector2(size.x - 28.0, maxf(1.0, _bottom_dock.position.y - top_end - 12.0)))


func visible_modal_ids() -> Array[String]:
	var result: Array[String] = []
	if _catalog.visible: result.append("build_catalog")
	if _statistics_panel.visible: result.append("statistics")
	if _controls_panel.visible: result.append("controls")
	return result


func apply_layout_fixture(multiplier := 1.6) -> void:
	var suffix := " · EXTENDED PLAYER-FACING LOCALIZATION FIXTURE".repeat(maxi(1, ceili(multiplier)))
	_status.text = "Vibration actuator selected%s" % suffix
	_goal_title.text = "Build a pressure-safe wet-processing line%s" % suffix
	_goal_button.text = "GOAL · %s  ▾" % _goal_title.text
	_goal_criteria.text = "Move material · separate heavy concentrate · prevent local pipe damage%s" % suffix
	_onboarding_hint.text = "Open the Build Catalog and inspect the physical cause before changing the factory%s" % suffix
	if has_meta("catalog_tools"):
		var tools: Array = get_meta("catalog_tools")
		for index in mini(8, tools.size()):
			var tool: Dictionary = tools[index]
			tool.name = "%s%s" % [tool.name, suffix]
		_refresh_catalog()
	call_deferred("_relayout")


func _toggle_goal_details() -> void:
	_goal_expanded = not _goal_expanded
	_goal_criteria.visible = _goal_expanded
	_goal_help_button.visible = _goal_expanded
	_goal_button.text = "GOAL · %s  %s" % [_goal_title.text, "▾" if _goal_expanded else "▸"]
	call_deferred("_relayout")


func preview_goal_expanded() -> void:
	if not _goal_expanded: _toggle_goal_details()


func _show_navigation_menu(button: Button) -> void:
	_navigation_menu.position = Vector2i(button.global_position + Vector2(0, button.size.y))
	_navigation_menu.popup()


func _on_navigation_selected(id: int) -> void:
	match id:
		0: codex_requested.emit("")
		1: experiments_requested.emit()
		2: map_requested.emit()
		3: toggle_statistics()


func _close_internal_modals_except(id: String) -> void:
	if id != "build_catalog" and _catalog != null and _catalog.visible:
		_catalog.hide(); _ui_state.close_modal("build_catalog")
	if id != "statistics" and _statistics_panel != null and _statistics_panel.visible:
		_statistics_panel.hide(); _ui_state.close_modal("statistics")
	if id != "controls" and _controls_panel != null and _controls_panel.visible:
		_controls_panel.hide(); _ui_state.close_modal("controls")


func _sync_help_safe_regions() -> void:
	if _tooltip_layer == null or _top_bar == null or _bottom_dock == null:
		return
	var reserved: Array[Rect2] = [_top_bar.get_global_rect(), _bottom_dock.get_global_rect()]
	if _inspector != null and _inspector.visible: reserved.append(_inspector.get_global_rect())
	var modals: Array[Rect2] = []
	for panel: PanelContainer in [_catalog, _statistics_panel, _controls_panel]:
		if panel != null and panel.visible: modals.append(panel.get_global_rect())
	_tooltip_layer.set_safe_regions(reserved, modals)
	if _highlight_layer != null: _highlight_layer.set_safe_regions(reserved)


func _build_tool_data() -> void:
	var structures: Dictionary = {}
	for definition: Dictionary in _world.get_structure_definitions(): structures[int(definition.type_id)] = definition
	var tools: Array[Dictionary] = [
		{"kind":"structure", "id":2, "name":"Conveyor", "short":"2", "icon":"conveyor", "category":"Logistics"},
		{"kind":"structure", "id":3, "name":"Funnel", "short":"3", "icon":"funnel", "category":"Logistics"},
		{"kind":"structure", "id":4, "name":"Storage Bin", "short":"4", "icon":"storage", "category":"Storage"},
		{"kind":"structure", "id":8, "name":"Research Bank", "short":"8", "icon":"bank", "category":"Infrastructure"},
		{"kind":"structure", "id":10, "name":"Pipe", "short":"P", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":11, "name":"Pipe Junction", "short":"PJ", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":12, "name":"Fluid Intake", "short":"IN", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":13, "name":"Fluid Outlet", "short":"OUT", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":14, "name":"Basic Pump", "short":"PU", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":15, "name":"Pipe Valve", "short":"VL", "icon":"pipe", "category":"Fluid"},
		{"kind":"structure", "id":16, "name":"Reservoir Wall", "short":"RW", "icon":"storage", "category":"Fluid"},
		{"kind":"structure", "id":24, "name":"Thermal Switch", "short":"TS", "icon":"wire", "category":"Thermal"},
		{"kind":"structure", "id":25, "name":"Heat Exchanger", "short":"HX", "icon":"furnace", "category":"Thermal"},
		{"kind":"structure", "id":26, "name":"Mechanical Shaft", "short":"SH", "icon":"conveyor", "category":"Power"},
		{"kind":"structure", "id":27, "name":"Steam Turbine", "short":"TU", "icon":"furnace", "category":"Power"},
		{"kind":"structure", "id":28, "name":"Generator", "short":"GN", "icon":"bank", "category":"Power"},
		{"kind":"structure", "id":29, "name":"Power Pole", "short":"PO", "icon":"wire", "category":"Power"},
		{"kind":"structure", "id":30, "name":"Power Switch", "short":"PS", "icon":"wire", "category":"Power"},
		{"kind":"structure", "id":31, "name":"Accumulator", "short":"AC", "icon":"storage", "category":"Power"},
		{"kind":"structure", "id":33, "name":"Flywheel", "short":"FW", "icon":"conveyor", "category":"Power"},
		{"kind":"structure", "id":34, "name":"Resistive Heater", "short":"RH", "icon":"furnace", "category":"Power"},
		{"kind":"structure", "id":37, "name":"Structural Wall", "short":"W", "icon":"storage", "category":"Components"},
		{"kind":"structure", "id":38, "name":"Metal Plate", "short":"MP", "icon":"storage", "category":"Components"},
		{"kind":"structure", "id":39, "name":"Ceramic Wall", "short":"CW", "icon":"storage", "category":"Components"},
		{"kind":"structure", "id":40, "name":"Refractory Wall", "short":"RW", "icon":"furnace", "category":"Components"},
		{"kind":"structure", "id":41, "name":"Mesh Screen", "short":"MS", "icon":"screen", "category":"Components"},
		{"kind":"structure", "id":42, "name":"Grate", "short":"GR", "icon":"screen", "category":"Components"},
		{"kind":"structure", "id":43, "name":"Riffle", "short":"RF", "icon":"screen", "category":"Components"},
		{"kind":"structure", "id":44, "name":"Thermal Insulator", "short":"TI", "icon":"storage", "category":"Components"},
		{"kind":"structure", "id":45, "name":"Vibration Actuator", "short":"VA", "icon":"screen", "category":"Components"},
		{"kind":"structure", "id":46, "name":"Electromagnet", "short":"EM", "icon":"magnet", "category":"Components"},
		{"kind":"structure", "id":47, "name":"Blower", "short":"BL", "icon":"furnace", "category":"Components"},
		{"kind":"subsurface", "id":0, "depth":0, "name":"Subsurface Channel I", "short":"I", "icon":"conveyor", "category":"Subsurface Logistics"},
		{"kind":"subsurface", "id":1, "depth":1, "name":"Subsurface Channel II", "short":"II", "icon":"conveyor", "category":"Subsurface Logistics"},
		{"kind":"subsurface", "id":2, "depth":2, "name":"Subsurface Channel III", "short":"III", "icon":"conveyor", "category":"Subsurface Logistics"},
		{"kind":"terrain", "id":0, "name":"Raw Sand", "short":"S", "icon":"tool", "category":"Terrain / Creative"},
		{"kind":"terrain", "id":3, "name":"Dig / Harvest", "short":"D", "icon":"dig", "category":"Terrain / Creative"},
		{"kind":"material", "id":21, "name":"Wood", "short":"WD", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":22, "name":"Leaves", "short":"LV", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":23, "name":"Charcoal", "short":"CH", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":24, "name":"Smoke", "short":"SM", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":25, "name":"Raw Food", "short":"RF", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":26, "name":"Cooked Food", "short":"CF", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"material", "id":27, "name":"Burnt Food", "short":"BF", "icon":"tool", "category":"Organic / Creative"},
		{"kind":"organic_clear", "id":0, "name":"Clear Vegetation", "short":"CUT", "icon":"remove", "category":"Organic"},
		{"kind":"ignite", "id":0, "name":"Igniter", "short":"FIRE", "icon":"furnace", "category":"Organic"},
		{"kind":"remove", "id":0, "name":"Remove", "short":"X", "icon":"remove", "category":"Infrastructure"},
		{"kind":"automation", "id":2, "name":"Material Sensor", "short":"MS", "icon":"sensor", "category":"Automation"},
		{"kind":"automation", "id":3, "name":"Level Sensor", "short":"LS", "icon":"sensor", "category":"Automation"},
		{"kind":"automation", "id":14, "name":"Pump Enable", "short":"PE", "icon":"wire", "category":"Fluid Automation"},
		{"kind":"automation", "id":15, "name":"Valve Control", "short":"VC", "icon":"wire", "category":"Fluid Automation"},
		{"kind":"automation", "id":16, "name":"Flow Meter", "short":"FM", "icon":"sensor", "category":"Fluid Automation"},
		{"kind":"automation", "id":17, "name":"Pipe Fill Sensor", "short":"PF", "icon":"sensor", "category":"Fluid Automation"},
		{"kind":"automation", "id":18, "name":"Temperature Sensor", "short":"T", "icon":"sensor", "category":"Thermal Automation"},
		{"kind":"automation", "id":19, "name":"Pipe Temperature Sensor", "short":"PT", "icon":"sensor", "category":"Thermal Automation"},
		{"kind":"automation", "id":20, "name":"Pipe Pressure Sensor", "short":"PP", "icon":"sensor", "category":"Thermal Automation"},
		{"kind":"automation", "id":21, "name":"Thermal Switch Control", "short":"TC", "icon":"wire", "category":"Thermal Automation"},
		{"kind":"automation", "id":22, "name":"Power Network Sensor", "short":"PW", "icon":"sensor", "category":"Power Automation"},
		{"kind":"automation", "id":23, "name":"Shaft Speed Sensor", "short":"RPM", "icon":"sensor", "category":"Power Automation"},
		{"kind":"automation", "id":24, "name":"Power Switch Control", "short":"PSC", "icon":"wire", "category":"Power Automation"},
		{"kind":"wiring", "id":0, "name":"Wire", "short":"Y", "icon":"wire", "category":"Automation"},
	]
	tools = tools.filter(func(tool: Dictionary) -> bool: return str(tool.kind) not in ["organic_clear", "ignite", "remove", "wiring"] and not (str(tool.kind) == "terrain" and int(tool.id) == 3))
	tools = tools.filter(func(tool: Dictionary) -> bool: return str(tool.kind) != "automation")
	for automation_definition: Dictionary in _world.get_automation_definitions():
		var automation_help_definition := automation_definition.duplicate(true); automation_help_definition.key = str(automation_definition.id)
		tools.append({"kind":"automation", "id":int(automation_definition.type_id), "name":str(automation_definition.display_name), "short":"A%d" % int(automation_definition.type_id), "icon":"wire" if bool(automation_definition.actuator) else "sensor", "category":"Automation", "locked":not bool(automation_definition.unlocked), "help":HelpCatalog.automation(automation_help_definition, not bool(automation_definition.unlocked))})
	for tool in tools:
		if tool.kind == "structure":
			tool.locked = not _world.is_structure_unlocked(tool.id)
			tool.help = HelpCatalog.component(int(tool.id), Dictionary(structures.get(int(tool.id), {})), bool(tool.locked))
		elif tool.kind in ["terrain", "material"]:
			var registry := MaterialRegistry.new()
			if registry.load_directory() == OK:
				var material_id := materials_id_for_tool(tool, registry)
				var material_definition := registry.get_definition(material_id)
				if material_definition != null: tool.help = HelpCatalog.material(material_definition)
		elif not tool.has("help"):
			tool.help = {"title":str(tool.name), "description":"Select this tool to interact with ordinary physical world cells."}
	for page in PAGE_COUNT:
		_pages[page] = []
		for index in SLOT_COUNT:
			var tool_index := page * SLOT_COUNT + index
			_pages[page].append(tools[tool_index] if tool_index < tools.size() else {})
	set_meta("catalog_tools", tools)

func _refresh_slots() -> void:
	for index in SLOT_COUNT:
		var slot: ToolSlot = _slot_nodes[index]
		slot.page = _active_page
		slot.configure(_pages[_active_page][index], _active_page, index)
		slot.modulate = Color.WHITE
		if not slot.tool.is_empty():
			var spec := Dictionary(slot.tool.get("help", {})).duplicate(true)
			spec.shortcut_action = StringName("quickbar_%d" % (0 if index == 9 else index + 1))
			HelpCatalog.attach(slot, spec)

func _refresh_catalog() -> void:
	if _catalog_grid == null or not has_meta("catalog_tools"):
		return
	for child in _catalog_grid.get_children(): child.queue_free()
	for category: String in _category_buttons:
		(_category_buttons[category] as Button).button_pressed = category == _category_filter
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var visible_cards := 0
	for tool: Dictionary in get_meta("catalog_tools"):
		if not query.is_empty() and not query in str(tool.name).to_lower() and not query in str(tool.category).to_lower(): continue
		if _category_filter != "ALL" and _canonical_category(tool) != _category_filter: continue
		var display_tool := tool.duplicate(true); display_tool.display_category = _canonical_category(tool).capitalize()
		var entry := CatalogCard.new(); entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _catalog_grid.add_child(entry); entry.configure(display_tool, _new_tool_keys.has(_tool_key(tool)), _selected_tool_key == _tool_key(tool)); entry.apply_ui_scale(_ui_scale); entry.tool_activated.connect(_on_catalog_tool_activated)
		if _tooltip_layer != null: _tooltip_layer.bind(entry)
		visible_cards += 1
	_catalog_empty.visible = visible_cards == 0
	call_deferred("_relayout")


func _on_catalog_tool_activated(selected: Dictionary) -> void:
	_selected_tool_key = _tool_key(selected)
	for node: Node in _catalog_grid.get_children():
		if node is CatalogCard: (node as CatalogCard).set_selected(_tool_key((node as CatalogCard).tool) == _selected_tool_key)
	tool_selected.emit(selected)


func _tool_key(tool: Dictionary) -> String:
	if tool.is_empty(): return ""
	return "%s:%d" % [str(tool.get("kind", "")), int(tool.get("id", -1))]

func _canonical_category(tool: Dictionary) -> String:
	var source := str(tool.get("category", "")).to_lower()
	if "automation" in source: return "AUTOMATION"
	if "fluid" in source or "pipe" in source: return "FLUIDS"
	if "thermal" in source or "organic" in source: return "THERMAL"
	if "power" in source: return "POWER"
	if "component" in source or "infrastructure" in source: return "STRUCTURES"
	if "processing" in source: return "PROCESSING"
	return "LOGISTICS"

func _activate_slot_node(page: int, index: int) -> void:
	set_page(page)
	var tool: Dictionary = _pages[page][index]
	if not tool.is_empty() and not bool(tool.get("locked", false)): tool_selected.emit(tool)

func _activate_visible_slot(index: int) -> void:
	_activate_slot_node(_active_page, index)

func _on_slot_drop(target_page: int, target_index: int, data: Dictionary) -> void:
	var incoming: Dictionary = data.tool
	if not bool(data.get("catalog", false)):
		var source_page := int(data.source_page); var source_index := int(data.source_index)
		var displaced: Dictionary = _pages[target_page][target_index]
		_pages[target_page][target_index] = incoming
		_pages[source_page][source_index] = displaced
	else:
		_pages[target_page][target_index] = incoming
	_refresh_slots()

func _on_slot_clear(page: int, index: int) -> void:
	_pages[page][index] = {}
	_refresh_slots()

func _show_overlay_menu(button: Button) -> void:
	_overlay_menu.position = Vector2i(button.global_position + Vector2(0, button.size.y))
	_overlay_menu.popup()

func _refresh_statistics() -> void:
	if _world == null or not _world.has_method("get_production_statistics"):
		return
	var statistics: Dictionary = _world.get_production_statistics()
	var lines: Array[String] = ["PRODUCTION", "", "MATERIAL                 1 MIN       5 MIN      TOTAL"]
	var material_rows := 0
	for material: Dictionary in statistics.get("materials", []):
		if int(material.produced_lifetime) == 0 and int(material.consumed_lifetime) == 0:
			continue
		var name := str(_material_names.get(int(material.material_id), "Material %d" % int(material.material_id))).left(20)
		lines.append("%-20s  +%-8d  +%-8d  +%d" % [name, material.produced_1m, material.produced_5m, material.produced_lifetime])
		lines.append("%-20s  −%-8d  −%-8d  −%d" % ["consumed", material.consumed_1m, material.consumed_5m, material.consumed_lifetime])
		material_rows += 1
	if material_rows == 0:
		lines.append("No production data yet.")
		lines.append("Build and run a physical process to begin recording throughput.")
	lines.append("")
	lines.append("%d tracked material events" % int(statistics.get("events_total", 0)))
	if _world.has_method("get_organic_statistics"):
		var organic: Dictionary = _world.get_organic_statistics()
		lines.append("")
		lines.append("ORGANIC / COMBUSTION")
		lines.append("Trees felled %d · Wood produced/burned %d/%d" % [organic.trees_felled, organic.wood_produced, organic.wood_burned])
		lines.append("Charcoal produced/burned %d/%d · Ash %d · Smoke %d" % [organic.charcoal_produced, organic.charcoal_burned, organic.ash_produced, organic.smoke_produced])
		lines.append("Wood water released %d · Food cooked/burned %d/%d" % [organic.water_evaporated_from_wood, organic.food_cooked, organic.food_burned])
		lines.append("Fire active %d · Smoke produced %d" % [organic.reaction_cells_visited, organic.smoke_produced])
	_statistics_text.text = "\n".join(lines)


func materials_id_for_tool(tool: Dictionary, registry: MaterialRegistry) -> int:
	if str(tool.kind) == "terrain" and int(tool.id) == 0: return registry.get_id(&"raw_sand")
	return int(tool.id)


func toggle_controls() -> void:
	_controls_panel.visible = not _controls_panel.visible
	if _controls_panel.visible:
		_close_internal_modals_except("controls")
		_controls_text.text = _controls_copy()
		_ui_state.open_modal("controls")
		KoalaSandTheme.animate_in(_controls_panel)
		if _highlight_layer != null: _highlight_layer.clear()
	else:
		_ui_state.close_modal("controls")
		_refresh_onboarding()
	_sync_help_safe_regions()


func _build_controls_panel() -> void:
	_controls_panel = PanelContainer.new(); _controls_panel.name = "ControlsPanel"; _controls_panel.theme_type_variation = "ModalPanel"; _controls_panel.visible = false; _controls_panel.mouse_filter = Control.MOUSE_FILTER_STOP; _controls_panel.z_index = UILayoutPolicy.LAYER_MODAL; add_child(_controls_panel)
	var column := VBoxContainer.new(); _controls_panel.add_child(column)
	var row := HBoxContainer.new(); column.add_child(row)
	var title := Label.new(); title.text = "Controls"; title.theme_type_variation = "ScreenTitleLabel"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(title)
	var close := Button.new(); close.text = "Close"; close.pressed.connect(toggle_controls); row.add_child(close)
	var intro := Label.new(); intro.text = "Current bindings · updates whenever this panel opens"; intro.theme_type_variation = "CaptionLabel"; column.add_child(intro)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	_controls_text = Label.new(); _controls_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _controls_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_controls_text)


func _controls_copy() -> String:
	var groups := {
		"MOVEMENT":[&"move_left", &"move_right", &"jump", &"jetpack", &"sprint", &"hover"],
		"BUILD & EDIT":[&"build_catalog", &"pipette", &"rotate", &"copy", &"cut", &"paste", &"undo", &"redo", &"blueprint"],
		"INSPECT & PLAN":[&"info_mode", &"planning_pause", &"open_research", &"open_codex", &"map", &"overlay_selector", &"toggle_wiring"],
	}
	var lines: Array[String] = []
	for group: String in groups:
		lines.append(group)
		for action: StringName in groups[group]:
			lines.append("%-26s %s" % [String(action).replace("_", " ").capitalize(), InputGlyphs.action(action)])
		lines.append("")
	return "\n".join(lines)


func _install_help_layers() -> void:
	_toast_center = ToastCenter.new(); add_child(_toast_center)
	_highlight_layer = GuidedHighlightLayer.new(); add_child(_highlight_layer)
	_tooltip_layer = ContextTooltipLayer.new(); _tooltip_layer.codex_requested.connect(func(entry_id: String): codex_requested.emit(entry_id)); add_child(_tooltip_layer)
	_tooltip_layer.call_deferred("bind_tree", self)
	call_deferred("_sync_help_safe_regions")
	call_deferred("_refresh_onboarding")


func _refresh_onboarding() -> void:
	if _onboarding_hint == null:
		return
	_onboarding_hint.text = _onboarding.current_hint()
	_onboarding_hint.visible = not _onboarding_hint.text.is_empty()
	if _highlight_layer == null:
		return
	if _ui_state.world_input_blocked():
		_highlight_layer.clear()
		return
	var target := _help_targets.get(_onboarding.current_target()) as Control
	if _onboarding_hint.visible and is_instance_valid(target):
		_highlight_layer.show_step(target, "NEXT")
	else:
		_highlight_layer.clear()

func _build_theme() -> Theme:
	return KoalaSandTheme.build()
