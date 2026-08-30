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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = KoalaSandTheme.build()
	for page in PAGE_COUNT:
		_pages.append([])
	_build_hud()
	_install_help_layers()

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
	_reserves.text = "◆ %d   ▰ %d   ● %d" % [progression.glass, progression.iron, progression.gold]
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
		KoalaSandTheme.animate_in(_catalog)
		_ui_state.open_modal("build_catalog")
		_search.grab_focus()
		demonstrate_onboarding("OPEN_CATALOG")
	else:
		_ui_state.close_modal("build_catalog")

func set_page(page: int) -> void:
	_active_page = wrapi(page, 0, PAGE_COUNT)
	if _page_label != null:
		_page_label.text = "%d / %d" % [_active_page + 1, PAGE_COUNT]
	_refresh_slots()

func change_page(delta: int) -> void:
	set_page(_active_page + delta)

func toggle_statistics() -> void:
	_statistics_panel.visible = not _statistics_panel.visible
	if _statistics_panel.visible:
		KoalaSandTheme.animate_in(_statistics_panel)
		_ui_state.open_modal("statistics")
		_refresh_statistics()
	else:
		_ui_state.close_modal("statistics")

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
	var target := _help_targets.get(target_id) as Control
	if _tooltip_layer != null and is_instance_valid(target):
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

func set_planning_paused(paused: bool) -> void:
	_planning_badge.visible = paused

func set_current_goal(title: String, criteria: Array[String], help_id := "concept:construction") -> void:
	_goal_title.text = title
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
	return true


func set_external_modal(id: String, open: bool) -> void:
	if open:
		_ui_state.open_modal(id)
		if _highlight_layer != null: _highlight_layer.clear()
	else:
		_ui_state.close_modal(id)
		_refresh_onboarding()

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
	var top := PanelContainer.new()
	top.theme_type_variation = "HudPanel"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18; top.offset_top = 14; top.offset_right = -18; top.offset_bottom = 56
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top)
	var top_row := HBoxContainer.new(); top.add_child(top_row)
	_mode_badge = Label.new(); _mode_badge.text = "FACTORY"; _mode_badge.theme_type_variation = "SectionTitleLabel"; top_row.add_child(_mode_badge)
	_status = Label.new(); _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top_row.add_child(_status)
	_reserves = Label.new(); _reserves.theme_type_variation = "NumericLabel"; top_row.add_child(_reserves)
	var research := Button.new(); research.theme_type_variation = "QuietButton"; research.text = "Research"; research.tooltip_text = InputGlyphs.hint(&"open_research", "Open Research"); research.pressed.connect(func(): research_requested.emit()); top_row.add_child(research)
	_help_targets.research = research; HelpCatalog.attach(research, HelpCatalog.control("research"))
	var codex := Button.new(); codex.theme_type_variation = "QuietButton"; codex.text = "Codex"; codex.pressed.connect(func(): codex_requested.emit("")); top_row.add_child(codex)
	HelpCatalog.attach(codex, HelpCatalog.control("codex"))
	var experiments := Button.new(); experiments.theme_type_variation = "QuietButton"; experiments.text = "Ideas"; experiments.tooltip_text = "Optional physical experiments"; experiments.pressed.connect(func(): experiments_requested.emit()); top_row.add_child(experiments)
	HelpCatalog.attach(experiments, HelpCatalog.control("experiments"))
	var map_button := Button.new(); map_button.theme_type_variation = "QuietButton"; map_button.text = "Map"; map_button.tooltip_text = InputGlyphs.hint(&"map", "Open Map"); map_button.pressed.connect(func(): map_requested.emit()); top_row.add_child(map_button)
	HelpCatalog.attach(map_button, HelpCatalog.control("map"))
	var statistics := Button.new(); statistics.theme_type_variation = "QuietButton"; statistics.text = "Stats"; statistics.tooltip_text = InputGlyphs.hint(&"statistics", "Open Statistics"); statistics.pressed.connect(toggle_statistics); top_row.add_child(statistics)
	var overlay_button := Button.new(); overlay_button.theme_type_variation = "QuietButton"; overlay_button.text = "Overlay  ▾"; overlay_button.pressed.connect(_show_overlay_menu.bind(overlay_button)); top_row.add_child(overlay_button)
	HelpCatalog.attach(overlay_button, HelpCatalog.control("overlay"))
	var planning := Button.new(); planning.theme_type_variation = "QuietButton"; planning.text = "Plan"; planning.pressed.connect(func(): planning_pause_requested.emit()); top_row.add_child(planning)
	_help_targets.planning_pause = planning; HelpCatalog.attach(planning, HelpCatalog.control("planning_pause"))
	var controls := Button.new(); controls.theme_type_variation = "QuietButton"; controls.text = "? Controls"; controls.pressed.connect(toggle_controls); top_row.add_child(controls)
	_help_targets.controls = controls; HelpCatalog.attach(controls, HelpCatalog.control("controls"))
	_overlay_menu = PopupMenu.new()
	var overlays := [["None",0], ["Geology",1], ["Temperature",4], ["Magnetic Field",5], ["Automation",8], ["Underground Logistics",9], ["Production Flow",12], ["Power",13]]
	for entry: Array in overlays: _overlay_menu.add_item(str(entry[0]), int(entry[1]))
	_overlay_menu.id_pressed.connect(func(id: int): overlay_selected.emit(id)); add_child(_overlay_menu)
	_info_badge = Label.new(); _info_badge.text = "I · INFO MODE"; _info_badge.visible = false; _info_badge.add_theme_color_override("font_color", Color("69d8e6")); top_row.add_child(_info_badge)
	_alert_text = Label.new(); _alert_text.visible = false; _alert_text.add_theme_color_override("font_color", Color("ff815c")); top_row.add_child(_alert_text)
	_planning_badge = Label.new(); _planning_badge.text = "Ⅱ  PLANNING PAUSE"; _planning_badge.visible = false; _planning_badge.theme_type_variation = "WarningLabel"; top_row.add_child(_planning_badge)

	_action_row = HBoxContainer.new()
	_action_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_action_row.offset_left = 16; _action_row.offset_top = -68; _action_row.offset_right = 610; _action_row.offset_bottom = -16
	_action_row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_action_row)
	var actions: Array[Dictionary] = [
		{"name":"SELECT", "kind":"select", "id":0, "icon":"select"},
		{"name":"PIPETTE", "kind":"pipette", "id":0, "icon":"pipette"},
		{"name":"DIG", "kind":"terrain", "id":3, "icon":"dig"},
		{"name":"CUT", "kind":"organic_clear", "id":0, "icon":"remove"},
		{"name":"IGNITE", "kind":"ignite", "id":0, "icon":"furnace"},
		{"name":"REMOVE", "kind":"remove", "id":0, "icon":"remove"},
		{"name":"BLUEPRINT", "kind":"blueprint_select", "id":0, "icon":"blueprint"},
	]
	for action: Dictionary in actions:
		var button := Button.new(); button.theme_type_variation = "QuietButton"; button.text = str(action.name).capitalize(); button.pressed.connect(func(): tool_selected.emit(action)); _action_row.add_child(button)
		var help_id: String = str({"pipette":"pipette", "blueprint_select":"blueprint", "select":"info_mode"}.get(str(action.kind), ""))
		var action_help: Dictionary = HelpCatalog.control(help_id) if not help_id.is_empty() else {"title":str(action.name).capitalize(), "description":"Use this world tool to interact with physical cells and Components."}
		HelpCatalog.attach(button, action_help)
		if str(action.kind) == "terrain": _help_targets.dig = button
		if str(action.kind) == "select": _help_targets.info = button

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -360; bottom.offset_top = -96; bottom.offset_right = 360; bottom.offset_bottom = -14
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(bottom)
	var page_row := HBoxContainer.new(); page_row.alignment = BoxContainer.ALIGNMENT_CENTER; bottom.add_child(page_row)
	var previous_page := Button.new(); previous_page.text = "◀"; previous_page.pressed.connect(change_page.bind(-1)); page_row.add_child(previous_page)
	HelpCatalog.attach(previous_page, HelpCatalog.control("quickbar_previous"))
	_page_label = Label.new(); _page_label.text = "1 / %d" % PAGE_COUNT; _page_label.theme_type_variation = "CaptionLabel"; page_row.add_child(_page_label)
	var next_page := Button.new(); next_page.text = "▶"; next_page.pressed.connect(change_page.bind(1)); page_row.add_child(next_page)
	HelpCatalog.attach(next_page, HelpCatalog.control("quickbar_next"))
	var catalog_button := Button.new(); catalog_button.text = "Build catalog"; catalog_button.tooltip_text = InputGlyphs.hint(&"build_catalog", "Open Catalog"); catalog_button.pressed.connect(toggle_catalog); page_row.add_child(catalog_button)
	_help_targets.catalog = catalog_button; HelpCatalog.attach(catalog_button, HelpCatalog.control("catalog"))
	var blueprint_button := Button.new(); blueprint_button.text = "Blueprints"; blueprint_button.pressed.connect(func(): blueprints_requested.emit()); page_row.add_child(blueprint_button)
	_help_targets.blueprints = blueprint_button; HelpCatalog.attach(blueprint_button, HelpCatalog.control("blueprint"))
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 5); bottom.add_child(row)
	for index in SLOT_COUNT:
		var slot := ToolSlot.new(); slot.custom_minimum_size = Vector2(62, 50); slot.index = index
		slot.pressed.connect(_activate_visible_slot.bind(index)); slot.slot_drop.connect(_on_slot_drop); slot.slot_clear.connect(_on_slot_clear)
		row.add_child(slot); _slot_nodes.append(slot)
	_help_targets.quickbar = row

	_catalog = PanelContainer.new()
	_catalog.theme_type_variation = "ElevatedPanel"
	_catalog.visible = false
	_catalog.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_catalog.offset_left = 18; _catalog.offset_top = -330; _catalog.offset_right = 650; _catalog.offset_bottom = 330
	add_child(_catalog)
	var catalog_margin := MarginContainer.new(); catalog_margin.add_theme_constant_override("margin_left", 16); catalog_margin.add_theme_constant_override("margin_top", 14); catalog_margin.add_theme_constant_override("margin_right", 16); catalog_margin.add_theme_constant_override("margin_bottom", 14); _catalog.add_child(catalog_margin)
	var catalog_column := VBoxContainer.new(); catalog_margin.add_child(catalog_column)
	var title_row := HBoxContainer.new(); catalog_column.add_child(title_row)
	var title := Label.new(); title.text = "Build catalog"; title.theme_type_variation = "ScreenTitleLabel"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title_row.add_child(title)
	var close_catalog := Button.new(); close_catalog.theme_type_variation = "QuietButton"; close_catalog.text = "Close  [B]"; close_catalog.pressed.connect(toggle_catalog); title_row.add_child(close_catalog)
	_search = LineEdit.new(); _search.placeholder_text = "Search by name or purpose…"; _search.text_changed.connect(func(_text: String): _refresh_catalog()); catalog_column.add_child(_search)
	var category_row := HBoxContainer.new(); catalog_column.add_child(category_row)
	for category in ["ALL", "LOGISTICS", "PROCESSING", "FLUIDS", "THERMAL", "POWER", "AUTOMATION", "STRUCTURES"]:
		var category_button := Button.new(); category_button.theme_type_variation = "QuietButton"; category_button.text = category.capitalize(); category_button.pressed.connect(func(): _category_filter = category; _refresh_catalog()); category_row.add_child(category_button)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; catalog_column.add_child(scroll)
	_catalog_grid = GridContainer.new(); _catalog_grid.columns = 3; _catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_catalog_grid)
	var hint := Label.new(); hint.text = "Select · drag to quickbar · right-click a slot to clear"; hint.theme_type_variation = "CaptionLabel"; catalog_column.add_child(hint)

	_statistics_panel = PanelContainer.new(); _statistics_panel.visible = false; _statistics_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT); _statistics_panel.offset_left = -420; _statistics_panel.offset_top = -280; _statistics_panel.offset_right = -16; _statistics_panel.offset_bottom = 280; add_child(_statistics_panel)
	var statistics_margin := MarginContainer.new(); statistics_margin.add_theme_constant_override("margin_left", 16); statistics_margin.add_theme_constant_override("margin_top", 14); statistics_margin.add_theme_constant_override("margin_right", 16); statistics_margin.add_theme_constant_override("margin_bottom", 14); _statistics_panel.add_child(statistics_margin)
	_statistics_text = Label.new(); _statistics_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP; statistics_margin.add_child(_statistics_text)

	_inspector = PanelContainer.new(); _inspector.theme_type_variation = "ElevatedPanel"; _inspector.visible = false; _inspector.set_anchors_preset(Control.PRESET_CENTER_RIGHT); _inspector.offset_left = -390; _inspector.offset_top = -220; _inspector.offset_right = -18; _inspector.offset_bottom = 220; _inspector.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(_inspector)
	var inspector_margin := MarginContainer.new(); inspector_margin.add_theme_constant_override("margin_left", 16); inspector_margin.add_theme_constant_override("margin_top", 14); inspector_margin.add_theme_constant_override("margin_right", 16); inspector_margin.add_theme_constant_override("margin_bottom", 14); _inspector.add_child(inspector_margin)
	_inspector_text = Label.new(); _inspector_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; inspector_margin.add_child(_inspector_text)
	var inspector_column := VBoxContainer.new()
	inspector_margin.remove_child(_inspector_text)
	inspector_margin.add_child(inspector_column)
	inspector_column.add_child(_inspector_text)
	_inspector_advanced_button = Button.new(); _inspector_advanced_button.text = "ADVANCED DETAILS"; _inspector_advanced_button.visible = false; _inspector_advanced_button.pressed.connect(func(): _inspector_advanced.visible = not _inspector_advanced.visible); inspector_column.add_child(_inspector_advanced_button)
	_inspector_advanced = Label.new(); _inspector_advanced.visible = false; _inspector_advanced.add_theme_color_override("font_color", Color("7f9295")); inspector_column.add_child(_inspector_advanced)
	var inspector_codex := Button.new(); inspector_codex.text = "OPEN IN CODEX"; inspector_codex.pressed.connect(func(): if not _inspector_codex_id.is_empty(): codex_requested.emit(_inspector_codex_id)); inspector_column.add_child(inspector_codex)

	var onboarding_panel := PanelContainer.new(); onboarding_panel.theme_type_variation = "HudPanel"; onboarding_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT); onboarding_panel.offset_left = -390; onboarding_panel.offset_top = 70; onboarding_panel.offset_right = -18; onboarding_panel.offset_bottom = 202; onboarding_panel.mouse_filter = Control.MOUSE_FILTER_PASS; add_child(onboarding_panel)
	var goal_column := VBoxContainer.new(); onboarding_panel.add_child(goal_column)
	var goal_badge := Label.new(); goal_badge.text = "CURRENT GOAL"; goal_badge.theme_type_variation = "CaptionLabel"; goal_column.add_child(goal_badge)
	_goal_title = Label.new(); _goal_title.text = "Discover physical processing"; _goal_title.theme_type_variation = "SectionTitleLabel"; goal_column.add_child(_goal_title)
	_goal_criteria = Label.new(); _goal_criteria.text = "Build · Observe · Iterate"; _goal_criteria.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _goal_criteria.add_theme_color_override("font_color", KoalaSandTheme.COLOR_TEXT_SECONDARY); goal_column.add_child(_goal_criteria)
	var goal_help := Button.new(); goal_help.theme_type_variation = "QuietButton"; goal_help.text = "How?"; goal_help.pressed.connect(func(): codex_requested.emit(_goal_help_id)); goal_column.add_child(goal_help)
	_help_targets.goal_help = goal_help
	HelpCatalog.attach(goal_help, {"title":"Goal help", "description":"Opens a relevant physical principle. It explains the outcome without prescribing one exact factory design.", "codex_id":"concept:construction"})
	_onboarding_hint = Label.new(); _onboarding_hint.text = _onboarding.current_hint(); _onboarding_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _onboarding_hint.add_theme_color_override("font_color", Color("a9c3bd")); goal_column.add_child(_onboarding_hint)
	_help_targets.status = onboarding_panel
	_build_controls_panel()

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
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	for tool: Dictionary in get_meta("catalog_tools"):
		if not query.is_empty() and not query in str(tool.name).to_lower() and not query in str(tool.category).to_lower(): continue
		if _category_filter != "ALL" and _canonical_category(tool) != _category_filter: continue
		var entry := ToolSlot.new(); entry.custom_minimum_size = Vector2(188, 76); entry.configure(tool, 0, 0, true); entry.text = "       %s\n       %s" % [tool.name, "Research required" if bool(tool.get("locked", false)) else _canonical_category(tool).capitalize()]; entry.alignment = HORIZONTAL_ALIGNMENT_LEFT; entry.pressed.connect(func(): tool_selected.emit(tool)); _catalog_grid.add_child(entry)
		if _tooltip_layer != null: _tooltip_layer.bind(entry)

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
		_controls_text.text = _controls_copy()
		_ui_state.open_modal("controls")
		KoalaSandTheme.animate_in(_controls_panel)
		if _highlight_layer != null: _highlight_layer.clear()
	else:
		_ui_state.close_modal("controls")
		_refresh_onboarding()


func _build_controls_panel() -> void:
	_controls_panel = PanelContainer.new(); _controls_panel.theme_type_variation = "ModalPanel"; _controls_panel.visible = false; _controls_panel.set_anchors_preset(Control.PRESET_CENTER); _controls_panel.offset_left = -330; _controls_panel.offset_top = -300; _controls_panel.offset_right = 330; _controls_panel.offset_bottom = 300; _controls_panel.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(_controls_panel)
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
