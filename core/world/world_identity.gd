class_name WorldIdentity
extends RefCounted

const SCHEMA_VERSION := 1

var seed: int
var generation_version: int
var generator_settings_hash: String


static func from_native(world: Variant) -> WorldIdentity:
	var identity := WorldIdentity.new()
	var data: Dictionary = world.get_world_identity()
	identity.seed = int(data.seed)
	identity.generation_version = int(data.generation_version)
	identity.generator_settings_hash = str(data.generator_settings_hash)
	return identity


func serialize() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"generation_version": generation_version,
		"generator_settings_hash": generator_settings_hash,
	}


func stable_key() -> String:
	return "%d:v%d:%s" % [seed, generation_version, generator_settings_hash]
