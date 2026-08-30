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
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24; scroll.offset_top = 18; scroll.offset_right = -24; scroll.offset_bottom = -18
	add_child(scroll)
	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(1240, 720)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 14)
	scroll.add_child(center)
	var brand_rule := HSeparator.new(); center.add_child(brand_rule)
	var title := Label.new()
	title.text = "KOALASAND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = "DisplayLabel"
	center.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Matter moves. Heat spreads. Factories emerge."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = "SecondaryLabel"
	center.add_child(subtitle)
	var version := Label.new(); version.text = BuildInfo.display(); version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; version.theme_type_variation = "CaptionLabel"; center.add_child(version)
	var worlds_label := Label.new(); worlds_label.text = "YOUR WORLDS"; worlds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; worlds_label.theme_type_variation = "SectionTitleLabel"; center.add_child(worlds_label)
	var session_row := HBoxContainer.new()
	session_row.alignment = BoxContainer.ALIGNMENT_CENTER
	session_row.add_theme_constant_override("separation", 10)
	center.add_child(session_row)
	_continue_button = Button.new(); _continue_button.theme_type_variation = "PrimaryButton"; _continue_button.text = "Continue"; _continue_button.custom_minimum_size.x = 150; _continue_button.pressed.connect(_continue_latest); session_row.add_child(_continue_button)
	_save_selector = OptionButton.new(); _save_selector.custom_minimum_size.x = 260; session_row.add_child(_save_selector)
	_load_button = Button.new(); _load_button.text = "Load"; _load_button.pressed.connect(_load_selected); session_row.add_child(_load_button)
	_recover_button = Button.new(); _recover_button.text = "Restore backup"; _recover_button.visible = false; _recover_button.pressed.connect(_recover_selected); session_row.add_child(_recover_button)
	_delete_button = Button.new(); _delete_button.theme_type_variation = "DangerButton"; _delete_button.text = "Delete…"; _delete_button.pressed.connect(_confirm_delete); session_row.add_child(_delete_button)
	var diagnostics := Button.new(); diagnostics.theme_type_variation = "QuietButton"; diagnostics.text = "Export diagnostics"; diagnostics.pressed.connect(func(): diagnostics_requested.emit()); session_row.add_child(diagnostics)
	_save_details = Label.new(); _save_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _save_details.theme_type_variation = "SecondaryLabel"; center.add_child(_save_details)
	_save_selector.item_selected.connect(_update_save_details)
	var new_label := Label.new(); new_label.text = "NEW WORLD"; new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; new_label.theme_type_variation = "SectionTitleLabel"; center.add_child(new_label)

	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 14)
	center.add_child(cards_row)
	var descriptions := [
		"RECOMMENDED FIRST\nFree camera · build at any visible location\nPhysical Research progression enabled",
		"PLAY AS THE KOALA\nMove, dig and fly · local vision and build range\nSame physical world and Research progression",
		"EXPERIMENT FREELY\nFree camera · all materials and Components unlocked\nPhysics stays fully active; progression gates are off",
	]
	for index in range(3):
		var axes := GameModeCapabilities.preset(index)
		var card := Button.new()
		card.custom_minimum_size = Vector2(400, 124)
		card.toggle_mode = true
		card.text = "%s\n\n%s" % [str(axes.display_name).to_upper(), descriptions[index]]
		card.add_theme_font_size_override("font_size", 15)
		card.pressed.connect(_select_preset.bind(index))
		cards_row.add_child(card)
		_cards.append(card)
	var choice_help := Label.new(); choice_help.text = "Which should I choose?  Factory teaches large-scale building · Character adds movement and discovery · Creative is for unrestricted experiments."; choice_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; choice_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; choice_help.theme_type_variation = "SecondaryLabel"; center.add_child(choice_help)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	center.add_child(content)
	var preview_frame := PanelContainer.new(); preview_frame.theme_type_variation = "ElevatedPanel"; preview_frame.custom_minimum_size = Vector2(760, 340); content.add_child(preview_frame)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(740, 330)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_frame.add_child(_preview)
	var settings := VBoxContainer.new()
	settings.custom_minimum_size = Vector2(400, 330)
	settings.add_theme_constant_override("separation", 12)
	content.add_child(settings)
	var seed_label := Label.new()
	seed_label.text = "WORLD IDENTITY"
	seed_label.theme_type_variation = "SectionTitleLabel"
	settings.add_child(seed_label)
	_world_name_input = LineEdit.new()
	_world_name_input.placeholder_text = "World name"
	_world_name_input.text = "New World"
	settings.add_child(_world_name_input)
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = "signed 64-bit integer"
	_seed_input.text_submitted.connect(func(_text: String) -> void: _refresh_preview())
	settings.add_child(_seed_input)
	var seed_help := Label.new(); seed_help.text = "Leave this value unchanged for the shown world, or choose New seed. The same seed and generation version reproduce the same world."; seed_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; seed_help.theme_type_variation = "CaptionLabel"; settings.add_child(seed_help)
	var seed_actions := HBoxContainer.new()
	settings.add_child(seed_actions)
	var randomize := Button.new()
	randomize.text = "New seed"
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
	settings.add_child(_identity_label)
	var note := Label.new()
	note.text = "The preview shows only surface terrain. Caves and deposits remain undiscovered."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = "CaptionLabel"
	settings.add_child(note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_child(spacer)
	var start := Button.new()
	start.theme_type_variation = "PrimaryButton"
	start.text = "Create world"
	start.custom_minimum_size = Vector2(0, 52)
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(_start)
	settings.add_child(start)
	_select_preset(GameModeCapabilities.Preset.FACTORY)
	set_saved_worlds([])
	KoalaSandTheme.animate_in(center, false, true)


func set_seed(seed: int) -> void:
	_seed_input.text = str(seed)
	_refresh_preview()


func _select_preset(preset_id: int) -> void:
	selected_preset = clampi(preset_id, 0, 2)
	for index in range(_cards.size()):
		_cards[index].button_pressed = index == selected_preset
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
	_preview_world.configure_world({"seed": seed, "generation_version": 2}, 1)
	var page: Dictionary = _preview_world.get_macro_preview(190, 104)
	var image := Image.create_from_data(int(page.width), int(page.height), false, Image.FORMAT_RGBA8, page.pixels)
	_preview.texture = ImageTexture.create_from_image(image)
	var identity: Dictionary = _preview_world.get_world_identity()
	var axes := GameModeCapabilities.preset(selected_preset)
	var mode_detail: String = [
		"Global factory view · Research enabled",
		"Physical character · Local discovery and building",
		"Full sandbox access · Everything unlocked",
	][selected_preset]
	_identity_label.text = "Seed  %d\nWorld signature  %s\n\n%s\n%s" % [seed, str(identity.generator_settings_hash), str(axes.display_name), mode_detail]


func set_saved_worlds(worlds: Array[Dictionary]) -> void:
	_saved_worlds = worlds.duplicate(true)
	if _save_selector == null:
		return
	_save_selector.clear()
	for metadata in _saved_worlds:
		var state := "RECOVERY AVAILABLE" if bool(metadata.get("recoverable", false)) else "CORRUPT" if not bool(metadata.get("primary_valid", true)) else "READY"
		_save_selector.add_item("%s  ·  %s  ·  %s" % [str(metadata.get("world_name", "World")), str(metadata.get("timestamp_utc", "")), state])
	var has_saves := _saved_worlds.any(func(metadata: Dictionary) -> bool: return bool(metadata.get("primary_valid", true)))
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
		if _save_details != null: _save_details.text = "No saved worlds yet. Create a world below; KoalaSand will save it from the pause menu and through autosave."
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
