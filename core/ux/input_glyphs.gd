class_name InputGlyphs
extends RefCounted

const DISPLAY_NAMES := {
	KEY_SPACE: "Space",
	KEY_SHIFT: "Shift",
	KEY_CTRL: "Ctrl",
	KEY_ALT: "Alt",
	KEY_ESCAPE: "Esc",
	KEY_ENTER: "Enter",
	KEY_DELETE: "Delete",
	KEY_PAGEUP: "Page Up",
	KEY_PAGEDOWN: "Page Down",
}


static func action(action_name: StringName) -> String:
	if not InputMap.has_action(action_name):
		return str(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			var label := str(DISPLAY_NAMES.get(code, OS.get_keycode_string(code)))
			if key.ctrl_pressed: label = "Ctrl + " + label
			if key.shift_pressed: label = "Shift + " + label
			if key.alt_pressed: label = "Alt + " + label
			return label
		if event is InputEventMouseButton:
			var mouse := event as InputEventMouseButton
			return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB"}.get(mouse.button_index, "Mouse %d" % mouse.button_index)
	return str(action_name)


static func hint(action_name: StringName, verb: String) -> String:
	return "%s  %s" % [action(action_name), verb]
