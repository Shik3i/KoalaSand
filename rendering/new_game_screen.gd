class_name NewGameScreen
extends Control

signal start_requested(preset_id: int, seed: int, world_name: String)
signal continue_requested(world_name: String)
signal delete_requested(world_name: String)
signal recovery_requested(world_name: String)
signal diagnostics_requested

var selected_preset := GameModeCapabilities.Preset.FACTORY
var _preview_world: Variant
var _seed_input: LineEdit
var _preview: TextureRect
var _cards: Array[Button] = []
var _identity_label: Label
var _world_name_input: LineEdit
var _save_selector: OptionButton
var _saved_worlds: Array[Dictionary] = []
var _continue_button: Button
var _load_button: Button
var _delete_button: Button
var _recover_button: Button
var _save_details: Label
var _root_column: VBoxContainer
var _mode_row: HBoxContainer
var _content_row: HBoxContainer
var _preview_frame: PanelContainer
var _settings_panel: VBoxContainer
var _start_button: Button
var _existing_label: Label
var _session_row: HBoxContainer
var _diagnostics_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = KoalaSandTheme.build()
	_build_ui()
	set_seed(8675309)


func _build_ui() -> void:
	var backdrop := IndustrialBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	_root_column = VBoxContainer.new()
	_root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_column.add_theme_constant_override("separation", 7)
	margin.add_child(_root_column)
	var brand_rule := HSeparator.new(); _root_column.add_child(brand_rule)
	var title := Label.new()
	title.text = "KOALASAND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "DisplayLabel"
	title.add_theme_font_size_override("font_size", 32)
	_root_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Matter moves. Heat spreads. Factories emerge."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = "SecondaryLabel"
	_root_column.add_child(subtitle)
	var version := Label.new(); version.text = BuildInfo.display(); version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; version.theme_type_variation = "CaptionLabel"; _root_column.add_child(version)
	_existing_label = Label.new(); _existing_label.text = "CONTINUE"; _existing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _existing_label.theme_type_variation = "SectionTitleLabel"; _root_column.add_child(_existing_label)
	_session_row = HBoxContainer.new()
	_session_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_session_row.add_theme_constant_override("separation", 8)
	_root_column.add_child(_session_row)
	_continue_button = Button.new(); _continue_button.theme_type_variation = "PrimaryButton"; _continue_button.text = "Continue"; _continue_button.custom_minimum_size.x = 132; _continue_button.pressed.connect(_continue_latest); _session_row.add_child(_continue_button)
	_save_selector = OptionButton.new(); _save_selector.custom_minimum_size.x = 240; _session_row.add_child(_save_selector)
	_load_button = Button.new(); _load_button.text = "Load"; _load_button.pressed.connect(_load_selected); _session_row.add_child(_load_button)
	_recover_button = Button.new(); _recover_button.text = "Restore backup"; _recover_button.visible = false; _recover_button.pressed.connect(_recover_selected); _session_row.add_child(_recover_button)
	_delete_button = Button.new(); _delete_button.theme_type_variation = "DangerButton"; _delete_button.text = "Delete…"; _delete_button.pressed.connect(_confirm_delete); _session_row.add_child(_delete_button)
	_save_details = Label.new(); _save_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _save_details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _save_details.theme_type_variation = "CaptionLabel"; _root_column.add_child(_save_details)
	_save_selector.item_selected.connect(_update_save_details)
	var new_label := Label.new(); new_label.text = "NEW WORLD"; new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; new_label.theme_type_variation = "SectionTitleLabel"; _root_column.add_child(new_label)

	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 10)
	_root_column.add_child(_mode_row)
	var descriptions := [
		"RECOMMENDED · BUILD AND AUTOMATE",
		"EXPLORE · DIG · BUILD LOCALLY",
		"EXPERIMENT WITHOUT LIMITS",
	]
	for index in range(3):
		var axes := GameModeCapabilities.preset(index)
		var card := Button.new()
		card.custom_minimum_size.y = 76
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.text = "%s\n%s" % [str(axes.display_name).capitalize(), descriptions[index]]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", 14)
		card.pressed.connect(_select_preset.bind(index))
		_mode_row.add_child(card)
		_cards.append(card)

	_content_row = HBoxContainer.new()
	_content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_row.add_theme_constant_override("separation", 14)
	_root_column.add_child(_content_row)
	_preview_frame = PanelContainer.new(); _preview_frame.theme_type_variation = "ElevatedPanel"; _preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _preview_frame.size_flags_stretch_ratio = 1.65; _content_row.add_child(_preview_frame)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_frame.add_child(_preview)
	_settings_panel = VBoxContainer.new()
	_settings_panel.custom_minimum_size.x = 330
	_settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_panel.size_flags_stretch_ratio = 1.0
	_settings_panel.add_theme_constant_override("separation", 6)
	_content_row.add_child(_settings_panel)
	var seed_label := Label.new()
	seed_label.text = "WORLD SETUP"
	seed_label.theme_type_variation = "SectionTitleLabel"
	_settings_panel.add_child(seed_label)
	_world_name_input = LineEdit.new()
	_world_name_input.placeholder_text = "World name"
	_world_name_input.text = "New World"
	_settings_panel.add_child(_world_name_input)
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = "signed 64-bit integer"
	_seed_input.text_submitted.connect(func(_text: String) -> void: _refresh_preview())
	_settings_panel.add_child(_seed_input)
	var seed_actions := HBoxContainer.new()
	seed_actions.add_theme_constant_override("separation", 6)
	_settings_panel.add_child(seed_actions)
	var randomize := Button.new()
	randomize.text = "↻ Seed"
	randomize.pressed.connect(_randomize_seed)
	seed_actions.add_child(randomize)
	var copy := Button.new()
	copy.text = "Copy"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_seed_input.text))
	seed_actions.add_child(copy)
	var paste := Button.new()
	paste.text = "Paste"
	paste.pressed.connect(func() -> void:
		var clipboard := DisplayServer.clipboard_get().strip_edges()
		if clipboard.is_valid_int(): set_seed(clipboard.to_int())
	)
	seed_actions.add_child(paste)
	_identity_label = Label.new()
	_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_identity_label.theme_type_variation = "SecondaryLabel"
	_identity_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_panel.add_child(_identity_label)
	var note_row := HBoxContainer.new()
	note_row.add_theme_constant_override("separation", 8)
	_settings_panel.add_child(note_row)
	var note := Label.new()
	note.text = "A glimpse of the landscape. Underground remains undiscovered."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = "CaptionLabel"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_row.add_child(note)
	_diagnostics_button = Button.new()
	_diagnostics_button.theme_type_variation = "QuietButton"
	_diagnostics_button.text = "⋯"
	_diagnostics_button.tooltip_text = "Diagnostics"
	_diagnostics_button.pressed.connect(func(): diagnostics_requested.emit())
	note_row.add_child(_diagnostics_button)
	_start_button = Button.new()
	_start_button.theme_type_variation = "PrimaryButton"
	_start_button.text = "Create world"
	_start_button.custom_minimum_size = Vector2(0, 46)
	_start_button.add_theme_font_size_override("font_size", 17)
	_start_button.pressed.connect(_start)
	_settings_panel.add_child(_start_button)
	_select_preset(GameModeCapabilities.Preset.FACTORY)
	set_saved_worlds([])
	KoalaSandTheme.animate_in(_root_column, false, true)


func set_seed(seed: int) -> void:
	_seed_input.text = str(seed)
	_refresh_preview()


func _select_preset(preset_id: int) -> void:
	selected_preset = clampi(preset_id, 0, 2)
	for index in range(_cards.size()):
		_cards[index].button_pressed = index == selected_preset
		_cards[index].theme_type_variation = "PrimaryButton" if index == selected_preset else "QuietButton"
	_refresh_preview()


func select_preset(preset_id: int) -> void:
	_select_preset(preset_id)


func _randomize_seed() -> void:
	var next_seed := int(Time.get_ticks_usec()) ^ int(Time.get_unix_time_from_system() * 1000.0)
	set_seed(next_seed)


func _refresh_preview() -> void:
	if _seed_input == null or not _seed_input.text.strip_edges().is_valid_int():
		return
	if _preview_world == null:
		_preview_world = NativeSandWorld.new()
	var seed := _seed_input.text.to_int()
	_preview_world.configure_world({"seed": seed, "generation_version": BuildInfo.GENERATION_VERSION}, 1)
	var page: Dictionary = _preview_world.get_macro_preview(384, 216)
	var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
	_preview.texture = ImageTexture.create_from_image(image)
	var identity: Dictionary = _preview_world.get_world_identity()
	var axes := GameModeCapabilities.preset(selected_preset)
	var mode_detail: String = [
		"Global factory view · Research enabled",
		"Physical character · Local discovery and building",
		"Full sandbox access · Everything unlocked",
	][selected_preset]
	_identity_label.text = "Seed %d  ·  %s\n%s\n%s" % [seed, str(axes.display_name), _describe_world(), mode_detail]


func _describe_world() -> String:
	# The preview describes the surface a player can see from spawn. Caves, ore and
	# groundwater stay undiscovered on purpose.
	var summary: Dictionary = _preview_world.get_world_preview_summary()
	if not bool(summary.get("supported", false)):
		var macro: Dictionary = _preview_world.get_macro_sample(Vector2i.ZERO)
		var legacy := ["Slate highlands", "Amethyst faultland", "Verdant basin", "Ochre shelves", "Blue granite range"]
		return legacy[int(macro.get("geology_province", 0)) % legacy.size()]
	var parts: Array[String] = [str(summary.biome), str(summary.terrain)]
	if bool(summary.get("surface_water", false)):
		parts.append("Surface water")
	return "  ·  ".join(parts) + "\nBedrock: " + str(summary.province)


func layout_metrics() -> Dictionary:
	return {
		"viewport": Rect2(Vector2.ZERO, size),
		"root": _root_column.get_global_rect(),
		"modes": _mode_row.get_global_rect(),
		"preview": _preview_frame.get_global_rect(),
		"settings": _settings_panel.get_global_rect(),
		"create": _start_button.get_global_rect(),
		"scroll_containers": get_children().filter(func(node: Node) -> bool: return node is ScrollContainer).size(),
		"mode_cards": _cards.map(func(card: Button) -> Rect2: return card.get_global_rect()),
	}


func set_saved_worlds(worlds: Array[Dictionary]) -> void:
	_saved_worlds = worlds.duplicate(true)
	if _save_selector == null:
		return
	_save_selector.clear()
	for metadata in _saved_worlds:
		var state := "RECOVERY AVAILABLE" if bool(metadata.get("recoverable", false)) else "CORRUPT" if not bool(metadata.get("primary_valid", true)) else "READY"
		_save_selector.add_item("%s  ·  %s  ·  %s" % [str(metadata.get("world_name", "World")), str(metadata.get("timestamp_utc", "")), state])
	var has_saves := _saved_worlds.any(func(metadata: Dictionary) -> bool: return bool(metadata.get("primary_valid", true)))
	var show_saved := not _saved_worlds.is_empty()
	if _existing_label != null: _existing_label.visible = show_saved
	if _session_row != null: _session_row.visible = show_saved
	if _save_details != null: _save_details.visible = show_saved
	if _continue_button != null: _continue_button.disabled = not has_saves
	if _continue_button != null:
		HelpCatalog.attach(_continue_button, {"title":"Continue latest world", "description":"Loads the newest valid saved world.", "disabled_reason":"No valid saved world exists yet." if not has_saves else ""})
	if _load_button != null: _load_button.visible = not _saved_worlds.is_empty()
	if _delete_button != null: _delete_button.visible = not _saved_worlds.is_empty()
	if _save_selector != null: _save_selector.visible = not _saved_worlds.is_empty()
	_update_save_details(0)


func _continue_latest() -> void:
	for metadata: Dictionary in _saved_worlds:
		if bool(metadata.get("primary_valid", true)):
			continue_requested.emit(str(metadata.world_name))
			return


func _load_selected() -> void:
	if _saved_worlds.is_empty(): return
	var metadata: Dictionary = _saved_worlds[clampi(_save_selector.selected, 0, _saved_worlds.size() - 1)]
	if bool(metadata.get("primary_valid", true)): continue_requested.emit(str(metadata.world_name))
	else: _update_save_details(_save_selector.selected)

func _recover_selected() -> void:
	if not _saved_worlds.is_empty(): recovery_requested.emit(str(_saved_worlds[clampi(_save_selector.selected, 0, _saved_worlds.size() - 1)].world_name))

func _update_save_details(index: int) -> void:
	if _save_details == null or _saved_worlds.is_empty():
		if _save_details != null: _save_details.text = ""
		if _recover_button != null: _recover_button.visible = false
		return
	var metadata: Dictionary = _saved_worlds[clampi(index, 0, _saved_worlds.size() - 1)]
	var modes := ["Factory", "Character", "Creative"]
	var mode: String = modes[clampi(int(metadata.get("mode", 0)), 0, 2)]
	var playtime := int(metadata.get("playtime_seconds", 0))
	var status := "Primary save valid."
	if bool(metadata.get("recoverable", false)): status = "Primary save is invalid. A valid atomic backup can be restored explicitly."
	elif not bool(metadata.get("primary_valid", true)): status = "Save cannot be loaded: %s" % str(metadata.get("primary_error", "UNKNOWN SAVE ERROR"))
	_save_details.text = "%s · Seed %d · Played %02d:%02d · Save schema %d · %s\n%s" % [mode, int(metadata.get("seed", 0)), playtime / 3600, (playtime / 60) % 60, int(metadata.get("save_schema_version", 0)), str(metadata.get("game_version", "unknown")), status]
	_recover_button.visible = bool(metadata.get("recoverable", false))


func _confirm_delete() -> void:
	if _saved_worlds.is_empty(): return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete world?"
	dialog.dialog_text = "Delete '%s' and its recovery backup?" % str(_saved_worlds[clampi(_save_selector.selected, 0, _saved_worlds.size() - 1)].world_name)
	dialog.confirmed.connect(func() -> void: delete_requested.emit(str(_saved_worlds[clampi(_save_selector.selected, 0, _saved_worlds.size() - 1)].world_name)); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _start() -> void:
	if _seed_input.text.strip_edges().is_valid_int() and not _world_name_input.text.strip_edges().is_empty():
		start_requested.emit(selected_preset, _seed_input.text.to_int(), _world_name_input.text.strip_edges())
