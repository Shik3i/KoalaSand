#include "native_sand_world.hpp"
#include "physical_traits.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <exception>
#include <limits>
#include <stdexcept>

namespace godot {

namespace {
constexpr uint32_t MASK_31 = 0x7fffffffu;
constexpr int32_t EMPTY_ID = 0;
constexpr int32_t STONE_ID = 1;
constexpr int32_t SAND_ID = 2;
constexpr int32_t WATER_ID = 3;
constexpr int32_t COAL_ID = 4;
constexpr int32_t BEDROCK_ID = 5;
constexpr int32_t FINE_SAND_ID = 6;
constexpr int32_t HEAVY_CONCENTRATE_ID = 7;
constexpr int32_t IRON_CONCENTRATE_ID = 8;
constexpr int32_t NONMAGNETIC_CONCENTRATE_ID = 9;
constexpr int32_t GLASS_ID = 10;
constexpr int32_t IRON_ID = 11;
constexpr int32_t GOLD_ID = 12;
constexpr int32_t CRUDE_RESIDUE_ID = 13;
constexpr int32_t COAL_CHUNK_ID = 14;
constexpr int32_t ASH_ID = 15;
constexpr int32_t ICE_ID = 16;
constexpr int32_t STEAM_ID = 17;
constexpr int32_t MOLTEN_GLASS_ID = 18;
constexpr int32_t MOLTEN_IRON_ID = 19;
constexpr int32_t ROCK_DEBRIS_ID = 20;
constexpr int32_t WOOD_ID = 21;
constexpr int32_t LEAVES_ID = 22;
constexpr int32_t CHARCOAL_ID = 23;
constexpr int32_t SMOKE_ID = 24;
constexpr int32_t RAW_FOOD_ID = 25;
constexpr int32_t COOKED_FOOD_ID = 26;
constexpr int32_t BURNT_FOOD_ID = 27;
constexpr int32_t MAX_MATERIAL_ID = BURNT_FOOD_ID;
// A brush stroke is one gesture: wide enough for any editor brush, bounded so that a malformed
// command cannot ask the simulation to sweep the whole world.
constexpr int32_t MAX_BRUSH_RADIUS = 64;
constexpr int64_t MAX_STROKE_CELLS = 4'194'304;
constexpr int32_t UNGENERATED_ID = -1;
constexpr uint8_t STRUCTURE_NONE = 0;
constexpr uint8_t STRUCTURE_CONVEYOR_LEFT = 1;
constexpr uint8_t STRUCTURE_CONVEYOR_RIGHT = 2;
constexpr int32_t STRUCTURE_FURNACE = 5;
constexpr int32_t STRUCTURE_SIEVE = 6;
constexpr int32_t STRUCTURE_MAGNETIC_SEPARATOR = 7;
constexpr int32_t STRUCTURE_RESEARCH_BANK = 8;
constexpr int32_t STRUCTURE_CONTROL_GATE = 9;
constexpr int32_t STRUCTURE_PIPE = 10;
constexpr int32_t STRUCTURE_PIPE_JUNCTION = 11;
constexpr int32_t STRUCTURE_FLUID_INTAKE = 12;
constexpr int32_t STRUCTURE_FLUID_OUTLET = 13;
constexpr int32_t STRUCTURE_BASIC_PUMP = 14;
constexpr int32_t STRUCTURE_PIPE_VALVE = 15;
constexpr int32_t STRUCTURE_RESERVOIR_WALL = 16;
constexpr int32_t STRUCTURE_WASH_SLUICE = 17;
constexpr int32_t STRUCTURE_THERMAL_SWITCH = 24;
constexpr int32_t STRUCTURE_HEAT_EXCHANGER = 25;
constexpr int32_t STRUCTURE_SHAFT = 26;
constexpr int32_t STRUCTURE_TURBINE = 27;
constexpr int32_t STRUCTURE_GENERATOR = 28;
constexpr int32_t STRUCTURE_POWER_POLE = 29;
constexpr int32_t STRUCTURE_POWER_SWITCH = 30;
constexpr int32_t STRUCTURE_ACCUMULATOR = 31;
constexpr int32_t STRUCTURE_TRANSFORMER = 32;
constexpr int32_t STRUCTURE_FLYWHEEL = 33;
constexpr int32_t STRUCTURE_RESISTIVE_HEATER = 34;
constexpr int32_t STRUCTURE_IRON_POT = 35;
constexpr int32_t STRUCTURE_CERAMIC_TEST_VESSEL = 36;
constexpr int32_t STRUCTURE_MESH_SCREEN = 41;
constexpr int32_t STRUCTURE_RIFFLE = 43;
constexpr int32_t STRUCTURE_VIBRATION_ACTUATOR = 45;
constexpr int32_t STRUCTURE_ELECTROMAGNET = 46;
constexpr int32_t STRUCTURE_STRUCTURAL_WALL = 37;
constexpr int32_t STRUCTURE_METAL_PLATE = 38;
constexpr int32_t STRUCTURE_CERAMIC_WALL = 39;
constexpr int32_t STRUCTURE_REFRACTORY_WALL = 40;
constexpr int32_t STRUCTURE_GRATE = 42;
constexpr int32_t STRUCTURE_THERMAL_INSULATOR = 44;
constexpr int32_t STRUCTURE_BLOWER = 47;
constexpr uint8_t MOVED_FLAG = 1u;
constexpr uint8_t ORGANIC_LOOSE_FLAG = 1u << 3;
constexpr int32_t BASIC_CONVEYOR_TICKS_PER_CELL = 2;
constexpr int32_t PROCESS_SIEVE = 101;
constexpr int32_t PROCESS_SIEVE_PRECISION = 102;
constexpr int32_t PROCESS_MAGNETIC = 201;
constexpr int32_t PROCESS_FURNACE_RAW = 301;
constexpr int32_t PROCESS_FURNACE_RECOVERY = 401;
constexpr int32_t FURNACE_FUEL_UNITS = 64;

enum Constituent : int32_t { SILICA = 0, IRON_BEARING = 1, HEAVY_MINERAL = 2, GOLD_BEARING = 3, OTHER = 4 };
enum MachineState : int32_t { MACHINE_IDLE = 0, MACHINE_NO_INPUT = 1, MACHINE_NO_FUEL = 2, MACHINE_RUNNING = 3,
                              MACHINE_OUTPUT_BLOCKED = 4, MACHINE_ASH_BLOCKED = 5, MACHINE_ACCEPTING = 6,
                              MACHINE_REJECTING = 7, MACHINE_REJECT_BLOCKED = 8, MACHINE_INPUT_BLOCKED = 9 };

struct RgbaFloat {
    float r;
    float g;
    float b;
    float a;
};

constexpr std::array<RgbaFloat, 4> STONE_PALETTE{{
    {0.18f, 0.22f, 0.27f, 1.0f}, {0.21f, 0.25f, 0.30f, 1.0f},
    {0.15f, 0.19f, 0.23f, 1.0f}, {0.23f, 0.28f, 0.33f, 1.0f},
}};
constexpr std::array<RgbaFloat, 4> SAND_PALETTE{{
    {0.81f, 0.61f, 0.29f, 1.0f}, {0.77f, 0.57f, 0.26f, 1.0f},
    {0.85f, 0.66f, 0.33f, 1.0f}, {0.74f, 0.53f, 0.22f, 1.0f},
}};
constexpr std::array<RgbaFloat, 4> WATER_PALETTE{{
    {0.06f, 0.46f, 0.57f, 0.90f}, {0.08f, 0.55f, 0.67f, 0.90f},
    {0.04f, 0.39f, 0.50f, 0.90f}, {0.12f, 0.61f, 0.70f, 0.90f},
}};
constexpr std::array<RgbaFloat, 4> COAL_PALETTE{{
    {0.055f, 0.065f, 0.075f, 1.0f}, {0.075f, 0.085f, 0.095f, 1.0f},
    {0.040f, 0.047f, 0.055f, 1.0f}, {0.105f, 0.110f, 0.115f, 1.0f},
}};
constexpr std::array<RgbaFloat, 4> BEDROCK_PALETTE{{
    {0.095f, 0.075f, 0.105f, 1.0f}, {0.125f, 0.095f, 0.130f, 1.0f},
    {0.070f, 0.060f, 0.080f, 1.0f}, {0.150f, 0.115f, 0.145f, 1.0f},
}};
constexpr std::array<RgbaFloat, 4> FINE_SAND_PALETTE{{{0.91f,0.79f,0.52f,1},{0.86f,0.73f,0.45f,1},{0.95f,0.85f,0.61f,1},{0.82f,0.68f,0.39f,1}}};
constexpr std::array<RgbaFloat, 4> HEAVY_PALETTE{{{0.29f,0.27f,0.25f,1},{0.36f,0.31f,0.25f,1},{0.24f,0.25f,0.27f,1},{0.42f,0.35f,0.27f,1}}};
constexpr std::array<RgbaFloat, 4> IRON_CONC_PALETTE{{{0.20f,0.22f,0.23f,1},{0.28f,0.25f,0.23f,1},{0.15f,0.18f,0.20f,1},{0.35f,0.30f,0.25f,1}}};
constexpr std::array<RgbaFloat, 4> NONMAG_PALETTE{{{0.31f,0.25f,0.30f,1},{0.39f,0.31f,0.32f,1},{0.24f,0.21f,0.28f,1},{0.44f,0.35f,0.29f,1}}};
constexpr std::array<RgbaFloat, 4> GLASS_PALETTE{{{0.67f,0.84f,0.84f,1},{0.80f,0.91f,0.88f,1},{0.56f,0.73f,0.77f,1},{0.90f,0.96f,0.91f,1}}};
constexpr std::array<RgbaFloat, 4> IRON_PALETTE{{{0.25f,0.29f,0.31f,1},{0.38f,0.42f,0.43f,1},{0.18f,0.21f,0.23f,1},{0.48f,0.45f,0.39f,1}}};
constexpr std::array<RgbaFloat, 4> GOLD_PALETTE{{{0.92f,0.62f,0.12f,1},{1.0f,0.78f,0.24f,1},{0.76f,0.43f,0.07f,1},{1.0f,0.88f,0.43f,1}}};
constexpr std::array<RgbaFloat, 4> RESIDUE_PALETTE{{{0.19f,0.15f,0.14f,1},{0.25f,0.20f,0.18f,1},{0.14f,0.13f,0.14f,1},{0.31f,0.24f,0.19f,1}}};
constexpr std::array<RgbaFloat, 4> COAL_CHUNK_PALETTE{{{0.06f,0.07f,0.08f,1},{0.10f,0.11f,0.12f,1},{0.035f,0.04f,0.05f,1},{0.15f,0.15f,0.16f,1}}};
constexpr std::array<RgbaFloat, 4> ASH_PALETTE{{{0.48f,0.48f,0.47f,1},{0.58f,0.57f,0.54f,1},{0.38f,0.39f,0.40f,1},{0.66f,0.64f,0.60f,1}}};
constexpr std::array<RgbaFloat, 4> ICE_PALETTE{{{0.66f,0.88f,0.96f,1},{0.80f,0.95f,1.0f,1},{0.48f,0.74f,0.88f,1},{0.91f,0.98f,1.0f,1}}};
constexpr std::array<RgbaFloat, 4> STEAM_PALETTE{{{0.76f,0.82f,0.84f,0.22f},{0.90f,0.94f,0.95f,0.28f},{0.62f,0.69f,0.73f,0.18f},{1.0f,1.0f,1.0f,0.31f}}};
constexpr std::array<RgbaFloat, 4> MOLTEN_GLASS_PALETTE{{{1.0f,0.43f,0.06f,1},{1.0f,0.72f,0.14f,1},{0.86f,0.16f,0.025f,1},{1.0f,0.91f,0.38f,1}}};
constexpr std::array<RgbaFloat, 4> MOLTEN_IRON_PALETTE{{{1.0f,0.24f,0.015f,1},{1.0f,0.58f,0.05f,1},{0.72f,0.055f,0.01f,1},{1.0f,0.86f,0.27f,1}}};
constexpr std::array<RgbaFloat, 4> ROCK_DEBRIS_PALETTE{{{0.30f,0.34f,0.37f,1},{0.38f,0.41f,0.43f,1},{0.24f,0.28f,0.31f,1},{0.45f,0.43f,0.39f,1}}};
constexpr std::array<RgbaFloat, 4> WOOD_PALETTE{{{0.34f,0.17f,0.07f,1},{0.43f,0.23f,0.09f,1},{0.27f,0.12f,0.05f,1},{0.53f,0.31f,0.12f,1}}};
constexpr std::array<RgbaFloat, 4> LEAVES_PALETTE{{{0.12f,0.34f,0.10f,1},{0.19f,0.45f,0.13f,1},{0.08f,0.26f,0.07f,1},{0.31f,0.53f,0.17f,1}}};
constexpr std::array<RgbaFloat, 4> CHARCOAL_PALETTE{{{0.07f,0.06f,0.055f,1},{0.12f,0.10f,0.08f,1},{0.035f,0.03f,0.028f,1},{0.18f,0.13f,0.09f,1}}};
constexpr std::array<RgbaFloat, 4> SMOKE_PALETTE{{{0.22f,0.23f,0.24f,0.58f},{0.32f,0.33f,0.34f,0.52f},{0.14f,0.15f,0.16f,0.64f},{0.42f,0.40f,0.38f,0.46f}}};
constexpr std::array<RgbaFloat, 4> RAW_FOOD_PALETTE{{{0.53f,0.22f,0.43f,1},{0.68f,0.31f,0.51f,1},{0.39f,0.15f,0.34f,1},{0.78f,0.44f,0.60f,1}}};
constexpr std::array<RgbaFloat, 4> COOKED_FOOD_PALETTE{{{0.70f,0.43f,0.18f,1},{0.82f,0.56f,0.24f,1},{0.56f,0.31f,0.12f,1},{0.91f,0.68f,0.34f,1}}};
constexpr std::array<RgbaFloat, 4> BURNT_FOOD_PALETTE{{{0.12f,0.07f,0.045f,1},{0.18f,0.10f,0.055f,1},{0.07f,0.04f,0.03f,1},{0.26f,0.14f,0.07f,1}}};

RgbaFloat lerp_color(const RgbaFloat &from, const RgbaFloat &to, float amount) {
    return {
        from.r + (to.r - from.r) * amount,
        from.g + (to.g - from.g) * amount,
        from.b + (to.b - from.b) * amount,
        from.a + (to.a - from.a) * amount,
    };
}

uint8_t to_byte(float value) {
    return static_cast<uint8_t>(std::clamp(std::lround(value * 255.0f), 0l, 255l));
}
} // namespace

void NativeSandWorld::Bounds::clear() {
    min_x = CHUNK_SIZE;
    min_y = CHUNK_SIZE;
    max_x = -1;
    max_y = -1;
}

void NativeSandWorld::Bounds::include(int32_t x, int32_t y, int32_t radius) {
    min_x = static_cast<int16_t>(std::min<int32_t>(min_x, std::max(0, x - radius)));
    min_y = static_cast<int16_t>(std::min<int32_t>(min_y, std::max(0, y - radius)));
    max_x = static_cast<int16_t>(std::max<int32_t>(max_x, std::min(CHUNK_SIZE - 1, x + radius)));
    max_y = static_cast<int16_t>(std::max<int32_t>(max_y, std::min(CHUNK_SIZE - 1, y + radius)));
}

void NativeSandWorld::Bounds::merge(const Bounds &other) {
    if (!other.valid()) {
        return;
    }
    include(other.min_x, other.min_y);
    include(other.max_x, other.max_y);
}

NativeSandWorld::FluidActivity::FluidActivity() { clear(); }

void NativeSandWorld::FluidActivity::clear() {
    rows = 0;
    min_x.fill(CHUNK_SIZE);
    max_x.fill(0);
}

void NativeSandWorld::FluidActivity::include(int32_t x, int32_t y, int32_t radius) {
    const int32_t first_y = std::max(0, y - radius);
    const int32_t last_y = std::min(CHUNK_SIZE - 1, y + radius);
    const uint8_t first_x = static_cast<uint8_t>(std::max(0, x - radius));
    const uint8_t last_x = static_cast<uint8_t>(std::min(CHUNK_SIZE - 1, x + radius));
    for (int32_t row = first_y; row <= last_y; ++row) {
        const uint64_t bit = uint64_t{1} << row;
        if ((rows & bit) == 0) { min_x[row] = first_x; max_x[row] = last_x; rows |= bit; }
        else { min_x[row] = std::min(min_x[row], first_x); max_x[row] = std::max(max_x[row], last_x); }
    }
}

void NativeSandWorld::FluidActivity::merge(const FluidActivity &other) {
    for (int32_t row = 0; row < CHUNK_SIZE; ++row) {
        if ((other.rows & (uint64_t{1} << row)) == 0) continue;
        include(other.min_x[row], row);
        include(other.max_x[row], row);
    }
}

int32_t NativeSandWorld::FluidActivity::area() const {
    int32_t total = 0;
    for (int32_t row = 0; row < CHUNK_SIZE; ++row) if ((rows & (uint64_t{1} << row)) != 0) total += max_x[row] - min_x[row] + 1;
    return total;
}

NativeSandWorld::Chunk::Chunk(Vector2i chunk_coordinate) : coordinate(chunk_coordinate) {
    temperature.fill(TEMPERATURE_AMBIENT);
    render_dirty.include(0, 0);
    render_dirty.include(CHUNK_SIZE - 1, CHUNK_SIZE - 1);
}

NativeSandWorld::NativeSandWorld() = default;

NativeSandWorld::~NativeSandWorld() {
    stop_generation_workers();
    stop_workers();
}

void NativeSandWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset", "world_seed", "requested_workers"), &NativeSandWorld::reset, DEFVAL(1), DEFVAL(1));
    ClassDB::bind_method(D_METHOD("set_cell", "world_cell", "material_id"), &NativeSandWorld::set_cell);
    ClassDB::bind_method(D_METHOD("set_cell_with_provenance", "world_cell", "material_id", "profile_id"), &NativeSandWorld::set_cell_with_provenance);
    ClassDB::bind_method(D_METHOD("set_cell_with_metadata", "world_cell", "material_id", "profile_id", "mineral_signature"), &NativeSandWorld::set_cell_with_metadata);
    ClassDB::bind_method(D_METHOD("initialize_cell", "world_cell", "material_id"), &NativeSandWorld::initialize_cell);
    ClassDB::bind_method(D_METHOD("get_cell", "world_cell"), &NativeSandWorld::get_cell);
    ClassDB::bind_method(D_METHOD("get_provenance", "world_cell"), &NativeSandWorld::get_provenance);
    ClassDB::bind_method(D_METHOD("get_mineral_signature", "world_cell"), &NativeSandWorld::get_mineral_signature);
    ClassDB::bind_method(D_METHOD("harvest_cell", "world_cell"), &NativeSandWorld::harvest_cell);
    ClassDB::bind_method(D_METHOD("paint_stroke", "from_cell", "to_cell", "radius", "material_id"), &NativeSandWorld::paint_stroke);
    ClassDB::bind_method(D_METHOD("harvest_stroke", "from_cell", "to_cell", "radius"), &NativeSandWorld::harvest_stroke);
    ClassDB::bind_method(D_METHOD("get_hidden_constituent", "profile_id", "mineral_signature"), &NativeSandWorld::get_hidden_constituent);
    ClassDB::bind_method(D_METHOD("process_material_for_test", "material_id", "profile_id", "mineral_signature", "process_id"), &NativeSandWorld::process_material_for_test);
    ClassDB::bind_method(D_METHOD("split_composition_for_test", "material_id", "profile_id", "mineral_signature", "route"), &NativeSandWorld::split_composition_for_test);
    ClassDB::bind_method(D_METHOD("fill_rect", "area", "material_id", "spacing"), &NativeSandWorld::fill_rect, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("allocate_chunk_rect", "chunk_area"), &NativeSandWorld::allocate_chunk_rect);
    ClassDB::bind_method(D_METHOD("finalize_initialization"), &NativeSandWorld::finalize_initialization);
    ClassDB::bind_method(D_METHOD("get_tick"), &NativeSandWorld::get_tick);
    ClassDB::bind_method(D_METHOD("get_frame_counters"), &NativeSandWorld::get_frame_counters);
    ClassDB::bind_method(D_METHOD("step"), &NativeSandWorld::step);
    ClassDB::bind_method(D_METHOD("inject_step_fault_for_test"), &NativeSandWorld::inject_step_fault_for_test);
    ClassDB::bind_method(D_METHOD("is_faulted"), &NativeSandWorld::is_faulted);
    ClassDB::bind_method(D_METHOD("get_fault_message"), &NativeSandWorld::get_fault_message);
    ClassDB::bind_method(D_METHOD("chunk_count"), &NativeSandWorld::chunk_count);
    ClassDB::bind_method(D_METHOD("active_chunk_count"), &NativeSandWorld::active_chunk_count);
    ClassDB::bind_method(D_METHOD("sleeping_chunk_count"), &NativeSandWorld::sleeping_chunk_count);
    ClassDB::bind_method(D_METHOD("total_allocated_cells"), &NativeSandWorld::total_allocated_cells);
    ClassDB::bind_method(D_METHOD("simulation_backing_bytes"), &NativeSandWorld::simulation_backing_bytes);
    ClassDB::bind_method(D_METHOD("presentation_backing_bytes"), &NativeSandWorld::presentation_backing_bytes);
    ClassDB::bind_method(D_METHOD("get_worker_count"), &NativeSandWorld::get_worker_count);
    ClassDB::bind_method(D_METHOD("get_chunk_coordinates"), &NativeSandWorld::get_chunk_coordinates);
    ClassDB::bind_method(D_METHOD("get_chunk_state", "coordinate"), &NativeSandWorld::get_chunk_state);
    ClassDB::bind_method(D_METHOD("get_statistics"), &NativeSandWorld::get_statistics);
    ClassDB::bind_method(D_METHOD("consume_dirty_render_chunks"), &NativeSandWorld::consume_dirty_render_chunks);
    ClassDB::bind_method(D_METHOD("consume_dirty_render_page", "chunk_area", "force"),
                         &NativeSandWorld::consume_dirty_render_page, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("get_non_empty_cells"), &NativeSandWorld::get_non_empty_cells);
    ClassDB::bind_method(D_METHOD("material_state_hash"), &NativeSandWorld::material_state_hash);
    ClassDB::bind_method(D_METHOD("material_and_provenance_hash"), &NativeSandWorld::material_and_provenance_hash);
    ClassDB::bind_method(D_METHOD("configure_world", "settings", "generation_workers"), &NativeSandWorld::configure_world, DEFVAL(2));
    ClassDB::bind_method(D_METHOD("get_world_settings"), &NativeSandWorld::get_world_settings);
    ClassDB::bind_method(D_METHOD("request_chunk", "coordinate", "priority"), &NativeSandWorld::request_chunk, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("request_chunk_region", "chunk_area", "priority"), &NativeSandWorld::request_chunk_region, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("pump_generation", "max_publish"), &NativeSandWorld::pump_generation, DEFVAL(4));
    ClassDB::bind_method(D_METHOD("flush_generation"), &NativeSandWorld::flush_generation);
    ClassDB::bind_method(D_METHOD("is_chunk_generated", "coordinate"), &NativeSandWorld::is_chunk_generated);
    ClassDB::bind_method(D_METHOD("get_generation_state", "coordinate"), &NativeSandWorld::get_generation_state);
    ClassDB::bind_method(D_METHOD("evict_pristine_outside", "keep_chunk_area", "max_evict"), &NativeSandWorld::evict_pristine_outside, DEFVAL(16));
    ClassDB::bind_method(D_METHOD("consume_evicted_chunks"), &NativeSandWorld::consume_evicted_chunks);
    ClassDB::bind_method(D_METHOD("get_generation_statistics"), &NativeSandWorld::get_generation_statistics);
    ClassDB::bind_method(D_METHOD("get_world_identity"), &NativeSandWorld::get_world_identity);
    ClassDB::bind_method(D_METHOD("get_generator_settings_hash"), &NativeSandWorld::get_generator_settings_hash);
    ClassDB::bind_method(D_METHOD("get_worldgen_v2_architecture"), &NativeSandWorld::get_worldgen_v2_architecture);
    ClassDB::bind_method(D_METHOD("get_macro_sample", "macro_coordinate"), &NativeSandWorld::get_macro_sample);
    ClassDB::bind_method(D_METHOD("get_macro_preview", "width", "height"), &NativeSandWorld::get_macro_preview, DEFVAL(160), DEFVAL(90));
    ClassDB::bind_method(D_METHOD("get_world_feature_templates"), &NativeSandWorld::get_world_feature_templates);
    ClassDB::bind_method(D_METHOD("get_world_feature_anchors", "macro_area"), &NativeSandWorld::get_world_feature_anchors);
    ClassDB::bind_method(D_METHOD("validate_world_seed", "seed"), &NativeSandWorld::validate_world_seed);
    ClassDB::bind_method(D_METHOD("validate_world_seeds", "first_seed", "count"), &NativeSandWorld::validate_world_seeds);
    ClassDB::bind_method(D_METHOD("get_worldgen_pass_hashes", "chunk_area"), &NativeSandWorld::get_worldgen_pass_hashes);
    ClassDB::bind_method(D_METHOD("get_worldgen_debug_sample", "cell_area", "stride"), &NativeSandWorld::get_worldgen_debug_sample, DEFVAL(8));
    ClassDB::bind_method(D_METHOD("get_generation_stability_report", "chunk_area"), &NativeSandWorld::get_generation_stability_report);
    ClassDB::bind_method(D_METHOD("get_worldgen_quality_report", "chunk_area"), &NativeSandWorld::get_worldgen_quality_report);
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_architecture"), &NativeSandWorld::get_worldgen_v5_architecture);
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_profiles"), &NativeSandWorld::get_worldgen_v5_profiles);
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_columns", "first_x", "count", "stride"),
                         &NativeSandWorld::get_worldgen_v5_columns, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_cell", "world_cell"), &NativeSandWorld::get_worldgen_v5_cell);
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_statistics", "first_seed", "count"),
                         &NativeSandWorld::get_worldgen_v5_statistics);
    ClassDB::bind_method(D_METHOD("get_worldgen_v5_start_report"), &NativeSandWorld::get_worldgen_v5_start_report);
    ClassDB::bind_method(D_METHOD("get_world_preview_summary"), &NativeSandWorld::get_world_preview_summary);
    ClassDB::bind_method(D_METHOD("get_worldgen_debug_chunk_view", "chunk_coordinate", "world_cell"), &NativeSandWorld::get_worldgen_debug_chunk_view);
    ClassDB::bind_method(D_METHOD("get_cave_topology_report", "chunk_area"), &NativeSandWorld::get_cave_topology_report);
    ClassDB::bind_method(D_METHOD("get_worldgen_debug_field", "cell_area", "field_id", "stride"),
                         &NativeSandWorld::get_worldgen_debug_field, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("get_structure_candidates", "cell_area", "structure_type"),
                         &NativeSandWorld::get_structure_candidates);
    ClassDB::bind_method(D_METHOD("get_natural_scene_candidates", "cell_area"),
                         &NativeSandWorld::get_natural_scene_candidates);
    ClassDB::bind_method(D_METHOD("get_character_spawn"), &NativeSandWorld::get_character_spawn);
    ClassDB::bind_method(D_METHOD("query_character_collision", "body"), &NativeSandWorld::query_character_collision);
    ClassDB::bind_method(D_METHOD("character_dig_cell", "world_cell"), &NativeSandWorld::character_dig_cell);
    ClassDB::bind_method(D_METHOD("update_character_visibility", "owner_id", "origin", "radius", "solid_shell_depth"), &NativeSandWorld::update_character_visibility, DEFVAL(72), DEFVAL(8));
    ClassDB::bind_method(D_METHOD("is_cell_discovered", "owner_id", "world_cell"), &NativeSandWorld::is_cell_discovered);
    ClassDB::bind_method(D_METHOD("is_cell_live_visible", "owner_id", "world_cell"), &NativeSandWorld::is_cell_live_visible);
    ClassDB::bind_method(D_METHOD("get_visibility_render_page", "owner_id", "chunk_area"), &NativeSandWorld::get_visibility_render_page);
    ClassDB::bind_method(D_METHOD("get_visibility_statistics", "owner_id"), &NativeSandWorld::get_visibility_statistics);
    ClassDB::bind_method(D_METHOD("clear_visibility", "owner_id"), &NativeSandWorld::clear_visibility, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("serialize_visibility_state", "owner_id"), &NativeSandWorld::serialize_visibility_state);
    ClassDB::bind_method(D_METHOD("deserialize_visibility_state", "state"), &NativeSandWorld::deserialize_visibility_state);
    ClassDB::bind_method(D_METHOD("visibility_state_hash", "owner_id"), &NativeSandWorld::visibility_state_hash);
    ClassDB::bind_method(D_METHOD("geology_profile_id_at", "world_cell"), &NativeSandWorld::geology_profile_id_at);
    ClassDB::bind_method(D_METHOD("get_geology_profile", "profile_id"), &NativeSandWorld::get_geology_profile);
    ClassDB::bind_method(D_METHOD("get_geology_profile_at", "world_cell"), &NativeSandWorld::get_geology_profile_at);
    ClassDB::bind_method(D_METHOD("get_chunk_content_hash", "coordinate"), &NativeSandWorld::get_chunk_content_hash);
    ClassDB::bind_method(D_METHOD("get_region_content_hash", "chunk_area"), &NativeSandWorld::get_region_content_hash);
    ClassDB::bind_method(D_METHOD("get_organic_material_definitions"), &NativeSandWorld::get_organic_material_definitions);
    ClassDB::bind_method(D_METHOD("get_fuel_definitions"), &NativeSandWorld::get_fuel_definitions);
    ClassDB::bind_method(D_METHOD("get_organic_architecture"), &NativeSandWorld::get_organic_architecture);
    ClassDB::bind_method(D_METHOD("get_organic_state", "world_cell"), &NativeSandWorld::get_organic_state);
    ClassDB::bind_method(D_METHOD("set_organic_moisture", "world_cell", "moisture"), &NativeSandWorld::set_organic_moisture);
    ClassDB::bind_method(D_METHOD("get_organic_moisture", "world_cell"), &NativeSandWorld::get_organic_moisture);
    ClassDB::bind_method(D_METHOD("bind_water_to_sediment", "sediment_cell", "water_cell", "requested_amount"), &NativeSandWorld::bind_water_to_sediment);
    ClassDB::bind_method(D_METHOD("get_bound_water_mass"), &NativeSandWorld::get_bound_water_mass);
    ClassDB::bind_method(D_METHOD("get_oxidizer", "world_cell"), &NativeSandWorld::get_oxidizer);
    ClassDB::bind_method(D_METHOD("character_cut_cell", "world_cell"), &NativeSandWorld::character_cut_cell);
    ClassDB::bind_method(D_METHOD("clear_vegetation_rect", "area"), &NativeSandWorld::clear_vegetation_rect);
    ClassDB::bind_method(D_METHOD("ignite_cell", "world_cell", "energy"), &NativeSandWorld::ignite_cell, DEFVAL(180000));
    ClassDB::bind_method(D_METHOD("get_visible_fellable_clusters", "cell_area"), &NativeSandWorld::get_visible_fellable_clusters);
    ClassDB::bind_method(D_METHOD("get_visible_organic_effects", "cell_area"), &NativeSandWorld::get_visible_organic_effects);
    ClassDB::bind_method(D_METHOD("get_organic_statistics"), &NativeSandWorld::get_organic_statistics);
    ClassDB::bind_method(D_METHOD("organic_state_hash"), &NativeSandWorld::organic_state_hash);
    ClassDB::bind_method(D_METHOD("configure_phase12_benchmark", "scenario", "count"), &NativeSandWorld::configure_phase12_benchmark);
    ClassDB::bind_method(D_METHOD("get_thermal_vessel_definition", "type_id"), &NativeSandWorld::get_thermal_vessel_definition);
    ClassDB::bind_method(D_METHOD("get_conservation_architecture"), &NativeSandWorld::get_conservation_architecture);
    ClassDB::bind_method(D_METHOD("derive_material_composition", "profile_id", "mineral_signature"), &NativeSandWorld::derive_material_composition);
    ClassDB::bind_method(D_METHOD("run_fractionation_fixture", "numerator", "denominator", "input_count", "route"), &NativeSandWorld::run_fractionation_fixture, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("run_variable_composition_fixture", "gold_numerators", "denominator", "route"), &NativeSandWorld::run_variable_composition_fixture, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("run_global_mass_fixture", "input_count", "profile_id", "mineral_signature"), &NativeSandWorld::run_global_mass_fixture);
    ClassDB::bind_method(D_METHOD("accumulate_fraction_for_test", "ledger_id", "numerator", "denominator", "route", "output_available"), &NativeSandWorld::accumulate_fraction_for_test, DEFVAL(0), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("get_fractional_ledger", "ledger_id"), &NativeSandWorld::get_fractional_ledger);
    ClassDB::bind_method(D_METHOD("get_component_classification"), &NativeSandWorld::get_component_classification);
    ClassDB::bind_method(D_METHOD("get_structure_physical_properties", "type_id"), &NativeSandWorld::get_structure_physical_properties);
    ClassDB::bind_method(D_METHOD("serialize_world_snapshot"), &NativeSandWorld::serialize_world_snapshot);
    ClassDB::bind_method(D_METHOD("deserialize_world_snapshot", "state"), &NativeSandWorld::deserialize_world_snapshot);
    ClassDB::bind_method(D_METHOD("phase13_state_hash"), &NativeSandWorld::phase13_state_hash);
    ClassDB::bind_method(D_METHOD("get_milestone_state"), &NativeSandWorld::get_milestone_state);
    ClassDB::bind_method(D_METHOD("evaluate_mvp_playthrough", "minutes", "profile_id"), &NativeSandWorld::evaluate_mvp_playthrough, DEFVAL(4590));
    ClassDB::bind_method(D_METHOD("get_structure_definitions"), &NativeSandWorld::get_structure_definitions);
    ClassDB::bind_method(D_METHOD("get_memory_layout"), &NativeSandWorld::get_memory_layout);
    ClassDB::bind_method(D_METHOD("can_place_structure", "type_id", "origin", "orientation"), &NativeSandWorld::can_place_structure, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("place_structure", "type_id", "origin", "orientation"), &NativeSandWorld::place_structure, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("apply_structure_batch", "operations", "validation_mode"), &NativeSandWorld::apply_structure_batch, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("is_subsurface_unlocked", "depth"), &NativeSandWorld::subsurface_unlocked);
    ClassDB::bind_method(D_METHOD("can_place_subsurface_channel", "depth", "entrance", "exit"), &NativeSandWorld::can_place_subsurface_channel);
    ClassDB::bind_method(D_METHOD("place_subsurface_channel", "depth", "entrance", "exit"), &NativeSandWorld::place_subsurface_channel);
    ClassDB::bind_method(D_METHOD("remove_subsurface_channel", "channel_id", "removal_policy"), &NativeSandWorld::remove_subsurface_channel, DEFVAL(1));
    ClassDB::bind_method(D_METHOD("get_subsurface_channel_state", "channel_id"), &NativeSandWorld::get_subsurface_channel_state);
    ClassDB::bind_method(D_METHOD("get_visible_subsurface_routes", "cell_area"), &NativeSandWorld::get_visible_subsurface_routes);
    ClassDB::bind_method(D_METHOD("get_subsurface_statistics"), &NativeSandWorld::get_subsurface_statistics);
    ClassDB::bind_method(D_METHOD("get_factory_foundation_architecture"), &NativeSandWorld::get_factory_foundation_architecture);
    ClassDB::bind_method(D_METHOD("get_production_statistics"), &NativeSandWorld::get_production_statistics);
    ClassDB::bind_method(D_METHOD("benchmark_production_events", "event_count"), &NativeSandWorld::benchmark_production_events, DEFVAL(1000000));
    ClassDB::bind_method(D_METHOD("record_production_event_for_test", "material_id", "amount", "produced"), &NativeSandWorld::record_production_event_for_test);
    ClassDB::bind_method(D_METHOD("serialize_subsurface_state"), &NativeSandWorld::serialize_subsurface_state);
    ClassDB::bind_method(D_METHOD("deserialize_subsurface_state", "state"), &NativeSandWorld::deserialize_subsurface_state);
    ClassDB::bind_method(D_METHOD("subsurface_state_hash"), &NativeSandWorld::subsurface_state_hash);
    ClassDB::bind_method(D_METHOD("seed_subsurface_packet_for_test", "channel_id", "lane_index", "material_id", "temperature", "provenance", "signature"),
                         &NativeSandWorld::seed_subsurface_packet_for_test, DEFVAL(TEMPERATURE_AMBIENT), DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("can_place_conveyor_line", "from", "to", "direction"), &NativeSandWorld::can_place_conveyor_line);
    ClassDB::bind_method(D_METHOD("place_conveyor_line", "from", "to", "direction"), &NativeSandWorld::place_conveyor_line);
    ClassDB::bind_method(D_METHOD("place_pipe_line", "from", "to"), &NativeSandWorld::place_pipe_line);
    ClassDB::bind_method(D_METHOD("remove_structure_at", "world_cell"), &NativeSandWorld::remove_structure_at);
    ClassDB::bind_method(D_METHOD("remove_structures_rect", "area"), &NativeSandWorld::remove_structures_rect);
    ClassDB::bind_method(D_METHOD("get_structure", "world_cell"), &NativeSandWorld::get_structure);
    ClassDB::bind_method(D_METHOD("get_visible_structure_cells", "chunk_area"), &NativeSandWorld::get_visible_structure_cells);
    ClassDB::bind_method(D_METHOD("get_visible_machine_entities", "chunk_area"), &NativeSandWorld::get_visible_machine_entities);
    ClassDB::bind_method(D_METHOD("consume_dirty_structure_chunks"), &NativeSandWorld::consume_dirty_structure_chunks);
    ClassDB::bind_method(D_METHOD("get_structure_statistics"), &NativeSandWorld::get_structure_statistics);
    ClassDB::bind_method(D_METHOD("get_processing_statistics"), &NativeSandWorld::get_processing_statistics);
    ClassDB::bind_method(D_METHOD("get_physical_processing_statistics"), &NativeSandWorld::get_physical_processing_statistics);
    ClassDB::bind_method(D_METHOD("get_magnetic_field_sample", "cell_area", "stride"), &NativeSandWorld::get_magnetic_field_sample, DEFVAL(2));
    ClassDB::bind_method(D_METHOD("get_grain_size_class", "world_cell"), &NativeSandWorld::get_grain_size_class);
    ClassDB::bind_method(D_METHOD("get_magnetic_susceptibility", "world_cell"), &NativeSandWorld::get_magnetic_susceptibility);
    ClassDB::bind_method(D_METHOD("get_temperature", "world_cell"), &NativeSandWorld::get_temperature);
    ClassDB::bind_method(D_METHOD("set_material_state", "world_cell", "material_id", "amount", "temperature", "provenance", "mineral_signature"), &NativeSandWorld::set_material_state,
                         DEFVAL(255), DEFVAL(TEMPERATURE_AMBIENT), DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("fill_rect_state", "area", "material_id", "amount", "temperature"), &NativeSandWorld::fill_rect_state,
                         DEFVAL(255), DEFVAL(TEMPERATURE_AMBIENT));
    ClassDB::bind_method(D_METHOD("fill_pattern_state", "area", "material_id", "amount_a", "amount_b", "temperature_a", "temperature_b"),
                         &NativeSandWorld::fill_pattern_state);
    ClassDB::bind_method(D_METHOD("get_material_amount", "world_cell"), &NativeSandWorld::get_material_amount);
    ClassDB::bind_method(D_METHOD("get_phase_energy", "world_cell"), &NativeSandWorld::get_phase_energy);
    ClassDB::bind_method(D_METHOD("get_total_phase_family_mass", "family_id"), &NativeSandWorld::get_total_phase_family_mass);
    ClassDB::bind_method(D_METHOD("get_total_thermal_enthalpy"), &NativeSandWorld::get_total_thermal_enthalpy);
    ClassDB::bind_method(D_METHOD("get_material_thermal_definition", "material_id"), &NativeSandWorld::get_material_thermal_definition);
    ClassDB::bind_method(D_METHOD("get_thermal_statistics"), &NativeSandWorld::get_thermal_statistics);
    ClassDB::bind_method(D_METHOD("get_gas_statistics"), &NativeSandWorld::get_gas_statistics);
    ClassDB::bind_method(D_METHOD("get_phase9_architecture"), &NativeSandWorld::get_phase9_architecture);
    ClassDB::bind_method(D_METHOD("set_thermal_switch_open", "world_cell", "open"), &NativeSandWorld::set_thermal_switch_open);
    ClassDB::bind_method(D_METHOD("physical_processing_hash"), &NativeSandWorld::physical_processing_hash);
    ClassDB::bind_method(D_METHOD("get_machine_state_at", "world_cell"), &NativeSandWorld::get_machine_state_at);
    ClassDB::bind_method(D_METHOD("evaluate_processing_routes", "profile_id", "sample_count"), &NativeSandWorld::evaluate_processing_routes, DEFVAL(100000));
    ClassDB::bind_method(D_METHOD("logistics_state_hash"), &NativeSandWorld::logistics_state_hash);
    ClassDB::bind_method(D_METHOD("processing_state_hash"), &NativeSandWorld::processing_state_hash);
    ClassDB::bind_method(D_METHOD("set_game_mode", "mode"), &NativeSandWorld::set_game_mode);
    ClassDB::bind_method(D_METHOD("get_game_mode"), &NativeSandWorld::get_game_mode);
    ClassDB::bind_method(D_METHOD("initialize_progression"), &NativeSandWorld::initialize_progression);
    ClassDB::bind_method(D_METHOD("get_research_definitions"), &NativeSandWorld::get_research_definitions);
    ClassDB::bind_method(D_METHOD("get_progression_state"), &NativeSandWorld::get_progression_state);
    ClassDB::bind_method(D_METHOD("get_research_state", "research_id"), &NativeSandWorld::get_research_state);
    ClassDB::bind_method(D_METHOD("try_unlock_research", "research_id"), &NativeSandWorld::try_unlock_research);
    ClassDB::bind_method(D_METHOD("is_structure_unlocked", "type_id"), &NativeSandWorld::is_structure_unlocked);
    ClassDB::bind_method(D_METHOD("serialize_progression_state"), &NativeSandWorld::serialize_progression_state);
    ClassDB::bind_method(D_METHOD("deserialize_progression_state", "state"), &NativeSandWorld::deserialize_progression_state);
    ClassDB::bind_method(D_METHOD("credit_research_material_for_test", "material_id", "amount"), &NativeSandWorld::credit_research_material_for_test);
    ClassDB::bind_method(D_METHOD("get_bank_statistics"), &NativeSandWorld::get_bank_statistics);
    ClassDB::bind_method(D_METHOD("evaluate_progression_pacing", "profile_id", "sample_limit"), &NativeSandWorld::evaluate_progression_pacing, DEFVAL(200000));
    ClassDB::bind_method(D_METHOD("get_automation_definitions"), &NativeSandWorld::get_automation_definitions);
    ClassDB::bind_method(D_METHOD("create_automation_component", "type_id", "position", "configuration"), &NativeSandWorld::create_automation_component, DEFVAL(Dictionary()));
    ClassDB::bind_method(D_METHOD("remove_automation_component", "component_id"), &NativeSandWorld::remove_automation_component);
    ClassDB::bind_method(D_METHOD("configure_automation_component", "component_id", "configuration"), &NativeSandWorld::configure_automation_component);
    ClassDB::bind_method(D_METHOD("set_manual_switch", "component_id", "enabled"), &NativeSandWorld::set_manual_switch);
    ClassDB::bind_method(D_METHOD("create_automation_connection", "source_component", "source_port", "target_component", "target_port"), &NativeSandWorld::create_automation_connection);
    ClassDB::bind_method(D_METHOD("remove_automation_connection", "connection_id"), &NativeSandWorld::remove_automation_connection);
    ClassDB::bind_method(D_METHOD("remove_component_connections", "component_id"), &NativeSandWorld::remove_component_connections);
    ClassDB::bind_method(D_METHOD("get_automation_component_ports", "component_id"), &NativeSandWorld::get_automation_component_ports);
    ClassDB::bind_method(D_METHOD("get_automation_component_state", "component_id"), &NativeSandWorld::get_automation_component_state);
    ClassDB::bind_method(D_METHOD("get_automation_subgraph", "component_id", "max_components"), &NativeSandWorld::get_automation_subgraph, DEFVAL(256));
    ClassDB::bind_method(D_METHOD("get_visible_automation_components", "cell_area"), &NativeSandWorld::get_visible_automation_components);
    ClassDB::bind_method(D_METHOD("get_visible_automation_connections", "cell_area"), &NativeSandWorld::get_visible_automation_connections);
    ClassDB::bind_method(D_METHOD("get_automation_statistics"), &NativeSandWorld::get_automation_statistics);
    ClassDB::bind_method(D_METHOD("serialize_automation_state"), &NativeSandWorld::serialize_automation_state);
    ClassDB::bind_method(D_METHOD("deserialize_automation_state", "state"), &NativeSandWorld::deserialize_automation_state);
    ClassDB::bind_method(D_METHOD("automation_state_hash"), &NativeSandWorld::automation_state_hash);
    ClassDB::bind_method(D_METHOD("set_automation_input_for_test", "component_id", "port", "value"), &NativeSandWorld::set_automation_input_for_test);
    ClassDB::bind_method(D_METHOD("set_water_mass", "world_cell", "mass", "temperature"), &NativeSandWorld::set_water_mass, DEFVAL(TEMPERATURE_AMBIENT));
    ClassDB::bind_method(D_METHOD("get_liquid_mass", "world_cell"), &NativeSandWorld::get_liquid_mass);
    ClassDB::bind_method(D_METHOD("set_pipe_mass", "world_cell", "mass", "temperature"), &NativeSandWorld::set_pipe_mass, DEFVAL(TEMPERATURE_AMBIENT));
    ClassDB::bind_method(D_METHOD("set_pipe_fluid", "world_cell", "fluid_type", "mass", "temperature"), &NativeSandWorld::set_pipe_fluid, DEFVAL(TEMPERATURE_AMBIENT));
    ClassDB::bind_method(D_METHOD("get_pipe_state", "world_cell"), &NativeSandWorld::get_pipe_state);
    ClassDB::bind_method(D_METHOD("get_pipe_statistics"), &NativeSandWorld::get_pipe_statistics);
    ClassDB::bind_method(D_METHOD("get_visible_pipe_segments", "chunk_area"), &NativeSandWorld::get_visible_pipe_segments);
    ClassDB::bind_method(D_METHOD("get_infrastructure_render_page", "chunk_coordinate"), &NativeSandWorld::get_infrastructure_render_page);
    ClassDB::bind_method(D_METHOD("get_total_pipe_water_mass"), &NativeSandWorld::get_total_pipe_water_mass);
    ClassDB::bind_method(D_METHOD("get_total_conserved_water_mass"), &NativeSandWorld::get_total_conserved_water_mass);
    ClassDB::bind_method(D_METHOD("get_total_pipe_water_phase_mass"), &NativeSandWorld::get_total_pipe_water_phase_mass);
    ClassDB::bind_method(D_METHOD("get_total_conserved_water_phase_mass"), &NativeSandWorld::get_total_conserved_water_phase_mass);
    ClassDB::bind_method(D_METHOD("set_pipe_device_enabled", "world_cell", "enabled"), &NativeSandWorld::set_pipe_device_enabled);
    ClassDB::bind_method(D_METHOD("set_pipe_valve_open", "world_cell", "open"), &NativeSandWorld::set_pipe_valve_open);
    ClassDB::bind_method(D_METHOD("damage_pipe", "world_cell", "damage", "cause"), &NativeSandWorld::damage_pipe, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("pipe_state_hash"), &NativeSandWorld::pipe_state_hash);
    ClassDB::bind_method(D_METHOD("get_wet_processing_statistics"), &NativeSandWorld::get_wet_processing_statistics);
    ClassDB::bind_method(D_METHOD("get_total_water_mass"), &NativeSandWorld::get_total_water_mass);
    ClassDB::bind_method(D_METHOD("get_fluid_statistics"), &NativeSandWorld::get_fluid_statistics);
    ClassDB::bind_method(D_METHOD("get_fluid_render_page", "chunk_area"), &NativeSandWorld::get_fluid_render_page);
    ClassDB::bind_method(D_METHOD("get_temperature_sample", "cell_area", "stride"), &NativeSandWorld::get_temperature_sample, DEFVAL(4));
    ClassDB::bind_method(D_METHOD("get_temperature_render_page", "chunk_area"), &NativeSandWorld::get_temperature_render_page);
    ClassDB::bind_method(D_METHOD("configure_thermal_candidate", "width", "height", "workers"), &NativeSandWorld::configure_thermal_candidate, DEFVAL(1024), DEFVAL(512), DEFVAL(8));
    ClassDB::bind_method(D_METHOD("step_thermal_candidate", "cadence_scale"), &NativeSandWorld::step_thermal_candidate, DEFVAL(2));
    ClassDB::bind_method(D_METHOD("get_thermal_candidate_statistics"), &NativeSandWorld::get_thermal_candidate_statistics);
    ClassDB::bind_method(D_METHOD("authoritative_physical_hash"), &NativeSandWorld::authoritative_physical_hash);
    ClassDB::bind_method(D_METHOD("place_mechanical_shaft_line", "from", "to"), &NativeSandWorld::place_mechanical_shaft_line);
    ClassDB::bind_method(D_METHOD("configure_power_structure", "world_cell", "configuration"), &NativeSandWorld::configure_power_structure);
    ClassDB::bind_method(D_METHOD("set_power_switch_closed", "world_cell", "closed"), &NativeSandWorld::set_power_switch_closed);
    ClassDB::bind_method(D_METHOD("set_power_consumer_priority", "world_cell", "priority"), &NativeSandWorld::set_power_consumer_priority);
    ClassDB::bind_method(D_METHOD("get_power_state_at", "world_cell"), &NativeSandWorld::get_power_state_at);
    ClassDB::bind_method(D_METHOD("get_power_network_state", "network_id"), &NativeSandWorld::get_power_network_state);
    ClassDB::bind_method(D_METHOD("get_power_statistics"), &NativeSandWorld::get_power_statistics);
    ClassDB::bind_method(D_METHOD("get_mechanical_statistics"), &NativeSandWorld::get_mechanical_statistics);
    ClassDB::bind_method(D_METHOD("get_energy_accounting"), &NativeSandWorld::get_energy_accounting);
    ClassDB::bind_method(D_METHOD("get_phase10_architecture"), &NativeSandWorld::get_phase10_architecture);
    ClassDB::bind_method(D_METHOD("get_visible_power_elements", "cell_area"), &NativeSandWorld::get_visible_power_elements);
    ClassDB::bind_method(D_METHOD("power_state_hash"), &NativeSandWorld::power_state_hash);
    ClassDB::bind_method(D_METHOD("serialize_power_state"), &NativeSandWorld::serialize_power_state);
    ClassDB::bind_method(D_METHOD("deserialize_power_state", "state"), &NativeSandWorld::deserialize_power_state);
    ClassDB::bind_method(D_METHOD("configure_power_benchmark", "scenario", "count"), &NativeSandWorld::configure_power_benchmark);
}

// Everything a world owns, returned to the state a brand new world starts in.
//
// Both entry points that begin a world -- reset() and configure_world() -- must forget the
// previous one completely. They used to clear their own lists, and configure_world() cleared
// machine_entities_ while leaving physical_processors_, the active magnet/screen/heater/sluice
// sets, the thermal switch and exchanger cells, and the automation, power, pipe, organic and
// phase13 registries populated with the previous world's ids. Starting a second world then
// stepped over a heater id that no longer had a machine behind it and took the process down.
// One list, called from both, is the only version of this that stays correct as subsystems
// are added.
void NativeSandWorld::clear_world_state() {
    invalidate_chunk_order();
    // Starting a fresh world is the one recovery a faulted simulation gets.
    faulted_ = false;
    fault_message_ = String();
    inject_fault_for_test_ = false;
    chunks_.clear();
    tick_index_ = 0;
    last_movements_ = 0;
    last_cells_visited_ = 0;
    last_cells_skipped_ = 0;
    last_active_rectangles_ = 0;
    last_dirty_render_pixels_ = 0;
    last_render_upload_pixels_ = 0;
    last_render_workers_used_ = 0;
    last_granular_usec_ = last_granular_barrier_usec_ = last_fluid_usec_ = last_fluid_barrier_usec_ = 0;
    last_fluid_cells_active_ = last_fluid_cells_visited_ = last_fluid_transfers_ = last_fluid_mass_transferred_ = 0;
    last_fluid_downward_ = last_fluid_lateral_ = last_fluid_displacements_ = last_fluid_blocked_ = 0;
    last_fluid_wake_transitions_ = last_fluid_sleep_transitions_ = last_fluid_border_crossings_ = 0;
    last_gas_active_ = last_gas_visited_ = last_gas_transfers_ = last_gas_mass_transferred_ = last_gas_usec_ = 0;
    last_simulation_workers_used_ = 0;
    fluid_render_revision_ = 0;
    thermal_candidate_.reset();
    thermal_candidate_statistics_.clear();
    generation_queue_.clear();
    generating_keys_.clear();
    queued_keys_.clear();
    completed_keys_.clear();
    completed_generation_.clear();
    evicted_chunks_.clear();
    last_chunks_published_ = 0;
    last_publish_usec_ = 0;
    total_generation_usec_ = 0;
    worst_generation_usec_ = 0;
    total_chunks_generated_ = 0;
    total_chunks_published_ = 0;
    total_chunks_evicted_ = 0;
    peak_generation_queue_ = 0;
    peak_allocated_chunks_ = 0;
    clear_visibility();
    next_machine_id_ = 1;
    structure_revision_ = 0;
    machine_visual_revision_ = 0;
    machine_entities_.clear();
    active_belts_.clear();
    active_machines_.clear();
    machine_port_watchers_.clear();
    dirty_structure_chunks_.clear();
    structures_allocated_ = 0;
    belts_total_ = 0;
    last_belts_active_ = 0;
    last_belts_considered_ = 0;
    last_belts_skipped_ = 0;
    last_belt_moves_ = 0;
    last_blocked_belt_attempts_ = 0;
    last_logistics_usec_ = 0;
    last_machines_active_ = last_machines_visited_ = last_machine_inputs_ = last_machine_outputs_ = 0;
    last_machine_blocked_ = last_fuel_starved_ = last_machine_usec_ = 0;
    total_sieve_processed_ = total_magnetic_processed_ = total_furnace_processed_ = 0;
    total_glass_ = total_iron_ = total_gold_ = total_residue_ = total_ash_ = 0;
    reset_subsurface_logistics();
    reset_production_statistics();
    physical_processors_.clear();
    physical_chunk_watchers_.clear();
    active_magnets_.clear();
    active_screens_.clear();
    active_heaters_.clear();
    active_wet_sluices_.clear();
    last_magnets_active_ = last_magnetic_cells_tested_ = last_magnetic_moves_ = last_magnetic_usec_ = 0;
    last_screens_active_ = last_screen_grains_tested_ = last_screen_vibration_evaluations_ = last_screen_passes_ = last_screen_usec_ = 0;
    total_magnetic_moves_ = total_screen_passes_ = 0;
    last_heaters_active_ = last_heated_cells_ = last_heat_reactions_ = last_heat_usec_ = total_heat_reactions_ = 0;
    thermal_switch_cells_.clear(); closed_thermal_switches_.clear(); heat_exchanger_cells_.clear();
    last_thermal_active_ = 0; last_thermal_visited_ = 0; last_thermal_exchanges_ = 0; last_thermal_energy_moved_ = 0;
    last_thermal_source_energy_ = 0; last_phase_changes_ = 0; last_thermal_usec_ = 0; last_thermal_barrier_usec_ = 0;
    last_thermal_workers_used_ = 0;
    total_phase_changes_ = 0; total_thermal_source_energy_ = 0; total_steam_generated_ = 0; total_steam_condensed_ = 0;
    thermal_rounding_reservoir_ = 0;
    last_gas_active_ = last_gas_visited_ = last_gas_transfers_ = last_gas_mass_transferred_ = last_gas_usec_ = 0;
    initialize_progression();
    last_banks_active_ = last_banks_visited_ = last_bank_accepted_ = last_bank_rejected_ = 0;
    last_bank_blocked_ = last_bank_usec_ = total_bank_accepted_ = total_bank_rejected_ = 0;
    reset_automation();
    reset_pipe_logistics();
    reset_power();
    reset_organic_physics();
    reset_phase13();
}

void NativeSandWorld::reset(int64_t world_seed, int32_t requested_workers) {
    stop_generation_workers();
    stop_workers();
    seed_ = world_seed;
    configure_workers(requested_workers);
    clear_world_state();
    world_generation_enabled_ = false;
}

int32_t NativeSandWorld::floor_div(int32_t value, int32_t divisor) {
    const int64_t wide_value = value;
    const int64_t wide_divisor = divisor;
    if (wide_value >= 0) return static_cast<int32_t>(wide_value / wide_divisor);
    return static_cast<int32_t>(-((-wide_value + wide_divisor - 1) / wide_divisor));
}

bool NativeSandWorld::checked_rect_end(Rect2i area, int64_t maximum_cells, Vector2i &end) {
    if (area.size.x < 0 || area.size.y < 0) return false;
    const int64_t cells = static_cast<int64_t>(area.size.x) * static_cast<int64_t>(area.size.y);
    const int64_t end_x = static_cast<int64_t>(area.position.x) + area.size.x;
    const int64_t end_y = static_cast<int64_t>(area.position.y) + area.size.y;
    if (cells > maximum_cells || end_x < std::numeric_limits<int32_t>::min() || end_x > std::numeric_limits<int32_t>::max() ||
        end_y < std::numeric_limits<int32_t>::min() || end_y > std::numeric_limits<int32_t>::max()) return false;
    end = {static_cast<int32_t>(end_x), static_cast<int32_t>(end_y)};
    return true;
}

bool NativeSandWorld::has_neighbor_margin(Vector2i cell, int32_t margin) {
    if (margin < 0) return false;
    return static_cast<int64_t>(cell.x) - margin >= std::numeric_limits<int32_t>::min() &&
           static_cast<int64_t>(cell.x) + margin <= std::numeric_limits<int32_t>::max() &&
           static_cast<int64_t>(cell.y) - margin >= std::numeric_limits<int32_t>::min() &&
           static_cast<int64_t>(cell.y) + margin <= std::numeric_limits<int32_t>::max();
}

Vector2i NativeSandWorld::world_to_chunk(Vector2i world_cell) {
    return {floor_div(world_cell.x, CHUNK_SIZE), floor_div(world_cell.y, CHUNK_SIZE)};
}

Vector2i NativeSandWorld::world_to_local(Vector2i world_cell) {
    const Vector2i coordinate = world_to_chunk(world_cell);
    return world_cell - coordinate * CHUNK_SIZE;
}

uint64_t NativeSandWorld::chunk_key(Vector2i coordinate) {
    return (static_cast<uint64_t>(static_cast<uint32_t>(coordinate.x)) << 32u) |
           static_cast<uint32_t>(coordinate.y);
}

int32_t NativeSandWorld::local_index(Vector2i local) {
    return local.y * CHUNK_SIZE + local.x;
}

uint32_t NativeSandWorld::hash_2d(int64_t seed, Vector2i position, int32_t salt) {
    const uint32_t seed_bits = static_cast<uint32_t>(seed) ^
                               (static_cast<uint32_t>(static_cast<uint64_t>(seed) >> 32u) * 0x9e3779b9u);
    uint32_t value = (seed_bits ^ static_cast<uint32_t>(salt) ^ 0x045d9f3bu) & MASK_31;
    value = ((value ^ static_cast<uint32_t>(position.x)) * 0x119de1f3u) & MASK_31;
    value = ((value ^ static_cast<uint32_t>(position.y)) * 0x1b873593u) & MASK_31;
    value = (value ^ (value >> 16u)) & MASK_31;
    value = (value * 0x045d9f3bu) & MASK_31;
    return (value ^ (value >> 16u)) & MASK_31;
}

uint32_t NativeSandWorld::mix_int(uint32_t hash, int32_t component) {
    return ((hash ^ (static_cast<uint32_t>(component) & MASK_31)) * 16777619u) & MASK_31;
}

uint64_t NativeSandWorld::cell_key(Vector2i world_cell) {
    return (static_cast<uint64_t>(static_cast<uint32_t>(world_cell.x)) << 32u) |
           static_cast<uint32_t>(world_cell.y);
}

Vector2i NativeSandWorld::cell_from_key(uint64_t key) {
    return {static_cast<int32_t>(key >> 32u), static_cast<int32_t>(key & 0xffffffffu)};
}

NativeSandWorld::Chunk *NativeSandWorld::get_chunk(Vector2i coordinate) {
    const auto found = chunks_.find(chunk_key(coordinate));
    return found == chunks_.end() ? nullptr : found->second.get();
}

const NativeSandWorld::Chunk *NativeSandWorld::get_chunk(Vector2i coordinate) const {
    const auto found = chunks_.find(chunk_key(coordinate));
    return found == chunks_.end() ? nullptr : found->second.get();
}

NativeSandWorld::Chunk *NativeSandWorld::get_or_create_chunk(Vector2i coordinate) {
    const uint64_t key = chunk_key(coordinate);
    const auto found = chunks_.find(key);
    if (found != chunks_.end()) {
        return found->second.get();
    }
    auto chunk = std::make_unique<Chunk>(coordinate);
    Chunk *result = chunk.get();
    chunks_.emplace(key, std::move(chunk));
    invalidate_chunk_order();
    return result;
}

void NativeSandWorld::invalidate_chunk_order() {
    chunk_order_dirty_ = true;
}

const std::vector<NativeSandWorld::Chunk *> &NativeSandWorld::chunk_order() const {
    // The size comparison is a backstop, not the mechanism: the three places that create,
    // evict or clear chunks invalidate explicitly. It costs one integer compare and means a
    // missed invalidation cannot silently hand out a dangling pointer.
    if (chunk_order_dirty_ || chunk_order_.size() != chunks_.size()) {
        chunk_order_.clear();
        chunk_order_.reserve(chunks_.size());
        for (const auto &[key, chunk] : chunks_) {
            (void)key;
            chunk_order_.push_back(chunk.get());
        }
        std::sort(chunk_order_.begin(), chunk_order_.end(), [](const Chunk *a, const Chunk *b) {
            return a->coordinate.y < b->coordinate.y ||
                   (a->coordinate.y == b->coordinate.y && a->coordinate.x < b->coordinate.x);
        });
        chunk_order_dirty_ = false;
    }
    return chunk_order_;
}

std::vector<NativeSandWorld::Chunk *> NativeSandWorld::sorted_chunks() {
    return chunk_order();
}

std::vector<const NativeSandWorld::Chunk *> NativeSandWorld::sorted_chunks() const {
    // Same order, narrowed to const. Built from the cache rather than sorted again; the const
    // callers are statistics and hashes rather than the per-tick walks, so the remaining copy
    // is not worth a second cache.
    const std::vector<Chunk *> &order = chunk_order();
    return std::vector<const Chunk *>(order.begin(), order.end());
}

int32_t NativeSandWorld::get_cell(Vector2i world_cell) const {
    if (world_generation_enabled_) {
        if (world_cell.y < -world_settings_.sky) {
            return EMPTY_ID;
        }
        const int32_t half_width = world_settings_.width / 2;
        if (world_cell.x < -half_width || world_cell.x >= -half_width + world_settings_.width ||
            world_cell.y >= world_settings_.depth) {
            return BEDROCK_ID;
        }
    }
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) {
        return world_generation_enabled_ ? UNGENERATED_ID : EMPTY_ID;
    }
    return chunk->material[local_index(world_to_local(world_cell))];
}

int32_t NativeSandWorld::get_provenance(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    return chunk == nullptr ? 0 : chunk->provenance[local_index(world_to_local(world_cell))];
}

int32_t NativeSandWorld::get_mineral_signature(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    return chunk == nullptr ? 0 : chunk->mineral_signature[local_index(world_to_local(world_cell))];
}

uint16_t NativeSandWorld::mineral_signature_for(Vector2i original_cell) const {
    const uint32_t value = hash_2d(seed_, original_cell, 0x534947 + world_settings_.generation_version * 7919);
    return static_cast<uint16_t>((value ^ (value >> 16u)) & 0xffffu);
}

int64_t NativeSandWorld::fill_rect(Rect2i area, int32_t material_id, int32_t spacing) {
    Vector2i end;
    if (material_id < EMPTY_ID || material_id > MAX_MATERIAL_ID || spacing < 1 || !checked_rect_end(area, 16'777'216, end)) {
        return -1;
    }
    int64_t written = 0;
    for (int32_t y = area.position.y; y < end.y; y += spacing) {
        for (int32_t x = area.position.x; x < end.x; x += spacing) {
            const Vector2i cell{x, y};
            if (world_generation_enabled_ && !is_inside_virtual_world(cell)) {
                continue;
            }
            ensure_generated_for_edit(world_to_chunk(cell));
            Chunk *chunk = get_or_create_chunk(world_to_chunk(cell));
            const Vector2i local = world_to_local({x, y});
            const int32_t index = local_index(local);
            const bool requested_full_water = material_id == WATER_ID && water_mass_at(*chunk, index) != 255;
            if (chunk->material[index] == material_id && !requested_full_water) {
                continue;
            }
            chunk->material[index] = material_id;
            chunk->temperature[index] = material_id == EMPTY_ID ? TEMPERATURE_AMBIENT : chunk->temperature[index];
            chunk->provenance[index] = material_id == SAND_ID ? static_cast<uint16_t>(geology_profile_id_at({x, y})) : 0;
            chunk->mineral_signature[index] = material_id == SAND_ID ? mineral_signature_for(cell) : 0;
            chunk->flags[index] = 0;
            if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = material_id == EMPTY_ID ? 0 : 255;
            ++chunk->revision;
            chunk->pristine = false;
            chunk->render_dirty.include(local.x, local.y, 1);
            activate_world_cell(cell, 1);
            activate_fluid_world_cell(cell, 1);
            activate_belts_near(cell);
            activate_machines_at_port(cell);
            ++written;
        }
    }
    if (written > 0) ++fluid_render_revision_;
    return written;
}

int32_t NativeSandWorld::allocate_chunk_rect(Rect2i chunk_area) {
    Vector2i end;
    if (!checked_rect_end(chunk_area, 4096, end)) {
        return -1;
    }
    for (int32_t y = chunk_area.position.y; y < end.y; ++y) {
        for (int32_t x = chunk_area.position.x; x < end.x; ++x) {
            if (world_generation_enabled_) {
                ensure_generated_for_edit({x, y});
            } else {
                get_or_create_chunk({x, y});
            }
        }
    }
    return chunk_count();
}

int32_t NativeSandWorld::initialize_cell(Vector2i world_cell, int32_t material_id) {
    if (material_id < EMPTY_ID || material_id > MAX_MATERIAL_ID) {
        return 31; // ERR_INVALID_PARAMETER
    }
    if (material_id == EMPTY_ID) {
        return 0;
    }
    if (world_generation_enabled_ && !is_inside_virtual_world(world_cell)) {
        return 31;
    }
    ensure_generated_for_edit(world_to_chunk(world_cell));
    Chunk *chunk = get_or_create_chunk(world_to_chunk(world_cell));
    const int32_t index = local_index(world_to_local(world_cell));
    const int32_t old_material = chunk->material[index];
    if (chunk->material[index] == material_id) {
        return 0;
    }
    chunk->material[index] = material_id;
    if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = material_id == EMPTY_ID ? 0 : 255;
    if (old_material != material_id) {
        if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
        if (chunk->reaction_progress != nullptr) (*chunk->reaction_progress)[index] = 0;
        if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = 0;
        reactive_cells_.erase(cell_key(world_cell));
    }
    chunk->provenance[index] = material_id == SAND_ID ? static_cast<uint16_t>(geology_profile_id_at(world_cell)) : 0;
    chunk->mineral_signature[index] = material_id == SAND_ID ? mineral_signature_for(world_cell) : 0;
    ++chunk->revision;
    chunk->pristine = false;
    mark_render_world_cell(world_cell);
    activate_belts_near(world_cell);
    activate_machines_at_port(world_cell);
    wake_subsurface_at(world_cell);
    activate_physical_near(world_cell);
    activate_reactive_cell(world_cell);
    activate_fluid_world_cell(world_cell, 1);
    ++fluid_render_revision_;
    wake_pipe_neighbors(world_cell);
    notify_automation_cell_change(world_cell);
    return 0;
}

int32_t NativeSandWorld::set_cell(Vector2i world_cell, int32_t material_id) {
    const int32_t profile_id = material_id == SAND_ID ? geology_profile_id_at(world_cell) : 0;
    return set_cell_with_provenance(world_cell, material_id, profile_id);
}

int32_t NativeSandWorld::set_cell_with_provenance(Vector2i world_cell, int32_t material_id, int32_t profile_id) {
    const int32_t signature = material_id == SAND_ID ? mineral_signature_for(world_cell) : 0;
    return set_cell_with_metadata(world_cell, material_id, profile_id, signature);
}

int32_t NativeSandWorld::set_cell_with_metadata(Vector2i world_cell, int32_t material_id, int32_t profile_id, int32_t mineral_signature) {
    if (material_id < EMPTY_ID || material_id > MAX_MATERIAL_ID || profile_id < 0 || profile_id > 65535 ||
        mineral_signature < 0 || mineral_signature > 65535 || !has_neighbor_margin(world_cell, 1)) {
        return 31;
    }
    if (world_generation_enabled_ && !is_inside_virtual_world(world_cell)) {
        return 31;
    }
    ensure_generated_for_edit(world_to_chunk(world_cell));
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr && material_id == EMPTY_ID) {
        return 0;
    }
    if (chunk == nullptr) {
        chunk = get_or_create_chunk(world_to_chunk(world_cell));
    }
    const int32_t index = local_index(world_to_local(world_cell));
    const int32_t old_material = chunk->material[index];
    const bool geological = material_id == SAND_ID || (material_id >= FINE_SAND_ID && material_id <= CRUDE_RESIDUE_ID);
    const uint16_t next_provenance = geological ? static_cast<uint16_t>(profile_id) : 0;
    const uint16_t next_signature = geological ? static_cast<uint16_t>(mineral_signature) : 0;
    const bool requested_full_water = material_id == WATER_ID && water_mass_at(*chunk, index) != 255;
    if (chunk->material[index] == material_id && chunk->provenance[index] == next_provenance &&
        chunk->mineral_signature[index] == next_signature && !requested_full_water) {
        return 0;
    }
    chunk->material[index] = material_id;
    chunk->provenance[index] = next_provenance;
    chunk->mineral_signature[index] = next_signature;
    chunk->flags[index] = 0;
    if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = material_id == EMPTY_ID ? 0 : 255;
    if (old_material != material_id) {
        if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
        if (chunk->reaction_progress != nullptr) (*chunk->reaction_progress)[index] = 0;
        if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = 0;
        reactive_cells_.erase(cell_key(world_cell));
    }
    if (material_id == EMPTY_ID) chunk->temperature[index] = TEMPERATURE_AMBIENT;
    ++chunk->revision;
    chunk->pristine = false;
    activate_world_cell(world_cell);
    activate_world_cell(world_cell + Vector2i(-1, -1));
    activate_world_cell(world_cell + Vector2i(0, -1));
    activate_world_cell(world_cell + Vector2i(1, -1));
    mark_render_world_cell(world_cell);
    activate_belts_near(world_cell);
    activate_machines_at_port(world_cell);
    wake_subsurface_at(world_cell);
    activate_physical_near(world_cell);
    activate_fluid_world_cell(world_cell);
    activate_fluid_world_cell(world_cell + Vector2i(0, -1));
    activate_reactive_cell(world_cell);
    ++fluid_render_revision_;
    notify_automation_cell_change(world_cell);
    return 0;
}

int32_t NativeSandWorld::set_water_mass(Vector2i world_cell, int32_t mass, int32_t temperature) {
    if (mass < 0 || mass > 255 || temperature < 0 || temperature > TEMPERATURE_MAX || !has_neighbor_margin(world_cell, 1)) return 31;
    if (world_generation_enabled_ && !is_inside_virtual_world(world_cell)) return 31;
    ensure_generated_for_edit(world_to_chunk(world_cell));
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr && mass == 0) return 0;
    if (chunk == nullptr) chunk = get_or_create_chunk(world_to_chunk(world_cell));
    const int32_t index = local_index(world_to_local(world_cell));
    if (mass > 0 && chunk->material[index] != EMPTY_ID && chunk->material[index] != WATER_ID) return 31;
    MatterJobResult result;
    write_water_state(world_cell, mass, static_cast<uint16_t>(temperature), &result, true);
    std::vector<MatterJobResult> results;
    results.push_back(std::move(result));
    apply_matter_notifications(results);
    ++fluid_render_revision_;
    activate_fluid_world_cell(world_cell, 1);
    activate_fluid_world_cell(world_cell + Vector2i(0, -1), 1);
    return 0;
}

int32_t NativeSandWorld::get_liquid_mass(Vector2i world_cell) const { return water_mass_at(world_cell); }

int64_t NativeSandWorld::get_total_water_mass() const {
    int64_t total = 0;
    for (const Chunk *chunk : sorted_chunks()) for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) total += water_mass_at(*chunk, index);
    return total;
}

// The cells one brush stroke covers.
//
// The editor stamps a disc at every interpolated point between the previous pointer cell and
// the current one. That set -- not an idealised capsule -- is what the brush has always
// painted, and a performance fix is not allowed to change how the brush feels, so the same
// set is built here. The interpolation is done in exact integer arithmetic rather than with
// lerp and round, because a stroke edits the world and two machines must agree on it.
//
// The mask deduplicates: consecutive discs overlap heavily, and every cell should be visited
// once, in a fixed row-major order, so the edit does not depend on the path that produced it.
bool NativeSandWorld::stroke_mask(Vector2i from_cell, Vector2i to_cell, int32_t radius,
                                  Rect2i &area, std::vector<uint8_t> &mask) {
    if (radius < 0 || radius > MAX_BRUSH_RADIUS) return false;
    const int64_t left = std::min(from_cell.x, to_cell.x) - static_cast<int64_t>(radius);
    const int64_t right = std::max(from_cell.x, to_cell.x) + static_cast<int64_t>(radius);
    const int64_t top = std::min(from_cell.y, to_cell.y) - static_cast<int64_t>(radius);
    const int64_t bottom = std::max(from_cell.y, to_cell.y) + static_cast<int64_t>(radius);
    if (left < std::numeric_limits<int32_t>::min() + 2 || right > std::numeric_limits<int32_t>::max() - 2 ||
        top < std::numeric_limits<int32_t>::min() + 2 || bottom > std::numeric_limits<int32_t>::max() - 2) return false;
    const int64_t width = right - left + 1;
    const int64_t height = bottom - top + 1;
    if (width * height > MAX_STROKE_CELLS) return false;

    area = Rect2i(static_cast<int32_t>(left), static_cast<int32_t>(top),
                  static_cast<int32_t>(width), static_cast<int32_t>(height));
    mask.assign(static_cast<size_t>(width * height), 0);

    const int32_t steps = std::max(std::abs(to_cell.x - from_cell.x), std::abs(to_cell.y - from_cell.y));
    const int64_t radius_squared = static_cast<int64_t>(radius) * radius;
    for (int32_t step = 0; step <= steps; ++step) {
        const Vector2i point{
            from_cell.x + rounded_fraction(static_cast<int64_t>(to_cell.x) - from_cell.x, step, steps),
            from_cell.y + rounded_fraction(static_cast<int64_t>(to_cell.y) - from_cell.y, step, steps)};
        for (int32_t offset_y = -radius; offset_y <= radius; ++offset_y) {
            for (int32_t offset_x = -radius; offset_x <= radius; ++offset_x) {
                if (static_cast<int64_t>(offset_x) * offset_x + static_cast<int64_t>(offset_y) * offset_y > radius_squared) continue;
                const int64_t column = static_cast<int64_t>(point.x) + offset_x - left;
                const int64_t row = static_cast<int64_t>(point.y) + offset_y - top;
                if (column < 0 || column >= width || row < 0 || row >= height) continue;
                mask[static_cast<size_t>(row * width + column)] = 1;
            }
        }
    }
    return true;
}

// delta * step / steps, rounded to nearest with ties away from zero, without touching a float.
int32_t NativeSandWorld::rounded_fraction(int64_t delta, int32_t step, int32_t steps) {
    if (steps <= 0) return 0;
    const int64_t numerator = delta * step;
    const int64_t denominator = steps;
    const int64_t magnitude = (std::abs(numerator) * 2 + denominator) / (denominator * 2);
    return static_cast<int32_t>(numerator < 0 ? -magnitude : magnitude);
}

// One brush stroke, applied once.
//
// The editor used to send one command per painted cell. A radius-3 brush dragged across 160
// cells in a frame is roughly 4,700 commands, each allocating a CommandBatch, deep-copying its
// payload, reading the whole statistics dictionary and serialising itself into a log -- about
// five seconds of GDScript for a tenth of a millisecond of actual work. The gesture is one
// player action, so it travels as one command and is swept here.
//
// Cells are written through set_cell, so provenance, activation, belt and machine port wake-ups
// and automation notifications behave exactly as they do for a single edit. There is no second
// implementation of what it means to place a cell.
int64_t NativeSandWorld::paint_stroke(Vector2i from_cell, Vector2i to_cell, int32_t radius, int32_t material_id) {
    if (material_id < EMPTY_ID || material_id > MAX_MATERIAL_ID) return -1;
    Rect2i area;
    std::vector<uint8_t> mask;
    if (!stroke_mask(from_cell, to_cell, radius, area, mask)) return -1;
    int64_t written = 0;
    for (int32_t row = 0; row < area.size.y; ++row) {
        for (int32_t column = 0; column < area.size.x; ++column) {
            if (mask[static_cast<size_t>(row) * area.size.x + column] == 0) continue;
            if (set_cell({area.position.x + column, area.position.y + row}, material_id) == 0) ++written;
        }
    }
    return written;
}

// The harvest brush, swept the same way and for the same reason.
int64_t NativeSandWorld::harvest_stroke(Vector2i from_cell, Vector2i to_cell, int32_t radius) {
    Rect2i area;
    std::vector<uint8_t> mask;
    if (!stroke_mask(from_cell, to_cell, radius, area, mask)) return -1;
    int64_t harvested = 0;
    for (int32_t row = 0; row < area.size.y; ++row) {
        for (int32_t column = 0; column < area.size.x; ++column) {
            if (mask[static_cast<size_t>(row) * area.size.x + column] == 0) continue;
            const Vector2i cell{area.position.x + column, area.position.y + row};
            if (get_cell(cell) == COAL_ID && harvest_cell(cell) == 0) ++harvested;
        }
    }
    return harvested;
}

int32_t NativeSandWorld::harvest_cell(Vector2i world_cell) {
    if (get_cell(world_cell) != COAL_ID) return get_cell(world_cell) == BEDROCK_ID ? 31 : 0;
    return set_cell_with_metadata(world_cell, COAL_CHUNK_ID, 0, 0);
}

void NativeSandWorld::activate_world_cell(Vector2i world_cell, int32_t radius) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) {
        return;
    }
    const Vector2i local = world_to_local(world_cell);
    chunk->active.include(local.x, local.y, radius);
    chunk->stable_ticks = 0;
}

void NativeSandWorld::include_next_world_cell(Vector2i world_cell, int32_t radius) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) {
        return;
    }
    const Vector2i local = world_to_local(world_cell);
    chunk->next_active.include(local.x, local.y, radius);
}

void NativeSandWorld::mark_render_world_cell(Vector2i world_cell, int32_t radius) {
    if (radius < 0) return;
    const int64_t minimum_y = std::max<int64_t>(std::numeric_limits<int32_t>::min(), static_cast<int64_t>(world_cell.y) - radius);
    const int64_t maximum_y = std::min<int64_t>(std::numeric_limits<int32_t>::max(), static_cast<int64_t>(world_cell.y) + radius);
    const int64_t minimum_x = std::max<int64_t>(std::numeric_limits<int32_t>::min(), static_cast<int64_t>(world_cell.x) - radius);
    const int64_t maximum_x = std::min<int64_t>(std::numeric_limits<int32_t>::max(), static_cast<int64_t>(world_cell.x) + radius);
    for (int64_t y = minimum_y; y <= maximum_y; ++y) {
        for (int64_t x = minimum_x; x <= maximum_x; ++x) {
            const Vector2i cell{static_cast<int32_t>(x), static_cast<int32_t>(y)};
            Chunk *chunk = get_chunk(world_to_chunk(cell));
            if (chunk == nullptr) {
                continue;
            }
            const Vector2i local = world_to_local(cell);
            chunk->render_dirty.include(local.x, local.y);
        }
    }
}

void NativeSandWorld::finalize_initialization() {
    for (Chunk *chunk : sorted_chunks()) {
        chunk->active.clear();
        chunk->next_active.clear();
        chunk->stable_ticks = 0;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (!material_transportable(chunk->material[index])) {
                continue;
            }
            const int32_t x = index % CHUNK_SIZE;
            const int32_t y = index / CHUNK_SIZE;
            chunk->active.include(x, y, 1);
        }
        refresh_fluid_activity(*chunk);
    }
}

Vector2i NativeSandWorld::choose_destination(Vector2i source) const {
    if (magnetic_capture_supports(source)) return source;
    const Vector2i direct = source + Vector2i(0, 1);
    if (can_material_enter(source, direct)) {
        return direct;
    }
    const bool prefer_left = (hash_2d(seed_, source, static_cast<int32_t>(tick_index_)) & 1u) == 0u;
    const Vector2i first = source + (prefer_left ? Vector2i(-1, 1) : Vector2i(1, 1));
    if (can_material_enter(source, first)) {
        return first;
    }
    const Vector2i second = source + (prefer_left ? Vector2i(1, 1) : Vector2i(-1, 1));
    return can_material_enter(source, second) ? second : source;
}

bool NativeSandWorld::is_empty_for_material(Vector2i world_cell) const {
    return get_cell(world_cell) == EMPTY_ID && !is_structure_solid(world_cell);
}

bool NativeSandWorld::can_material_enter(Vector2i source, Vector2i destination) const {
    if (get_cell(destination) != EMPTY_ID) return false;
    const int32_t structure = get_structure(destination);
    if (structure == STRUCTURE_NONE || (structure == STRUCTURE_CONTROL_GATE && open_gate_cells_.contains(cell_key(destination)))) return true;
    if (structure != STRUCTURE_SIEVE || destination.y <= source.y || !is_permeable_screen_cell(destination)) return false;
    const int32_t material = get_cell(source);
    const Chunk *chunk = get_chunk(world_to_chunk(source));
    if (chunk == nullptr) return false;
    const int32_t index = local_index(world_to_local(source));
    return permeability_allows(fine_screen_permeability_rule(), material, chunk->provenance[index], chunk->mineral_signature[index]);
}

bool NativeSandWorld::is_structure_solid(Vector2i world_cell) const {
    if (structures_allocated_ <= 0) return false;
    const int32_t type_id = get_structure(world_cell);
    return type_id != STRUCTURE_NONE && type_id != STRUCTURE_SHAFT && type_id != STRUCTURE_POWER_POLE &&
           (type_id != STRUCTURE_CONTROL_GATE || !open_gate_cells_.contains(cell_key(world_cell)));
}

bool NativeSandWorld::material_transportable(int32_t material_id) const {
    static constexpr std::array<bool, MATERIAL_COUNT> TRANSPORTABLE{{false, false, true, false, false, false,
        true, true, true, true, true, true, true, true, true, true, false, false, false, false, true,
        true, true, true, false, true, true, true}};
    return material_id >= 0 && material_id < static_cast<int32_t>(TRANSPORTABLE.size()) && TRANSPORTABLE[material_id];
}

bool NativeSandWorld::moved_this_tick(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    return chunk != nullptr && (chunk->flags[local_index(world_to_local(world_cell))] & MOVED_FLAG) != 0;
}

void NativeSandWorld::mark_moved_this_tick(Vector2i world_cell) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk != nullptr) chunk->flags[local_index(world_to_local(world_cell))] |= MOVED_FLAG;
}

bool NativeSandWorld::move_if_empty(Vector2i source, Vector2i destination) {
    Chunk *source_chunk = get_chunk(world_to_chunk(source));
    if (source_chunk == nullptr || !can_material_enter(source, destination)) {
        return false;
    }
    const Vector2i source_local = world_to_local(source);
    const int32_t source_index = local_index(source_local);
    const int32_t material_id = source_chunk->material[source_index];
    if (material_id == EMPTY_ID) {
        return false;
    }
    Chunk *destination_chunk = get_or_create_chunk(world_to_chunk(destination));
    const Vector2i destination_local = world_to_local(destination);
    const int32_t destination_index = local_index(destination_local);
    destination_chunk->material[destination_index] = material_id;
    destination_chunk->temperature[destination_index] = source_chunk->temperature[source_index];
    destination_chunk->provenance[destination_index] = source_chunk->provenance[source_index];
    destination_chunk->mineral_signature[destination_index] = source_chunk->mineral_signature[source_index];
    const int32_t source_amount = material_amount_at(*source_chunk, source_index);
    const uint16_t source_phase_energy = source_chunk->phase_energy == nullptr ? 0 : (*source_chunk->phase_energy)[source_index];
    const uint8_t source_moisture = source_chunk->organic_moisture == nullptr ? 0 : (*source_chunk->organic_moisture)[source_index];
    const uint16_t source_reaction_progress = source_chunk->reaction_progress == nullptr ? 0 : (*source_chunk->reaction_progress)[source_index];
    const uint8_t source_reaction_state = source_chunk->reaction_state == nullptr ? 0 : (*source_chunk->reaction_state)[source_index];
    if (source_amount < 255) ensure_liquid_plane(*destination_chunk);
    if (destination_chunk->material_amount != nullptr) (*destination_chunk->material_amount)[destination_index] = static_cast<uint8_t>(source_amount);
    if (source_phase_energy > 0) ensure_phase_energy_plane(*destination_chunk);
    if (destination_chunk->phase_energy != nullptr) (*destination_chunk->phase_energy)[destination_index] = source_phase_energy;
    if (source_moisture > 0) ensure_moisture_plane(*destination_chunk);
    if (destination_chunk->organic_moisture != nullptr) (*destination_chunk->organic_moisture)[destination_index] = source_moisture;
    if (source_reaction_progress > 0 || source_reaction_state > 0) ensure_reaction_planes(*destination_chunk);
    if (destination_chunk->reaction_progress != nullptr) (*destination_chunk->reaction_progress)[destination_index] = source_reaction_progress;
    if (destination_chunk->reaction_state != nullptr) (*destination_chunk->reaction_state)[destination_index] = source_reaction_state;
    destination_chunk->flags[destination_index] = static_cast<uint8_t>((source_chunk->flags[source_index] & ~MOVED_FLAG) | MOVED_FLAG);
    if (get_structure(destination) == STRUCTURE_SIEVE && material_id == SAND_ID) {
        destination_chunk->material[destination_index] = FINE_SAND_ID;
        ++total_screen_passes_;
        ++last_screen_passes_;
    }
    source_chunk->material[source_index] = EMPTY_ID;
    source_chunk->temperature[source_index] = TEMPERATURE_AMBIENT;
    source_chunk->provenance[source_index] = 0;
    source_chunk->mineral_signature[source_index] = 0;
    source_chunk->flags[source_index] = 0;
    if (source_chunk->material_amount != nullptr) (*source_chunk->material_amount)[source_index] = 0;
    if (source_chunk->phase_energy != nullptr) (*source_chunk->phase_energy)[source_index] = 0;
    if (source_chunk->organic_moisture != nullptr) (*source_chunk->organic_moisture)[source_index] = 0;
    if (source_chunk->reaction_progress != nullptr) (*source_chunk->reaction_progress)[source_index] = 0;
    if (source_chunk->reaction_state != nullptr) (*source_chunk->reaction_state)[source_index] = 0;
    reactive_cells_.erase(cell_key(source));
    if (is_combustible_material(material_id)) activate_reactive_cell(destination);
    ++source_chunk->revision;
    ++destination_chunk->revision;
    source_chunk->moved_this_tick = true;
    destination_chunk->moved_this_tick = true;
    source_chunk->pristine = false;
    destination_chunk->pristine = false;
    include_next_world_cell(source, 1);
    include_next_world_cell(source + Vector2i(0, -1), 1);
    include_next_world_cell(destination, 1);
    mark_render_world_cell(source);
    mark_render_world_cell(destination);
    activate_belts_near(source);
    activate_belts_near(destination);
    activate_machines_at_port(source);
    activate_machines_at_port(destination);
    activate_physical_near(source);
    activate_physical_near(destination);
    notify_automation_cell_change(source);
    notify_automation_cell_change(destination);
    return true;
}

void NativeSandWorld::clear_movement_flags(const std::vector<Chunk *> &active_chunks) {
    std::unordered_set<uint64_t> cleared;
    for (Chunk *chunk : active_chunks) {
        for (uint8_t &flags : chunk->flags) flags &= static_cast<uint8_t>(~MOVED_FLAG);
        cleared.insert(chunk_key(chunk->coordinate));
    }
    for (const uint64_t key : active_belts_) {
        Chunk *chunk = get_chunk(world_to_chunk(cell_from_key(key) + Vector2i(0, -1)));
        if (chunk != nullptr && cleared.insert(chunk_key(chunk->coordinate)).second)
            for (uint8_t &flags : chunk->flags) flags &= static_cast<uint8_t>(~MOVED_FLAG);
    }
}

int32_t NativeSandWorld::water_mass_at(const Chunk &chunk, int32_t index) const {
    if (chunk.material[index] != WATER_ID) return 0;
    return chunk.material_amount == nullptr ? 255 : (*chunk.material_amount)[index];
}

int32_t NativeSandWorld::water_mass_at(Vector2i cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(cell));
    return chunk == nullptr ? 0 : water_mass_at(*chunk, local_index(world_to_local(cell)));
}

void NativeSandWorld::ensure_liquid_plane(Chunk &chunk) {
    if (chunk.material_amount != nullptr) return;
    chunk.material_amount = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) (*chunk.material_amount)[index] = chunk.material[index] == EMPTY_ID ? 0 : 255;
}

bool NativeSandWorld::fluid_destination_available(Vector2i cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr || is_structure_solid(cell)) return false;
    const int32_t material = chunk->material[local_index(world_to_local(cell))];
    return material == EMPTY_ID || material == WATER_ID;
}

void NativeSandWorld::activate_fluid_world_cell(Vector2i world_cell, int32_t radius) {
    if (radius < 0) return;
    std::unordered_set<uint64_t> awakened;
    const int64_t minimum_y = std::max<int64_t>(std::numeric_limits<int32_t>::min(), static_cast<int64_t>(world_cell.y) - radius);
    const int64_t maximum_y = std::min<int64_t>(std::numeric_limits<int32_t>::max(), static_cast<int64_t>(world_cell.y) + radius);
    const int64_t minimum_x = std::max<int64_t>(std::numeric_limits<int32_t>::min(), static_cast<int64_t>(world_cell.x) - radius);
    const int64_t maximum_x = std::min<int64_t>(std::numeric_limits<int32_t>::max(), static_cast<int64_t>(world_cell.x) + radius);
    for (int64_t y = minimum_y; y <= maximum_y; ++y) for (int64_t x = minimum_x; x <= maximum_x; ++x) {
        const Vector2i cell{static_cast<int32_t>(x), static_cast<int32_t>(y)};
        Chunk *chunk = get_chunk(world_to_chunk(cell));
        if (chunk == nullptr) continue;
        const bool was_sleeping = !chunk->fluid_active.valid();
        const Vector2i local = world_to_local(cell);
        chunk->fluid_active.include(local.x, local.y, 0);
        chunk->fluid_plane_quiet_ticks = 0;
        if (was_sleeping && awakened.insert(chunk_key(chunk->coordinate)).second) ++last_fluid_wake_transitions_;
    }
}

void NativeSandWorld::include_next_fluid_world_cell(Vector2i world_cell, int32_t radius) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return;
    const Vector2i local = world_to_local(world_cell);
    chunk->fluid_next_active.include(local.x, local.y, radius);
}

void NativeSandWorld::write_water_state(Vector2i cell, int32_t mass, uint16_t temperature, MatterJobResult *result, bool collect_changes) {
    Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr) return;
    const Vector2i local = world_to_local(cell);
    const int32_t index = local_index(local);
    const int32_t old_mass = water_mass_at(*chunk, index);
    const uint16_t old_temperature = chunk->temperature[index];
    if (old_mass == mass && (mass == 0 || old_temperature == temperature)) return;
    if (mass > 0 && mass < 255) ensure_liquid_plane(*chunk);
    if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = static_cast<uint8_t>(mass);
    chunk->material[index] = mass > 0 ? WATER_ID : EMPTY_ID;
    chunk->temperature[index] = mass > 0 ? temperature : TEMPERATURE_AMBIENT;
    chunk->provenance[index] = 0;
    chunk->mineral_signature[index] = 0;
    if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
    if (chunk->reaction_progress != nullptr) (*chunk->reaction_progress)[index] = 0;
    if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = 0;
    reactive_cells_.erase(cell_key(cell));
    ++chunk->revision;
    chunk->pristine = false;
    chunk->fluid_moved_this_tick = true;
    chunk->render_dirty.include(local.x, local.y, 1);
    chunk->fluid_next_active.include(local.x, local.y, 1);
    if (collect_changes && result != nullptr) result->changed_cells.push_back(cell);
}

int32_t NativeSandWorld::transfer_water(Vector2i source, Vector2i destination, int32_t requested, MatterJobResult &result,
                                         bool downward, bool collect_changes) {
    return transfer_mobile_material(source, destination, requested, result, downward, collect_changes);
}

// Whether a granular or fluid move has to report the cells it touched to the serial barrier.
//
// Every term here asks whether a subsystem *exists* that could care -- except that the belt term
// used to ask whether any belt was already awake, which is circular: a sleeping belt is woken by
// activate_belts_near(), activate_belts_near() is only reached through these notifications, and
// the notifications were switched off precisely because no belt was awake. So a Conveyor could
// never be started by matter falling onto it. Painting matter directly into the cell above a
// belt happened to work, because set_cell() wakes belts itself; dropping it from one cell higher
// -- which is what the game tells a new player to do -- left the matter sitting on a dead belt
// forever. Belts existing is the condition, not belts already running.
bool NativeSandWorld::should_collect_matter_changes() const {
    return !automation_cell_watchers_.empty() || !machine_port_watchers_.empty() || !physical_processors_.empty() ||
           belts_total_ > 0 || !pipe_segments_.empty() || !subsurface_cell_watchers_.empty();
}

void NativeSandWorld::apply_matter_notifications(const std::vector<MatterJobResult> &results) {
    // Which subsystems can do anything at all, asked once instead of once per moved cell.
    //
    // Each of these calls already returns immediately when its own container is empty, but only
    // after a hash lookup -- and activate_physical_near() does nine of them, one per chunk in a
    // 3x3 neighbourhood. A wall of falling Sand in a world that contains belts and nothing else
    // was paying roughly sixteen lookups per moved cell so that one of them could matter.
    const bool has_belts = belts_total_ > 0;
    const bool has_machine_ports = !machine_port_watchers_.empty();
    const bool has_subsurface = !subsurface_cell_watchers_.empty();
    const bool has_physical = !physical_chunk_watchers_.empty();
    const bool has_pipes = !pipe_segments_.empty();
    const bool has_automation = !automation_cell_watchers_.empty() || !blocked_gate_components_.empty();
    bool changed = false;
    for (const MatterJobResult &result : results) {
        changed = changed || result.transfers > 0 || result.displaced > 0;
        for (const Vector2i cell : result.reactive_cells_changed) {
            reactive_cells_.erase(cell_key(cell));
            activate_reactive_cell(cell);
        }
        for (const Vector2i cell : result.changed_cells) {
            if (has_belts) activate_belts_near(cell);
            if (has_machine_ports) activate_machines_at_port(cell);
            if (has_subsurface) wake_subsurface_at(cell);
            if (has_physical) activate_physical_near(cell);
            if (has_pipes) wake_pipe_neighbors(cell);
            if (has_automation) notify_automation_cell_change(cell);
        }
    }
    if (changed) ++fluid_render_revision_;
}

bool NativeSandWorld::displace_water_for_sand(Vector2i destination, MatterJobResult &result, bool collect_changes) {
    const int32_t mass = water_mass_at(destination);
    if (mass <= 0) return false;
    const bool prefer_left = (hash_2d(seed_, destination, static_cast<int32_t>(tick_index_) ^ 0x51a7) & 1u) == 0u;
    const std::array<Vector2i, 3> offsets{{prefer_left ? Vector2i(-1, 0) : Vector2i(1, 0),
                                          prefer_left ? Vector2i(1, 0) : Vector2i(-1, 0), Vector2i(0, -1)}};
    for (const Vector2i offset : offsets) {
        const Vector2i target = destination + offset;
        if (!fluid_destination_available(target) || 255 - water_mass_at(target) < mass) continue;
        if (transfer_water(destination, target, mass, result, false, collect_changes) == mass) {
            ++result.displaced;
            return true;
        }
    }
    return false;
}

// The exact condition under which activate_reactive_cell() would put a cell in reactive_cells_.
// Kept next to move_granular_fast so that a change to the insert rule in native_organic_physics
// is visibly a change to this one too.
bool NativeSandWorld::reactive_state_possible(int32_t material, int32_t bound_moisture) {
    if (bound_moisture > 0) return true;
    return material >= 0 && material < MATERIAL_COUNT && organic_material_definitions()[material].reactive;
}

bool NativeSandWorld::move_granular_fast(Chunk &source_chunk, int32_t source_index, Vector2i source, Vector2i destination,
                                          MatterJobResult &result, bool collect_changes) {
    // Resolve the destination without touching the chunk map when it lies inside the chunk we
    // are already holding. Only cells on a chunk edge fall out of it, so this is the common
    // case by a wide margin -- and this function is called up to three times for every mobile
    // cell of every active chunk, which made that hash lookup one of the most executed
    // instructions in the simulation. The fluid path has always had this fast index; the
    // granular path went the long way round.
    const Vector2i chunk_origin = source_chunk.coordinate * CHUNK_SIZE;
    const int32_t local_x = destination.x - chunk_origin.x;
    const int32_t local_y = destination.y - chunk_origin.y;
    Chunk *destination_chunk = nullptr;
    int32_t destination_index = 0;
    if (static_cast<uint32_t>(local_x) < static_cast<uint32_t>(CHUNK_SIZE) &&
        static_cast<uint32_t>(local_y) < static_cast<uint32_t>(CHUNK_SIZE)) {
        destination_chunk = &source_chunk;
        destination_index = local_y * CHUNK_SIZE + local_x;
    } else {
        destination_chunk = get_chunk(world_to_chunk(destination));
        if (destination_chunk == nullptr) return false;
        destination_index = local_index(world_to_local(destination));
    }
    const uint16_t source_material = source_chunk.material[source_index];
    const int32_t source_amount = material_amount_at(source_chunk, source_index);
    const uint16_t source_phase_energy = source_chunk.phase_energy == nullptr ? 0 : (*source_chunk.phase_energy)[source_index];
    const uint8_t source_moisture = source_chunk.organic_moisture == nullptr ? 0 : (*source_chunk.organic_moisture)[source_index];
    const uint16_t source_reaction_progress = source_chunk.reaction_progress == nullptr ? 0 : (*source_chunk.reaction_progress)[source_index];
    const uint8_t source_reaction_state = source_chunk.reaction_state == nullptr ? 0 : (*source_chunk.reaction_state)[source_index];
    const uint16_t destination_material = destination_chunk->material[destination_index];
    const uint8_t destination_moisture = destination_chunk->organic_moisture == nullptr
            ? 0 : (*destination_chunk->organic_moisture)[destination_index];
    if (destination_material == WATER_ID) {
        if (source_material != SAND_ID || !displace_water_for_sand(destination, result, collect_changes)) return false;
    } else if (destination_material != EMPTY_ID) return false;
    // The destination chunk is already resolved, and most chunks carry no structure plane at
    // all, so read it directly instead of going back through get_structure()'s chunk lookup.
    const int32_t structure = destination_chunk->structures == nullptr
            ? STRUCTURE_NONE
            : static_cast<int32_t>((*destination_chunk->structures)[destination_index] & 0x7fu);
    if (structure != STRUCTURE_NONE && !(structure == STRUCTURE_CONTROL_GATE && open_gate_cells_.contains(cell_key(destination)))) {
        if (structure != STRUCTURE_SIEVE || destination.y <= source.y || !is_permeable_screen_cell(destination) ||
            !permeability_allows(fine_screen_permeability_rule(), source_material, source_chunk.provenance[source_index], source_chunk.mineral_signature[source_index])) return false;
    }
    destination_chunk->material[destination_index] = source_material;
    destination_chunk->temperature[destination_index] = source_chunk.temperature[source_index];
    destination_chunk->provenance[destination_index] = source_chunk.provenance[source_index];
    destination_chunk->mineral_signature[destination_index] = source_chunk.mineral_signature[source_index];
    destination_chunk->flags[destination_index] = static_cast<uint8_t>((source_chunk.flags[source_index] & ~MOVED_FLAG) | MOVED_FLAG);
    if (source_amount < 255) ensure_liquid_plane(*destination_chunk);
    if (destination_chunk->material_amount != nullptr) (*destination_chunk->material_amount)[destination_index] = static_cast<uint8_t>(source_amount);
    if (source_phase_energy > 0) ensure_phase_energy_plane(*destination_chunk);
    if (destination_chunk->phase_energy != nullptr) (*destination_chunk->phase_energy)[destination_index] = source_phase_energy;
    if (source_moisture > 0) ensure_moisture_plane(*destination_chunk);
    if (destination_chunk->organic_moisture != nullptr) (*destination_chunk->organic_moisture)[destination_index] = source_moisture;
    if (source_reaction_progress > 0 || source_reaction_state > 0) ensure_reaction_planes(*destination_chunk);
    if (destination_chunk->reaction_progress != nullptr) (*destination_chunk->reaction_progress)[destination_index] = source_reaction_progress;
    if (destination_chunk->reaction_state != nullptr) (*destination_chunk->reaction_state)[destination_index] = source_reaction_state;
    if (structure == STRUCTURE_SIEVE && source_material == SAND_ID) {
        destination_chunk->material[destination_index] = FINE_SAND_ID;
        ++result.screen_passes;
    }
    source_chunk.material[source_index] = EMPTY_ID;
    source_chunk.temperature[source_index] = TEMPERATURE_AMBIENT;
    source_chunk.provenance[source_index] = 0;
    source_chunk.mineral_signature[source_index] = 0;
    source_chunk.flags[source_index] = 0;
    if (source_chunk.material_amount != nullptr) (*source_chunk.material_amount)[source_index] = 0;
    if (source_chunk.phase_energy != nullptr) (*source_chunk.phase_energy)[source_index] = 0;
    if (source_chunk.organic_moisture != nullptr) (*source_chunk.organic_moisture)[source_index] = 0;
    if (source_chunk.reaction_progress != nullptr) (*source_chunk.reaction_progress)[source_index] = 0;
    if (source_chunk.reaction_state != nullptr) (*source_chunk.reaction_state)[source_index] = 0;
    // reactive_cells_ is a shared unordered_set. Granular jobs run in parallel, so defer both
    // cells to the serial barrier commit instead of mutating the container from worker threads.
    //
    // Only cells whose reactive status can actually change are worth deferring. A cell enters
    // reactive_cells_ only if its material is reactive or it carries bound water, so when
    // neither the material leaving nor the material arriving qualifies, the erase finds
    // nothing and the re-activation inserts nothing: the whole notification is a provable
    // no-op. It was not free, though. Every notification cost two hash-set erases and two
    // chunk-map lookups on the serial barrier, and a wall of falling Sand moves a cell per
    // cell per tick -- a million moves meant four million serial map operations that no
    // subsystem ever read. That is the whole of why a million active Sand cells cost roughly
    // five times what a million active Water cells cost, for the same number of cells visited.
    if (reactive_state_possible(source_material, source_moisture) ||
        reactive_state_possible(destination_material, destination_moisture)) {
        result.reactive_cells_changed.push_back(source);
        result.reactive_cells_changed.push_back(destination);
    }
    ++source_chunk.revision;
    ++destination_chunk->revision;
    source_chunk.moved_this_tick = destination_chunk->moved_this_tick = true;
    source_chunk.pristine = destination_chunk->pristine = false;
    const Vector2i source_local = world_to_local(source);
    const Vector2i destination_local = world_to_local(destination);
    source_chunk.next_active.include(source_local.x, source_local.y, 1);
    destination_chunk->next_active.include(destination_local.x, destination_local.y, 1);
    source_chunk.render_dirty.include(source_local.x, source_local.y, 1);
    destination_chunk->render_dirty.include(destination_local.x, destination_local.y, 1);
    if (collect_changes) { result.changed_cells.push_back(source); result.changed_cells.push_back(destination); }
    ++result.moved;
    if (world_to_chunk(source) != world_to_chunk(destination)) ++result.border;
    return true;
}

void NativeSandWorld::process_granular_chunk(Chunk &chunk, const Bounds &bounds, MatterJobResult &result, bool collect_changes) {
    const bool left_to_right = (tick_index_ & 1) == 0;
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t local_y = bounds.max_y; local_y >= bounds.min_y; --local_y) {
        const int32_t first = left_to_right ? bounds.min_x : bounds.max_x;
        const int32_t last = left_to_right ? bounds.max_x + 1 : bounds.min_x - 1;
        const int32_t stride = left_to_right ? 1 : -1;
        for (int32_t local_x = first; local_x != last; local_x += stride) {
            ++result.visited;
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            if (!material_transportable(chunk.material[index]) || (chunk.flags[index] & MOVED_FLAG) != 0) continue;
            if ((chunk.material[index] == WOOD_ID || chunk.material[index] == LEAVES_ID) &&
                (chunk.flags[index] & ORGANIC_LOOSE_FLAG) == 0) continue;
            const Vector2i source = origin + Vector2i(local_x, local_y);
            if (!physical_processors_.empty() && magnetic_capture_supports(source)) continue;
            const Vector2i down = source + Vector2i(0, 1);
            if (move_granular_fast(chunk, index, source, down, result, collect_changes)) continue;
            const bool prefer_left = (hash_2d(seed_, source, static_cast<int32_t>(tick_index_)) & 1u) == 0u;
            const Vector2i first_diagonal = source + (prefer_left ? Vector2i(-1, 1) : Vector2i(1, 1));
            if (move_granular_fast(chunk, index, source, first_diagonal, result, collect_changes)) continue;
            const Vector2i second_diagonal = source + (prefer_left ? Vector2i(1, 1) : Vector2i(-1, 1));
            move_granular_fast(chunk, index, source, second_diagonal, result, collect_changes);
        }
    }
}

void NativeSandWorld::process_granular_parallel(const std::vector<Chunk *> &active_chunks) {
    const auto started = std::chrono::steady_clock::now();
    const bool collect_changes = should_collect_matter_changes();
    last_movements_ = last_cells_visited_ = last_granular_barrier_usec_ = 0;
    last_simulation_workers_used_ = 0;
    for (int32_t color = 0; color < 9; ++color) {
        std::vector<Chunk *> jobs;
        std::vector<Bounds> bounds;
        for (Chunk *chunk : active_chunks) {
            const int32_t color_x = ((chunk->coordinate.x % 3) + 3) % 3;
            const int32_t color_y = ((chunk->coordinate.y % 3) + 3) % 3;
            if (color_y * 3 + color_x == color) { jobs.push_back(chunk); bounds.push_back(chunk->active); }
        }
        std::vector<MatterJobResult> results(jobs.size());
        simulation_executor_->run(static_cast<int32_t>(jobs.size()), [&](int32_t index, int32_t) {
            process_granular_chunk(*jobs[index], bounds[index], results[index], collect_changes);
        });
        last_granular_barrier_usec_ += static_cast<int64_t>(simulation_executor_->wait_ns_last_run() / 1000);
        last_simulation_workers_used_ = std::max(last_simulation_workers_used_, simulation_executor_->workers_used_last_run());
        const auto commit_started = std::chrono::steady_clock::now();
        apply_matter_notifications(results);
        last_matter_commit_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - commit_started).count();
        for (const MatterJobResult &result : results) {
            last_movements_ += result.moved;
            last_cells_visited_ += result.visited;
            last_fluid_displacements_ += result.displaced;
            last_fluid_mass_transferred_ += result.mass_transferred;
            last_screen_passes_ += result.screen_passes;
            total_screen_passes_ += result.screen_passes;
        }
    }
    last_granular_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::process_fluid_chunk(Chunk &chunk, const FluidActivity &activity, MatterJobResult &result, bool collect_changes) {
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t local_y = CHUNK_SIZE - 1; local_y >= 0; --local_y) {
        if ((activity.rows & (uint64_t{1} << local_y)) == 0) continue;
        const bool left_to_right = ((tick_index_ + local_y) & 1) == 0;
        const int32_t first = left_to_right ? activity.min_x[local_y] : activity.max_x[local_y];
        const int32_t last = left_to_right ? activity.max_x[local_y] + 1 : activity.min_x[local_y] - 1;
        const int32_t stride = left_to_right ? 1 : -1;
        for (int32_t local_x = first; local_x != last; local_x += stride) {
            ++result.visited;
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            const int32_t material = chunk.material[index];
            if (!is_mobile_material(material)) continue;
            ++result.active;
            if (is_gas_material(material)) { ++result.gas_active; ++result.gas_visited; }
            if ((chunk.flags[index] & MOVED_FLAG) != 0) continue;
            const int32_t mobility = thermal_material_definitions()[material].mobility;
            const int32_t cadence = material == WATER_ID || is_gas_material(material) ? 1 : std::max(1, 32 / std::max(1, mobility));
            if (tick_index_ % cadence != 0) continue;
            const Vector2i source = origin + Vector2i(local_x, local_y);
            const int32_t source_mass = material_amount_at(chunk, index);
            const int32_t vertical_sign = is_gas_material(material) ? -1 : 1;
            auto transfer = [&](Vector2i destination, int32_t requested, bool primary) {
                const int32_t destination_x = destination.x - origin.x;
                const int32_t destination_y = destination.y - origin.y;
                if (static_cast<uint32_t>(destination_x) < CHUNK_SIZE && static_cast<uint32_t>(destination_y) < CHUNK_SIZE) {
                    return transfer_mobile_material_indexed(chunk, index, source, chunk,
                            destination_y * CHUNK_SIZE + destination_x, destination, requested, result, primary, collect_changes);
                }
                return material == WATER_ID ? transfer_water(source, destination, requested, result, primary, collect_changes)
                                            : transfer_mobile_material(source, destination, requested, result, primary, collect_changes);
            };
            auto compatible_amount = [&](Vector2i destination) {
                const int32_t destination_x = destination.x - origin.x;
                const int32_t destination_y = destination.y - origin.y;
                if (static_cast<uint32_t>(destination_x) < CHUNK_SIZE && static_cast<uint32_t>(destination_y) < CHUNK_SIZE) {
                    const int32_t destination_index = destination_y * CHUNK_SIZE + destination_x;
                    if (structures_allocated_ > 0 && is_structure_solid(destination)) return 255;
                    const int32_t destination_material = chunk.material[destination_index];
                    if (destination_material == EMPTY_ID) return 0;
                    return destination_material == material ? material_amount_at(chunk, destination_index) : 255;
                }
                if (material == WATER_ID ? !fluid_destination_available(destination) : !mobile_destination_available(destination, material)) return 255;
                return get_cell(destination) == material ? material_amount_at(destination) : 0;
            };
            const Vector2i vertical = source + Vector2i(0, vertical_sign);
            if (is_gas_material(material)) ++result.gas_vertical_attempts;
            if (transfer(vertical, source_mass, true) > 0) continue;
            const bool prefer_left = (hash_2d(seed_, source, static_cast<int32_t>(tick_index_) ^ 0x77d1) & 1u) == 0u;
            const Vector2i diagonal_a = source + (prefer_left ? Vector2i(-1, vertical_sign) : Vector2i(1, vertical_sign));
            if (is_gas_material(material)) ++result.gas_diagonal_attempts;
            if (transfer(diagonal_a, source_mass, true) > 0) continue;
            const Vector2i diagonal_b = source + (prefer_left ? Vector2i(1, vertical_sign) : Vector2i(-1, vertical_sign));
            if (is_gas_material(material)) ++result.gas_diagonal_attempts;
            if (transfer(diagonal_b, source_mass, true) > 0) continue;
            const Vector2i side_a = source + (prefer_left ? Vector2i(-1, 0) : Vector2i(1, 0));
            const Vector2i side_b = source + (prefer_left ? Vector2i(1, 0) : Vector2i(-1, 0));
            bool moved = false;
            for (const Vector2i side : {side_a, side_b}) {
                if (is_gas_material(material)) ++result.gas_lateral_attempts;
                const int32_t side_amount = compatible_amount(side);
                const int32_t difference = source_mass - side_amount;
                if (difference <= 2) continue;
                if (transfer(side, difference / 2, false) > 0) { moved = true; break; }
            }
            if (!moved) ++result.blocked;
        }
    }
}

void NativeSandWorld::process_fluid_parallel() {
    const auto started = std::chrono::steady_clock::now();
    const auto schedule_started = started;
    std::vector<Chunk *> active;
    for (Chunk *chunk : sorted_chunks()) if (chunk->fluid_active.valid()) {
        chunk->fluid_next_active.clear();
        chunk->fluid_moved_this_tick = false;
        active.push_back(chunk);
    }
    last_fluid_schedule_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - schedule_started).count();
    const bool collect_changes = should_collect_matter_changes();
    for (int32_t color = 0; color < 9; ++color) {
        const auto color_schedule_started = std::chrono::steady_clock::now();
        std::vector<Chunk *> jobs;
        std::vector<FluidActivity> activity;
        for (Chunk *chunk : active) {
            const int32_t color_x = ((chunk->coordinate.x % 3) + 3) % 3;
            const int32_t color_y = ((chunk->coordinate.y % 3) + 3) % 3;
            if (color_y * 3 + color_x == color) { jobs.push_back(chunk); activity.push_back(chunk->fluid_active); }
        }
        last_fluid_schedule_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - color_schedule_started).count();
        std::vector<MatterJobResult> results(jobs.size());
        const auto traversal_started = std::chrono::steady_clock::now();
        simulation_executor_->run(static_cast<int32_t>(jobs.size()), [&](int32_t index, int32_t worker_index) {
            const auto job_started = std::chrono::steady_clock::now();
            results[index].worker_index = worker_index;
            process_fluid_chunk(*jobs[index], activity[index], results[index], collect_changes);
            results[index].work_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - job_started).count();
        });
        last_fluid_traversal_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - traversal_started).count();
        last_fluid_barrier_usec_ += static_cast<int64_t>(simulation_executor_->wait_ns_last_run() / 1000);
        last_simulation_workers_used_ = std::max(last_simulation_workers_used_, simulation_executor_->workers_used_last_run());
        const auto commit_started = std::chrono::steady_clock::now();
        apply_matter_notifications(results);
        const int64_t commit_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - commit_started).count();
        last_matter_commit_usec_ += commit_usec;
        last_fluid_commit_profile_usec_ += commit_usec;
        for (const MatterJobResult &result : results) {
            last_fluid_cells_active_ += result.active;
            last_fluid_cells_visited_ += result.visited;
            last_fluid_transfers_ += result.transfers;
            last_fluid_mass_transferred_ += result.mass_transferred;
            last_fluid_downward_ += result.downward;
            last_fluid_lateral_ += result.lateral;
            last_fluid_blocked_ += result.blocked;
            last_fluid_border_crossings_ += result.border;
            last_gas_active_ += result.gas_active;
            last_gas_visited_ += result.gas_visited;
            last_gas_transfers_ += result.gas_transfers;
            last_gas_mass_transferred_ += result.gas_mass_transferred;
            last_gas_vertical_attempts_ += result.gas_vertical_attempts;
            last_gas_diagonal_attempts_ += result.gas_diagonal_attempts;
            last_gas_lateral_attempts_ += result.gas_lateral_attempts;
            last_gas_local_transfers_ += result.gas_local_transfers;
            last_gas_cross_chunk_transfers_ += result.gas_cross_chunk_transfers;
            const int32_t worker = std::clamp(result.worker_index, 0, 7);
            ++last_fluid_worker_jobs_[worker];
            last_fluid_worker_cells_[worker] += result.visited;
            last_fluid_worker_usec_[worker] += result.work_usec;
            thermal_rounding_reservoir_ += result.enthalpy_rounding;
        }
    }
    const auto settle_started = std::chrono::steady_clock::now();
    for (Chunk *chunk : active) {
        if (chunk->fluid_moved_this_tick) {
            chunk->fluid_plane_quiet_ticks = 0;
            chunk->fluid_next_active.merge(chunk->fluid_active);
            chunk->fluid_active = chunk->fluid_next_active;
        } else {
            ++chunk->fluid_plane_quiet_ticks;
            if (chunk->fluid_plane_quiet_ticks < 2) chunk->fluid_next_active.merge(chunk->fluid_active);
            else ++last_fluid_sleep_transitions_;
            chunk->fluid_active = chunk->fluid_next_active;
        }
        chunk->fluid_next_active.clear();
    }
    for (Chunk *chunk : sorted_chunks()) if (chunk->fluid_next_active.valid()) {
        chunk->fluid_active.merge(chunk->fluid_next_active);
        chunk->fluid_plane_quiet_ticks = 0;
        chunk->fluid_next_active.clear();
    }
    release_redundant_liquid_planes();
    last_fluid_settle_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - settle_started).count();
    last_fluid_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    last_gas_usec_ = last_gas_visited_ > 0 ? last_fluid_usec_ : 0;
}

void NativeSandWorld::release_redundant_liquid_planes() {
    // Reclaiming a liquid plane needs the chunk to have been quiet for 120 ticks, so asking
    // every tick walks the whole map 119 times to reach the same answer. At a sixteenth of the
    // quiet threshold the memory comes back within eight ticks of when it used to, and the
    // other fifteen walks are gone.
    if ((tick_index_ % 8) != 0) return;
    for (Chunk *chunk : sorted_chunks()) {
        if (chunk->material_amount == nullptr || chunk->fluid_active.valid() || chunk->fluid_plane_quiet_ticks < 120) continue;
        bool redundant = true;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const uint8_t expected = chunk->material[index] == EMPTY_ID ? 0 : 255;
            if ((*chunk->material_amount)[index] != expected) { redundant = false; break; }
        }
        if (redundant) chunk->material_amount.reset();
    }
}

// The only place an exception can leave the simulation and reach Godot.
//
// C++ that throws through a GDExtension boundary calls std::terminate: the process vanishes
// without an engine error, a log line or a crash dialog, so a player sees nothing but a closed
// window and has nothing to send back. The registries this tick walks are keyed by ids written
// by fifteen different subsystems, and one stale id is all it takes. Record the reason, tell
// Godot's error stream so it reaches user://logs/godot.log, and stop simulating -- a frozen
// world the player can still read, save and report beats a process that is simply gone.
int32_t NativeSandWorld::step() {
    if (faulted_) return 0;
    try {
        return step_simulation();
    } catch (const std::exception &error) {
        enter_fault("step", error.what());
    } catch (...) {
        enter_fault("step", "unknown exception");
    }
    return 0;
}

void NativeSandWorld::inject_step_fault_for_test() {
    inject_fault_for_test_ = true;
}

void NativeSandWorld::enter_fault(const char *stage, const char *detail) {
    faulted_ = true;
    fault_message_ = String("Simulation stopped in ") + String(stage) + String(": ") + String(detail) +
        String(" (tick ") + String::num_int64(static_cast<int64_t>(tick_index_)) + String(")");
    UtilityFunctions::push_error(fault_message_);
}

bool NativeSandWorld::is_faulted() const {
    return faulted_;
}

String NativeSandWorld::get_fault_message() const {
    return fault_message_;
}

int32_t NativeSandWorld::step_simulation() {
    // The guard above is only worth having if it is exercised; this is how the test throws.
    if (inject_fault_for_test_) {
        inject_fault_for_test_ = false;
        throw std::runtime_error("injected simulation fault");
    }
    last_screen_passes_ = 0;
    last_thermal_source_energy_ = 0;
    last_gas_active_ = last_gas_visited_ = last_gas_transfers_ = last_gas_mass_transferred_ = last_gas_usec_ = 0;
    last_fluid_cells_active_ = last_fluid_cells_visited_ = last_fluid_transfers_ = last_fluid_mass_transferred_ = 0;
    last_fluid_downward_ = last_fluid_lateral_ = last_fluid_displacements_ = last_fluid_blocked_ = 0;
    last_fluid_wake_transitions_ = last_fluid_sleep_transitions_ = last_fluid_border_crossings_ = 0;
    last_fluid_barrier_usec_ = 0;
    last_fluid_schedule_usec_ = last_fluid_traversal_usec_ = last_fluid_commit_profile_usec_ = last_fluid_settle_usec_ = 0;
    last_gas_vertical_attempts_ = last_gas_diagonal_attempts_ = last_gas_lateral_attempts_ = 0;
    last_gas_local_transfers_ = last_gas_cross_chunk_transfers_ = 0;
    last_fluid_worker_jobs_.fill(0); last_fluid_worker_cells_.fill(0); last_fluid_worker_usec_.fill(0);
    last_matter_commit_usec_ = 0;
    std::vector<Chunk *> active_chunks;
    for (Chunk *chunk : sorted_chunks()) {
        if (!chunk->active.valid()) {
            continue;
        }
        chunk->next_active.clear();
        chunk->moved_this_tick = false;
        active_chunks.push_back(chunk);
    }
    std::sort(active_chunks.begin(), active_chunks.end(), [this](const Chunk *a, const Chunk *b) {
        if (a->coordinate.y != b->coordinate.y) {
            return a->coordinate.y > b->coordinate.y;
        }
        return (tick_index_ & 1) == 0 ? a->coordinate.x < b->coordinate.x : a->coordinate.x > b->coordinate.x;
    });
    // Fluid-active chunks that granular movement did not already claim.
    //
    // This used to ask std::find whether each candidate was already in movement_chunks, which
    // is a linear scan of a list that grows with the world: a wet world with a thousand active
    // chunks paid half a million pointer comparisons a tick to answer a question the chunk can
    // answer about itself. active_chunks was just built from exactly the chunks whose active
    // bitmap is valid, so that is the test.
    std::vector<Chunk *> movement_chunks = active_chunks;
    for (Chunk *chunk : sorted_chunks())
        if (chunk->fluid_active.valid() && !chunk->active.valid()) movement_chunks.push_back(chunk);
    clear_movement_flags(movement_chunks);
    request_simulation_halo(active_chunks);

    last_cells_skipped_ = static_cast<int64_t>(active_chunks.size()) * CELLS_PER_CHUNK;
    last_active_rectangles_ = static_cast<int32_t>(active_chunks.size());
    process_granular_parallel(active_chunks);

    for (Chunk *chunk : active_chunks) {
        if (chunk->moved_this_tick) {
            chunk->stable_ticks = 0;
            chunk->next_active.merge(chunk->active);
            chunk->active = chunk->next_active;
        } else {
            ++chunk->stable_ticks;
            if (chunk->stable_ticks < SLEEP_TICKS) {
                chunk->next_active.merge(chunk->active);
            }
            chunk->active = chunk->next_active;
        }
    }
    for (Chunk *chunk : sorted_chunks()) {
        if (chunk->moved_this_tick && !chunk->active.valid() && chunk->next_active.valid()) {
            chunk->active = chunk->next_active;
            chunk->stable_ticks = 0;
        }
        chunk->next_active.clear();
    }

    for (Chunk *chunk : sorted_chunks()) if (chunk->fluid_next_active.valid()) {
        chunk->fluid_active.merge(chunk->fluid_next_active);
        chunk->fluid_next_active.clear();
    }
    process_fluid_parallel();
    process_pipe_fluid();
    process_subsurface_logistics();

    process_physical_fields();
    process_vibrating_screens();
    process_physical_heaters();
    process_thermodynamics();
    process_organic_physics();
    process_wet_sluices();
    process_component_processing();
    process_conveyors();
    process_machines();
    process_power();
    process_automation();
    update_milestones();
    for (Chunk *chunk : sorted_chunks()) {
        if (chunk->next_active.valid()) {
            chunk->active.merge(chunk->next_active);
            chunk->stable_ticks = 0;
            chunk->next_active.clear();
        }
    }

    last_cells_skipped_ -= last_cells_visited_;
    ++tick_index_;
    return static_cast<int32_t>(last_movements_);
}

int32_t NativeSandWorld::chunk_count() const {
    return static_cast<int32_t>(chunks_.size());
}

int32_t NativeSandWorld::active_chunk_count() const {
    int32_t result = 0;
    for (const auto &[key, chunk] : chunks_) {
        (void)key;
        result += chunk->active.valid() ? 1 : 0;
    }
    return result;
}

int32_t NativeSandWorld::sleeping_chunk_count() const {
    return chunk_count() - active_chunk_count();
}

int64_t NativeSandWorld::total_allocated_cells() const {
    return static_cast<int64_t>(chunks_.size()) * CELLS_PER_CHUNK;
}

int64_t NativeSandWorld::simulation_backing_bytes() const {
    return total_allocated_cells() * (sizeof(uint16_t) + sizeof(uint16_t) + sizeof(uint8_t) + sizeof(uint16_t) + sizeof(uint16_t));
}

int64_t NativeSandWorld::presentation_backing_bytes() const {
    return total_allocated_cells() * 4;
}

int32_t NativeSandWorld::get_worker_count() const {
    return worker_count_;
}

Array NativeSandWorld::get_chunk_coordinates() const {
    Array result;
    for (const Chunk *chunk : sorted_chunks()) {
        result.push_back(chunk->coordinate);
    }
    return result;
}

Dictionary NativeSandWorld::get_chunk_state(Vector2i coordinate) const {
    Dictionary result;
    const Chunk *chunk = get_chunk(coordinate);
    if (chunk == nullptr) {
        return result;
    }
    result["active"] = chunk->active.valid();
    result["sleeping"] = !chunk->active.valid();
    result["dirty"] = chunk->render_dirty.valid();
    result["active_area"] = chunk->active.area();
    result["revision"] = static_cast<int64_t>(chunk->revision);
    result["generated"] = chunk->generated;
    result["pristine"] = chunk->pristine;
    result["modified"] = !chunk->pristine;
    result["generation_state"] = 2;
    return result;
}

int64_t NativeSandWorld::get_tick() const {
    return tick_index_;
}

// The handful of per-frame counters, without walking anything.
//
// get_statistics() assembles the full diagnostic picture: it walks every chunk itself and then
// merges in the fluid, generation, structure, pipe and wet-processing dictionaries, several of
// which walk the chunk map again. On a world with 1600 resident chunks one call measured
// 5.70 ms. The renderer called it every frame for two pixel counters and the audio mixer called
// it for one movement count, so a settled world spent most of a frame budget assembling
// diagnostics nobody was reading.
Dictionary NativeSandWorld::get_frame_counters() const {
    Dictionary result;
    result["tick"] = tick_index_;
    result["cells_moved"] = last_movements_;
    result["cells_visited"] = last_cells_visited_;
    result["dirty_render_pixels"] = last_dirty_render_pixels_;
    result["render_upload_pixels"] = last_render_upload_pixels_;
    return result;
}

// One walk, not three.
//
// This used to compute active_region_cells in its own loop, then call active_chunk_count(),
// then sleeping_chunk_count() -- which is chunk_count() minus active_chunk_count() and so walks
// the map a third time. Every chunk is a multi-kilobyte object, so each walk is a cache miss per
// chunk, and GDScript called this several times a frame just to read "tick": once per brush
// stroke in _submit_brush_batch() and once per placement in _submit_world_command(). On a world
// with 1600 resident chunks that was over a millisecond of the main thread per paint event, on
// the exact path the frame-rate collapse was reported on. get_tick() exists for the callers that
// only wanted the number.
Dictionary NativeSandWorld::get_statistics() const {
    Dictionary result;
    int64_t active_region_cells = 0;
    int32_t active_chunks = 0;
    for (const auto &[key, chunk] : chunks_) {
        (void)key;
        // area() is already zero for an invalid region, so this is the same sum as before.
        active_region_cells += chunk->active.area();
        active_chunks += chunk->active.valid() ? 1 : 0;
    }
    result["tick"] = tick_index_;
    result["active_chunks"] = active_chunks;
    result["sleeping_chunks"] = chunk_count() - active_chunks;
    result["allocated_chunks"] = chunk_count();
    result["allocated_cells"] = total_allocated_cells();
    result["simulation_backing_bytes"] = simulation_backing_bytes();
    result["presentation_backing_bytes"] = presentation_backing_bytes();
    result["active_rectangles"] = last_active_rectangles_;
    result["active_region_cells"] = active_region_cells;
    result["cells_visited"] = last_cells_visited_;
    result["cells_skipped"] = last_cells_skipped_;
    result["cells_moved"] = last_movements_;
    result["dirty_render_pixels"] = last_dirty_render_pixels_;
    result["render_upload_pixels"] = last_render_upload_pixels_;
    result["worker_count"] = get_worker_count();
    result["worker_utilization_percent"] = worker_count_ > 0 ?
        100.0 * static_cast<double>(last_render_workers_used_) / static_cast<double>(worker_count_) : 0.0;
    result["simulation_workers_used"] = last_simulation_workers_used_;
    result["simulation_worker_utilization_percent"] = worker_count_ > 0 ?
        100.0 * static_cast<double>(last_simulation_workers_used_) / static_cast<double>(worker_count_) : 0.0;
    result["granular_usec"] = last_granular_usec_;
    result["granular_barrier_usec"] = last_granular_barrier_usec_;
    result["phase_barrier_usec"] = last_granular_barrier_usec_ + last_fluid_barrier_usec_;
    result["parallel_work_usec"] = std::max<int64_t>(0, last_granular_usec_ + last_fluid_usec_ -
        last_granular_barrier_usec_ - last_fluid_barrier_usec_ - last_matter_commit_usec_);
    result["serial_commit_usec"] = last_matter_commit_usec_;
    result["border_intents"] = 0;
    const Dictionary fluids = get_fluid_statistics();
    for (const Variant &key : fluids.keys()) result[key] = fluids[key];
    const Dictionary generation = get_generation_statistics();
    result["generation_workers"] = generation["workers"];
    result["generation_queue"] = generation["queued"];
    result["generation_in_flight"] = generation["in_flight"];
    result["generation_completed"] = generation["completed"];
    result["chunks_published_last_frame"] = generation["published_last_frame"];
    const Dictionary structures = get_structure_statistics();
    for (const Variant &key : structures.keys()) result[key] = structures[key];
    const Dictionary pipes = get_pipe_statistics();
    for (const Variant &key : pipes.keys()) result[String("pipe_") + String(key)] = pipes[key];
    const Dictionary wet = get_wet_processing_statistics();
    for (const Variant &key : wet.keys()) result[String("wet_") + String(key)] = wet[key];
    return result;
}

Dictionary NativeSandWorld::get_fluid_statistics() const {
    int64_t planes = 0;
    int64_t bearing_chunks = 0;
    int64_t active_rows = 0;
    int64_t active_spans = 0;
    for (const Chunk *chunk : sorted_chunks()) {
        planes += chunk->material_amount != nullptr ? 1 : 0;
        bool bearing = false;
        for (int32_t index = 0; index < CELLS_PER_CHUNK && !bearing; ++index) bearing = chunk->material[index] == WATER_ID;
        bearing_chunks += bearing ? 1 : 0;
        for (int32_t row = 0; row < CHUNK_SIZE; ++row) if ((chunk->fluid_active.rows & (uint64_t{1} << row)) != 0) {
            ++active_rows;
            ++active_spans;
        }
    }
    Dictionary result;
    result["fluid_mass_total"] = get_total_water_mass();
    result["fluid_bearing_chunks"] = bearing_chunks;
    result["fluid_plane_chunks"] = planes;
    result["fluid_plane_bytes"] = planes * CELLS_PER_CHUNK;
    result["fluid_activity_bytes"] = static_cast<int64_t>(chunks_.size()) * 136;
    result["fluid_cells_active"] = last_fluid_cells_active_;
    result["fluid_cells_visited"] = last_fluid_cells_visited_;
    result["fluid_transfers"] = last_fluid_transfers_;
    result["fluid_mass_transferred"] = last_fluid_mass_transferred_;
    result["fluid_downward_transfers"] = last_fluid_downward_;
    result["fluid_lateral_transfers"] = last_fluid_lateral_;
    result["fluid_sand_displacements"] = last_fluid_displacements_;
    result["fluid_blocked"] = last_fluid_blocked_;
    result["fluid_border_crossings"] = last_fluid_border_crossings_;
    result["fluid_wake_transitions"] = last_fluid_wake_transitions_;
    result["fluid_sleep_transitions"] = last_fluid_sleep_transitions_;
    result["fluid_active_rows"] = active_rows;
    result["fluid_active_spans"] = active_spans;
    result["fluid_usec"] = last_fluid_usec_;
    result["fluid_barrier_usec"] = last_fluid_barrier_usec_;
    result["fluid_schedule_usec"] = last_fluid_schedule_usec_;
    result["fluid_traversal_usec"] = last_fluid_traversal_usec_;
    result["fluid_commit_usec"] = last_fluid_commit_profile_usec_;
    result["fluid_settle_usec"] = last_fluid_settle_usec_;
    Array worker_jobs, worker_cells, worker_usec;
    for (int32_t worker = 0; worker < 8; ++worker) {
        worker_jobs.push_back(last_fluid_worker_jobs_[worker]);
        worker_cells.push_back(last_fluid_worker_cells_[worker]);
        worker_usec.push_back(last_fluid_worker_usec_[worker]);
    }
    result["fluid_worker_jobs"] = worker_jobs;
    result["fluid_worker_cells"] = worker_cells;
    result["fluid_worker_usec"] = worker_usec;
    result["fluid_render_revision"] = static_cast<int64_t>(fluid_render_revision_);
    return result;
}

Dictionary NativeSandWorld::get_fluid_render_page(Rect2i chunk_area) const {
    Dictionary result;
    Vector2i end;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 || !checked_rect_end(chunk_area, 4096, end)) return result;
    const int32_t width = chunk_area.size.x * CHUNK_SIZE;
    const int32_t height = chunk_area.size.y * CHUNK_SIZE;
    PackedByteArray pixels;
    pixels.resize(width * height);
    for (int32_t chunk_y = 0; chunk_y < chunk_area.size.y; ++chunk_y) {
        for (int32_t chunk_x = 0; chunk_x < chunk_area.size.x; ++chunk_x) {
            const Chunk *chunk = get_chunk(chunk_area.position + Vector2i(chunk_x, chunk_y));
            if (chunk == nullptr) continue;
            for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
                const int32_t source_index = local_y * CHUNK_SIZE + local_x;
                const int32_t destination_index = (chunk_y * CHUNK_SIZE + local_y) * width + chunk_x * CHUNK_SIZE + local_x;
                pixels[destination_index] = static_cast<uint8_t>(water_mass_at(*chunk, source_index));
            }
        }
    }
    result["chunk_area"] = chunk_area;
    result["cell_position"] = chunk_area.position * CHUNK_SIZE;
    result["width"] = width;
    result["height"] = height;
    result["pixels"] = pixels;
    result["bytes"] = static_cast<int64_t>(pixels.size());
    result["revision"] = static_cast<int64_t>(fluid_render_revision_);
    return result;
}

Dictionary NativeSandWorld::get_temperature_sample(Rect2i cell_area, int32_t stride) const {
    Dictionary result;
    PackedInt32Array samples;
    Vector2i end;
    if (cell_area.size.x <= 0 || cell_area.size.y <= 0 || !checked_rect_end(cell_area, 16'777'216, end)) { result["samples"] = samples; return result; }
    stride = std::clamp(stride, 1, 64);
    for (int32_t y = cell_area.position.y; y < end.y; y += stride) for (int32_t x = cell_area.position.x; x < end.x; x += stride) {
        const Chunk *chunk = get_chunk(world_to_chunk({x, y}));
        if (chunk == nullptr) continue;
        const int32_t temperature = chunk->temperature[local_index(world_to_local({x, y}))];
        if (temperature == TEMPERATURE_AMBIENT && get_cell({x, y}) == EMPTY_ID) continue;
        samples.push_back(x);
        samples.push_back(y);
        samples.push_back(temperature);
    }
    result["samples"] = samples;
    result["stride"] = stride;
    return result;
}

Dictionary NativeSandWorld::get_temperature_render_page(Rect2i chunk_area) const {
    Dictionary result;
    Vector2i end;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 || !checked_rect_end(chunk_area, 4096, end)) return result;
    const int32_t width = chunk_area.size.x * CHUNK_SIZE;
    const int32_t height = chunk_area.size.y * CHUNK_SIZE;
    PackedByteArray pixels;
    pixels.resize(width * height * 2);
    uint8_t *bytes = pixels.ptrw();
    std::fill(bytes, bytes + pixels.size(), uint8_t{0});
    for (int32_t chunk_y = 0; chunk_y < chunk_area.size.y; ++chunk_y) {
        for (int32_t chunk_x = 0; chunk_x < chunk_area.size.x; ++chunk_x) {
            const Chunk *chunk = get_chunk(chunk_area.position + Vector2i(chunk_x, chunk_y));
            if (chunk == nullptr) continue;
            for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
                const int32_t source = local_y * CHUNK_SIZE + local_x;
                const int32_t destination = ((chunk_y * CHUNK_SIZE + local_y) * width + chunk_x * CHUNK_SIZE + local_x) * 2;
                const uint16_t temperature = chunk->temperature[source];
                bytes[destination] = static_cast<uint8_t>(temperature & 0xffu);
                bytes[destination + 1] = static_cast<uint8_t>(temperature >> 8u);
            }
        }
    }
    result["chunk_area"] = chunk_area;
    result["cell_position"] = chunk_area.position * CHUNK_SIZE;
    result["width"] = width;
    result["height"] = height;
    result["pixels"] = pixels;
    result["bytes"] = static_cast<int64_t>(pixels.size());
    return result;
}

bool NativeSandWorld::is_inside_virtual_world(Vector2i world_cell) const {
    const int32_t half_width = world_settings_.width / 2;
    return world_cell.x >= -half_width && world_cell.x < -half_width + world_settings_.width &&
           world_cell.y >= -world_settings_.sky && world_cell.y < world_settings_.depth;
}

bool NativeSandWorld::is_chunk_in_virtual_world(Vector2i coordinate) const {
    const int64_t first_x = static_cast<int64_t>(coordinate.x) * CHUNK_SIZE;
    const int64_t first_y = static_cast<int64_t>(coordinate.y) * CHUNK_SIZE;
    const int64_t last_x = first_x + CHUNK_SIZE - 1;
    const int64_t last_y = first_y + CHUNK_SIZE - 1;
    const int64_t half_width = world_settings_.width / 2;
    return last_x >= -half_width && first_x < -half_width + world_settings_.width &&
           last_y >= -world_settings_.sky && first_y < world_settings_.depth;
}

void NativeSandWorld::configure_world(Dictionary settings, int32_t generation_workers) {
    stop_generation_workers();
    const int32_t hardware = static_cast<int32_t>(std::max(1u, std::thread::hardware_concurrency()));
    const int32_t requested_simulation_workers = simulation_executor_ == nullptr ? std::clamp(hardware - 1, 1, 8) : worker_count_;
    stop_workers();
    configure_workers(requested_simulation_workers);
    clear_world_state();

    if (settings.has("seed")) seed_ = static_cast<int64_t>(settings["seed"]);
    if (settings.has("width")) world_settings_.width = static_cast<int32_t>(settings["width"]);
    if (settings.has("depth")) world_settings_.depth = static_cast<int32_t>(settings["depth"]);
    if (settings.has("sky")) world_settings_.sky = static_cast<int32_t>(settings["sky"]);
    if (settings.has("surface_baseline")) world_settings_.surface_baseline = static_cast<int32_t>(settings["surface_baseline"]);
    if (settings.has("surface_amplitude")) world_settings_.surface_amplitude = static_cast<int32_t>(settings["surface_amplitude"]);
    if (settings.has("sediment_depth")) world_settings_.sediment_depth = static_cast<int32_t>(settings["sediment_depth"]);
    if (settings.has("cave_density")) world_settings_.cave_density = static_cast<double>(settings["cave_density"]);
    if (settings.has("coal_frequency")) world_settings_.coal_frequency = static_cast<double>(settings["coal_frequency"]);
    if (settings.has("water_frequency")) world_settings_.water_frequency = static_cast<double>(settings["water_frequency"]);
    if (settings.has("geology_scale")) world_settings_.geology_scale = static_cast<int32_t>(settings["geology_scale"]);
    if (settings.has("generation_version")) world_settings_.generation_version = static_cast<int32_t>(settings["generation_version"]);

    world_settings_.width = std::clamp(world_settings_.width, CHUNK_SIZE, 65536);
    world_settings_.depth = std::clamp(world_settings_.depth, CHUNK_SIZE, 16384);
    world_settings_.sky = std::clamp(world_settings_.sky, 0, 4096);
    world_settings_.surface_amplitude = std::clamp(world_settings_.surface_amplitude, 0, 512);
    world_settings_.sediment_depth = std::clamp(world_settings_.sediment_depth, 1, 256);
    world_settings_.cave_density = std::clamp(world_settings_.cave_density, 0.05, 0.95);
    world_settings_.coal_frequency = std::clamp(world_settings_.coal_frequency, 0.50, 0.99);
    world_settings_.water_frequency = std::clamp(world_settings_.water_frequency, 0.50, 0.99);
    world_settings_.geology_scale = std::clamp(world_settings_.geology_scale, 64, 4096);
    world_settings_.generation_version = std::clamp(world_settings_.generation_version, 1, 5);

    world_generation_enabled_ = true;
    configure_generation_workers(generation_workers);
}

Dictionary NativeSandWorld::get_world_settings() const {
    Dictionary result;
    result["seed"] = seed_;
    result["width"] = world_settings_.width;
    result["depth"] = world_settings_.depth;
    result["sky"] = world_settings_.sky;
    result["surface_baseline"] = world_settings_.surface_baseline;
    result["surface_amplitude"] = world_settings_.surface_amplitude;
    result["sediment_depth"] = world_settings_.sediment_depth;
    result["cave_density"] = world_settings_.cave_density;
    result["coal_frequency"] = world_settings_.coal_frequency;
    result["water_frequency"] = world_settings_.water_frequency;
    result["geology_scale"] = world_settings_.geology_scale;
    result["generation_version"] = world_settings_.generation_version;
    result["min_x"] = -world_settings_.width / 2;
    result["max_x"] = -world_settings_.width / 2 + world_settings_.width - 1;
    result["min_y"] = -world_settings_.sky;
    result["max_y"] = world_settings_.depth - 1;
    return result;
}

bool NativeSandWorld::request_chunk(Vector2i coordinate, int32_t priority) {
    if (!world_generation_enabled_ || !is_chunk_in_virtual_world(coordinate) || get_chunk(coordinate) != nullptr) {
        return false;
    }
    const uint64_t key = chunk_key(coordinate);
    {
        std::lock_guard<std::mutex> lock(generation_mutex_);
        if (queued_keys_.count(key) != 0 || generating_keys_.count(key) != 0 || completed_keys_.count(key) != 0) {
            return false;
        }
        generation_queue_.push_back({coordinate, std::clamp(priority, 0, 100), generation_sequence_++});
        queued_keys_.insert(key);
        peak_generation_queue_ = std::max(peak_generation_queue_, static_cast<int32_t>(generation_queue_.size()));
    }
    generation_start_.notify_one();
    return true;
}

int32_t NativeSandWorld::request_chunk_region(Rect2i chunk_area, int32_t priority) {
    Vector2i end;
    if (!checked_rect_end(chunk_area, 4096, end)) return -1;
    int32_t requested = 0;
    for (int32_t y = chunk_area.position.y; y < end.y; ++y) {
        for (int32_t x = chunk_area.position.x; x < end.x; ++x) {
            requested += request_chunk({x, y}, priority) ? 1 : 0;
        }
    }
    return requested;
}

void NativeSandWorld::configure_generation_workers(int32_t requested_workers) {
    stop_generation_workers();
    const int32_t hardware_workers = static_cast<int32_t>(std::max(1u, std::thread::hardware_concurrency()));
    generation_worker_count_ = std::clamp(requested_workers, 1, std::min(hardware_workers, 8));
    generation_stop_ = false;
    for (int32_t index = 0; index < generation_worker_count_; ++index) {
        generation_workers_.emplace_back(&NativeSandWorld::generation_worker_loop, this);
    }
}

void NativeSandWorld::stop_generation_workers() {
    {
        std::lock_guard<std::mutex> lock(generation_mutex_);
        generation_stop_ = true;
    }
    generation_start_.notify_all();
    for (std::thread &worker : generation_workers_) {
        if (worker.joinable()) worker.join();
    }
    generation_workers_.clear();
    generation_worker_count_ = 0;
    generation_stop_ = false;
}

void NativeSandWorld::generation_worker_loop() {
    while (true) {
        GenerationTask task;
        {
            std::unique_lock<std::mutex> lock(generation_mutex_);
            generation_start_.wait(lock, [this] { return generation_stop_ || !generation_queue_.empty(); });
            if (generation_stop_) return;
            const auto best = std::min_element(generation_queue_.begin(), generation_queue_.end(), [](const GenerationTask &a, const GenerationTask &b) {
                if (a.priority != b.priority) return a.priority < b.priority;
                if (a.coordinate.y != b.coordinate.y) return a.coordinate.y < b.coordinate.y;
                if (a.coordinate.x != b.coordinate.x) return a.coordinate.x < b.coordinate.x;
                return a.sequence < b.sequence;
            });
            task = *best;
            generation_queue_.erase(best);
            const uint64_t key = chunk_key(task.coordinate);
            queued_keys_.erase(key);
            generating_keys_.insert(key);
        }
        std::unique_ptr<GeneratedChunk> generated = generate_chunk_data(task.coordinate);
        {
            std::lock_guard<std::mutex> lock(generation_mutex_);
            const uint64_t key = chunk_key(task.coordinate);
            generating_keys_.erase(key);
            completed_keys_.insert(key);
            total_generation_usec_ += generated->generation_usec;
            worst_generation_usec_ = std::max(worst_generation_usec_, generated->generation_usec);
            ++total_chunks_generated_;
            completed_generation_.push_back(std::move(generated));
        }
        generation_idle_.notify_all();
    }
}

int32_t NativeSandWorld::pump_generation(int32_t max_publish) {
    const auto started = std::chrono::steady_clock::now();
    last_chunks_published_ = 0;
    const int32_t limit = std::max(0, max_publish);
    while (last_chunks_published_ < limit) {
        std::unique_ptr<GeneratedChunk> generated;
        {
            std::lock_guard<std::mutex> lock(generation_mutex_);
            if (completed_generation_.empty()) break;
            generated = std::move(completed_generation_.front());
            completed_generation_.pop_front();
            completed_keys_.erase(chunk_key(generated->coordinate));
        }
        publish_generated_chunk(std::move(generated));
        ++last_chunks_published_;
    }
    last_publish_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return last_chunks_published_;
}

int32_t NativeSandWorld::flush_generation() {
    {
        std::unique_lock<std::mutex> lock(generation_mutex_);
        generation_idle_.wait(lock, [this] { return generation_queue_.empty() && generating_keys_.empty(); });
    }
    int32_t published = 0;
    while (true) {
        int32_t pending = 0;
        {
            std::lock_guard<std::mutex> lock(generation_mutex_);
            pending = static_cast<int32_t>(completed_generation_.size());
        }
        if (pending == 0) break;
        published += pump_generation(pending);
    }
    return published;
}

bool NativeSandWorld::is_chunk_generated(Vector2i coordinate) const {
    const Chunk *chunk = get_chunk(coordinate);
    return chunk != nullptr && chunk->generated;
}

int32_t NativeSandWorld::get_generation_state(Vector2i coordinate) const {
    if (is_chunk_generated(coordinate)) return 2;
    const uint64_t key = chunk_key(coordinate);
    std::lock_guard<std::mutex> lock(generation_mutex_);
    return queued_keys_.count(key) != 0 || generating_keys_.count(key) != 0 || completed_keys_.count(key) != 0 ? 1 : 0;
}

void NativeSandWorld::ensure_generated_for_edit(Vector2i coordinate) {
    if (!world_generation_enabled_ || get_chunk(coordinate) != nullptr || !is_chunk_in_virtual_world(coordinate)) return;
    publish_generated_chunk(generate_chunk_data(coordinate));
}

void NativeSandWorld::publish_generated_chunk(std::unique_ptr<GeneratedChunk> generated) {
    if (generated == nullptr || get_chunk(generated->coordinate) != nullptr) return;
    auto chunk = std::make_unique<Chunk>(generated->coordinate);
    chunk->material = generated->material;
    chunk->temperature = generated->temperature;
    chunk->provenance = generated->provenance;
    chunk->mineral_signature = generated->mineral_signature;
    chunk->organic_moisture = std::move(generated->organic_moisture);
    chunk->material_amount = std::move(generated->material_amount);
    chunk->generated = true;
    chunk->pristine = true;
    chunk->revision = 1;
    chunk->render_dirty.include(0, 0);
    chunk->render_dirty.include(CHUNK_SIZE - 1, CHUNK_SIZE - 1);
    const int64_t generated_structure_count = std::count_if(generated->structure.begin(), generated->structure.end(),
        [](uint8_t type_id) { return type_id != STRUCTURE_NONE; });
    if (generated_structure_count > 0) {
        chunk->structures = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>(generated->structure);
    }
    Chunk *published = chunk.get();
    chunks_.emplace(chunk_key(generated->coordinate), std::move(chunk));
    invalidate_chunk_order();
    if (generated_structure_count > 0) {
        structures_allocated_ += generated_structure_count;
        ++structure_revision_;
        mark_structure_chunk_dirty(generated->coordinate);
    }
    ++fluid_render_revision_;
    ++total_chunks_published_;
    peak_allocated_chunks_ = std::max(peak_allocated_chunks_, chunk_count());
    refresh_generated_activity(*published);
    refresh_fluid_activity(*published);
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        if (published->temperature[index] == TEMPERATURE_AMBIENT) continue;
        const int32_t x = index % CHUNK_SIZE;
        const int32_t y = index / CHUNK_SIZE;
        const bool gradient = x == 0 || y == 0 || x == CHUNK_SIZE - 1 || y == CHUNK_SIZE - 1 ||
            published->temperature[index - 1] != published->temperature[index] ||
            published->temperature[index + 1] != published->temperature[index] ||
            published->temperature[index - CHUNK_SIZE] != published->temperature[index] ||
            published->temperature[index + CHUNK_SIZE] != published->temperature[index];
        if (gradient) published->thermal_active.include(x, y, 1);
    }
    const std::array<Vector2i, 4> neighbors{{Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)}};
    for (const Vector2i offset : neighbors) {
        Chunk *neighbor = get_chunk(generated->coordinate + offset);
        if (neighbor != nullptr) {
            refresh_generated_activity(*neighbor);
            refresh_fluid_activity(*neighbor);
            neighbor->render_dirty.include(0, 0);
            neighbor->render_dirty.include(CHUNK_SIZE - 1, CHUNK_SIZE - 1);
        }
    }
}

void NativeSandWorld::refresh_generated_activity(Chunk &chunk) {
    chunk.active.clear();
    chunk.next_active.clear();
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        if (chunk.material[index] != SAND_ID) continue;
        const Vector2i local{index % CHUNK_SIZE, index / CHUNK_SIZE};
        const Vector2i cell = origin + local;
        if (get_cell(cell + Vector2i(0, 1)) == EMPTY_ID || get_cell(cell + Vector2i(-1, 1)) == EMPTY_ID ||
            get_cell(cell + Vector2i(1, 1)) == EMPTY_ID) {
            chunk.active.include(local.x, local.y, 1);
        }
    }
    chunk.stable_ticks = 0;
}

void NativeSandWorld::refresh_fluid_activity(Chunk &chunk) {
    chunk.fluid_active.clear();
    chunk.fluid_next_active.clear();
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        if (chunk.material[index] != WATER_ID) continue;
        const Vector2i local{index % CHUNK_SIZE, index / CHUNK_SIZE};
        const Vector2i cell = origin + local;
        const int32_t mass = water_mass_at(chunk, index);
        if ((fluid_destination_available(cell + Vector2i(0, 1)) && water_mass_at(cell + Vector2i(0, 1)) < 255) ||
            (fluid_destination_available(cell + Vector2i(-1, 0)) && water_mass_at(cell + Vector2i(-1, 0)) + 1 < mass) ||
            (fluid_destination_available(cell + Vector2i(1, 0)) && water_mass_at(cell + Vector2i(1, 0)) + 1 < mass)) {
            chunk.fluid_active.include(local.x, local.y, 1);
        }
    }
    chunk.fluid_plane_quiet_ticks = 0;
}

void NativeSandWorld::request_simulation_halo(const std::vector<Chunk *> &active_chunks) {
    if (!world_generation_enabled_) return;
    for (const Chunk *chunk : active_chunks) {
        request_chunk(chunk->coordinate + Vector2i(-1, 1), 0);
        request_chunk(chunk->coordinate + Vector2i(0, 1), 0);
        request_chunk(chunk->coordinate + Vector2i(1, 1), 0);
    }
    // V2 streaming owns fluid-neighbor generation through InterestRegions.
    // Treat an unloaded boundary as sealed until it enters an interest region;
    // otherwise one unsettled aquifer recursively generates the entire world.
    if (world_settings_.generation_version < 2) {
        for (const Chunk *chunk : sorted_chunks()) {
            if (!chunk->fluid_active.valid()) continue;
            for (int32_t y = -1; y <= 1; ++y) for (int32_t x = -1; x <= 1; ++x) if (x != 0 || y != 0)
                request_chunk(chunk->coordinate + Vector2i(x, y), 0);
        }
    }
}

int32_t NativeSandWorld::evict_pristine_outside(Rect2i keep_chunk_area, int32_t max_evict) {
    if (max_evict <= 0) return 0;
    std::vector<Vector2i> candidates;
    const Vector2i keep_end = keep_chunk_area.position + keep_chunk_area.size;
    for (const Chunk *chunk : sorted_chunks()) {
        const bool inside = chunk->coordinate.x >= keep_chunk_area.position.x && chunk->coordinate.x < keep_end.x &&
                            chunk->coordinate.y >= keep_chunk_area.position.y && chunk->coordinate.y < keep_end.y;
        if (!inside && chunk->generated && chunk->pristine && !chunk->active.valid()) candidates.push_back(chunk->coordinate);
    }
    const int32_t count = std::min(max_evict, static_cast<int32_t>(candidates.size()));
    for (int32_t index = 0; index < count; ++index) {
        const auto found = chunks_.find(chunk_key(candidates[index]));
        if (found != chunks_.end() && found->second->structures != nullptr) {
            structures_allocated_ -= std::count_if(found->second->structures->begin(), found->second->structures->end(),
                [](uint8_t type_id) { return type_id != STRUCTURE_NONE; });
            ++structure_revision_;
        }
        chunks_.erase(chunk_key(candidates[index]));
        invalidate_chunk_order();
        evicted_chunks_.push_back(candidates[index]);
        ++total_chunks_evicted_;
    }
    return count;
}

Array NativeSandWorld::consume_evicted_chunks() {
    Array result;
    for (const Vector2i coordinate : evicted_chunks_) result.push_back(coordinate);
    evicted_chunks_.clear();
    return result;
}

Dictionary NativeSandWorld::get_generation_statistics() const {
    Dictionary result;
    std::lock_guard<std::mutex> lock(generation_mutex_);
    result["workers"] = generation_worker_count_;
    result["queued"] = static_cast<int32_t>(generation_queue_.size());
    result["in_flight"] = static_cast<int32_t>(generating_keys_.size());
    result["completed"] = static_cast<int32_t>(completed_generation_.size());
    result["published_last_frame"] = last_chunks_published_;
    result["publish_usec_last_frame"] = last_publish_usec_;
    result["generated_total"] = total_chunks_generated_;
    result["published_total"] = total_chunks_published_;
    result["evicted_total"] = total_chunks_evicted_;
    result["generation_usec_total"] = total_generation_usec_;
    result["generation_usec_worst"] = worst_generation_usec_;
    result["generation_usec_average"] = total_chunks_generated_ > 0 ? static_cast<double>(total_generation_usec_) / total_chunks_generated_ : 0.0;
    result["queue_peak"] = peak_generation_queue_;
    result["allocated_chunks_peak"] = peak_allocated_chunks_;
    return result;
}

double NativeSandWorld::smoothstep(double value) {
    value = std::clamp(value, 0.0, 1.0);
    return value * value * (3.0 - 2.0 * value);
}

double NativeSandWorld::lerp_double(double from, double to, double amount) {
    return from + (to - from) * amount;
}

double NativeSandWorld::value_noise_1d(double x, int32_t salt) const {
    const int32_t x0 = static_cast<int32_t>(std::floor(x));
    const double t = smoothstep(x - static_cast<double>(x0));
    const double a = static_cast<double>(hash_2d(seed_, {x0, world_settings_.generation_version}, salt)) / MASK_31;
    const double b = static_cast<double>(hash_2d(seed_, {x0 + 1, world_settings_.generation_version}, salt)) / MASK_31;
    return lerp_double(a, b, t);
}

double NativeSandWorld::value_noise_2d(double x, double y, int32_t salt) const {
    const int32_t x0 = static_cast<int32_t>(std::floor(x));
    const int32_t y0 = static_cast<int32_t>(std::floor(y));
    const double tx = smoothstep(x - static_cast<double>(x0));
    const double ty = smoothstep(y - static_cast<double>(y0));
    const auto sample = [this, salt](int32_t sx, int32_t sy) {
        return static_cast<double>(hash_2d(seed_, {sx, sy}, salt + world_settings_.generation_version * 7919)) / MASK_31;
    };
    return lerp_double(lerp_double(sample(x0, y0), sample(x0 + 1, y0), tx),
                       lerp_double(sample(x0, y0 + 1), sample(x0 + 1, y0 + 1), tx), ty);
}

double NativeSandWorld::fbm_2d(double x, double y, int32_t salt, int32_t octaves) const {
    double total = 0.0;
    double amplitude = 0.5;
    double normalization = 0.0;
    for (int32_t octave = 0; octave < octaves; ++octave) {
        total += value_noise_2d(x, y, salt + octave * 1013) * amplitude;
        normalization += amplitude;
        x *= 2.03;
        y *= 2.03;
        amplitude *= 0.5;
    }
    return normalization > 0.0 ? total / normalization : 0.0;
}

int32_t NativeSandWorld::surface_height_at(int32_t world_x) const {
    const double broad = value_noise_1d(static_cast<double>(world_x) / 900.0, 1201) * 2.0 - 1.0;
    const double medium = value_noise_1d(static_cast<double>(world_x) / 260.0, 1213) * 2.0 - 1.0;
    const double fine = value_noise_1d(static_cast<double>(world_x) / 84.0, 1231) * 2.0 - 1.0;
    return world_settings_.surface_baseline + static_cast<int32_t>(std::lround(world_settings_.surface_amplitude * (0.58 * broad + 0.29 * medium + 0.13 * fine)));
}

bool NativeSandWorld::cave_at(Vector2i world_cell, int32_t surface_height) const {
    if (world_cell.y < surface_height + world_settings_.sediment_depth + 8) return false;
    const double warp = value_noise_2d(world_cell.x / 310.0, world_cell.y / 310.0, 2003) * 46.0 - 23.0;
    const double cave = fbm_2d((world_cell.x + warp) / 118.0, (world_cell.y - warp) / 92.0, 2027, 4);
    const double tunnels = std::abs(value_noise_2d(world_cell.x / 72.0, world_cell.y / 48.0, 2063) * 2.0 - 1.0);
    return cave > world_settings_.cave_density && tunnels < 0.72;
}

bool NativeSandWorld::coal_at(Vector2i world_cell, int32_t surface_height) const {
    if (world_cell.y < surface_height + 48) return false;
    const double deposit = fbm_2d(world_cell.x / 74.0, world_cell.y / 54.0, 3011, 3);
    const double seam = std::abs(value_noise_2d(world_cell.x / 210.0, world_cell.y / 18.0, 3037) * 2.0 - 1.0);
    return deposit > world_settings_.coal_frequency && seam < 0.48;
}

bool NativeSandWorld::water_at(Vector2i world_cell, int32_t surface_height) const {
    if (world_cell.y < surface_height + 80) return false;
    const double reservoir = fbm_2d(world_cell.x / 190.0, world_cell.y / 135.0, 4001, 3);
    const double local_level = value_noise_1d(world_cell.x / 340.0, 4021);
    const int32_t ceiling = surface_height + 120 + static_cast<int32_t>(local_level * 260.0);
    return reservoir > world_settings_.water_frequency && world_cell.y > ceiling;
}

int32_t NativeSandWorld::geology_profile_id_at(Vector2i world_cell) const {
    const double scale = static_cast<double>(world_settings_.geology_scale);
    const double silica = 0.70 + 0.23 * fbm_2d(world_cell.x / scale, world_cell.y / scale, 5003, 4);
    const double iron = 0.018 + 0.105 * fbm_2d(world_cell.x / (scale * 0.72), world_cell.y / (scale * 0.72), 5021, 3);
    const double heavy = 0.004 + 0.043 * fbm_2d(world_cell.x / (scale * 0.48), world_cell.y / (scale * 0.48), 5039, 3);
    const double gold_field = fbm_2d(world_cell.x / (scale * 1.35), world_cell.y / (scale * 1.35), 5051, 4);
    const uint16_t q_silica = static_cast<uint16_t>(std::clamp(std::lround((silica - 0.68) / 0.28 * 31.0), 0l, 31l));
    const uint16_t q_iron = static_cast<uint16_t>(std::clamp(std::lround((iron - 0.01) / 0.13 * 31.0), 0l, 31l));
    const uint16_t q_heavy = static_cast<uint16_t>(std::clamp(std::lround((heavy - 0.002) / 0.055 * 7.0), 0l, 7l));
    const uint16_t q_gold = gold_field <= 0.78 ? 0 : static_cast<uint16_t>(std::clamp(std::lround((gold_field - 0.78) / 0.16 * 7.0), 1l, 7l));
    uint16_t profile = static_cast<uint16_t>(q_silica | (q_iron << 5u) | (q_heavy << 10u) | (q_gold << 13u));
    if (profile == 0) profile = 1;
    return profile;
}

Dictionary NativeSandWorld::get_geology_profile(int32_t profile_id) const {
    Dictionary result;
    if (profile_id < 1 || profile_id > 65535) return result;
    const uint16_t packed = static_cast<uint16_t>(profile_id);
    if (world_settings_.generation_version >= 5) {
        // Same decoder the conservation ledger uses, so the reported composition is the
        // composition. Signature-driven clay is reported at its mid value here because a
        // profile alone does not identify a cell.
        double fractions[6];
        v5_profile_fractions(packed, 0x1f, fractions);
        result["profile_id"] = profile_id;
        result["silica_fraction"] = fractions[0];
        result["iron_fraction"] = fractions[1];
        result["heavy_minerals_fraction"] = fractions[2];
        result["clay_fraction"] = fractions[4];
        result["other_fraction"] = fractions[5];
        result["gold_ppm"] = fractions[3] * 1000000.0;
        result["rock_family"] = (packed & 31u) >> 1u;
        return result;
    }
    const int32_t q_silica = packed & 31u;
    const int32_t q_iron = (packed >> 5u) & 31u;
    const int32_t q_heavy = (packed >> 10u) & 7u;
    const int32_t q_gold = (packed >> 13u) & 7u;
    double silica = 0.68 + 0.28 * q_silica / 31.0;
    double iron = 0.01 + 0.13 * q_iron / 31.0;
    double heavy = 0.002 + 0.055 * q_heavy / 7.0;
    const double primary = silica + iron + heavy;
    if (primary > 0.985) {
        const double factor = 0.985 / primary;
        silica *= factor;
        iron *= factor;
        heavy *= factor;
    }
    result["profile_id"] = profile_id;
    result["silica_fraction"] = silica;
    result["iron_fraction"] = iron;
    result["heavy_minerals_fraction"] = heavy;
    result["other_fraction"] = 1.0 - silica - iron - heavy;
    result["gold_ppm"] = q_gold == 0 ? 0.0 : 0.125 * static_cast<double>(1 << q_gold);
    return result;
}

Dictionary NativeSandWorld::get_geology_profile_at(Vector2i world_cell) const {
    return get_geology_profile(geology_profile_id_at(world_cell));
}

std::unique_ptr<NativeSandWorld::GeneratedChunk> NativeSandWorld::generate_chunk_data(Vector2i coordinate) const {
    if (world_settings_.generation_version >= 5) return generate_chunk_data_v5(coordinate);
    if (world_settings_.generation_version >= 4) return generate_chunk_data_v4(coordinate);
    if (world_settings_.generation_version >= 3) return generate_chunk_data_v3(coordinate);
    if (world_settings_.generation_version >= 2) return generate_chunk_data_v2(coordinate);
    const auto started = std::chrono::steady_clock::now();
    auto generated = std::make_unique<GeneratedChunk>();
    generated->coordinate = coordinate;
    generated->temperature.fill(TEMPERATURE_AMBIENT);
    const Vector2i origin = coordinate * CHUNK_SIZE;
    for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
        for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            const Vector2i cell = origin + Vector2i(local_x, local_y);
            if (!is_inside_virtual_world(cell)) {
                generated->material[index] = cell.y < -world_settings_.sky ? EMPTY_ID : BEDROCK_ID;
                continue;
            }
            const int32_t surface = surface_height_at(cell.x);
            if (cell.y < surface) {
                generated->material[index] = EMPTY_ID;
            } else if (cell.y >= world_settings_.depth - 8) {
                generated->material[index] = BEDROCK_ID;
            } else if (cell.y < surface + world_settings_.sediment_depth) {
                generated->material[index] = SAND_ID;
                generated->provenance[index] = static_cast<uint16_t>(geology_profile_id_at(cell));
                generated->mineral_signature[index] = mineral_signature_for(cell);
            } else if (cave_at(cell, surface)) {
                generated->material[index] = water_at(cell, surface) ? WATER_ID : EMPTY_ID;
            } else {
                generated->material[index] = coal_at(cell, surface) ? COAL_ID : STONE_ID;
            }
        }
    }
    generated->generation_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return generated;
}

uint32_t NativeSandWorld::content_hash_mix(uint32_t hash, uint32_t component) {
    hash ^= component;
    hash *= 16777619u;
    return hash;
}

String NativeSandWorld::get_chunk_content_hash(Vector2i coordinate) const {
    const Chunk *chunk = get_chunk(coordinate);
    if (chunk == nullptr) return String();
    uint32_t hash = 2166136261u;
    hash = content_hash_mix(hash, static_cast<uint32_t>(coordinate.x));
    hash = content_hash_mix(hash, static_cast<uint32_t>(coordinate.y));
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        hash = content_hash_mix(hash, static_cast<uint32_t>(chunk->material[index]));
        hash = content_hash_mix(hash, chunk->provenance[index]);
    }
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

String NativeSandWorld::get_region_content_hash(Rect2i chunk_area) const {
    uint32_t hash = 2166136261u;
    Vector2i end;
    if (!checked_rect_end(chunk_area, 4096, end)) return String();
    for (int32_t y = chunk_area.position.y; y < end.y; ++y) {
        for (int32_t x = chunk_area.position.x; x < end.x; ++x) {
            hash = content_hash_mix(hash, static_cast<uint32_t>(x));
            hash = content_hash_mix(hash, static_cast<uint32_t>(y));
            const Chunk *chunk = get_chunk({x, y});
            if (chunk == nullptr) {
                hash = content_hash_mix(hash, 0xffffffffu);
                continue;
            }
            for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
                hash = content_hash_mix(hash, static_cast<uint32_t>(chunk->material[index]));
                hash = content_hash_mix(hash, chunk->provenance[index]);
            }
        }
    }
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

const std::vector<NativeSandWorld::StructureDefinition> &NativeSandWorld::structure_definitions() {
    static const std::vector<StructureDefinition> definitions{
        {1, "Conveyor Left", "Logistics", "logistics.conveyor.basic", 1, 1, true, true,
         {{0, 0}}, {}, {}},
        {2, "Conveyor Right", "Logistics", "logistics.conveyor.basic", 1, 1, true, true,
         {{0, 0}}, {}, {}},
        {3, "Funnel", "Logistics", "logistics.funnel.basic", 7, 4, false, false,
         {{0, 0}, {6, 0}, {0, 1}, {1, 1}, {5, 1}, {6, 1},
          {0, 2}, {1, 2}, {2, 2}, {4, 2}, {5, 2}, {6, 2}},
         {{1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}}, {{3, 3}}},
        {4, "Storage Bin", "Storage", "storage.bin.basic", 8, 8, false, false,
         {{0, 0}, {7, 0}, {0, 1}, {7, 1}, {0, 2}, {7, 2}, {0, 3}, {7, 3},
          {0, 4}, {7, 4}, {0, 5}, {7, 5}, {0, 6}, {7, 6}, {0, 7}, {1, 7},
          {2, 7}, {3, 7}, {4, 7}, {5, 7}, {6, 7}, {7, 7}}, {{2, 0}, {3, 0}, {4, 0}, {5, 0}}, {}},
        {5, "Radiant Crude Furnace", "Dev Fixture", "processing.crude_furnace", 10, 4, false, true,
         {{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {6, 0}, {7, 0}, {8, 0}, {9, 0},
          {0, 1}, {9, 1}, {0, 2}, {9, 2}}, {}, {}},
        {6, "Vibrating Screen", "Dev Fixture", "", 10, 5, false, true,
         {{0, 0}, {9, 0}, {0, 1}, {9, 1}, {0, 2}, {9, 2},
          {0, 3}, {1, 3}, {2, 3}, {3, 3}, {4, 3}, {5, 3}, {6, 3}, {7, 3}, {8, 3}, {9, 3}},
         {}, {}},
        {7, "Overbelt Magnetic Separator", "Dev Fixture", "", 12, 6, false, true,
         {{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {6, 0}, {7, 0}, {8, 0}, {9, 0}, {10, 0}, {11, 0},
          {0, 1}, {11, 1}, {0, 2}, {11, 2}, {0, 3}, {11, 3}, {0, 4}, {11, 4}, {0, 5}, {11, 5}},
         {}, {}},
        {8, "Research Bank", "Progression", "progression.research_bank", 8, 6, false, true,
         {{0, 0}, {1, 0}, {2, 0}, {3, 0}, {4, 0}, {5, 0}, {6, 0}, {7, 0}, {0, 1}, {7, 1}, {0, 2}, {7, 2},
          {0, 3}, {7, 3}, {0, 4}, {7, 4}, {0, 5}, {1, 5}, {2, 5}, {3, 5}, {4, 5}, {5, 5}, {6, 5}, {7, 5}},
         {{3, -1}}, {{8, 4}}},
        {9, "Control Gate", "Automation", "automation.advanced_routing", 1, 1, true, true,
         {{0, 0}}, {}, {}},
        {10, "Pipe", "Fluid", "fluid.basic_handling", 1, 1, true, true, {{0, 0}}, {}, {}},
        {11, "Pipe Junction", "Fluid", "fluid.basic_handling", 1, 1, true, false, {{0, 0}}, {}, {}},
        {12, "Fluid Intake", "Fluid", "fluid.basic_handling", 1, 1, true, true, {{0, 0}}, {}, {}},
        {13, "Fluid Outlet", "Fluid", "fluid.basic_handling", 1, 1, true, true, {{0, 0}}, {}, {}},
        {14, "Basic Pump", "Fluid", "fluid.basic_handling", 1, 1, true, true, {{0, 0}}, {}, {}},
        {15, "Pipe Valve", "Fluid", "fluid.flow_control", 1, 1, true, true, {{0, 0}}, {}, {}},
        {16, "Industrial Reservoir Wall", "Fluid", "fluid.basic_handling", 1, 1, true, false, {{0, 0}}, {}, {}},
        {17, "Wash Sluice", "Dev Fixture", "", 18, 6, false, true,
         {{0,0},{1,0},{2,0},{3,0},{4,0},{5,0},{6,0},{7,0},{8,0},{9,0},{10,0},{11,0},{12,0},{13,0},{14,0},{15,0},{16,0},{17,0},
          {0,1},{17,1},{0,2},{17,2},{0,3},{17,3},{0,4},{17,4},
          {0,5},{1,5},{2,5},{3,5},{4,5},{5,5},{6,5},{7,5},{8,5},{9,5},{10,5},{11,5},{12,5},{13,5},{14,5},{15,5},{16,5},{17,5},
          {4,4},{8,4},{12,4},{16,4}}, {}, {}},
        {18, "Subsurface Entrance I", "Subsurface Logistics", "logistics.subsurface_1", 1, 1, true, true, {{0, 0}}, {}, {}},
        {19, "Subsurface Exit I", "Subsurface Logistics", "logistics.subsurface_1", 1, 1, true, true, {{0, 0}}, {}, {}},
        {20, "Subsurface Entrance II", "Subsurface Logistics", "logistics.subsurface_2", 1, 1, true, true, {{0, 0}}, {}, {}},
        {21, "Subsurface Exit II", "Subsurface Logistics", "logistics.subsurface_2", 1, 1, true, true, {{0, 0}}, {}, {}},
        {22, "Subsurface Entrance III", "Subsurface Logistics", "logistics.subsurface_3", 1, 1, true, true, {{0, 0}}, {}, {}},
        {23, "Subsurface Exit III", "Subsurface Logistics", "logistics.subsurface_3", 1, 1, true, true, {{0, 0}}, {}, {}},
        {24, "Thermal Switch", "Thermal", "thermal.basic_thermodynamics", 1, 1, true, true, {{0, 0}}, {}, {}},
        {25, "Heat Exchanger", "Thermal", "thermal.phase_processing", 3, 3, false, true,
         {{1,0},{0,1},{1,1},{2,1},{1,2}}, {}, {}},
        {26, "Mechanical Shaft", "Power", "power.steam_generation", 1, 1, true, true, {{0,0}}, {}, {}},
        {27, "Steam Turbine", "Power", "power.steam_generation", 6, 4, false, true,
         {{0,0},{1,0},{2,0},{3,0},{4,0},{5,0},{0,1},{1,1},{2,1},{3,1},{4,1},{5,1},{0,2},{1,2},{2,2},{3,2},{4,2},{5,2},{0,3},{1,3},{2,3},{3,3},{4,3},{5,3}}, {}, {}},
        {28, "Generator", "Power", "power.steam_generation", 5, 4, false, true,
         {{0,0},{1,0},{2,0},{3,0},{4,0},{0,1},{1,1},{2,1},{3,1},{4,1},{0,2},{1,2},{2,2},{3,2},{4,2},{0,3},{1,3},{2,3},{3,3},{4,3}}, {}, {}},
        {29, "Power Pole", "Power", "power.electrical_distribution", 1, 1, true, false, {{0,0}}, {}, {}},
        {30, "Power Switch", "Power", "power.electrical_distribution", 3, 1, false, true, {{0,0},{1,0},{2,0}}, {}, {}},
        {31, "Accumulator", "Power", "power.energy_storage", 3, 3, false, true,
         {{0,0},{1,0},{2,0},{0,1},{1,1},{2,1},{0,2},{1,2},{2,2}}, {}, {}},
        {33, "Flywheel", "Power", "power.mechanical_storage", 3, 3, false, true,
         {{0,0},{1,0},{2,0},{0,1},{1,1},{2,1},{0,2},{1,2},{2,2}}, {}, {}},
        {34, "Resistive Heater", "Power", "power.electrified_industry", 3, 2, false, true,
         {{0,0},{1,0},{2,0},{0,1},{1,1},{2,1}}, {}, {}},
        {35, "Iron Pot", "Thermal", "thermal.cookware", 9, 6, false, false,
         {{0,0},{8,0},{0,1},{8,1},{0,2},{8,2},{0,3},{8,3},{0,4},{8,4},
          {0,5},{1,5},{2,5},{3,5},{4,5},{5,5},{6,5},{7,5},{8,5}}, {}, {}},
        {36, "Ceramic Test Vessel", "Test", "", 9, 6, false, false,
         {{0,0},{8,0},{0,1},{8,1},{0,2},{8,2},{0,3},{8,3},{0,4},{8,4},
          {0,5},{1,5},{2,5},{3,5},{4,5},{5,5},{6,5},{7,5},{8,5}}, {}, {}},
        {37, "Structural Wall", "Construction", "foundation.basic_industry", 1, 1, true, false, {{0,0}}, {}, {}},
        {38, "Metal Plate", "Construction", "processing.ferrous_separation", 1, 1, true, false, {{0,0}}, {}, {}},
        {39, "Ceramic Wall", "Construction", "thermal.phase_processing", 1, 1, true, false, {{0,0}}, {}, {}},
        {40, "Refractory Wall", "Construction", "thermal.phase_processing", 1, 1, true, false, {{0,0}}, {}, {}},
        {41, "Mesh Screen", "Processing Component", "processing.dry_separation", 1, 1, true, false, {{0,0}}, {}, {}},
        {42, "Grate", "Processing Component", "organic.wood_processing", 1, 1, true, false, {{0,0}}, {}, {}},
        {43, "Riffle", "Processing Component", "processing.wet_separation", 1, 1, true, false, {{0,0}}, {}, {}},
        {44, "Thermal Insulator", "Construction", "thermal.basic_thermodynamics", 1, 1, true, false, {{0,0}}, {}, {}},
        {45, "Vibration Actuator", "Processing Component", "processing.dry_separation", 1, 1, true, true, {{0,0}}, {}, {}},
        {46, "Electromagnet", "Processing Component", "processing.ferrous_separation", 1, 1, true, true, {{0,0}}, {}, {}},
        {47, "Blower", "Processing Component", "thermal.basic_thermodynamics", 1, 1, true, true, {{0,0}}, {}, {}},
    };
    return definitions;
}

const std::vector<NativeSandWorld::ResearchDefinition> &NativeSandWorld::research_definitions() {
    static const std::vector<ResearchDefinition> definitions{
        {"foundation.basic_industry", "Foundation", "Primitive logistics, the Research Bank, Structural Walls and Harvest.", {}, 0, 0, 0, "Starting industrial toolkit", 2, 0},
        {"mobility.sprint", "Sprint", "Early character mobility without stamina or survival upkeep.", {"foundation.basic_industry"}, 600, 10, 0, "Unlock Sprint", 1, 1},
        {"mobility.hover", "Hover / Precision Flight", "Stabilize the Basic Jetpack for precise mid-air factory construction.", {"mobility.sprint", "automation.basic_sensing"}, 1800, 90, 1, "Unlock Hover toggle", 1, 2},
        {"processing.dry_separation", "Dry Separation", "Physically screen Raw Sand by stable grain size.", {"foundation.basic_industry"}, 2400, 40, 0, "Unlock Mesh Screen and Vibration Actuator", 0, 1},
        {"logistics.belt_drive_1", "Belt Drive I", "Double Basic Conveyor transfer cadence.", {"foundation.basic_industry"}, 1000, 25, 0, "Belts: 1 cell/tick", 2, 1},
        {"furnace.fuel_economy_1", "Thermal Efficiency I", "Stop heat leaking sideways through the Insulators that line an enclosure.", {"foundation.basic_industry"}, 1200, 30, 0, "Thermal Insulators stop conducting heat", 4, 1},
        {"processing.ferrous_separation", "Ferrous Separation", "Lift susceptible grains from a moving physical stream.", {"processing.dry_separation"}, 3000, 180, 0, "Unlock Electromagnet and Metal Plate", 0, 2},
        {"furnace.throughput_1", "Radiant Intensity I", "React more of what a hot enclosure is already holding, in the same tick.", {"furnace.fuel_economy_1"}, 2200, 80, 0, "Refractory geometry reacts two cells per tick", 4, 2},
        {"logistics.high_throughput_handling", "High-Throughput Handling", "Keep a Component fed while whatever clears its outputs catches up.", {"processing.dry_separation", "logistics.belt_drive_1"}, 3500, 180, 0, "Components buffer twice as much when blocked", 2, 3},
        {"processing.precision_screening", "Precision Screening", "Refine the deck aperture so the heavy mineral stops diluting the fines.", {"processing.ferrous_separation"}, 4000, 250, 1, "Mesh Screens send heavy mineral to the concentrate", 0, 3},
        {"processing.concentrate_recovery", "Concentrate Recovery", "Recover metal from a concentrate that a raw reaction would vitrify.", {"processing.ferrous_separation", "furnace.throughput_1", "logistics.high_throughput_handling"}, 6000, 400, 2, "Concentrates yield their heavy fraction as Iron", 2, 4},
        {"automation.basic_sensing", "Basic Sensing", "Read visible material and physical fill without geological leakage.", {"foundation.basic_industry"}, 800, 15, 0, "Wire, Manual Switch, Material Sensor, Level Sensor", 6, 1},
        {"automation.logic_control", "Logic Control", "Combine integer signals with deterministic one-tick logic.", {"automation.basic_sensing"}, 1600, 50, 0, "NOT, AND, OR, Comparator", 6, 2},
        {"automation.machine_control", "Machine Control", "Sense and enable processors and individual Conveyors.", {"automation.logic_control", "processing.dry_separation"}, 2800, 140, 0, "Machine telemetry, Machine ENABLE, Conveyor control", 5, 3},
        {"automation.timed_control", "Timed Control", "Build simulation-tick timers and reset-dominant memory.", {"automation.logic_control"}, 2400, 100, 0, "Timer and Memory Latch", 7, 3},
        {"automation.advanced_routing", "Advanced Routing", "Route physical material with signal-controlled retractable gates.", {"automation.machine_control", "automation.logic_control"}, 4200, 220, 1, "Unlock Control Gate", 5, 4},
        {"fluid.basic_handling", "Basic Fluid Handling", "Local enclosed Water transport with physical world boundaries.", {"processing.dry_separation", "logistics.belt_drive_1"}, 2600, 120, 0, "Unlock Pipe, Intake, Outlet, Pump and Reservoir Wall", 9, 2},
        {"fluid.pressurized_transport", "Pressurized Transport", "Higher finite pump rate and head for long lifts.", {"fluid.basic_handling"}, 2200, 180, 0, "Pump head 8192 to 12288; rate 4096 to 6144", 9, 3},
        {"fluid.flow_control", "Flow Control", "Signal-controlled valves and local pipe telemetry.", {"fluid.basic_handling", "automation.basic_sensing"}, 2400, 160, 0, "Unlock Pipe Valve, Flow Meter and Pipe Fill Sensor", 8, 4},
        {"processing.wet_separation", "Wet Separation", "Use real flowing Water, gravity and riffles to classify grains.", {"processing.dry_separation", "fluid.basic_handling"}, 3600, 240, 0, "Unlock Riffle", 10, 4},
        {"logistics.subsurface_1", "Subsurface Logistics I", "One finite hidden lane below the factory floor.", {"foundation.basic_industry"}, 700, 20, 0, "Unlock Amber channel I", 3, 1},
        {"logistics.subsurface_2", "Subsurface Logistics II", "A second independent lane can cross depth I.", {"logistics.subsurface_1"}, 1800, 80, 0, "Unlock Cyan channel II", 3, 2},
        {"logistics.subsurface_3", "Subsurface Logistics III", "A third independent lane for dense factories.", {"logistics.subsurface_2"}, 3600, 180, 1, "Unlock Violet channel III", 3, 3},
        {"thermal.basic_thermodynamics", "Basic Thermodynamics", "Measure and route real cell heat without gating natural physics.", {"foundation.basic_industry", "automation.basic_sensing"}, 1200, 40, 0, "Temperature Sensor and Thermal Switch", 12, 2},
        {"thermal.phase_processing", "Phase Processing", "Industrial heat transfer for physical melting, freezing and casting.", {"thermal.basic_thermodynamics", "furnace.throughput_1"}, 2600, 140, 0, "Heat Exchanger and phase processing", 12, 3},
        {"thermal.steam_handling", "Steam Handling", "Rated enclosed transport and pressure telemetry for Steam.", {"thermal.phase_processing", "fluid.flow_control"}, 3400, 220, 0, "Steam-compatible Pipes and pressure sensing", 12, 4},
        {"thermal.molten_processing", "Molten Processing", "Heat-resistant infrastructure around physical molten Glass and Iron.", {"thermal.phase_processing", "processing.concentrate_recovery"}, 5200, 420, 1, "Molten processing infrastructure", 12, 5},
        {"organic.wood_processing", "Wood Processing", "Cut standing vegetation into physical Wood and Leaves without turning it into inventory tokens.", {"foundation.basic_industry"}, 500, 10, 0, "Vegetation clearing and physical Wood handling", 11, 1},
        {"thermal.cookware", "Cookware", "Build open Iron vessels that conduct real heat into physical Water and ingredients.", {"thermal.basic_thermodynamics", "processing.ferrous_separation"}, 900, 60, 0, "Unlock Iron Pot", 11, 3},
        {"power.steam_generation", "Steam Generation", "Convert physical Pipe Steam through a Turbine and shaft-driven Generator.", {"thermal.steam_handling", "thermal.phase_processing"}, 4200, 320, 0, "Steam Turbine, Mechanical Shaft, Generator", 14, 4},
        {"power.electrical_distribution", "Electrical Distribution", "Distribute generated energy through cached Power Pole networks.", {"power.steam_generation", "automation.basic_sensing"}, 2800, 240, 0, "Power Pole, Power Switch and Power Network Sensor", 15, 5},
        {"power.electrified_industry", "Electrified Industry", "Optional electric drives improve physical Pump, Screen and Magnet operation.", {"power.electrical_distribution", "processing.ferrous_separation"}, 4600, 420, 1, "Electric Drives, Electromagnet Mode and Resistive Heater", 14, 6},
        {"power.energy_storage", "Energy Storage", "Buffer electrical and mechanical energy without hidden resource recipes.", {"power.electrical_distribution"}, 5200, 480, 1, "Accumulator", 16, 6},
        {"power.mechanical_storage", "Mechanical Storage", "Add flywheel inertia to shaft networks.", {"power.steam_generation"}, 2400, 260, 0, "Flywheel", 13, 5},
        {"power.grid_control", "Grid Control", "Segment, sense and capacity-limit deterministic electrical networks.", {"power.energy_storage", "power.electrified_industry", "automation.logic_control"}, 7200, 680, 3, "Priorities and Power Switch automation", 15, 7},
    };
    return definitions;
}

const NativeSandWorld::ResearchDefinition *NativeSandWorld::research_definition(const std::string &id) {
    const auto &definitions = research_definitions();
    const auto found = std::find_if(definitions.begin(), definitions.end(), [&id](const ResearchDefinition &definition) { return id == definition.id; });
    return found == definitions.end() ? nullptr : &*found;
}

const NativeSandWorld::StructureDefinition *NativeSandWorld::structure_definition(int32_t type_id) {
    const auto &definitions = structure_definitions();
    const auto found = std::find_if(definitions.begin(), definitions.end(), [type_id](const StructureDefinition &definition) {
        return definition.type_id == type_id;
    });
    return found == definitions.end() ? nullptr : &*found;
}

Array NativeSandWorld::get_structure_definitions() const {
    Array result;
    for (const StructureDefinition &definition : structure_definitions()) {
        Dictionary item;
        item["type_id"] = definition.type_id;
        item["display_name"] = String(definition.display_name);
        item["category"] = String(definition.category);
        item["unlock_key"] = String(definition.unlock_key);
        item["footprint"] = Vector2i(definition.width, definition.height);
        item["tile_like"] = definition.tile_like;
        item["directional"] = definition.directional;
        Array occupied;
        for (const Vector2i cell : definition.occupied) occupied.push_back(cell);
        Array inputs;
        for (const Vector2i cell : definition.input_ports) inputs.push_back(cell);
        Array outputs;
        for (const Vector2i cell : definition.output_ports) outputs.push_back(cell);
        item["occupied_cells"] = occupied;
        item["input_ports"] = inputs;
        item["output_ports"] = outputs;
        result.push_back(item);
    }
    return result;
}

bool NativeSandWorld::has_research(const char *id) const {
    return unlocked_research_.find(id) != unlocked_research_.end();
}

void NativeSandWorld::set_game_mode(int32_t mode) {
    if (mode != 0 && mode != 1) return;
    game_mode_ = mode;
    ++progression_revision_;
}

int32_t NativeSandWorld::get_game_mode() const { return game_mode_; }

void NativeSandWorld::initialize_progression() {
    game_mode_ = 0;
    bank_glass_ = bank_iron_ = bank_gold_ = 0;
    unlocked_research_.clear();
    unlocked_research_.insert("foundation.basic_industry");
    ++progression_revision_;
}

Array NativeSandWorld::get_research_definitions() const {
    Array result;
    for (const ResearchDefinition &definition : research_definitions()) {
        Dictionary item;
        item["id"] = String(definition.id);
        item["display_name"] = String(definition.display_name);
        item["description"] = String(definition.description);
        Array prerequisites;
        for (const char *prerequisite : definition.prerequisites) prerequisites.push_back(String(prerequisite));
        item["prerequisites"] = prerequisites;
        Dictionary costs;
        costs["glass"] = definition.glass_cost;
        costs["iron"] = definition.iron_cost;
        costs["gold"] = definition.gold_cost;
        item["costs"] = costs;
        item["effect"] = String(definition.effect);
        item["tree_position"] = Vector2i(definition.tree_x, definition.tree_y);
        result.push_back(item);
    }
    return result;
}

Dictionary NativeSandWorld::get_progression_state() const {
    Dictionary result;
    result["schema_version"] = PROGRESSION_SCHEMA_VERSION;
    result["definition_version"] = 1;
    result["game_mode"] = game_mode_;
    result["glass"] = bank_glass_;
    result["iron"] = bank_iron_;
    result["gold"] = bank_gold_;
    result["revision"] = static_cast<int64_t>(progression_revision_);
    Array unlocked;
    std::vector<std::string> ids(unlocked_research_.begin(), unlocked_research_.end());
    std::sort(ids.begin(), ids.end());
    for (const std::string &id : ids) unlocked.push_back(String(id.c_str()));
    result["unlocked"] = unlocked;
    return result;
}

Dictionary NativeSandWorld::get_research_state(String research_id) const {
    Dictionary result;
    const std::string id(research_id.utf8().get_data());
    const ResearchDefinition *definition = research_definition(id);
    if (definition == nullptr) return result;
    const bool unlocked = has_research(definition->id);
    bool prerequisites_met = true;
    for (const char *prerequisite : definition->prerequisites) prerequisites_met = prerequisites_met && has_research(prerequisite);
    const bool affordable = bank_glass_ >= definition->glass_cost && bank_iron_ >= definition->iron_cost && bank_gold_ >= definition->gold_cost;
    result["unlocked"] = unlocked;
    result["prerequisites_met"] = prerequisites_met;
    result["affordable"] = affordable;
    result["available"] = !unlocked && prerequisites_met;
    return result;
}

bool NativeSandWorld::try_unlock_research(String research_id) {
    if (game_mode_ == 1) return false;
    const std::string id(research_id.utf8().get_data());
    const ResearchDefinition *definition = research_definition(id);
    if (definition == nullptr || unlocked_research_.find(id) != unlocked_research_.end()) return false;
    for (const char *prerequisite : definition->prerequisites) if (!has_research(prerequisite)) return false;
    if (bank_glass_ < definition->glass_cost || bank_iron_ < definition->iron_cost || bank_gold_ < definition->gold_cost) return false;
    bank_glass_ -= definition->glass_cost;
    bank_iron_ -= definition->iron_cost;
    bank_gold_ -= definition->gold_cost;
    unlocked_research_.insert(id);
    ++progression_revision_;
    for (const auto &[machine_id, machine] : machine_entities_) if (machine.type_id == STRUCTURE_RESEARCH_BANK) active_machines_.insert(machine_id);
    return true;
}

bool NativeSandWorld::structure_unlocked(int32_t type_id) const {
    if (game_mode_ == 1) return true;
    if (type_id == STRUCTURE_SIEVE) return has_research("processing.dry_separation");
    if (type_id == STRUCTURE_MAGNETIC_SEPARATOR) return has_research("processing.ferrous_separation");
    if (type_id == STRUCTURE_CONTROL_GATE) return has_research("automation.advanced_routing");
    if (type_id >= STRUCTURE_PIPE && type_id <= STRUCTURE_BASIC_PUMP) return has_research("fluid.basic_handling");
    if (type_id == STRUCTURE_PIPE_VALVE) return has_research("fluid.flow_control");
    if (type_id == STRUCTURE_RESERVOIR_WALL) return has_research("fluid.basic_handling");
    if (type_id == STRUCTURE_WASH_SLUICE) return has_research("processing.wet_separation");
    if (type_id == STRUCTURE_THERMAL_SWITCH) return has_research("thermal.basic_thermodynamics");
    if (type_id == STRUCTURE_HEAT_EXCHANGER) return has_research("thermal.phase_processing");
    if (type_id >= STRUCTURE_SHAFT && type_id <= STRUCTURE_GENERATOR) return has_research("power.steam_generation");
    if (type_id == STRUCTURE_POWER_POLE || type_id == STRUCTURE_POWER_SWITCH) return has_research("power.electrical_distribution");
    if (type_id == STRUCTURE_ACCUMULATOR) return has_research("power.energy_storage");
    if (type_id == STRUCTURE_TRANSFORMER) return has_research("power.grid_control");
    if (type_id == STRUCTURE_FLYWHEEL) return has_research("power.mechanical_storage");
    if (type_id == STRUCTURE_RESISTIVE_HEATER) return has_research("power.electrified_industry");
    if (type_id == STRUCTURE_IRON_POT) return has_research("thermal.cookware");
    if (type_id == STRUCTURE_CERAMIC_TEST_VESSEL) return true;
    if (type_id == STRUCTURE_STRUCTURAL_WALL) return has_research("foundation.basic_industry");
    if (type_id == STRUCTURE_METAL_PLATE || type_id == STRUCTURE_ELECTROMAGNET) return has_research("processing.ferrous_separation");
    if (type_id == STRUCTURE_CERAMIC_WALL || type_id == STRUCTURE_REFRACTORY_WALL) return has_research("thermal.phase_processing");
    if (type_id == STRUCTURE_MESH_SCREEN || type_id == STRUCTURE_VIBRATION_ACTUATOR) return has_research("processing.dry_separation");
    if (type_id == STRUCTURE_GRATE) return has_research("organic.wood_processing");
    if (type_id == STRUCTURE_RIFFLE) return has_research("processing.wet_separation");
    if (type_id == STRUCTURE_THERMAL_INSULATOR || type_id == STRUCTURE_BLOWER) return has_research("thermal.basic_thermodynamics");
    if (type_id == 18 || type_id == 19) return has_research("logistics.subsurface_1");
    if (type_id == 20 || type_id == 21) return has_research("logistics.subsurface_2");
    if (type_id == 22 || type_id == 23) return has_research("logistics.subsurface_3");
    return structure_definition(type_id) != nullptr;
}

bool NativeSandWorld::is_structure_unlocked(int32_t type_id) const { return structure_unlocked(type_id); }

Dictionary NativeSandWorld::serialize_progression_state() const { return get_progression_state(); }

bool NativeSandWorld::deserialize_progression_state(Dictionary state) {
    if (!state.has("schema_version") || static_cast<int32_t>(state["schema_version"]) != PROGRESSION_SCHEMA_VERSION ||
        !state.has("glass") || !state.has("iron") || !state.has("gold") || !state.has("unlocked")) return false;
    const int64_t glass = state["glass"], iron = state["iron"], gold = state["gold"];
    if (glass < 0 || iron < 0 || gold < 0) return false;
    const Array unlocked = state["unlocked"];
    std::unordered_set<std::string> validated;
    for (int32_t index = 0; index < unlocked.size(); ++index) {
        const String value = unlocked[index];
        const std::string id(value.utf8().get_data());
        if (research_definition(id) == nullptr) return false;
        validated.insert(id);
    }
    if (validated.find("foundation.basic_industry") == validated.end()) return false;
    for (const std::string &id : validated) {
        const ResearchDefinition *definition = research_definition(id);
        for (const char *prerequisite : definition->prerequisites) if (validated.find(prerequisite) == validated.end()) return false;
    }
    bank_glass_ = glass; bank_iron_ = iron; bank_gold_ = gold;
    unlocked_research_.swap(validated);
    game_mode_ = state.has("game_mode") && static_cast<int32_t>(state["game_mode"]) == 1 ? 1 : 0;
    ++progression_revision_;
    return true;
}

bool NativeSandWorld::credit_research_material_for_test(int32_t material_id, int64_t amount) {
    if (game_mode_ != 1 || amount < 0) return false;
    int64_t *target = material_id == GLASS_ID ? &bank_glass_ : material_id == IRON_ID ? &bank_iron_ : material_id == GOLD_ID ? &bank_gold_ : nullptr;
    if (target == nullptr || amount > std::numeric_limits<int64_t>::max() - *target) return false;
    *target += amount;
    ++progression_revision_;
    return true;
}

int32_t NativeSandWorld::conveyor_ticks_per_cell() const { return has_research("logistics.belt_drive_1") ? 1 : BASIC_CONVEYOR_TICKS_PER_CELL; }
int32_t NativeSandWorld::furnace_fuel_units() const { return has_research("furnace.fuel_economy_1") ? 96 : FURNACE_FUEL_UNITS; }

Dictionary NativeSandWorld::get_memory_layout() const {
    Dictionary result;
    result["material_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t));
    result["temperature_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t));
    result["temperature_storage"] = "uint16";
    result["temperature_unit"] = "quarter_kelvin";
    result["temperature_units_per_kelvin"] = 4;
    result["temperature_precision_kelvin"] = 0.25;
    result["temperature_min_units"] = 0;
    result["temperature_max_units"] = static_cast<int32_t>(TEMPERATURE_MAX);
    result["temperature_min_kelvin"] = 0.0;
    result["temperature_max_kelvin"] = 16383.75;
    result["temperature_ambient_units"] = static_cast<int32_t>(TEMPERATURE_AMBIENT);
    result["temperature_saturation"] = true;
    result["flags_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint8_t));
    result["base_simulation_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t) + sizeof(uint16_t) + sizeof(uint8_t));
    result["provenance_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t));
    result["mineral_signature_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t));
    result["simulation_bytes_per_cell"] = static_cast<int32_t>(sizeof(uint16_t) + sizeof(uint16_t) + sizeof(uint8_t) + sizeof(uint16_t) + sizeof(uint16_t));
    result["invalid_api_sentinel"] = UNGENERATED_ID;
    result["maximum_material_id"] = MAX_MATERIAL_ID;
    result["rgba_cache_bytes_per_cell"] = 4;
    result["structure_bytes_per_cell_when_allocated"] = static_cast<int32_t>(sizeof(uint8_t));
    int64_t structure_chunks = 0;
    for (const auto &[key, chunk] : chunks_) {
        (void)key;
        structure_chunks += chunk->structures != nullptr ? 1 : 0;
    }
    result["structure_backing_bytes"] = structure_chunks * CELLS_PER_CHUNK;
    int64_t liquid_planes = 0;
    for (const auto &[key, chunk] : chunks_) { (void)key; liquid_planes += chunk->material_amount != nullptr ? 1 : 0; }
    result["liquid_mass_bytes_per_allocated_fluid_chunk"] = CELLS_PER_CHUNK;
    result["liquid_mass_plane_chunks"] = liquid_planes;
    result["liquid_mass_backing_bytes"] = liquid_planes * CELLS_PER_CHUNK;
    result["material_amount_bytes_per_allocated_chunk"] = CELLS_PER_CHUNK;
    result["material_amount_plane_chunks"] = liquid_planes;
    result["material_amount_backing_bytes"] = liquid_planes * CELLS_PER_CHUNK;
    int64_t phase_planes = 0;
    for (const auto &[key, chunk] : chunks_) { (void)key; phase_planes += chunk->phase_energy != nullptr ? 1 : 0; }
    result["phase_energy_bytes_per_allocated_chunk"] = CELLS_PER_CHUNK * 2;
    result["phase_energy_plane_chunks"] = phase_planes;
    result["phase_energy_backing_bytes"] = phase_planes * CELLS_PER_CHUNK * 2;
    int64_t moisture_planes = 0, oxidizer_planes = 0, reaction_planes = 0;
    for (const auto &[key, chunk] : chunks_) {
        (void)key;
        moisture_planes += chunk->organic_moisture != nullptr ? 1 : 0;
        oxidizer_planes += chunk->oxidizer != nullptr ? 1 : 0;
        reaction_planes += chunk->reaction_progress != nullptr ? 1 : 0;
    }
    result["organic_moisture_plane_chunks"] = moisture_planes;
    result["organic_moisture_backing_bytes"] = moisture_planes * CELLS_PER_CHUNK;
    result["oxidizer_plane_chunks"] = oxidizer_planes;
    result["oxidizer_backing_bytes"] = oxidizer_planes * CELLS_PER_CHUNK;
    result["organic_reaction_plane_chunks"] = reaction_planes;
    result["organic_reaction_backing_bytes"] = reaction_planes * CELLS_PER_CHUNK * 3;
    int64_t cluster_cells = 0;
    for (const auto &[id, cluster] : fellable_clusters_) { (void)id; cluster_cells += static_cast<int64_t>(cluster.cells.size()); }
    result["fellable_cluster_count"] = static_cast<int64_t>(fellable_clusters_.size());
    result["fellable_cluster_cell_count"] = cluster_cells;
    result["fellable_cluster_cell_bytes"] = static_cast<int32_t>(sizeof(FellableClusterCell));
    result["fellable_cluster_cell_backing_bytes"] = cluster_cells * static_cast<int64_t>(sizeof(FellableClusterCell));
    result["thermal_activity_bytes"] = static_cast<int64_t>(chunks_.size() * sizeof(FluidActivity) * 2);
    result["liquid_activity_bytes_per_chunk"] = 136;
    result["liquid_activity_backing_bytes"] = static_cast<int64_t>(chunks_.size()) * 136;
    result["pipe_segment_bytes"] = static_cast<int32_t>(sizeof(PipeSegment));
    result["pipe_segments"] = static_cast<int64_t>(pipe_segments_.size());
    result["pipe_fluid_backing_bytes"] = static_cast<int64_t>(pipe_segments_.size() * sizeof(PipeSegment));
    result["pipe_scheduler_key_bytes"] = static_cast<int64_t>(active_pipe_segments_.size() * sizeof(uint64_t));
    int64_t subsurface_packets = 0;
    for (const auto &[id, channel] : linked_transports_) { (void)id; subsurface_packets += static_cast<int64_t>(channel.lane.size()); }
    result["subsurface_packet_bytes"] = static_cast<int32_t>(sizeof(MaterialPacket));
    result["subsurface_packet_capacity"] = subsurface_packets;
    result["subsurface_packet_backing_bytes"] = subsurface_packets * static_cast<int64_t>(sizeof(MaterialPacket));
    result["subsurface_scheduler_key_bytes"] = static_cast<int64_t>(active_linked_transports_.size() * sizeof(uint64_t));
    return result;
}

std::vector<Vector2i> NativeSandWorld::transformed_occupied(const StructureDefinition &definition, Vector2i origin, int32_t orientation) const {
    std::vector<Vector2i> result;
    result.reserve(definition.occupied.size());
    const int32_t normalized = ((orientation % 4) + 4) % 4;
    for (const Vector2i local : definition.occupied) {
        Vector2i transformed = local;
        if (normalized == 1) transformed = {definition.height - 1 - local.y, local.x};
        else if (normalized == 2) transformed = {definition.width - 1 - local.x, definition.height - 1 - local.y};
        else if (normalized == 3) transformed = {local.y, definition.width - 1 - local.x};
        result.push_back(origin + transformed);
    }
    return result;
}

Vector2i NativeSandWorld::transform_local(const StructureDefinition &definition, Vector2i local, int32_t orientation) const {
    const int32_t normalized = ((orientation % 4) + 4) % 4;
    if (normalized == 1) return {definition.height - 1 - local.y, local.x};
    if (normalized == 2) return {definition.width - 1 - local.x, definition.height - 1 - local.y};
    if (normalized == 3) return {local.y, definition.width - 1 - local.x};
    return local;
}

bool NativeSandWorld::is_processing_machine(int32_t type_id) {
    return type_id == STRUCTURE_RESEARCH_BANK;
}

Vector2i NativeSandWorld::machine_port(const MachineEntity &entity, int32_t index, bool output) const {
    const StructureDefinition *definition = structure_definition(entity.type_id);
    if (definition == nullptr) return entity.origin;
    const auto &ports = output ? definition->output_ports : definition->input_ports;
    if (index < 0 || index >= static_cast<int32_t>(ports.size())) return entity.origin;
    return entity.origin + transform_local(*definition, ports[index], entity.orientation);
}

void NativeSandWorld::register_machine_ports(const MachineEntity &entity) {
    if (!is_processing_machine(entity.type_id)) return;
    const StructureDefinition *definition = structure_definition(entity.type_id);
    for (const Vector2i local : definition->input_ports) machine_port_watchers_[cell_key(entity.origin + transform_local(*definition, local, entity.orientation))].push_back(entity.id);
    for (const Vector2i local : definition->output_ports) machine_port_watchers_[cell_key(entity.origin + transform_local(*definition, local, entity.orientation))].push_back(entity.id);
    active_machines_.insert(entity.id);
}

void NativeSandWorld::unregister_machine_ports(const MachineEntity &entity) {
    if (!is_processing_machine(entity.type_id)) return;
    for (auto iterator = machine_port_watchers_.begin(); iterator != machine_port_watchers_.end();) {
        auto &ids = iterator->second;
        ids.erase(std::remove(ids.begin(), ids.end(), entity.id), ids.end());
        if (ids.empty()) iterator = machine_port_watchers_.erase(iterator); else ++iterator;
    }
    active_machines_.erase(entity.id);
}

void NativeSandWorld::activate_machines_at_port(Vector2i world_cell) {
    const auto found = machine_port_watchers_.find(cell_key(world_cell));
    if (found == machine_port_watchers_.end()) return;
    for (const uint64_t id : found->second) active_machines_.insert(id);
}

bool NativeSandWorld::ensure_structure_chunks_generated(const std::vector<Vector2i> &cells) {
    for (const Vector2i cell : cells) {
        if (world_generation_enabled_ && !is_inside_virtual_world(cell)) return false;
        const Vector2i coordinate = world_to_chunk(cell);
        if (world_generation_enabled_) ensure_generated_for_edit(coordinate);
        else get_or_create_chunk(coordinate);
    }
    return true;
}

bool NativeSandWorld::can_place_structure(int32_t type_id, Vector2i origin, int32_t orientation) const {
    const StructureDefinition *definition = structure_definition(type_id);
    if (definition == nullptr || !structure_unlocked(type_id)) return false;
    const std::vector<Vector2i> cells = transformed_occupied(*definition, origin, orientation);
    for (const Vector2i cell : cells) {
        if (world_generation_enabled_ && (!is_inside_virtual_world(cell) || !is_chunk_generated(world_to_chunk(cell)))) return false;
        if (get_cell(cell) != EMPTY_ID || get_structure(cell) != STRUCTURE_NONE) return false;
    }
    return true;
}

void NativeSandWorld::mark_structure_chunk_dirty(Vector2i coordinate) {
    Chunk *chunk = get_chunk(coordinate);
    if (chunk == nullptr || chunk->structure_render_dirty) return;
    chunk->structure_render_dirty = true;
    dirty_structure_chunks_.push_back(coordinate);
}

void NativeSandWorld::set_structure_cell(Vector2i world_cell, uint8_t type_id) {
    Chunk *chunk = get_or_create_chunk(world_to_chunk(world_cell));
    if (chunk->structures == nullptr) {
        chunk->structures = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
        chunk->structures->fill(0);
    }
    const int32_t index = local_index(world_to_local(world_cell));
    if ((*chunk->structures)[index] != STRUCTURE_NONE) return;
    (*chunk->structures)[index] = type_id;
    chunk->pristine = false;
    ++structures_allocated_;
    if (type_id == STRUCTURE_CONVEYOR_LEFT || type_id == STRUCTURE_CONVEYOR_RIGHT) ++belts_total_;
    if (type_id == STRUCTURE_THERMAL_SWITCH) thermal_switch_cells_.insert(cell_key(world_cell));
    if (type_id == STRUCTURE_HEAT_EXCHANGER) heat_exchanger_cells_.insert(cell_key(world_cell));
    if (type_id == STRUCTURE_REFRACTORY_WALL || type_id == STRUCTURE_MESH_SCREEN || type_id == STRUCTURE_RIFFLE || type_id == STRUCTURE_VIBRATION_ACTUATOR || type_id == STRUCTURE_ELECTROMAGNET)
        component_processing_cells_.insert(cell_key(world_cell));
    if (type_id >= STRUCTURE_STRUCTURAL_WALL && type_id <= STRUCTURE_THERMAL_INSULATOR)
        thermal_component_cells_.insert(cell_key(world_cell));
    ++structure_revision_;
    mark_structure_chunk_dirty(chunk->coordinate);
    wake_after_structure_change(world_cell);
}

void NativeSandWorld::clear_structure_cell(Vector2i world_cell) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr || chunk->structures == nullptr) return;
    const int32_t index = local_index(world_to_local(world_cell));
    const uint8_t previous = (*chunk->structures)[index] & 0x7fu;
    if (previous == STRUCTURE_NONE) return;
    (*chunk->structures)[index] = STRUCTURE_NONE;
    if (previous == STRUCTURE_CONVEYOR_LEFT || previous == STRUCTURE_CONVEYOR_RIGHT) {
        --belts_total_;
        active_belts_.erase(cell_key(world_cell));
    }
    if (previous == STRUCTURE_THERMAL_SWITCH) { thermal_switch_cells_.erase(cell_key(world_cell)); closed_thermal_switches_.erase(cell_key(world_cell)); }
    if (previous == STRUCTURE_HEAT_EXCHANGER) heat_exchanger_cells_.erase(cell_key(world_cell));
    if (previous == STRUCTURE_REFRACTORY_WALL || previous == STRUCTURE_MESH_SCREEN || previous == STRUCTURE_RIFFLE || previous == STRUCTURE_VIBRATION_ACTUATOR || previous == STRUCTURE_ELECTROMAGNET)
        component_processing_cells_.erase(cell_key(world_cell));
    if (previous >= STRUCTURE_STRUCTURAL_WALL && previous <= STRUCTURE_THERMAL_INSULATOR)
        thermal_component_cells_.erase(cell_key(world_cell));
    --structures_allocated_;
    ++structure_revision_;
    mark_structure_chunk_dirty(chunk->coordinate);
    wake_after_structure_change(world_cell);
}

void NativeSandWorld::wake_after_structure_change(Vector2i world_cell) {
    for (int32_t y = -2; y <= 1; ++y) {
        for (int32_t x = -2; x <= 2; ++x) {
            activate_world_cell(world_cell + Vector2i(x, y), 1);
            activate_fluid_world_cell(world_cell + Vector2i(x, y), 1);
            activate_thermal_world_cell(world_cell + Vector2i(x, y), 1);
        }
    }
    activate_belts_near(world_cell);
}

int64_t NativeSandWorld::place_structure(int32_t type_id, Vector2i origin, int32_t orientation) {
    const StructureDefinition *definition = structure_definition(type_id);
    if (definition == nullptr) return 0;
    const std::vector<Vector2i> cells = transformed_occupied(*definition, origin, orientation);
    if (!ensure_structure_chunks_generated(cells) || !can_place_structure(type_id, origin, orientation)) return 0;
    for (const Vector2i cell : cells) set_structure_cell(cell, static_cast<uint8_t>(type_id));
    if (is_pipe_structure(type_id)) for (const Vector2i cell : cells) register_pipe_segment(cell, type_id, orientation);
    if (definition->tile_like) {
        if (is_power_structure(type_id)) for (const Vector2i cell : cells) register_power_tile(type_id, cell, orientation);
        return 1;
    }
    const uint64_t id = next_machine_id_++;
    MachineEntity entity;
    entity.id = id;
    entity.type_id = type_id;
    entity.origin = origin;
    entity.orientation = orientation;
    machine_entities_.emplace(id, entity);
    register_machine_ports(machine_entities_.at(id));
    register_physical_processor(machine_entities_.at(id));
    if (is_power_structure(type_id)) register_power_structure(machine_entities_.at(id));
    return static_cast<int64_t>(id);
}

int32_t NativeSandWorld::place_conveyor_line(Vector2i from, Vector2i to, int32_t direction) {
    if (from.y != to.y || (direction != -1 && direction != 1)) return -1;
    const int32_t type_id = direction < 0 ? STRUCTURE_CONVEYOR_LEFT : STRUCTURE_CONVEYOR_RIGHT;
    const int32_t first = std::min(from.x, to.x);
    const int32_t last = std::max(from.x, to.x);
    std::vector<Vector2i> cells;
    cells.reserve(last - first + 1);
    for (int32_t x = first; x <= last; ++x) cells.push_back({x, from.y});
    if (!ensure_structure_chunks_generated(cells) || !can_place_conveyor_line(from, to, direction)) return -1;
    int32_t placed = 0;
    for (const Vector2i cell : cells) {
        if (get_structure(cell) == type_id) continue;
        set_structure_cell(cell, static_cast<uint8_t>(type_id));
        ++placed;
    }
    return placed;
}

int32_t NativeSandWorld::place_pipe_line(Vector2i from, Vector2i to) {
    if (from.x != to.x && from.y != to.y) return -1;
    std::vector<Vector2i> cells;
    if (from.y == to.y) {
        for (int32_t x = std::min(from.x, to.x); x <= std::max(from.x, to.x); ++x) cells.push_back({x, from.y});
    } else {
        for (int32_t y = std::min(from.y, to.y); y <= std::max(from.y, to.y); ++y) cells.push_back({from.x, y});
    }
    if (!ensure_structure_chunks_generated(cells)) return -1;
    for (const Vector2i cell : cells) if (get_cell(cell) != EMPTY_ID || (get_structure(cell) != STRUCTURE_NONE && get_structure(cell) != STRUCTURE_PIPE)) return -1;
    int32_t placed = 0;
    const int32_t orientation = from.y == to.y ? 0 : 1;
    for (const Vector2i cell : cells) if (get_structure(cell) == STRUCTURE_NONE) {
        set_structure_cell(cell, STRUCTURE_PIPE);
        register_pipe_segment(cell, STRUCTURE_PIPE, orientation);
        ++placed;
    }
    return placed;
}

bool NativeSandWorld::can_place_conveyor_line(Vector2i from, Vector2i to, int32_t direction) const {
    if (from.y != to.y || (direction != -1 && direction != 1)) return false;
    const int32_t type_id = direction < 0 ? STRUCTURE_CONVEYOR_LEFT : STRUCTURE_CONVEYOR_RIGHT;
    const int32_t first = std::min(from.x, to.x);
    const int32_t last = std::max(from.x, to.x);
    for (int32_t x = first; x <= last; ++x) {
        const Vector2i cell{x, from.y};
        if (world_generation_enabled_ && (!is_inside_virtual_world(cell) || !is_chunk_generated(world_to_chunk(cell)))) return false;
        const int32_t current = get_structure(cell);
        if (get_cell(cell) != EMPTY_ID || (current != STRUCTURE_NONE && current != type_id)) return false;
    }
    return true;
}

int32_t NativeSandWorld::get_structure(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr || chunk->structures == nullptr) return STRUCTURE_NONE;
    return (*chunk->structures)[local_index(world_to_local(world_cell))] & 0x7fu;
}

int32_t NativeSandWorld::remove_structure_at(Vector2i world_cell) {
    const int32_t type_id = get_structure(world_cell);
    if (type_id == STRUCTURE_NONE) return 0;
    const auto linked = subsurface_endpoint_channels_.find(cell_key(world_cell));
    if (linked != subsurface_endpoint_channels_.end()) return remove_subsurface_channel(static_cast<int64_t>(linked->second), 1) ? 2 : 0;
    if (type_id == STRUCTURE_CONVEYOR_LEFT || type_id == STRUCTURE_CONVEYOR_RIGHT) {
        clear_structure_cell(world_cell);
        return 1;
    }
    const StructureDefinition *structure = structure_definition(type_id);
    if (structure != nullptr && structure->tile_like) {
        if (structure_has_fractional_contents(world_cell)) {
            ++conservation_rejected_removals_;
            return 0;
        }
        if (is_pipe_structure(type_id) && !unregister_pipe_segment(world_cell, true)) return 1;
        if (is_power_structure(type_id)) unregister_power_tile(type_id, world_cell);
        clear_structure_cell(world_cell);
        std::vector<uint64_t> attached_automation;
        for (const auto &[id, component] : automation_components_) {
            if (component.type_id == 13 && component.target_position == world_cell) attached_automation.push_back(id);
        }
        for (const uint64_t id : attached_automation) remove_automation_component(static_cast<int64_t>(id));
        open_gate_cells_.erase(cell_key(world_cell));
        return 1;
    }
    uint64_t found_id = 0;
    std::vector<Vector2i> found_cells;
    for (const auto &[id, entity] : machine_entities_) {
        if (entity.type_id != type_id) continue;
        const StructureDefinition *definition = structure_definition(entity.type_id);
        const std::vector<Vector2i> cells = transformed_occupied(*definition, entity.origin, entity.orientation);
        if (std::find(cells.begin(), cells.end(), world_cell) != cells.end()) {
            found_id = id;
            found_cells = cells;
            break;
        }
    }
    if (found_id == 0) return 0;
    MachineEntity &removed_machine = machine_entities_.at(found_id);
    if (removed_machine.type_id == STRUCTURE_IRON_POT || removed_machine.type_id == STRUCTURE_CERAMIC_TEST_VESSEL) {
        for (int32_t y = 0; y < 5; ++y) for (int32_t x = 1; x < 8; ++x)
            if (get_cell(removed_machine.origin + Vector2i(x, y)) != EMPTY_ID) return 0;
    }
    if (is_processing_machine(removed_machine.type_id)) {
        struct Spill { Vector2i cell; uint16_t material; uint16_t provenance; uint16_t signature; };
        std::vector<Spill> spills;
        if (removed_machine.input_material != EMPTY_ID) spills.push_back({machine_port(removed_machine, 0, false), removed_machine.input_material, removed_machine.input_provenance, removed_machine.input_signature});
        if (removed_machine.fuel_remaining > 0) spills.push_back({machine_port(removed_machine, 1, false), COAL_CHUNK_ID, 0, 0});
        if (removed_machine.result_material != EMPTY_ID) {
            int32_t output_index = 0;
            if (removed_machine.type_id == STRUCTURE_SIEVE) output_index = removed_machine.result_material == HEAVY_CONCENTRATE_ID ? 1 : 0;
            else if (removed_machine.type_id == STRUCTURE_MAGNETIC_SEPARATOR) output_index = removed_machine.result_material == NONMAGNETIC_CONCENTRATE_ID ? 1 : 0;
            spills.push_back({machine_port(removed_machine, output_index, true), removed_machine.result_material, removed_machine.result_provenance, removed_machine.result_signature});
        }
        if (removed_machine.ash_material != EMPTY_ID) spills.push_back({machine_port(removed_machine, 1, true), ASH_ID, 0, 0});
        for (const Spill &spill : spills) if (!is_empty_for_material(spill.cell)) return 0;
        for (const Spill &spill : spills) emit_cell(spill.cell, spill.material, spill.provenance, spill.signature);
    }
    for (const Vector2i cell : found_cells) clear_structure_cell(cell);
    if (is_power_structure(removed_machine.type_id)) unregister_power_structure(found_id);
    unregister_machine_ports(removed_machine);
    unregister_physical_processor(found_id);
    machine_entities_.erase(found_id);
    return static_cast<int32_t>(found_cells.size());
}

int32_t NativeSandWorld::remove_structures_rect(Rect2i area) {
    Vector2i end;
    if (!checked_rect_end(area, 1'048'576, end)) return -1;
    std::vector<Vector2i> targets;
    for (int32_t y = area.position.y; y < end.y; ++y) {
        for (int32_t x = area.position.x; x < end.x; ++x) if (get_structure({x, y}) != STRUCTURE_NONE) targets.push_back({x, y});
    }
    const int64_t before = structures_allocated_;
    for (const Vector2i target : targets) remove_structure_at(target);
    return static_cast<int32_t>(before - structures_allocated_);
}

PackedInt32Array NativeSandWorld::get_visible_structure_cells(Rect2i chunk_area) const {
    PackedInt32Array result;
    Vector2i end;
    if (!checked_rect_end(chunk_area, 4096, end)) return result;
    for (const Chunk *chunk : sorted_chunks()) {
        if (chunk->structures == nullptr || chunk->coordinate.x < chunk_area.position.x || chunk->coordinate.x >= end.x ||
            chunk->coordinate.y < chunk_area.position.y || chunk->coordinate.y >= end.y) continue;
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const uint8_t type_id = (*chunk->structures)[index] & 0x7fu;
            if (type_id == STRUCTURE_NONE) continue;
            result.push_back(origin.x + index % CHUNK_SIZE);
            result.push_back(origin.y + index / CHUNK_SIZE);
            result.push_back(type_id);
        }
    }
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_machine_entities(Rect2i chunk_area) const {
    PackedInt32Array result;
    const Rect2i cell_area(chunk_area.position * CHUNK_SIZE, chunk_area.size * CHUNK_SIZE);
    std::vector<const MachineEntity *> entities;
    entities.reserve(machine_entities_.size());
    for (const auto &[id, entity] : machine_entities_) {
        (void)id;
        entities.push_back(&entity);
    }
    std::sort(entities.begin(), entities.end(), [](const MachineEntity *a, const MachineEntity *b) { return a->id < b->id; });
    for (const MachineEntity *entity_ptr : entities) {
        const MachineEntity &entity = *entity_ptr;
        const StructureDefinition *definition = structure_definition(entity.type_id);
        if (definition == nullptr) continue;
        const int32_t normalized = ((entity.orientation % 4) + 4) % 4;
        const Vector2i size = (normalized & 1) == 0 ? Vector2i(definition->width, definition->height) : Vector2i(definition->height, definition->width);
        if (!cell_area.intersects(Rect2i(entity.origin, size))) continue;
        result.push_back(entity.origin.x);
        result.push_back(entity.origin.y);
        result.push_back(entity.type_id);
        result.push_back(normalized);
        result.push_back(size.x);
        result.push_back(size.y);
        int32_t visual_state = entity.state;
        const auto turbine = turbines_.find(entity.id); if (turbine != turbines_.end()) visual_state = turbine->second.state;
        const auto generator = generators_.find(entity.id); if (generator != generators_.end()) visual_state = generator->second.state;
        result.push_back(visual_state);
        int32_t visual_progress = entity.progress_ticks;
        const auto power_member = mechanical_members_.find((UINT64_C(0x8000000000000000) | entity.id));
        if (power_member != mechanical_members_.end()) visual_progress = static_cast<int32_t>(std::min<int64_t>(4000000, mechanical_speed_for_member(power_member->first)));
        result.push_back(visual_progress);
    }
    return result;
}

Array NativeSandWorld::consume_dirty_structure_chunks() {
    std::sort(dirty_structure_chunks_.begin(), dirty_structure_chunks_.end(), [](Vector2i a, Vector2i b) {
        return a.y < b.y || (a.y == b.y && a.x < b.x);
    });
    Array result;
    for (const Vector2i coordinate : dirty_structure_chunks_) {
        result.push_back(coordinate);
        Chunk *chunk = get_chunk(coordinate);
        if (chunk != nullptr) chunk->structure_render_dirty = false;
    }
    dirty_structure_chunks_.clear();
    return result;
}

// Wake any Conveyor that could carry matter now sitting in this cell.
//
// A belt carries what rests one cell above it, so the three candidates are horizontally
// adjacent on a single row and nearly always share one chunk. Asking the chunk map for each of
// them separately cost three lookups per moved cell, on a path that runs for every cell of
// every falling pile as soon as a world contains any belt at all. Resolve the row once, and
// leave immediately when that chunk holds no structures -- which is most of the world.
void NativeSandWorld::activate_belts_near(Vector2i material_cell) {
    if (belts_total_ == 0) return;
    const Vector2i below = material_cell + Vector2i(0, 1);
    const Vector2i row_chunk = world_to_chunk(below);
    const Chunk *chunk = get_chunk(row_chunk);
    const Vector2i local = below - row_chunk * CHUNK_SIZE;
    for (int32_t offset_x = -1; offset_x <= 1; ++offset_x) {
        const int32_t column = local.x + offset_x;
        const Chunk *holder = chunk;
        int32_t index = 0;
        if (static_cast<uint32_t>(column) < static_cast<uint32_t>(CHUNK_SIZE)) {
            if (holder == nullptr || holder->structures == nullptr) continue;
            index = local.y * CHUNK_SIZE + column;
        } else {
            // Only the two cells that fall off the edge of the row need their own lookup.
            const Vector2i belt = below + Vector2i(offset_x, 0);
            holder = get_chunk(world_to_chunk(belt));
            if (holder == nullptr || holder->structures == nullptr) continue;
            index = local_index(world_to_local(belt));
        }
        const int32_t type_id = (*holder->structures)[index] & 0x7fu;
        if (type_id == STRUCTURE_CONVEYOR_LEFT || type_id == STRUCTURE_CONVEYOR_RIGHT)
            active_belts_.insert(cell_key(below + Vector2i(offset_x, 0)));
    }
}

void NativeSandWorld::process_conveyors() {
    const auto started = std::chrono::steady_clock::now();
    last_belts_active_ = static_cast<int64_t>(active_belts_.size());
    last_belts_considered_ = 0;
    last_belt_moves_ = 0;
    last_blocked_belt_attempts_ = 0;
    if ((tick_index_ % conveyor_ticks_per_cell()) != 0) {
        last_belts_skipped_ = belts_total_;
        last_logistics_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
        return;
    }
    std::vector<Vector2i> belts;
    belts.reserve(active_belts_.size());
    for (const uint64_t key : active_belts_) belts.push_back(cell_from_key(key));
    std::sort(belts.begin(), belts.end(), [](Vector2i a, Vector2i b) { return a.y < b.y || (a.y == b.y && a.x < b.x); });
    std::unordered_set<uint64_t> next_active;
    for (const Vector2i belt : belts) {
        const Chunk *belt_chunk = get_chunk(world_to_chunk(belt));
        if (belt_chunk == nullptr || belt_chunk->structures == nullptr) continue;
        const uint8_t structure_record = (*belt_chunk->structures)[local_index(world_to_local(belt))];
        const int32_t type_id = structure_record & 0x7fu;
        if (type_id != STRUCTURE_CONVEYOR_LEFT && type_id != STRUCTURE_CONVEYOR_RIGHT) continue;
        if ((structure_record & 0x80u) != 0u) continue;
        const Vector2i source = belt + Vector2i(0, -1);
        const int32_t material_id = get_cell(source);
        if (!material_transportable(material_id)) continue;
        ++last_belts_considered_;
        if (moved_this_tick(source)) {
            next_active.insert(cell_key(belt));
            continue;
        }
        const int32_t direction = type_id == STRUCTURE_CONVEYOR_LEFT ? -1 : 1;
        const Vector2i destination = source + Vector2i(direction, 0);
        if (move_if_empty(source, destination)) {
            ++last_belt_moves_;
        } else {
            ++last_blocked_belt_attempts_;
            next_active.insert(cell_key(belt));
        }
    }
    for (const uint64_t key : active_belts_) {
        const Vector2i belt = cell_from_key(key);
        const Vector2i source = belt + Vector2i(0, -1);
        if (material_transportable(get_cell(source))) next_active.insert(key);
    }
    active_belts_.swap(next_active);
    last_belts_active_ = static_cast<int64_t>(active_belts_.size());
    last_belts_skipped_ = std::max<int64_t>(0, belts_total_ - last_belts_considered_);
    last_logistics_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

int32_t NativeSandWorld::hidden_constituent(int32_t profile_id, uint16_t signature) const {
    if (profile_id < 1 || profile_id > 65535) return OTHER;
    return static_cast<int32_t>(koalasand_core::hidden_constituent(static_cast<uint16_t>(profile_id), signature));
}

int32_t NativeSandWorld::get_hidden_constituent(int32_t profile_id, int32_t mineral_signature) const {
    if (mineral_signature < 0 || mineral_signature > 65535) return -1;
    return hidden_constituent(profile_id, static_cast<uint16_t>(mineral_signature));
}

int32_t NativeSandWorld::processing_result(int32_t material_id, int32_t profile_id, uint16_t signature, int32_t process_id) const {
    const int32_t constituent = hidden_constituent(profile_id, signature);
    if (process_id == PROCESS_SIEVE || process_id == PROCESS_SIEVE_PRECISION) {
        const bool heavy = constituent == IRON_BEARING || constituent == GOLD_BEARING ||
            (process_id == PROCESS_SIEVE_PRECISION && constituent == HEAVY_MINERAL);
        return heavy ?
            HEAVY_CONCENTRATE_ID : FINE_SAND_ID;
    }
    if (process_id == PROCESS_MAGNETIC) {
        return constituent == IRON_BEARING ? IRON_CONCENTRATE_ID : NONMAGNETIC_CONCENTRATE_ID;
    }
    // The mineral signature is generated geology/composition metadata, not a runtime yield roll.
    // Legacy DEV fixtures retain distinct recovery routes while every input still becomes exactly one output.
    if (material_id == SAND_ID) {
        if (constituent == SILICA && signature % 5u != 0u) return GLASS_ID;
        if (constituent == IRON_BEARING && signature % 4u == 0u) return IRON_ID;
        if (constituent == GOLD_BEARING && signature % 200u == 0u) return GOLD_ID;
    } else if (material_id == FINE_SAND_ID) {
        if (constituent == SILICA && signature % 20u != 0u) return GLASS_ID;
        if (constituent == IRON_BEARING && signature % 10u == 0u) return IRON_ID;
        if (constituent == GOLD_BEARING && signature % 333u == 0u) return GOLD_ID;
    } else if (material_id == HEAVY_CONCENTRATE_ID) {
        if (constituent == IRON_BEARING && signature % 2u == 0u) return IRON_ID;
        if (constituent == GOLD_BEARING && signature % 5u == 0u) return GOLD_ID;
        if (constituent == SILICA && signature % 5u == 0u) return GLASS_ID;
    } else if (material_id == IRON_CONCENTRATE_ID) {
        if (constituent == IRON_BEARING && signature % 100u < (process_id >= PROCESS_FURNACE_RECOVERY ? 97u : 90u)) return IRON_ID;
        if (constituent == GOLD_BEARING && signature % 100u < (process_id >= PROCESS_FURNACE_RECOVERY ? 12u : 8u)) return GOLD_ID;
    } else if (material_id == NONMAGNETIC_CONCENTRATE_ID) {
        if (constituent == GOLD_BEARING && signature % 10u < (process_id >= PROCESS_FURNACE_RECOVERY ? 7u : 5u)) return GOLD_ID;
        if (constituent == IRON_BEARING && signature % 100u < (process_id >= PROCESS_FURNACE_RECOVERY ? 12u : 8u)) return IRON_ID;
        if (constituent == SILICA && signature % 100u < (process_id >= PROCESS_FURNACE_RECOVERY ? 12u : 8u)) return GLASS_ID;
    }
    return CRUDE_RESIDUE_ID;
}

int32_t NativeSandWorld::process_material_for_test(int32_t material_id, int32_t profile_id, int32_t mineral_signature, int32_t process_id) const {
    if (material_id < 0 || material_id > MAX_MATERIAL_ID || profile_id < 0 || profile_id > 65535 ||
        mineral_signature < 0 || mineral_signature > 65535) return -1;
    return processing_result(material_id, profile_id, static_cast<uint16_t>(mineral_signature), process_id);
}

int32_t NativeSandWorld::process_ticks(int32_t type_id) const {
    if (type_id == STRUCTURE_FURNACE) return has_research("furnace.throughput_1") ? 3 : 4;
    if (type_id == STRUCTURE_MAGNETIC_SEPARATOR) return has_research("logistics.high_throughput_handling") ? 1 : 2;
    return 1;
}

bool NativeSandWorld::take_cell(Vector2i world_cell, uint16_t &material, uint16_t &provenance, uint16_t &signature) {
    if (moved_this_tick(world_cell)) return false;
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return false;
    const int32_t index = local_index(world_to_local(world_cell));
    if (chunk->material[index] == EMPTY_ID) return false;
    material = chunk->material[index];
    provenance = chunk->provenance[index];
    signature = chunk->mineral_signature[index];
    chunk->material[index] = EMPTY_ID;
    chunk->provenance[index] = 0;
    chunk->mineral_signature[index] = 0;
    chunk->temperature[index] = TEMPERATURE_AMBIENT;
    chunk->flags[index] = 0;
    ++chunk->revision;
    chunk->pristine = false;
    activate_world_cell(world_cell + Vector2i(0, -1));
    mark_render_world_cell(world_cell);
    activate_belts_near(world_cell);
    activate_machines_at_port(world_cell);
    wake_subsurface_at(world_cell);
    activate_physical_near(world_cell);
    notify_automation_cell_change(world_cell);
    return true;
}

bool NativeSandWorld::emit_cell(Vector2i world_cell, uint16_t material, uint16_t provenance, uint16_t signature) {
    if (!is_empty_for_material(world_cell)) return false;
    if (set_cell_with_metadata(world_cell, material, provenance, signature) != 0) return false;
    mark_moved_this_tick(world_cell);
    return true;
}

void NativeSandWorld::process_machines() {
    const auto started = std::chrono::steady_clock::now();
    last_machines_active_ = static_cast<int64_t>(active_machines_.size());
    last_machines_visited_ = last_machine_inputs_ = last_machine_outputs_ = last_machine_blocked_ = last_fuel_starved_ = 0;
    last_banks_active_ = last_banks_visited_ = last_bank_accepted_ = last_bank_rejected_ = last_bank_blocked_ = last_bank_usec_ = 0;
    std::vector<uint64_t> ids(active_machines_.begin(), active_machines_.end());
    std::sort(ids.begin(), ids.end());
    std::unordered_set<uint64_t> next_active;
    for (const uint64_t id : ids) {
        auto found = machine_entities_.find(id);
        if (found == machine_entities_.end() || !is_processing_machine(found->second.type_id)) continue;
        MachineEntity &machine = found->second;
        const int32_t previous_visual_state = machine.state;
        ++last_machines_visited_;
        bool keep_active = false;
        bool blocked = false;

        if (machine.control_connected && !machine.control_enabled) {
            machine.state = 10;
            if (machine.state != previous_visual_state) {
                ++machine_visual_revision_;
                notify_automation_machine_change(id);
            }
            continue;
        }

        if (machine.type_id == STRUCTURE_RESEARCH_BANK) {
            const auto bank_started = std::chrono::steady_clock::now();
            ++last_banks_active_;
            ++last_banks_visited_;
            if (machine.result_material != EMPTY_ID) {
                if (emit_cell(machine_port(machine, 0, true), machine.result_material, machine.result_provenance, machine.result_signature)) {
                    machine.result_material = EMPTY_ID;
                    ++machine.emitted_cells;
                    ++last_machine_outputs_;
                    ++last_bank_rejected_;
                    ++total_bank_rejected_;
                    machine.state = MACHINE_REJECTING;
                } else {
                    machine.state = MACHINE_REJECT_BLOCKED;
                    ++last_bank_blocked_;
                    ++last_machine_blocked_;
                    keep_active = true;
                }
            }
            if (machine.result_material == EMPTY_ID) {
                const Vector2i input_port = machine_port(machine, 0, false);
                const int32_t offered = get_cell(input_port);
                if (offered != EMPTY_ID && !moved_this_tick(input_port)) {
                    const bool useful = offered == GLASS_ID || offered == IRON_ID || offered == GOLD_ID;
                    const int64_t current_reserve = offered == GLASS_ID ? bank_glass_ : offered == IRON_ID ? bank_iron_ : offered == GOLD_ID ? bank_gold_ : 0;
                    if (useful && current_reserve == std::numeric_limits<int64_t>::max()) {
                        machine.state = MACHINE_INPUT_BLOCKED;
                        if (machine.state != previous_visual_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
                        last_bank_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - bank_started).count();
                        continue;
                    }
                    uint16_t material = 0, provenance = 0, signature = 0;
                    if (take_cell(input_port, material, provenance, signature)) {
                        ++last_machine_inputs_;
                        ++machine.processed_cells;
                        machine.last_process_tick = tick_index_;
                        if (material == GLASS_ID || material == IRON_ID || material == GOLD_ID) {
                            if (material == GLASS_ID) ++bank_glass_;
                            else if (material == IRON_ID) ++bank_iron_;
                            else ++bank_gold_;
                            ++last_bank_accepted_;
                            ++total_bank_accepted_;
                            record_production_event(material, 1, false);
                            record_production_flow(ProductionFlowKind::RESEARCH_BANK_DEPOSIT, 1);
                            ++progression_revision_;
                            machine.state = MACHINE_ACCEPTING;
                        } else {
                            machine.result_material = material;
                            machine.result_provenance = provenance;
                            machine.result_signature = signature;
                            machine.state = MACHINE_REJECTING;
                            keep_active = true;
                        }
                    }
                } else if (offered != EMPTY_ID) {
                    keep_active = true;
                } else if (machine.state != MACHINE_REJECTING) {
                    machine.state = MACHINE_NO_INPUT;
                }
            }
            if (machine.result_material != EMPTY_ID) keep_active = true;
            if (machine.state != previous_visual_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            if (keep_active) next_active.insert(id);
            last_bank_usec_ += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - bank_started).count();
            continue;
        }

        if (machine.ash_material != EMPTY_ID) {
            if (emit_cell(machine_port(machine, 1, true), machine.ash_material, 0, 0)) {
                machine.ash_material = EMPTY_ID;
                ++last_machine_outputs_;
                ++total_ash_;
            } else {
                machine.state = MACHINE_ASH_BLOCKED;
                blocked = keep_active = true;
            }
        }
        if (machine.result_material != EMPTY_ID) {
            int32_t output_index = 0;
            if (machine.type_id == STRUCTURE_SIEVE) output_index = machine.result_material == HEAVY_CONCENTRATE_ID ? 1 : 0;
            else if (machine.type_id == STRUCTURE_MAGNETIC_SEPARATOR) output_index = machine.result_material == NONMAGNETIC_CONCENTRATE_ID ? 1 : 0;
            if (emit_cell(machine_port(machine, output_index, true), machine.result_material, machine.result_provenance, machine.result_signature)) {
                machine.result_material = EMPTY_ID;
                ++machine.emitted_cells;
                ++last_machine_outputs_;
            } else {
                machine.state = MACHINE_OUTPUT_BLOCKED;
                blocked = keep_active = true;
            }
        }
        if (blocked) {
            ++last_machine_blocked_;
            if (machine.state != previous_visual_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            next_active.insert(id);
            continue;
        }

        if (machine.type_id == STRUCTURE_FURNACE && machine.fuel_remaining == 0 && machine.ash_material == EMPTY_ID) {
            const Vector2i fuel_port = machine_port(machine, 1, false);
            if (get_cell(fuel_port) == COAL_CHUNK_ID && !moved_this_tick(fuel_port)) {
                uint16_t material = 0, provenance = 0, signature = 0;
                if (take_cell(fuel_port, material, provenance, signature)) {
                    machine.fuel_remaining = furnace_fuel_units();
                    ++last_machine_inputs_;
                }
            }
            if (get_cell(fuel_port) == COAL_CHUNK_ID && moved_this_tick(fuel_port)) keep_active = true;
        }

        if (machine.input_material == EMPTY_ID && machine.result_material == EMPTY_ID) {
            const Vector2i input_port = machine_port(machine, 0, false);
            const int32_t offered = get_cell(input_port);
            const bool accepted = machine.type_id == STRUCTURE_SIEVE ? offered == SAND_ID :
                                  machine.type_id == STRUCTURE_MAGNETIC_SEPARATOR ? offered == HEAVY_CONCENTRATE_ID :
                                  offered == SAND_ID || (offered >= FINE_SAND_ID && offered <= NONMAGNETIC_CONCENTRATE_ID);
            if (accepted && !moved_this_tick(input_port)) {
                if (take_cell(input_port, machine.input_material, machine.input_provenance, machine.input_signature)) {
                    machine.progress_ticks = 0;
                    ++last_machine_inputs_;
                }
            }
        }

        if (machine.input_material != EMPTY_ID) {
            if (machine.type_id == STRUCTURE_FURNACE && machine.fuel_remaining <= 0) {
                machine.state = MACHINE_NO_FUEL;
                ++last_fuel_starved_;
            } else {
                machine.state = MACHINE_RUNNING;
                ++machine.progress_ticks;
                keep_active = true;
                if (machine.progress_ticks >= process_ticks(machine.type_id)) {
                    const uint16_t consumed_material = machine.input_material;
                    const int32_t process_id = machine.type_id == STRUCTURE_SIEVE ? (has_research("processing.precision_screening") ? PROCESS_SIEVE_PRECISION : PROCESS_SIEVE) :
                                               machine.type_id == STRUCTURE_MAGNETIC_SEPARATOR ? PROCESS_MAGNETIC :
                                               (has_research("processing.concentrate_recovery") && (machine.input_material == IRON_CONCENTRATE_ID || machine.input_material == NONMAGNETIC_CONCENTRATE_ID) ? PROCESS_FURNACE_RECOVERY : PROCESS_FURNACE_RAW) + machine.input_material;
                    machine.result_material = static_cast<uint16_t>(processing_result(machine.input_material, machine.input_provenance, machine.input_signature, process_id));
                    machine.result_provenance = machine.input_provenance;
                    machine.result_signature = machine.input_signature;
                    machine.last_route = machine.result_material;
                    machine.input_material = EMPTY_ID;
                    record_production_event(consumed_material, 1, false);
                    record_production_event(machine.result_material, 1, true);
                    machine.progress_ticks = 0;
                    ++machine.processed_cells;
                    machine.last_process_tick = tick_index_;
                    if (machine.type_id == STRUCTURE_SIEVE) ++total_sieve_processed_;
                    else if (machine.type_id == STRUCTURE_MAGNETIC_SEPARATOR) ++total_magnetic_processed_;
                    else {
                        ++total_furnace_processed_;
                        --machine.fuel_remaining;
                        if (machine.fuel_remaining == 0) machine.ash_material = ASH_ID;
                        if (machine.result_material == GLASS_ID) ++total_glass_;
                        else if (machine.result_material == IRON_ID) ++total_iron_;
                        else if (machine.result_material == GOLD_ID) ++total_gold_;
                        else ++total_residue_;
                    }
                    keep_active = true;
                }
            }
        } else {
            machine.state = MACHINE_NO_INPUT;
            const int32_t offered = get_cell(machine_port(machine, 0, false));
            if (offered != EMPTY_ID && moved_this_tick(machine_port(machine, 0, false))) keep_active = true;
        }
        if (machine.result_material != EMPTY_ID || machine.ash_material != EMPTY_ID) keep_active = true;
        if (machine.state != previous_visual_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
        if (keep_active) next_active.insert(id);
    }
    active_machines_.swap(next_active);
    last_machines_active_ = static_cast<int64_t>(active_machines_.size());
    last_machine_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

Dictionary NativeSandWorld::get_structure_statistics() const {
    Dictionary result;
    int64_t structure_chunks = 0;
    int64_t funnel_cells = 0;
    for (const auto &[key, chunk] : chunks_) {
        (void)key;
        if (chunk->structures == nullptr) continue;
        ++structure_chunks;
        funnel_cells += static_cast<int64_t>(std::count(chunk->structures->begin(), chunk->structures->end(), static_cast<uint8_t>(3)));
    }
    result["structures_allocated"] = structures_allocated_;
    result["structure_bearing_chunks"] = structure_chunks;
    result["structure_backing_bytes"] = structure_chunks * CELLS_PER_CHUNK;
    result["belts_total"] = belts_total_;
    result["belts_active"] = last_belts_active_;
    result["belts_considered"] = last_belts_considered_;
    result["belts_skipped"] = last_belts_skipped_;
    result["belt_moves"] = last_belt_moves_;
    result["blocked_belt_attempts"] = last_blocked_belt_attempts_;
    result["funnel_supported_cells"] = funnel_cells;
    result["machine_entities"] = static_cast<int64_t>(machine_entities_.size());
    result["structure_render_tiles"] = structures_allocated_;
    result["structure_revision"] = static_cast<int64_t>(structure_revision_);
    result["machine_visual_revision"] = static_cast<int64_t>(machine_visual_revision_);
    result["logistics_usec"] = last_logistics_usec_;
    result["processing_machines_total"] = static_cast<int64_t>(std::count_if(machine_entities_.begin(), machine_entities_.end(), [](const auto &entry) { return is_processing_machine(entry.second.type_id); }));
    result["processing_machines_active"] = last_machines_active_;
    result["processing_machines_visited"] = last_machines_visited_;
    result["machine_processing_usec"] = last_machine_usec_;
    return result;
}

Dictionary NativeSandWorld::get_processing_statistics() const {
    Dictionary result;
    int64_t total = 0;
    for (const auto &[id, machine] : machine_entities_) { (void)id; if (is_processing_machine(machine.type_id)) ++total; }
    result["machines_total"] = total;
    result["machines_active"] = last_machines_active_;
    result["machines_sleeping"] = std::max<int64_t>(0, total - last_machines_active_);
    result["machines_visited"] = last_machines_visited_;
    result["inputs_consumed"] = last_machine_inputs_;
    result["outputs_emitted"] = last_machine_outputs_;
    result["blocked_machines"] = last_machine_blocked_;
    result["fuel_starved_furnaces"] = last_fuel_starved_;
    result["machine_processing_usec"] = last_machine_usec_;
    result["sieve_processed_total"] = total_sieve_processed_;
    result["magnetic_processed_total"] = total_magnetic_processed_;
    result["furnace_processed_total"] = total_furnace_processed_;
    result["glass_total"] = total_glass_;
    result["iron_total"] = total_iron_;
    result["gold_total"] = total_gold_;
    result["residue_total"] = total_residue_;
    result["ash_total"] = total_ash_;
    result["port_watch_cells"] = static_cast<int64_t>(machine_port_watchers_.size());
    return result;
}

Dictionary NativeSandWorld::get_bank_statistics() const {
    Dictionary result;
    int64_t total = 0;
    for (const auto &[id, machine] : machine_entities_) { (void)id; if (machine.type_id == STRUCTURE_RESEARCH_BANK) ++total; }
    result["banks_total"] = total;
    result["banks_active"] = last_banks_active_;
    result["banks_sleeping"] = std::max<int64_t>(0, total - last_banks_active_);
    result["banks_visited"] = last_banks_visited_;
    result["accepted_cells"] = last_bank_accepted_;
    result["rejected_cells"] = last_bank_rejected_;
    result["blocked_banks"] = last_bank_blocked_;
    result["bank_usec"] = last_bank_usec_;
    result["accepted_total"] = total_bank_accepted_;
    result["rejected_total"] = total_bank_rejected_;
    return result;
}

Dictionary NativeSandWorld::get_machine_state_at(Vector2i world_cell) const {
    Dictionary result;
    for (const auto &[id, machine] : machine_entities_) {
        if (!is_processing_machine(machine.type_id) && !is_physical_processor(machine.type_id) && !is_power_structure(machine.type_id)) continue;
        const StructureDefinition *definition = structure_definition(machine.type_id);
        const std::vector<Vector2i> cells = transformed_occupied(*definition, machine.origin, machine.orientation);
        if (std::find(cells.begin(), cells.end(), world_cell) == cells.end()) continue;
        result["id"] = static_cast<int64_t>(id);
        result["type_id"] = machine.type_id;
        result["origin"] = machine.origin;
        result["orientation"] = machine.orientation;
        Dictionary configuration;
        if (turbines_.contains(id)) {
            configuration["target_millirpm"] = turbines_.at(id).target_millirpm;
            configuration["max_throttle"] = turbines_.at(id).max_throttle;
            configuration["enabled"] = turbines_.at(id).enabled;
        } else if (power_switches_.contains(id)) configuration["closed"] = power_switches_.at(id).closed;
        else if (transformers_.contains(id)) { configuration["max_transfer_rate"] = transformers_.at(id).max_transfer_rate; configuration["enabled"] = transformers_.at(id).enabled; }
        else if (power_entity_to_consumer_.contains(id)) configuration["priority"] = power_consumers_.at(power_entity_to_consumer_.at(id)).priority;
        result["configuration"] = configuration;
        result["physical"] = is_physical_processor(machine.type_id);
        result["state"] = turbines_.contains(id) ? turbines_.at(id).state : generators_.contains(id) ? generators_.at(id).state : machine.state;
        result["current_input"] = machine.input_material;
        result["result_waiting"] = machine.result_material;
        result["progress_ticks"] = machine.progress_ticks;
        result["process_ticks"] = (is_physical_processor(machine.type_id) || is_power_structure(machine.type_id)) ? 0 : process_ticks(machine.type_id);
        result["fuel_remaining"] = machine.fuel_remaining;
        result["ash_waiting"] = machine.ash_material != EMPTY_ID;
        result["processed_cells"] = machine.processed_cells;
        result["emitted_cells"] = machine.emitted_cells;
        result["last_output_route"] = machine.last_route;
        return result;
    }
    return result;
}

Dictionary NativeSandWorld::evaluate_processing_routes(int32_t profile_id, int32_t sample_count) const {
    Dictionary result;
    if (profile_id < 1 || profile_id > 65535 || sample_count < 1) return result;
    auto evaluate = [this, profile_id, sample_count](int32_t route) {
        int64_t glass = 0, iron = 0, gold = 0, residue = 0;
        for (int32_t index = 0; index < sample_count; ++index) {
            const uint16_t signature = mineral_signature_for({index, profile_id});
            int32_t feed = SAND_ID;
            if (route >= 1) feed = processing_result(SAND_ID, profile_id, signature, PROCESS_SIEVE);
            if (route >= 2 && feed == HEAVY_CONCENTRATE_ID) feed = processing_result(feed, profile_id, signature, PROCESS_MAGNETIC);
            const int32_t output = processing_result(feed, profile_id, signature, PROCESS_FURNACE_RAW + feed);
            if (output == GLASS_ID) ++glass; else if (output == IRON_ID) ++iron; else if (output == GOLD_ID) ++gold; else ++residue;
        }
        Dictionary values;
        values["glass"] = glass; values["iron"] = iron; values["gold"] = gold; values["residue"] = residue;
        values["coal"] = (sample_count + FURNACE_FUEL_UNITS - 1) / FURNACE_FUEL_UNITS;
        values["ash"] = values["coal"];
        return values;
    };
    result["route_a"] = evaluate(0);
    result["route_b"] = evaluate(1);
    result["route_c"] = evaluate(2);
    return result;
}

Dictionary NativeSandWorld::evaluate_progression_pacing(int32_t profile_id, int32_t sample_limit) const {
    Dictionary result;
    if (profile_id < 1 || profile_id > 65535 || sample_limit < 1) return result;
    struct Totals { int64_t raw = 0, glass = 0, iron = 0, gold = 0; };
    auto reach = [this, profile_id, sample_limit](int32_t route, int64_t need_glass, int64_t need_iron, int64_t need_gold, int32_t sieve_process) {
        Totals totals;
        for (int32_t index = 0; index < sample_limit; ++index) {
            const uint16_t signature = mineral_signature_for({index, profile_id});
            int32_t feed = SAND_ID;
            if (route >= 1) feed = processing_result(SAND_ID, profile_id, signature, sieve_process);
            if (route >= 2 && feed == HEAVY_CONCENTRATE_ID) feed = processing_result(feed, profile_id, signature, PROCESS_MAGNETIC);
            const int32_t output = processing_result(feed, profile_id, signature, PROCESS_FURNACE_RAW + feed);
            ++totals.raw;
            if (output == GLASS_ID) ++totals.glass;
            else if (output == IRON_ID) ++totals.iron;
            else if (output == GOLD_ID) ++totals.gold;
            if (totals.glass >= need_glass && totals.iron >= need_iron && totals.gold >= need_gold) break;
        }
        Dictionary stage;
        stage["raw_sand"] = totals.raw;
        stage["glass"] = totals.glass;
        stage["iron"] = totals.iron;
        stage["gold"] = totals.gold;
        stage["coal"] = (totals.raw + FURNACE_FUEL_UNITS - 1) / FURNACE_FUEL_UNITS;
        stage["estimated_seconds"] = static_cast<double>(totals.raw) / (route == 0 ? 120.0 : route == 1 ? 180.0 : 210.0);
        stage["reached"] = totals.glass >= need_glass && totals.iron >= need_iron && totals.gold >= need_gold;
        return stage;
    };
    result["dry_separation_primitive"] = reach(0, 2400, 40, 0, PROCESS_SIEVE);
    result["ferrous_via_sieve"] = reach(1, 3000, 180, 0, PROCESS_SIEVE);
    result["ferrous_primitive_comparison"] = reach(0, 3000, 180, 0, PROCESS_SIEVE);
    result["belt_drive_after_dry"] = reach(0, 3400, 65, 0, PROCESS_SIEVE);
    const int32_t later_profile = profile_id | (3 << 13);
    result["later_anomaly_profile_id"] = later_profile;
    auto reach_later = [this, later_profile, sample_limit]() {
        int64_t raw = 0, glass = 0, iron = 0, gold = 0;
        for (int32_t index = 0; index < sample_limit; ++index) {
            const uint16_t signature = mineral_signature_for({index, later_profile});
            int32_t feed = processing_result(SAND_ID, later_profile, signature, PROCESS_SIEVE_PRECISION);
            if (feed == HEAVY_CONCENTRATE_ID) feed = processing_result(feed, later_profile, signature, PROCESS_MAGNETIC);
            const int32_t process = (feed == IRON_CONCENTRATE_ID || feed == NONMAGNETIC_CONCENTRATE_ID) ? PROCESS_FURNACE_RECOVERY + feed : PROCESS_FURNACE_RAW + feed;
            const int32_t output = processing_result(feed, later_profile, signature, process);
            ++raw;
            if (output == GLASS_ID) ++glass; else if (output == IRON_ID) ++iron; else if (output == GOLD_ID) ++gold;
            if (glass >= 19300 && iron >= 935 && gold >= 2) break;
        }
        Dictionary stage;
        stage["raw_sand"] = raw; stage["glass"] = glass; stage["iron"] = iron; stage["gold"] = gold;
        stage["coal"] = (raw + 95) / 96;
        stage["estimated_seconds"] = static_cast<double>(raw) / 240.0;
        stage["reached"] = glass >= 19300 && iron >= 935 && gold >= 2;
        return stage;
    };
    result["concentrate_recovery_cumulative"] = reach_later();
    return result;
}

String NativeSandWorld::processing_state_hash() const {
    uint32_t hash = mix_int(0x4b535034u, static_cast<int32_t>(seed_));
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (chunk->material[index] == EMPTY_ID) continue;
            hash = mix_int(hash, origin.x + index % CHUNK_SIZE);
            hash = mix_int(hash, origin.y + index / CHUNK_SIZE);
            hash = mix_int(hash, chunk->material[index]);
            hash = mix_int(hash, chunk->provenance[index]);
            hash = mix_int(hash, chunk->mineral_signature[index]);
        }
    }
    std::vector<uint64_t> ids;
    for (const auto &[id, machine] : machine_entities_) if (is_processing_machine(machine.type_id)) ids.push_back(id);
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const MachineEntity &machine = machine_entities_.at(id);
        hash = mix_int(hash, machine.type_id); hash = mix_int(hash, machine.origin.x); hash = mix_int(hash, machine.origin.y);
        hash = mix_int(hash, machine.input_material); hash = mix_int(hash, machine.input_provenance); hash = mix_int(hash, machine.input_signature);
        hash = mix_int(hash, machine.result_material); hash = mix_int(hash, machine.fuel_remaining); hash = mix_int(hash, machine.ash_material);
    }
    char buffer[16]; std::snprintf(buffer, sizeof(buffer), "%08x", hash); return String(buffer);
}

String NativeSandWorld::logistics_state_hash() const {
    uint32_t hash = mix_int(0x4b534c47u, static_cast<int32_t>(seed_));
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const int32_t material = chunk->material[index];
            const int32_t structure = chunk->structures == nullptr ? 0 : (*chunk->structures)[index];
            if (material == EMPTY_ID && structure == 0) continue;
            hash = mix_int(hash, origin.x + index % CHUNK_SIZE);
            hash = mix_int(hash, origin.y + index / CHUNK_SIZE);
            hash = mix_int(hash, material);
            hash = mix_int(hash, chunk->provenance[index]);
            hash = mix_int(hash, chunk->mineral_signature[index]);
            hash = mix_int(hash, structure);
        }
    }
    std::vector<uint64_t> subsurface_ids;
    for (const auto &[id, run] : linked_transports_) { (void)run; subsurface_ids.push_back(id); }
    std::sort(subsurface_ids.begin(), subsurface_ids.end());
    for (const uint64_t id : subsurface_ids) {
        const LinkedTransportRun &run = linked_transports_.at(id);
        hash = mix_int(hash, static_cast<int32_t>(id)); hash = mix_int(hash, run.depth);
        hash = mix_int(hash, run.entrance.x); hash = mix_int(hash, run.entrance.y);
        hash = mix_int(hash, run.exit.x); hash = mix_int(hash, run.exit.y);
        for (const MaterialPacket &packet : run.lane) {
            hash = mix_int(hash, packet.material); hash = mix_int(hash, packet.temperature);
            hash = mix_int(hash, packet.provenance); hash = mix_int(hash, packet.mineral_signature);
        }
    }
    const String power_hash = power_state_hash();
    for (int64_t index = 0; index < power_hash.length(); ++index) hash = mix_int(hash, static_cast<int32_t>(power_hash.unicode_at(index)));
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

void NativeSandWorld::sample_rgba(const Chunk &chunk, int32_t local_x, int32_t local_y, uint8_t *output) const {
    const Vector2i world_cell = chunk.coordinate * CHUNK_SIZE + Vector2i(local_x, local_y);
    const int32_t material_id = chunk.material[local_y * CHUNK_SIZE + local_x];
    if (material_id == EMPTY_ID) {
        output[0] = output[1] = output[2] = output[3] = 0;
        return;
    }
    const auto &palette = material_id == STONE_ID ? STONE_PALETTE :
                          material_id == SAND_ID ? SAND_PALETTE :
                          material_id == WATER_ID ? WATER_PALETTE :
                          material_id == COAL_ID ? COAL_PALETTE :
                          material_id == FINE_SAND_ID ? FINE_SAND_PALETTE : material_id == HEAVY_CONCENTRATE_ID ? HEAVY_PALETTE :
                          material_id == IRON_CONCENTRATE_ID ? IRON_CONC_PALETTE : material_id == NONMAGNETIC_CONCENTRATE_ID ? NONMAG_PALETTE :
                          material_id == GLASS_ID ? GLASS_PALETTE : material_id == IRON_ID ? IRON_PALETTE : material_id == GOLD_ID ? GOLD_PALETTE :
                          material_id == CRUDE_RESIDUE_ID ? RESIDUE_PALETTE : material_id == COAL_CHUNK_ID ? COAL_CHUNK_PALETTE :
                          material_id == ASH_ID ? ASH_PALETTE : material_id == ICE_ID ? ICE_PALETTE :
                          material_id == STEAM_ID ? STEAM_PALETTE : material_id == MOLTEN_GLASS_ID ? MOLTEN_GLASS_PALETTE :
                          material_id == MOLTEN_IRON_ID ? MOLTEN_IRON_PALETTE : material_id == ROCK_DEBRIS_ID ? ROCK_DEBRIS_PALETTE :
                          material_id == WOOD_ID ? WOOD_PALETTE : material_id == LEAVES_ID ? LEAVES_PALETTE :
                          material_id == CHARCOAL_ID ? CHARCOAL_PALETTE : material_id == SMOKE_ID ? SMOKE_PALETTE :
                          material_id == RAW_FOOD_ID ? RAW_FOOD_PALETTE : material_id == COOKED_FOOD_ID ? COOKED_FOOD_PALETTE :
                          material_id == BURNT_FOOD_ID ? BURNT_FOOD_PALETTE : BEDROCK_PALETTE;
    const int32_t noise_scale = material_id == SAND_ID ? 5 : material_id == WATER_ID ? 12 : material_id == COAL_ID ? 6 : 9;
    const float depth_tint = material_id == SAND_ID ? 0.14f : material_id == COAL_ID ? 0.10f : 0.18f;
    RgbaFloat surface = material_id == STONE_ID ? RgbaFloat{0.42f, 0.50f, 0.56f, 1.0f} :
                              material_id == SAND_ID ? RgbaFloat{0.94f, 0.79f, 0.45f, 1.0f} :
                              material_id == WATER_ID ? RgbaFloat{0.38f, 0.82f, 0.86f, 0.95f} :
                              material_id == COAL_ID ? RgbaFloat{0.18f, 0.19f, 0.20f, 1.0f} :
                                                       palette[2];
    RgbaFloat shadow = material_id == STONE_ID ? RgbaFloat{0.075f, 0.10f, 0.14f, 1.0f} :
                             material_id == SAND_ID ? RgbaFloat{0.36f, 0.23f, 0.10f, 1.0f} :
                             material_id == WATER_ID ? RgbaFloat{0.025f, 0.18f, 0.25f, 0.92f} :
                             material_id == COAL_ID ? RgbaFloat{0.018f, 0.022f, 0.028f, 1.0f} :
                                                      RgbaFloat{palette[0].r * 0.36f, palette[0].g * 0.36f, palette[0].b * 0.36f, 1.0f};
    RgbaFloat color = palette[hash_2d(seed_, world_cell, material_id * 131) % palette.size()];
    if (world_settings_.generation_version >= 5 && (material_id == STONE_ID || material_id == SAND_ID)) {
        // V5 colours rock straight from its stored composition, so the section a player reads
        // is the material data. No extra per-cell state and no field evaluation while rendering.
        float rock[3];
        v5_profile_colour(chunk.provenance[local_y * CHUNK_SIZE + local_x], rock);
        if (material_id == SAND_ID) {
            surface = {0.94f, 0.82f, 0.52f, 1.0f};
            shadow = {rock[0] * 0.45f, rock[1] * 0.42f, rock[2] * 0.38f, 1.0f};
            color = {std::clamp(rock[0] * 0.35f + 0.58f, 0.0f, 1.0f),
                     std::clamp(rock[1] * 0.35f + 0.47f, 0.0f, 1.0f),
                     std::clamp(rock[2] * 0.35f + 0.24f, 0.0f, 1.0f), 1.0f};
        } else {
            color = {rock[0], rock[1], rock[2], 1.0f};
            surface = {std::clamp(rock[0] * 1.28f + 0.05f, 0.0f, 1.0f),
                       std::clamp(rock[1] * 1.28f + 0.05f, 0.0f, 1.0f),
                       std::clamp(rock[2] * 1.28f + 0.05f, 0.0f, 1.0f), 1.0f};
            shadow = {rock[0] * 0.30f, rock[1] * 0.30f, rock[2] * 0.32f, 1.0f};
        }
        // A bed covering a whole screen reads as flat paint without mid-frequency structure,
        // and per-cell noise alone reads as static rather than as rock. Laminae give the tone
        // a few-cell horizontal grain, warped along x so the banding is not a ruled line, and
        // a coarse mottle breaks up the remaining large areas.
        const int32_t warp = static_cast<int32_t>((hash_2d(seed_, {world_cell.x >> 4, 0}, 977) & 3u));
        const uint32_t lamina = hash_2d(seed_, {0, (world_cell.y + warp) >> 2}, 613) & 255u;
        const uint32_t mottle = hash_2d(seed_, {world_cell.x >> 3, world_cell.y >> 3}, 1097) & 255u;
        const uint32_t grain = hash_2d(seed_, world_cell, material_id * 131) & 63u;
        const float tone = (static_cast<float>(lamina) / 255.0f - 0.5f) * 0.085f +
                           (static_cast<float>(mottle) / 255.0f - 0.5f) * 0.070f +
                           (static_cast<float>(grain) / 63.0f - 0.5f) * 0.038f;
        color.r = std::clamp(color.r + tone, 0.0f, 1.0f);
        color.g = std::clamp(color.g + tone * 0.96f, 0.0f, 1.0f);
        color.b = std::clamp(color.b + tone * 0.90f, 0.0f, 1.0f);
    } else if (world_settings_.generation_version == 4 && material_id == STONE_ID) {
        const uint16_t tag = chunk.provenance[local_y * CHUNK_SIZE + local_x];
        if ((tag & 0x8000u) != 0u) {
            const int32_t layer = (tag >> 8u) & 7u;
            constexpr std::array<RgbaFloat, 5> PROVINCE{{
                RgbaFloat{0.22f,0.25f,0.27f,1}, RgbaFloat{0.27f,0.23f,0.29f,1}, RgbaFloat{0.20f,0.28f,0.25f,1},
                RgbaFloat{0.30f,0.26f,0.20f,1}, RgbaFloat{0.20f,0.23f,0.32f,1},
            }};
            if (layer == 1) { color = {0.30f,0.25f,0.14f,1}; surface = {0.42f,0.37f,0.19f,1}; shadow = {0.12f,0.10f,0.06f,1}; }
            else if (layer == 2) { color = {0.43f,0.31f,0.19f,1}; surface = {0.58f,0.43f,0.25f,1}; shadow = {0.18f,0.12f,0.08f,1}; }
            else if (layer == 3) { color = {0.34f,0.33f,0.29f,1}; surface = {0.48f,0.46f,0.39f,1}; shadow = {0.13f,0.13f,0.12f,1}; }
            else {
                const int32_t province_anchor = floor_div(world_cell.x, 512);
                const int32_t province_local_x = world_cell.x - province_anchor * 512;
                const int32_t left_province = geology_province_at_v4({province_anchor * 512 + 8, world_cell.y});
                const int32_t right_province = geology_province_at_v4({(province_anchor + 1) * 512 + 8, world_cell.y});
                float province_mix = static_cast<float>(province_local_x) / 512.0f;
                province_mix = province_mix * province_mix * (3.0f - 2.0f * province_mix);
                color = lerp_color(PROVINCE[left_province % PROVINCE.size()], PROVINCE[right_province % PROVINCE.size()], province_mix);
                const int32_t depth = world_cell.y - surface_height_at_v4(world_cell.x);
                const int32_t stripe = floor_div(world_cell.y + static_cast<int32_t>(std::lround(std::sin(world_cell.x * 0.018) * 11.0)), 28) & 3;
                const float lift = 0.018f * stripe - std::min(0.055f, depth * 0.000025f);
                color.r = std::clamp(color.r + lift, 0.0f, 1.0f);
                color.g = std::clamp(color.g + lift * 0.8f, 0.0f, 1.0f);
                color.b = std::clamp(color.b + lift * 1.1f, 0.0f, 1.0f);
                surface = lerp_color(color, RgbaFloat{0.58f,0.61f,0.59f,1}, 0.42f);
                shadow = lerp_color(color, RgbaFloat{0.03f,0.045f,0.06f,1}, 0.68f);
            }
        }
    }
    const Vector2i coarse{floor_div(world_cell.x, noise_scale), floor_div(world_cell.y, noise_scale)};
    const float coarse_value = static_cast<float>(hash_2d(seed_, coarse, material_id * 977)) / static_cast<float>(MASK_31);
    color = lerp_color(color, shadow, depth_tint * (0.25f + 0.50f * coarse_value));
    auto neighbor_material = [&](int32_t x, int32_t y) {
        if (x >= 0 && x < CHUNK_SIZE && y >= 0 && y < CHUNK_SIZE)
            return static_cast<int32_t>(chunk.material[y * CHUNK_SIZE + x]);
        return get_cell(world_cell + Vector2i(x - local_x, y - local_y));
    };
    const std::array<int32_t, 4> neighbors{{
        neighbor_material(local_x, local_y - 1), neighbor_material(local_x + 1, local_y),
        neighbor_material(local_x, local_y + 1), neighbor_material(local_x - 1, local_y),
    }};
    int32_t empty_neighbors = 0;
    int32_t same_neighbors = 0;
    for (const int32_t neighbor : neighbors) {
        empty_neighbors += neighbor == EMPTY_ID ? 1 : 0;
        same_neighbors += neighbor == material_id ? 1 : 0;
    }
    if (neighbors[0] == EMPTY_ID) {
        color = lerp_color(color, surface, material_id == SAND_ID ? 0.42f : 0.44f);
    } else if (empty_neighbors > 0) {
        color = lerp_color(color, surface, 0.16f);
    } else if (same_neighbors == 4) {
        color = lerp_color(color, shadow, depth_tint);
    }
    output[0] = to_byte(color.r);
    output[1] = to_byte(color.g);
    output[2] = to_byte(color.b);
    output[3] = to_byte(color.a);
}

void NativeSandWorld::rebuild_render_region(Chunk &chunk, const Bounds &bounds) {
    for (int32_t y = bounds.min_y; y <= bounds.max_y; ++y) {
        for (int32_t x = bounds.min_x; x <= bounds.max_x; ++x) {
            const int32_t index = y * CHUNK_SIZE + x;
            sample_rgba(chunk, x, y, &chunk.rgba[index * 4]);
            if (chunk.material[index] == WATER_ID) chunk.rgba[index * 4 + 3] = 0;
            else if (chunk.material[index] == STEAM_ID || chunk.material[index] == SMOKE_ID || chunk.material[index] == MOLTEN_GLASS_ID || chunk.material[index] == MOLTEN_IRON_ID) {
                const int32_t amount = material_amount_at(chunk, index);
                chunk.rgba[index * 4 + 3] = static_cast<uint8_t>(static_cast<int32_t>(chunk.rgba[index * 4 + 3]) * amount / 255);
                if (chunk.material[index] == MOLTEN_GLASS_ID || chunk.material[index] == MOLTEN_IRON_ID) {
                    const int32_t threshold = chunk.material[index] == MOLTEN_GLASS_ID ? 5873 : 7245;
                    const int32_t glow = std::clamp((static_cast<int32_t>(chunk.temperature[index]) - threshold) / 8, 0, 96);
                    chunk.rgba[index * 4] = static_cast<uint8_t>(std::min(255, static_cast<int32_t>(chunk.rgba[index * 4]) + glow));
                    chunk.rgba[index * 4 + 1] = static_cast<uint8_t>(std::min(255, static_cast<int32_t>(chunk.rgba[index * 4 + 1]) + glow / 2));
                }
            }
        }
    }
}

void NativeSandWorld::configure_workers(int32_t requested_workers) {
    const int32_t hardware_workers = static_cast<int32_t>(std::max(1u, std::thread::hardware_concurrency()));
    const int32_t next_count = std::clamp(requested_workers, 1, hardware_workers);
    if (next_count == worker_count_ && render_workers_.size() == static_cast<size_t>(next_count - 1) &&
        simulation_executor_ != nullptr && simulation_executor_->worker_count() == next_count) {
        return;
    }
    stop_workers();
    worker_count_ = next_count;
    render_stop_ = false;
    render_workers_ready_ = 0;
    for (int32_t index = 1; index < worker_count_; ++index) {
        render_workers_.emplace_back(&NativeSandWorld::render_worker_loop, this);
    }
    std::unique_lock<std::mutex> lock(render_mutex_);
    render_ready_.wait(lock, [this] { return render_workers_ready_ == render_workers_.size(); });
    lock.unlock();
    simulation_executor_ = std::make_unique<koalasand_core::ParallelExecutor>(worker_count_);
}

void NativeSandWorld::stop_workers() {
    {
        std::lock_guard<std::mutex> lock(render_mutex_);
        render_stop_ = true;
        ++render_generation_;
    }
    render_start_.notify_all();
    for (std::thread &worker : render_workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    render_workers_.clear();
    render_stop_ = false;
}

void NativeSandWorld::render_worker_loop() {
    uint64_t observed_generation;
    {
        std::lock_guard<std::mutex> lock(render_mutex_);
        observed_generation = render_generation_;
        ++render_workers_ready_;
        render_ready_.notify_one();
    }
    while (true) {
        {
            std::unique_lock<std::mutex> lock(render_mutex_);
            render_start_.wait(lock, [this, &observed_generation] {
                return render_stop_ || render_generation_ != observed_generation;
            });
            if (render_stop_) {
                return;
            }
            observed_generation = render_generation_;
        }
        bool handled_job = false;
        size_t index = render_job_index_.fetch_add(1);
        while (index < render_jobs_.size()) {
            handled_job = true;
            auto &[chunk, bounds] = render_jobs_[index];
            rebuild_render_region(*chunk, bounds);
            index = render_job_index_.fetch_add(1);
        }
        if (handled_job) {
            render_workers_used_current_.fetch_add(1);
        }
        {
            std::lock_guard<std::mutex> lock(render_mutex_);
            if (--render_workers_pending_ == 0) {
                render_done_.notify_one();
            }
        }
    }
}

void NativeSandWorld::rebuild_render_jobs() {
    if (render_jobs_.empty()) {
        last_render_workers_used_ = 0;
        return;
    }
    if (render_workers_.empty()) {
        for (auto &[chunk, bounds] : render_jobs_) {
            rebuild_render_region(*chunk, bounds);
        }
        last_render_workers_used_ = 1;
        return;
    }
    {
        std::lock_guard<std::mutex> lock(render_mutex_);
        render_job_index_.store(0);
        render_workers_used_current_.store(0);
        render_workers_pending_ = render_workers_.size();
        ++render_generation_;
    }
    render_start_.notify_all();
    bool handled_job = false;
    size_t index = render_job_index_.fetch_add(1);
    while (index < render_jobs_.size()) {
        handled_job = true;
        auto &[chunk, bounds] = render_jobs_[index];
        rebuild_render_region(*chunk, bounds);
        index = render_job_index_.fetch_add(1);
    }
    if (handled_job) {
        render_workers_used_current_.fetch_add(1);
    }
    std::unique_lock<std::mutex> lock(render_mutex_);
    render_done_.wait(lock, [this] { return render_workers_pending_ == 0; });
    last_render_workers_used_ = render_workers_used_current_.load();
}

Array NativeSandWorld::consume_dirty_render_chunks() {
    Array result;
    last_dirty_render_pixels_ = 0;
    last_render_upload_pixels_ = 0;
    render_jobs_.clear();
    for (Chunk *chunk : sorted_chunks()) {
        if (!chunk->render_dirty.valid()) {
            continue;
        }
        const Bounds dirty = chunk->render_dirty;
        render_jobs_.push_back({chunk, dirty});
    }
    rebuild_render_jobs();
    for (auto &[chunk, dirty] : render_jobs_) {
        PackedByteArray pixels;
        pixels.resize(static_cast<int64_t>(chunk->rgba.size()));
        std::copy(chunk->rgba.begin(), chunk->rgba.end(), pixels.ptrw());
        Dictionary item;
        item["coordinate"] = chunk->coordinate;
        item["pixels"] = pixels;
        item["dirty_rect"] = Rect2i(dirty.min_x, dirty.min_y, dirty.max_x - dirty.min_x + 1, dirty.max_y - dirty.min_y + 1);
        item["revision"] = static_cast<int64_t>(chunk->revision);
        result.push_back(item);
        last_dirty_render_pixels_ += dirty.area();
        last_render_upload_pixels_ += CELLS_PER_CHUNK;
        chunk->render_dirty.clear();
    }
    render_jobs_.clear();
    return result;
}

Dictionary NativeSandWorld::consume_dirty_render_page(Rect2i chunk_area, bool force) {
    Dictionary result;
    last_dirty_render_pixels_ = 0;
    last_render_upload_pixels_ = 0;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 ||
        static_cast<int64_t>(chunk_area.size.x) * chunk_area.size.y > 4096) return result;

    // Ask the visible area which chunks it contains, rather than asking every resident chunk
    // whether it is visible. This runs once a frame, and the area is the camera's -- capped at
    // 4096 chunks above and a few hundred in practice -- while the resident set grows with
    // everywhere the player has ever been, because only pristine chunks are ever evicted. The
    // walk order is unchanged: sorted_chunks() is ordered by y then x, and so is this.
    render_jobs_.clear();
    const Vector2i area_end = chunk_area.position + chunk_area.size;
    for (int32_t chunk_y = chunk_area.position.y; chunk_y < area_end.y; ++chunk_y) {
        for (int32_t chunk_x = chunk_area.position.x; chunk_x < area_end.x; ++chunk_x) {
            Chunk *chunk = get_chunk({chunk_x, chunk_y});
            if (chunk == nullptr || !chunk->render_dirty.valid()) continue;
            const Bounds dirty = chunk->render_dirty;
            render_jobs_.push_back({chunk, dirty});
            last_dirty_render_pixels_ += dirty.area();
        }
    }
    if (render_jobs_.empty() && !force) return result;
    rebuild_render_jobs();
    for (auto &[chunk, dirty] : render_jobs_) {
        (void)dirty;
        chunk->render_dirty.clear();
    }
    render_jobs_.clear();

    const int32_t width = chunk_area.size.x * CHUNK_SIZE;
    const int32_t height = chunk_area.size.y * CHUNK_SIZE;
    const int64_t required_bytes = static_cast<int64_t>(width) * height * 4;
    // The page is reassembled on every frame the visible world changes. A fresh PackedByteArray
    // meant allocating and zero-filling three and a half megabytes each time, and then
    // immediately overwriting nearly all of it with the chunk copies below -- the preparation
    // cost more than the work it was preparing for. Keep the buffer between calls and zero only
    // the regions no chunk covers, which is what the fresh allocation was really providing.
    if (render_page_pixels_.size() != required_bytes) render_page_pixels_.resize(required_bytes);
    uint8_t *destination = render_page_pixels_.ptrw();
    for (int32_t chunk_y = 0; chunk_y < chunk_area.size.y; ++chunk_y) {
        for (int32_t chunk_x = 0; chunk_x < chunk_area.size.x; ++chunk_x) {
            const Chunk *chunk = get_chunk(chunk_area.position + Vector2i(chunk_x, chunk_y));
            for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
                uint8_t *row = destination +
                        (static_cast<int64_t>(chunk_y * CHUNK_SIZE + local_y) * width + chunk_x * CHUNK_SIZE) * 4;
                if (chunk == nullptr) {
                    std::fill_n(row, CHUNK_SIZE * 4, uint8_t{0});
                    continue;
                }
                const auto source = chunk->rgba.begin() + static_cast<int64_t>(local_y) * CHUNK_SIZE * 4;
                std::copy_n(source, CHUNK_SIZE * 4, row);
            }
        }
    }
    last_render_upload_pixels_ = static_cast<int64_t>(width) * height;
    result["chunk_area"] = chunk_area;
    result["cell_position"] = chunk_area.position * CHUNK_SIZE;
    result["width"] = width;
    result["height"] = height;
    result["pixels"] = render_page_pixels_;
    result["bytes"] = required_bytes;
    result["dirty_pixels"] = last_dirty_render_pixels_;
    return result;
}

PackedInt32Array NativeSandWorld::get_non_empty_cells() const {
    PackedInt32Array result;
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const int32_t material_id = chunk->material[index];
            if (material_id == EMPTY_ID) {
                continue;
            }
            result.push_back(origin.x + index % CHUNK_SIZE);
            result.push_back(origin.y + index / CHUNK_SIZE);
            result.push_back(material_id);
        }
    }
    return result;
}

String NativeSandWorld::material_state_hash() const {
    struct CellRecord {
        int32_t x;
        int32_t y;
        int32_t material;
    };
    std::vector<CellRecord> cells;
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (chunk->material[index] != EMPTY_ID) {
                cells.push_back({origin.x + index % CHUNK_SIZE, origin.y + index / CHUNK_SIZE, chunk->material[index]});
            }
        }
    }
    std::sort(cells.begin(), cells.end(), [](const CellRecord &a, const CellRecord &b) {
        return a.y < b.y || (a.y == b.y && a.x < b.x);
    });
    uint32_t hash = mix_int(0x4b53414eu, static_cast<int32_t>(seed_));
    for (const CellRecord &cell : cells) {
        hash = mix_int(hash, cell.x);
        hash = mix_int(hash, cell.y);
        hash = mix_int(hash, cell.material);
    }
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

String NativeSandWorld::material_and_provenance_hash() const {
    uint32_t hash = mix_int(0x4b534750u, static_cast<int32_t>(seed_));
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (chunk->material[index] == EMPTY_ID) continue;
            hash = mix_int(hash, origin.x + index % CHUNK_SIZE);
            hash = mix_int(hash, origin.y + index / CHUNK_SIZE);
            hash = mix_int(hash, chunk->material[index]);
            hash = mix_int(hash, chunk->provenance[index]);
        }
    }
    const String phase13_hash = phase13_state_hash();
    for (int32_t index = 0; index < phase13_hash.length(); ++index)
        hash = mix_int(hash, static_cast<int32_t>(phase13_hash.unicode_at(index)));
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

String NativeSandWorld::authoritative_physical_hash() const {
    uint32_t hash = mix_int(0x4b535037u, static_cast<int32_t>(seed_));
    hash = mix_int(hash, static_cast<int32_t>(tick_index_));
    hash = mix_int(hash, static_cast<int32_t>(static_cast<uint64_t>(thermal_rounding_reservoir_) >> 32u));
    hash = mix_int(hash, static_cast<int32_t>(thermal_rounding_reservoir_));
    for (const Chunk *chunk : sorted_chunks()) {
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (chunk->material[index] == EMPTY_ID) continue;
            hash = mix_int(hash, origin.x + index % CHUNK_SIZE);
            hash = mix_int(hash, origin.y + index / CHUNK_SIZE);
            hash = mix_int(hash, chunk->material[index]);
            hash = mix_int(hash, chunk->temperature[index]);
            hash = mix_int(hash, chunk->provenance[index]);
            hash = mix_int(hash, chunk->mineral_signature[index]);
            hash = mix_int(hash, material_amount_at(*chunk, index));
            hash = mix_int(hash, chunk->phase_energy == nullptr ? 0 : (*chunk->phase_energy)[index]);
            hash = mix_int(hash, chunk->flags[index] & 0x06u);
            const bool organic_state = is_organic_material(chunk->material[index]) ||
                (chunk->organic_moisture != nullptr && (*chunk->organic_moisture)[index] != 0) ||
                (chunk->reaction_progress != nullptr && (*chunk->reaction_progress)[index] != 0) ||
                (chunk->reaction_state != nullptr && (*chunk->reaction_state)[index] != 0);
            if (organic_state) {
                hash = mix_int(hash, 0x4f524731);
                hash = mix_int(hash, chunk->organic_moisture == nullptr ? 0 : (*chunk->organic_moisture)[index]);
                hash = mix_int(hash, chunk->reaction_progress == nullptr ? 0 : (*chunk->reaction_progress)[index]);
                hash = mix_int(hash, chunk->reaction_state == nullptr ? 0 : (*chunk->reaction_state)[index]);
            }
        }
        if (chunk->oxidizer != nullptr) for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if ((*chunk->oxidizer)[index] == 255) continue;
            hash = mix_int(hash, 0x4f585931);
            hash = mix_int(hash, origin.x + index % CHUNK_SIZE);
            hash = mix_int(hash, origin.y + index / CHUNK_SIZE);
            hash = mix_int(hash, (*chunk->oxidizer)[index]);
        }
    }
    std::vector<uint64_t> organic_cluster_ids;
    for (const auto &[id, cluster] : fellable_clusters_) { (void)cluster; organic_cluster_ids.push_back(id); }
    std::sort(organic_cluster_ids.begin(), organic_cluster_ids.end());
    for (const uint64_t id : organic_cluster_ids) {
        const FellableCluster &cluster = fellable_clusters_.at(id);
        hash = mix_int(hash, 0x434c5531); hash = mix_int(hash, static_cast<int32_t>(id));
        hash = mix_int(hash, cluster.origin_q10.x); hash = mix_int(hash, cluster.origin_q10.y);
        hash = mix_int(hash, cluster.velocity_q10.x); hash = mix_int(hash, cluster.velocity_q10.y);
        hash = mix_int(hash, cluster.angle_q16); hash = mix_int(hash, cluster.angular_velocity_q16);
        for (const FellableClusterCell &cell : cluster.cells) {
            hash = mix_int(hash, cell.x); hash = mix_int(hash, cell.y); hash = mix_int(hash, cell.material);
            hash = mix_int(hash, cell.temperature); hash = mix_int(hash, cell.amount); hash = mix_int(hash, cell.moisture);
        }
    }
    std::vector<uint64_t> pipe_keys;
    pipe_keys.reserve(pipe_segments_.size());
    for (const auto &[key, segment] : pipe_segments_) { (void)segment; pipe_keys.push_back(key); }
    std::sort(pipe_keys.begin(), pipe_keys.end());
    for (const uint64_t key : pipe_keys) {
        const PipeSegment &segment = pipe_segments_.at(key);
        hash = mix_int(hash, static_cast<int32_t>(key >> 32u));
        hash = mix_int(hash, static_cast<int32_t>(key));
        hash = mix_int(hash, segment.fluid_type);
        hash = mix_int(hash, segment.mass);
        hash = mix_int(hash, segment.temperature);
        hash = mix_int(hash, segment.health);
        hash = mix_int(hash, segment.flags & 0x0fu);
    }
    std::vector<uint64_t> subsurface_ids;
    for (const auto &[id, run] : linked_transports_) { (void)run; subsurface_ids.push_back(id); }
    std::sort(subsurface_ids.begin(), subsurface_ids.end());
    for (const uint64_t id : subsurface_ids) {
        const LinkedTransportRun &run = linked_transports_.at(id);
        hash = mix_int(hash, static_cast<int32_t>(id >> 32u)); hash = mix_int(hash, static_cast<int32_t>(id));
        hash = mix_int(hash, run.depth); hash = mix_int(hash, run.entrance.x); hash = mix_int(hash, run.entrance.y);
        hash = mix_int(hash, run.exit.x); hash = mix_int(hash, run.exit.y);
        for (const MaterialPacket &packet : run.lane) {
            hash = mix_int(hash, packet.material); hash = mix_int(hash, packet.temperature);
            hash = mix_int(hash, packet.provenance); hash = mix_int(hash, packet.mineral_signature);
        }
    }
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

} // namespace godot
