class_name BlueprintLibraryPanel
extends PanelContainer

signal blueprint_selected(blueprint: BlueprintDefinition)
signal save_clipboard_requested(name: String)
signal closed

var library: BlueprintLibrary
var _search := LineEdit.new()
var _entries := VBoxContainer.new()
var _name := LineEdit.new()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	offset_left = 18; offset_top = -330; offset_right = 510; offset_bottom = 330
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = KoalaSandTheme.build()
	theme_type_variation = "ElevatedPanel"
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new(); margin.add_child(column)
	var head := HBoxContainer.new(); column.add_child(head)
	var title := Label.new(); title.text = "Blueprint library"; title.theme_type_variation = "ScreenTitleLabel"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(title)
	var close_button := Button.new(); close_button.theme_type_variation = "QuietButton"; close_button.text = "Close  [Esc]"; close_button.pressed.connect(close); head.add_child(close_button)
	var guidance := Label.new(); guidance.text = "Blueprints copy ordinary Component layouts. They do not contain recipes, hidden processing or free matter. Select an example to place an editable physical assembly."; guidance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; guidance.theme_type_variation = "SecondaryLabel"; column.add_child(guidance)
	_search.placeholder_text = "Search example and player blueprints…"; _search.text_changed.connect(func(_q: String): refresh()); column.add_child(_search)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	scroll.add_child(_entries)
	var save_title := Label.new(); save_title.text = "SAVE CURRENT COPY"; save_title.theme_type_variation = "SectionTitleLabel"; column.add_child(save_title)
	var save_row := HBoxContainer.new(); column.add_child(save_row)
	_name.placeholder_text = "My Furnace"; _name.size_flags_horizontal = Control.SIZE_EXPAND_FILL; save_row.add_child(_name)
	var save := Button.new(); save.theme_type_variation = "PrimaryButton"; save.text = "Save blueprint"; save.pressed.connect(func(): save_clipboard_requested.emit(_name.text.strip_edges())); save_row.add_child(save)

func initialize(value: BlueprintLibrary) -> void:
	library = value
	refresh()

func open() -> void:
	refresh()
	KoalaSandTheme.show_panel(self, true)
	_search.grab_focus()

func close() -> void:
	KoalaSandTheme.hide_panel(self, func() -> void: closed.emit())


func show_search(query: String) -> void:
	_search.text = query
	refresh()

func refresh() -> void:
	if library == null: return
	for child in _entries.get_children(): child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var ids := library.library.keys(); ids.sort()
	for raw_id: Variant in ids:
		var blueprint := library.load_blueprint(str(raw_id))
		if blueprint == null: continue
		var example := str(raw_id).begins_with("basic_")
		var haystack := (blueprint.display_name + " " + blueprint.description).to_lower()
		if not query.is_empty() and not haystack.contains(query): continue
		var button := Button.new()
		button.text = "%s   %s\n%s\n%s\n%d Components · editable physical assembly" % ["EXAMPLE" if example else "PLAYER", blueprint.display_name, blueprint.description, _example_guidance(str(raw_id)), blueprint.entries.size()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func(): blueprint_selected.emit(blueprint))
		_entries.add_child(button)
	if _entries.get_child_count() == 0:
		var empty := Label.new(); empty.text = "No blueprints match this search. Clear the search, or copy Components in the world and save the current copy below."; empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; empty.theme_type_variation = "SecondaryLabel"; _entries.add_child(empty)


func _example_guidance(blueprint_id: String) -> String:
	if "screen" in blueprint_id: return "LOOK FOR · Mesh aperture · Vibration Actuator · material path"
	if "sluice" in blueprint_id or "wet" in blueprint_id: return "LOOK FOR · Water direction → · Riffles · concentrate zone · tailings path"
	if "furnace" in blueprint_id: return "LOOK FOR · fuel · air opening · heated chamber · Refractory walls"
	if "vessel" in blueprint_id or "boiler" in blueprint_id: return "LOOK FOR · container geometry · heat path · real Water"
	return "ORDINARY LAYOUT · no hidden machine behavior"
