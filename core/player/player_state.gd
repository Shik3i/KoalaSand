class_name KoalaPlayerState
extends RefCounted

const SCHEMA_VERSION := 1

var world_identity: Dictionary = {}
var session_axes: Dictionary = {}
var character_state: Dictionary = {}
var discovery_state: Dictionary = {}
var visibility_owner_id := KoalaCharacterController.VISIBILITY_OWNER_ID


func capture(native_world: Variant, session: GameSession, controller: KoalaCharacterController) -> void:
	world_identity = native_world.get_world_identity().duplicate(true)
	session_axes = session.serialize().duplicate(true)
	character_state = controller.serialize_state().duplicate(true)
	discovery_state = native_world.serialize_visibility_state(visibility_owner_id).duplicate(true)


func restore(native_world: Variant, session: GameSession, controller: KoalaCharacterController) -> bool:
	if native_world.get_world_identity() != world_identity:
		return false
	if not session.deserialize(session_axes):
		return false
	if not controller.deserialize_state(character_state):
		return false
	return native_world.deserialize_visibility_state(discovery_state)


func serialize() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"world_identity": world_identity.duplicate(true),
		"session_axes": session_axes.duplicate(true),
		"character_state": character_state.duplicate(true),
		"discovery_state": discovery_state.duplicate(true),
		"visibility_owner_id": visibility_owner_id,
	}


func deserialize(state: Dictionary) -> bool:
	if int(state.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	if not (state.get("world_identity", null) is Dictionary) or not (state.get("session_axes", null) is Dictionary):
		return false
	if not (state.get("character_state", null) is Dictionary) or not (state.get("discovery_state", null) is Dictionary):
		return false
	world_identity = (state.world_identity as Dictionary).duplicate(true)
	session_axes = (state.session_axes as Dictionary).duplicate(true)
	character_state = (state.character_state as Dictionary).duplicate(true)
	discovery_state = (state.discovery_state as Dictionary).duplicate(true)
	visibility_owner_id = int(state.get("visibility_owner_id", KoalaCharacterController.VISIBILITY_OWNER_ID))
	return true
