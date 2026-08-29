class_name PowerContract
extends RefCounted

const SCHEMA_VERSION := 1
const MECHANICAL_TICK_HZ := 30
const ELECTRICAL_TICK_HZ := 30
const POWER_OVERLAY_PROVIDER_ID := 13

enum EnergyKind {
	THERMAL = 1,
	MECHANICAL = 2,
	ELECTRICAL = 3,
}

enum PortRole {
	PRODUCER = 1,
	CONSUMER = 2,
	STORAGE = 3,
	CONNECTION = 4,
}

enum ConsumerPriority {
	CRITICAL = 0,
	HIGH = 1,
	NORMAL = 2,
	LOW = 3,
}

enum FutureCommandId {
	SET_POWER_SWITCH = 21,
	SET_POWER_PRIORITY = 22,
	CONFIGURE_POWER_PORT = 23,
}

const RESEARCH_IDS := {
	"steam_power": "power.steam_generation",
	"electrical_distribution": "power.electrical_distribution",
	"storage": "power.energy_storage",
	"electrified_industry": "power.electrified_industry",
	"grid_control": "power.grid_control",
	"mechanical_storage": "power.mechanical_storage",
}

const STATISTIC_IDS := {
	"generated": "power.energy_generated",
	"consumed": "power.energy_consumed",
	"steam": "power.steam_consumed",
	"mechanical": "power.mechanical_generated",
	"storage_charge": "power.storage_charged",
	"storage_discharge": "power.storage_discharged",
}

const BLUEPRINT_FIELDS := {
	"port_role": "power_port_role",
	"priority": "power_consumer_priority",
	"switch_closed": "power_switch_closed",
}


static func port_metadata(role: int, rate_quanta_per_tick: int = 0, priority: int = ConsumerPriority.NORMAL) -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"role": int(role),
		"rate_quanta_per_tick": rate_quanta_per_tick,
		"priority": int(priority),
	}


static func architecture() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"authoritative_units": "signed int64 energy quanta and per-tick power rates",
		"mechanical_tick_hz": MECHANICAL_TICK_HZ,
		"electrical_tick_hz": ELECTRICAL_TICK_HZ,
		"topology": "cached connected components; union additions; localized split rebuild after removals",
		"allocation": "deterministic priority classes then proportional fixed-point satisfaction within each class",
		"automation_network_separate": true,
		"implemented_gameplay": true,
	}
