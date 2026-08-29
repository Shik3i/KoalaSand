class_name MaterialDefinition
extends Resource

enum Category {
	EMPTY,
	SOLID,
	GRANULAR,
	LIQUID,
	GAS,
	MOLTEN,
}

enum VisualFlag {
	SURFACE_EDGE = 1 << 0,
	DEPTH_TINT = 1 << 1,
	FINE_VARIATION = 1 << 2,
	EMISSIVE = 1 << 3,
}

@export_range(0, 2147483647, 1) var stable_id: int = 0
@export var key: StringName = &"empty"
@export var display_name: String = "Empty"
@export var category: Category = Category.EMPTY
@export_range(0.0, 100000.0, 0.1) var density_kg_m3: float = 0.0
@export_range(0, 65535, 1) var thermal_conductivity: int = 0
@export_range(1, 65535, 1) var specific_heat_units: int = 1
@export_range(0, 65535, 1) var freeze_threshold: int = 0
@export_range(0, 65535, 1) var boil_or_melt_threshold: int = 65535
@export var thermal_mass_uses_cell_mass: bool = false
@export var phase_family: StringName = &""
@export var freeze_to: StringName = &""
@export var melt_to: StringName = &""
@export var boil_to: StringName = &""
@export var condense_to: StringName = &""
@export_range(0, 65535, 1) var latent_heat_low: int = 0
@export_range(0, 65535, 1) var latent_heat_high: int = 0
@export_range(0, 255, 1) var mobility: int = 0
@export var pipe_compatible: bool = false
@export_range(0, 255, 1) var flammability: int = 0
@export_range(0, 65535, 1) var ignition_temperature: int = 65535
@export_range(0, 65535, 1) var pyrolysis_temperature: int = 65535
@export_range(0, 2147483647, 1) var combustion_heat: int = 0
@export_range(0, 255, 1) var moisture_capacity: int = 0
@export_range(0, 255, 1) var char_yield: int = 0
@export_range(0, 255, 1) var ash_yield: int = 0
@export_range(0, 255, 1) var smoke_yield: int = 0
@export_range(0, 255, 1) var burn_rate: int = 0
@export var debug_color: Color = Color.TRANSPARENT
@export var tags: Array[StringName] = []
@export var visual_palette := PackedColorArray()
@export var visual_surface_color: Color = Color.TRANSPARENT
@export var visual_shadow_color: Color = Color.TRANSPARENT
@export_flags("Surface edge", "Depth tint", "Fine variation", "Emissive") var visual_flags: int = 0
@export_range(1, 64, 1) var visual_noise_scale: int = 7
@export_range(0.0, 1.0, 0.01) var visual_depth_tint: float = 0.12
@export var visual_emission_color: Color = Color.TRANSPARENT
