#include "native_sand_world.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>

namespace godot {

namespace {
constexpr int32_t WATER_ID = 3;
constexpr int32_t STEAM_ID = 17;
constexpr int32_t WATER_FREEZE = 1092;
constexpr int32_t WATER_BOIL = 1492;
constexpr int32_t ICE_LATENT = 12000;
constexpr int32_t STEAM_LATENT = 42000;
constexpr int32_t STRUCTURE_PIPE = 10;
constexpr int32_t STRUCTURE_PIPE_JUNCTION = 11;
constexpr int32_t STRUCTURE_FLUID_INTAKE = 12;
constexpr int32_t STRUCTURE_FLUID_OUTLET = 13;
constexpr int32_t STRUCTURE_BASIC_PUMP = 14;
constexpr int32_t STRUCTURE_PIPE_VALVE = 15;
constexpr uint16_t PIPE_CAPACITY = 65535;
constexpr int32_t PASSIVE_RATE = 2048;
constexpr int32_t BASIC_PUMP_RATE = 4096;
constexpr int32_t BASIC_PUMP_HEAD = 8192;
constexpr int32_t UPGRADED_PUMP_RATE = 6144;
constexpr int32_t UPGRADED_PUMP_HEAD = 12288;
constexpr int32_t ELEVATION_HEAD_PER_CELL = 32;
constexpr int32_t PRESSURE_DEADBAND = 64;
constexpr uint8_t FLAG_DISABLED = 0x01;
constexpr uint8_t FLAG_VALVE_CLOSED = 0x02;
constexpr uint8_t FLAG_BREACHED = 0x04;
constexpr uint8_t FLAG_FLOWING = 0x08;
constexpr uint8_t QUIET_MASK = 0xf0;
const std::array<Vector2i, 4> DIRECTIONS{{Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)}};

int32_t direction_index(Vector2i direction) {
    if (direction == Vector2i(0, -1)) return 0;
    if (direction == Vector2i(1, 0)) return 1;
    if (direction == Vector2i(0, 1)) return 2;
    return 3;
}

Vector2i facing(int32_t orientation) { return DIRECTIONS[(orientation + 1) & 3]; }
uint8_t quiet_ticks(uint8_t flags) { return static_cast<uint8_t>((flags & QUIET_MASK) >> 4); }
void set_quiet(uint8_t &flags, uint8_t ticks) { flags = static_cast<uint8_t>((flags & ~QUIET_MASK) | (std::min<uint8_t>(ticks, 15) << 4)); }

int64_t pipe_capacity(int32_t fluid, int32_t mass) {
    const int32_t specific_heat = fluid == STEAM_ID ? 32 : 128;
    return std::max<int64_t>(1, (static_cast<int64_t>(specific_heat) * mass + 254) / 255);
}

int64_t pipe_ice_capacity(int32_t mass) {
    return std::max<int64_t>(1, (static_cast<int64_t>(64) * mass + 254) / 255);
}

int64_t pipe_scaled_latent(int32_t latent, int32_t mass) {
    return std::max<int64_t>(1, (static_cast<int64_t>(latent) * mass + 254) / 255);
}

struct PipeThermalScale {
    int64_t water_capacity = 0;
    int64_t steam_capacity = 0;
    int64_t water_base = 0;
    int64_t boiling_start = 0;
    int64_t boiling_end = 0;
    int64_t steam_base = 0;
};

struct PipeMassScale {
    uint16_t ice_capacity = 0;
    uint16_t water_capacity = 0;
    uint16_t steam_capacity = 0;
    int32_t ice_latent = 0;
    int32_t steam_latent = 0;
};
static_assert(sizeof(PipeMassScale) == 16);

const std::array<PipeMassScale, 65536> &pipe_mass_scales() {
    static const std::array<PipeMassScale, 65536> scales = [] {
        std::array<PipeMassScale, 65536> values{};
        for (int32_t mass = 1; mass <= 65535; ++mass) {
            values[static_cast<size_t>(mass)] = {
                static_cast<uint16_t>(pipe_ice_capacity(mass)),
                static_cast<uint16_t>(pipe_capacity(WATER_ID, mass)),
                static_cast<uint16_t>(pipe_capacity(STEAM_ID, mass)),
                static_cast<int32_t>(pipe_scaled_latent(ICE_LATENT, mass)),
                static_cast<int32_t>(pipe_scaled_latent(STEAM_LATENT, mass)),
            };
        }
        return values;
    }();
    return scales;
}

PipeThermalScale pipe_thermal_scale(int32_t mass) {
    PipeThermalScale scale;
    const PipeMassScale &mass_scale = pipe_mass_scales()[static_cast<uint16_t>(mass)];
    scale.water_capacity = mass_scale.water_capacity;
    scale.steam_capacity = mass_scale.steam_capacity;
    scale.water_base = static_cast<int64_t>(mass_scale.ice_capacity) * WATER_FREEZE + mass_scale.ice_latent -
                       scale.water_capacity * WATER_FREEZE;
    scale.boiling_start = scale.water_base + scale.water_capacity * WATER_BOIL;
    scale.boiling_end = scale.boiling_start + mass_scale.steam_latent;
    scale.steam_base = scale.boiling_end - scale.steam_capacity * WATER_BOIL;
    return scale;
}
}

bool NativeSandWorld::is_pipe_structure(int32_t type_id) {
    return type_id >= STRUCTURE_PIPE && type_id <= STRUCTURE_PIPE_VALVE;
}

bool NativeSandWorld::is_pipe_device(int32_t type_id) {
    return type_id >= STRUCTURE_FLUID_INTAKE && type_id <= STRUCTURE_PIPE_VALVE;
}

void NativeSandWorld::reset_pipe_logistics() {
    pipe_segments_.clear();
    pipe_phase_energy_.clear();
    active_pipe_segments_.clear();
    active_pipe_sorted_cache_.clear();
    active_pipe_record_cache_.clear();
    pipe_next_active_buffer_.clear();
    pipe_candidate_active_buffer_.clear();
    pipe_filtered_active_buffer_.clear();
    pipe_keep_active_buffer_.clear();
    active_pipe_cache_dirty_ = true;
    pipe_revision_ = 0;
    last_pipe_active_ = last_pipe_visited_ = last_pipe_transfers_ = last_pipe_mass_transferred_ = 0;
    last_pipe_pump_work_ = last_pipe_valve_work_ = last_pipe_intake_mass_ = last_pipe_outlet_mass_ = 0;
    last_pipe_leak_mass_ = last_pipe_breaches_ = last_pipe_usec_ = total_pipe_leak_mass_ = 0;
    last_pipe_gather_usec_ = last_pipe_state_usec_ = last_pipe_flow_usec_ = last_pipe_schedule_usec_ = 0;
    last_pipe_pressure_edges_ = last_pipe_damage_checks_ = last_pipe_phase_checks_ = 0;
    last_pipe_heat_edges_ = last_pipe_automation_hooks_ = 0;
    last_wet_cells_visited_ = last_wet_grains_moved_ = last_wet_heavy_captured_ = last_wet_light_output_ = last_wet_usec_ = 0;
}

void NativeSandWorld::register_pipe_segment(Vector2i world_cell, int32_t type_id, int32_t orientation) {
    PipeSegment segment;
    segment.type_id = static_cast<uint8_t>(type_id);
    segment.orientation = static_cast<uint8_t>(((orientation % 4) + 4) % 4);
    pipe_segments_[cell_key(world_cell)] = segment;
    ++pipe_revision_;
    wake_pipe(world_cell);
    refresh_pipe_connections(world_cell);
    for (const Vector2i direction : DIRECTIONS) refresh_pipe_connections(world_cell + direction);
}

bool NativeSandWorld::unregister_pipe_segment(Vector2i world_cell, bool cutting) {
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end()) return true;
    if (cutting && found->second.mass > 0) {
        damage_pipe(world_cell, 1000, 1);
        return false;
    }
    pipe_segments_.erase(found);
    pipe_phase_energy_.erase(cell_key(world_cell));
    if (active_pipe_segments_.erase(cell_key(world_cell)) > 0) active_pipe_cache_dirty_ = true;
    ++pipe_revision_;
    for (const Vector2i direction : DIRECTIONS) {
        refresh_pipe_connections(world_cell + direction);
        wake_pipe(world_cell + direction);
    }
    return true;
}

void NativeSandWorld::wake_pipe(Vector2i world_cell) {
    const uint64_t key = cell_key(world_cell);
    auto found = pipe_segments_.find(key);
    if (found == pipe_segments_.end()) return;
    set_quiet(found->second.flags, 0);
    if (active_pipe_segments_.insert(key).second) active_pipe_cache_dirty_ = true;
}

void NativeSandWorld::wake_pipe_neighbors(Vector2i world_cell) {
    wake_pipe(world_cell);
    for (const Vector2i direction : DIRECTIONS) wake_pipe(world_cell + direction);
}

void NativeSandWorld::refresh_pipe_connections(Vector2i world_cell) {
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end()) return;
    PipeSegment &segment = found->second;
    uint8_t allowed = 0x0f;
    const Vector2i forward = facing(segment.orientation);
    if (segment.type_id == STRUCTURE_FLUID_INTAKE || segment.type_id == STRUCTURE_FLUID_OUTLET) {
        allowed = static_cast<uint8_t>(1u << direction_index(-forward));
    } else if (segment.type_id == STRUCTURE_BASIC_PUMP || segment.type_id == STRUCTURE_PIPE_VALVE) {
        allowed = static_cast<uint8_t>((1u << direction_index(forward)) | (1u << direction_index(-forward)));
    }
    uint8_t connected = 0;
    for (int32_t index = 0; index < 4; ++index) {
        if ((allowed & (1u << index)) == 0) continue;
        auto neighbor = pipe_segments_.find(cell_key(world_cell + DIRECTIONS[index]));
        if (neighbor == pipe_segments_.end()) continue;
        uint8_t neighbor_allowed = 0x0f;
        const Vector2i neighbor_forward = facing(neighbor->second.orientation);
        if (neighbor->second.type_id == STRUCTURE_FLUID_INTAKE || neighbor->second.type_id == STRUCTURE_FLUID_OUTLET)
            neighbor_allowed = static_cast<uint8_t>(1u << direction_index(-neighbor_forward));
        else if (neighbor->second.type_id == STRUCTURE_BASIC_PUMP || neighbor->second.type_id == STRUCTURE_PIPE_VALVE)
            neighbor_allowed = static_cast<uint8_t>((1u << direction_index(neighbor_forward)) | (1u << direction_index(-neighbor_forward)));
        if ((neighbor_allowed & (1u << ((index + 2) & 3))) != 0) connected |= static_cast<uint8_t>(1u << index);
    }
    if (segment.connection_mask != connected) {
        segment.connection_mask = connected;
        ++pipe_revision_;
    }
}

bool NativeSandWorld::pipe_connection_open(Vector2i from, Vector2i to) const {
    const auto source = pipe_segments_.find(cell_key(from));
    const auto destination = pipe_segments_.find(cell_key(to));
    if (source == pipe_segments_.end() || destination == pipe_segments_.end()) return false;
    if ((source->second.flags & FLAG_BREACHED) != 0 || (destination->second.flags & FLAG_BREACHED) != 0) return false;
    if ((source->second.type_id == STRUCTURE_PIPE_VALVE && (source->second.flags & FLAG_VALVE_CLOSED) != 0) ||
        (destination->second.type_id == STRUCTURE_PIPE_VALVE && (destination->second.flags & FLAG_VALVE_CLOSED) != 0)) return false;
    const Vector2i delta = to - from;
    const int32_t index = direction_index(delta);
    return (source->second.connection_mask & (1u << index)) != 0 &&
           (destination->second.connection_mask & (1u << ((index + 2) & 3))) != 0;
}

int32_t NativeSandWorld::pipe_potential(Vector2i cell, const PipeSegment &segment, Vector2i direction) const {
    int32_t potential = static_cast<int32_t>(segment.mass) + segment.pressure - cell.y * ELEVATION_HEAD_PER_CELL;
    if (segment.fluid_type == STEAM_ID && segment.mass > 0)
        potential += 12000 + std::max(0, static_cast<int32_t>(segment.temperature) - WATER_BOIL) * 8;
    if (segment.type_id == STRUCTURE_BASIC_PUMP && (segment.flags & FLAG_DISABLED) == 0 && direction == facing(segment.orientation)) {
        const int32_t baseline = has_research("fluid.pressurized_transport") ? UPGRADED_PUMP_HEAD : BASIC_PUMP_HEAD;
        potential += baseline + 8192 * electric_satisfaction(STRUCTURE_BASIC_PUMP, 0, cell) / 1000;
    }
    return potential;
}

int64_t NativeSandWorld::pipe_enthalpy(uint64_t key, const PipeSegment &segment) const {
    if (segment.mass == 0 || (segment.fluid_type != WATER_ID && segment.fluid_type != STEAM_ID)) return 0;
    const PipeThermalScale scale = pipe_thermal_scale(segment.mass);
    if (!pipe_phase_energy_.empty()) {
        const auto progress = pipe_phase_energy_.find(key);
        if (progress != pipe_phase_energy_.end())
            return scale.boiling_start + progress->second;
    }
    return segment.fluid_type == STEAM_ID ? scale.steam_base + scale.steam_capacity * segment.temperature
                                          : scale.water_base + scale.water_capacity * segment.temperature;
}

int64_t NativeSandWorld::pipe_heat_capacity(const PipeSegment &segment) const {
    return segment.mass == 0 ? 0 : pipe_capacity(segment.fluid_type, segment.mass);
}

int64_t NativeSandWorld::set_pipe_enthalpy(uint64_t key, PipeSegment &segment, int64_t enthalpy, int32_t preferred_fluid) {
    if (segment.mass == 0) {
        segment.fluid_type = 0; segment.temperature = TEMPERATURE_AMBIENT; segment.pressure = 0;
        if (!pipe_phase_energy_.empty()) pipe_phase_energy_.erase(key);
        return 0;
    }
    const int32_t mass = segment.mass;
    const PipeThermalScale scale = pipe_thermal_scale(mass);
    enthalpy = std::max<int64_t>(scale.water_base, enthalpy);
    if (enthalpy < scale.boiling_start) {
        segment.fluid_type = WATER_ID;
        segment.temperature = static_cast<uint16_t>(std::clamp<int64_t>((enthalpy - scale.water_base) / scale.water_capacity, 0, TEMPERATURE_MAX));
        segment.pressure = std::min<uint16_t>(segment.pressure, 12000);
        if (!pipe_phase_energy_.empty()) pipe_phase_energy_.erase(key);
        return scale.water_base + scale.water_capacity * segment.temperature;
    } else if (enthalpy < scale.boiling_end) {
        segment.fluid_type = preferred_fluid == STEAM_ID ? STEAM_ID : WATER_ID;
        segment.temperature = WATER_BOIL;
        pipe_phase_energy_[key] = enthalpy - scale.boiling_start;
        if (segment.fluid_type == STEAM_ID) segment.pressure = std::max<uint16_t>(segment.pressure, 16000);
        return scale.boiling_start + pipe_phase_energy_.at(key);
    } else {
        segment.fluid_type = STEAM_ID;
        segment.temperature = static_cast<uint16_t>(std::clamp<int64_t>((enthalpy - scale.steam_base) / scale.steam_capacity, WATER_BOIL, TEMPERATURE_MAX));
        segment.pressure = std::max<uint16_t>(segment.pressure, 16000);
        if (!pipe_phase_energy_.empty()) pipe_phase_energy_.erase(key);
        return scale.steam_base + scale.steam_capacity * segment.temperature;
    }
}

int32_t NativeSandWorld::transfer_pipe_mass(Vector2i from, Vector2i to, int32_t requested) {
    auto source = pipe_segments_.find(cell_key(from));
    auto destination = pipe_segments_.find(cell_key(to));
    if (source == pipe_segments_.end() || destination == pipe_segments_.end() || requested <= 0) return 0;
    return transfer_pipe_mass_indexed(source->first, source->second, from, destination->first, destination->second, to, requested);
}

int32_t NativeSandWorld::transfer_pipe_mass_indexed(uint64_t source_key, PipeSegment &a, Vector2i from,
                                                     uint64_t destination_key, PipeSegment &b, Vector2i to,
                                                     int32_t requested) {
    if (a.mass == 0 || b.mass >= PIPE_CAPACITY || (b.mass > 0 && b.fluid_type != a.fluid_type)) return 0;
    const int32_t amount = std::min({requested, static_cast<int32_t>(a.mass), static_cast<int32_t>(PIPE_CAPACITY - b.mass)});
    if (amount <= 0) return 0;
    const int64_t source_energy = pipe_enthalpy(source_key, a);
    const int64_t destination_energy = pipe_enthalpy(destination_key, b);
    const int64_t moved_energy = source_energy * amount / a.mass;
    const int32_t source_fluid = a.fluid_type;
    const int32_t next_mass = static_cast<int32_t>(b.mass) + amount;
    b.mass = static_cast<uint16_t>(next_mass);
    int32_t transported_head = a.pressure;
    if (a.type_id == STRUCTURE_BASIC_PUMP && (a.flags & FLAG_DISABLED) == 0 && to - from == facing(a.orientation)) {
        const int32_t baseline = has_research("fluid.pressurized_transport") ? UPGRADED_PUMP_HEAD : BASIC_PUMP_HEAD;
        transported_head = std::max(transported_head, baseline + 8192 * electric_satisfaction(STRUCTURE_BASIC_PUMP, 0, from) / 1000);
    }
    b.pressure = static_cast<uint16_t>(std::clamp(std::max<int32_t>(b.pressure, transported_head - 8), 0, 65535));
    a.mass = static_cast<uint16_t>(a.mass - amount);
    const int64_t source_after = set_pipe_enthalpy(source_key, a, source_energy - moved_energy, source_fluid);
    const int64_t destination_after = set_pipe_enthalpy(destination_key, b, destination_energy + moved_energy, source_fluid);
    thermal_rounding_reservoir_ += source_energy + destination_energy - source_after - destination_after;
    a.last_flow = static_cast<int16_t>(-std::min(amount, 32767));
    b.last_flow = static_cast<int16_t>(std::min(amount, 32767));
    a.flags |= FLAG_FLOWING;
    b.flags |= FLAG_FLOWING;
    set_quiet(a.flags, 0);
    set_quiet(b.flags, 0);
    ++pipe_revision_;
    notify_automation_cell_change(from);
    notify_automation_cell_change(to);
    return amount;
}

int32_t NativeSandWorld::world_to_pipe(Vector2i world_cell, Vector2i pipe_cell, int32_t requested) {
    auto pipe = pipe_segments_.find(cell_key(pipe_cell));
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (pipe == pipe_segments_.end() || chunk == nullptr || requested <= 0) return 0;
    PipeSegment &segment = pipe->second;
    const int32_t source_index = local_index(world_to_local(world_cell));
    const int32_t source_material = chunk->material[source_index];
    const int32_t source_mass = material_amount_at(*chunk, source_index);
    if ((source_material != WATER_ID && source_material != STEAM_ID) || source_mass <= 0 || segment.mass >= PIPE_CAPACITY ||
        (segment.mass > 0 && segment.fluid_type != source_material)) return 0;
    const int32_t amount = std::min({requested, source_mass, static_cast<int32_t>(PIPE_CAPACITY - segment.mass)});
    const uint16_t source_temperature = chunk->temperature[source_index];
    const int64_t source_energy = cell_enthalpy(*chunk, source_index);
    const int64_t moved_energy = source_energy * amount / source_mass;
    const uint64_t pipe_key = cell_key(pipe_cell);
    const int64_t destination_energy = pipe_enthalpy(pipe_key, segment);
    segment.mass = static_cast<uint16_t>(segment.mass + amount);
    const int64_t pipe_after = set_pipe_enthalpy(pipe_key, segment, destination_energy + moved_energy, source_material);
    segment.flags |= FLAG_FLOWING;
    segment.last_flow = static_cast<int16_t>(std::min(amount, 32767));
    if (source_material == WATER_ID) write_water_state(world_cell, source_mass - amount, source_temperature);
    else write_mobile_state(world_cell, source_material, source_mass - amount, source_temperature,
                            chunk->provenance[source_index], chunk->mineral_signature[source_index]);
    if (source_mass - amount > 0) set_cell_enthalpy(world_cell, source_energy - moved_energy, source_material);
    thermal_rounding_reservoir_ += source_energy + destination_energy -
            (source_mass - amount > 0 ? cell_enthalpy(*chunk, source_index) : 0) - pipe_after;
    activate_fluid_world_cell(world_cell, 1);
    ++fluid_render_revision_;
    ++pipe_revision_;
    notify_automation_cell_change(pipe_cell);
    return amount;
}

int32_t NativeSandWorld::pipe_to_world(Vector2i pipe_cell, Vector2i world_cell, int32_t requested) {
    auto pipe = pipe_segments_.find(cell_key(pipe_cell));
    if (pipe == pipe_segments_.end() || requested <= 0) return 0;
    PipeSegment &segment = pipe->second;
    if (segment.fluid_type != WATER_ID && segment.fluid_type != STEAM_ID) return 0;
    if (segment.fluid_type == WATER_ID ? !fluid_destination_available(world_cell) : !mobile_destination_available(world_cell, segment.fluid_type)) return 0;
    const int32_t destination_mass = get_cell(world_cell) == segment.fluid_type ? material_amount_at(world_cell) : 0;
    const int32_t amount = std::min({requested, static_cast<int32_t>(segment.mass), 255 - destination_mass});
    if (amount <= 0) return 0;
    const uint64_t pipe_key = cell_key(pipe_cell);
    const int32_t source_fluid = segment.fluid_type;
    const int64_t source_energy = pipe_enthalpy(pipe_key, segment);
    const int64_t moved_energy = source_energy * amount / segment.mass;
    const Chunk *destination_chunk_before = get_chunk(world_to_chunk(world_cell));
    const int32_t destination_index = destination_chunk_before == nullptr ? 0 : local_index(world_to_local(world_cell));
    const int64_t destination_energy = destination_mass > 0 ? cell_enthalpy(*destination_chunk_before, destination_index) : 0;
    const uint16_t destination_temperature = destination_mass > 0 ? static_cast<uint16_t>(get_temperature(world_cell)) : segment.temperature;
    if (source_fluid == WATER_ID) write_water_state(world_cell, destination_mass + amount, destination_temperature);
    else write_mobile_state(world_cell, source_fluid, destination_mass + amount, destination_temperature, 0, 0);
    set_cell_enthalpy(world_cell, destination_energy + moved_energy, source_fluid);
    segment.mass = static_cast<uint16_t>(segment.mass - amount);
    segment.flags |= FLAG_FLOWING;
    segment.last_flow = static_cast<int16_t>(-std::min(amount, 32767));
    const int64_t pipe_after = set_pipe_enthalpy(pipe_key, segment, source_energy - moved_energy, source_fluid);
    const Chunk *destination_chunk_after = get_chunk(world_to_chunk(world_cell));
    thermal_rounding_reservoir_ += source_energy + destination_energy - pipe_after -
            (destination_chunk_after == nullptr ? 0 : cell_enthalpy(*destination_chunk_after, local_index(world_to_local(world_cell))));
    activate_fluid_world_cell(world_cell, 1);
    ++fluid_render_revision_;
    ++pipe_revision_;
    notify_automation_cell_change(pipe_cell);
    return amount;
}

void NativeSandWorld::update_pipe_damage(Vector2i cell, PipeSegment &segment) {
    if ((segment.flags & FLAG_BREACHED) != 0) return;
    int32_t damage = 0;
    const int32_t steam_pressure = segment.fluid_type == STEAM_ID ? 16000 + std::max(0, static_cast<int32_t>(segment.temperature) - WATER_BOIL) * 12 : 0;
    const int32_t total_pressure = static_cast<int32_t>(segment.mass) * 48000 / PIPE_CAPACITY + segment.pressure + steam_pressure;
    if (total_pressure > 60000) damage += 8 + (total_pressure - 60000) / 256;
    if (segment.temperature > TEMPERATURE_REACTION) damage += 4 + (segment.temperature - TEMPERATURE_REACTION) / 128;
    if (damage <= 0) return;
    segment.health = static_cast<uint16_t>(std::max(0, static_cast<int32_t>(segment.health) - damage));
    if (segment.health == 0 && (segment.flags & FLAG_BREACHED) == 0) {
        segment.flags |= FLAG_BREACHED;
        ++last_pipe_breaches_;
        refresh_pipe_connections(cell);
        wake_pipe_neighbors(cell);
    }
    ++pipe_revision_;
    notify_automation_cell_change(cell);
}

void NativeSandWorld::process_pipe_fluid() {
    const auto started = std::chrono::steady_clock::now();
    last_pipe_active_ = static_cast<int64_t>(active_pipe_segments_.size());
    last_pipe_visited_ = last_pipe_transfers_ = last_pipe_mass_transferred_ = 0;
    last_pipe_pump_work_ = last_pipe_valve_work_ = last_pipe_intake_mass_ = last_pipe_outlet_mass_ = 0;
    last_pipe_leak_mass_ = last_pipe_breaches_ = 0;
    last_pipe_gather_usec_ = last_pipe_state_usec_ = last_pipe_flow_usec_ = last_pipe_schedule_usec_ = 0;
    last_pipe_pressure_edges_ = last_pipe_damage_checks_ = last_pipe_phase_checks_ = 0;
    last_pipe_heat_edges_ = last_pipe_automation_hooks_ = 0;
    if (active_pipe_segments_.empty()) { last_pipe_usec_ = 0; return; }
    const auto gather_started = std::chrono::steady_clock::now();
    if (active_pipe_cache_dirty_ || active_pipe_sorted_cache_.size() != active_pipe_segments_.size()) {
        active_pipe_sorted_cache_.assign(active_pipe_segments_.begin(), active_pipe_segments_.end());
        std::sort(active_pipe_sorted_cache_.begin(), active_pipe_sorted_cache_.end());
        active_pipe_record_cache_.clear();
        active_pipe_record_cache_.reserve(active_pipe_sorted_cache_.size());
        for (const uint64_t key : active_pipe_sorted_cache_) active_pipe_record_cache_.push_back(&pipe_segments_.at(key));
        active_pipe_cache_dirty_ = false;
    }
    const std::vector<uint64_t> &keys = active_pipe_sorted_cache_;
    pipe_next_active_buffer_.clear();
    if (pipe_next_active_buffer_.capacity() < keys.size() * 2) pipe_next_active_buffer_.reserve(keys.size() * 2);
    pipe_keep_active_buffer_.assign(keys.size(), 0);
    last_pipe_gather_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - gather_started).count();
    const auto state_started = std::chrono::steady_clock::now();
    std::array<Vector2i, 4> cached_matter_coordinates{{
        Vector2i(INT32_MIN, INT32_MIN), Vector2i(INT32_MIN, INT32_MIN),
        Vector2i(INT32_MIN, INT32_MIN), Vector2i(INT32_MIN, INT32_MIN),
    }};
    std::array<Chunk *, 4> cached_matter_chunks{{nullptr, nullptr, nullptr, nullptr}};
    for (size_t key_index = 0; key_index < keys.size(); ++key_index) {
        const uint64_t key = keys[key_index];
        PipeSegment &segment = *active_pipe_record_cache_[key_index];
        const Vector2i cell = cell_from_key(key);
        ++last_pipe_visited_;
        segment.flags &= static_cast<uint8_t>(~FLAG_FLOWING);
        segment.last_flow = 0;
        bool changed = false;
        const Vector2i forward = facing(segment.orientation);
        if ((segment.flags & FLAG_BREACHED) != 0 && segment.mass > 0) {
            const std::array<Vector2i, 4> water_leak_order{{Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1)}};
            const std::array<Vector2i, 4> steam_leak_order{{Vector2i(0,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,1)}};
            const auto &leak_order = segment.fluid_type == STEAM_ID ? steam_leak_order : water_leak_order;
            for (const Vector2i offset : leak_order) {
                const int32_t amount = pipe_to_world(cell, cell + offset, std::min<int32_t>(4096, segment.mass));
                if (amount > 0) { last_pipe_leak_mass_ += amount; total_pipe_leak_mass_ += amount; record_production_flow(ProductionFlowKind::WATER_PIPE_TO_WORLD, amount); changed = true; }
                if (segment.mass == 0) break;
            }
        } else if (segment.type_id == STRUCTURE_FLUID_INTAKE && (segment.flags & FLAG_DISABLED) == 0) {
            const int32_t amount = world_to_pipe(cell + forward, cell, BASIC_PUMP_RATE);
            if (amount > 0) { last_pipe_intake_mass_ += amount; record_production_flow(ProductionFlowKind::WATER_WORLD_TO_PIPE, amount); changed = true; }
        } else if (segment.type_id == STRUCTURE_FLUID_OUTLET && (segment.flags & FLAG_DISABLED) == 0) {
            const int32_t amount = pipe_to_world(cell, cell + forward, BASIC_PUMP_RATE);
            if (amount > 0) { last_pipe_outlet_mass_ += amount; record_production_flow(ProductionFlowKind::WATER_PIPE_TO_WORLD, amount); changed = true; }
        }
        if ((tick_index_ & 1) == 0 && segment.mass > 0) {
            for (size_t direction = 0; direction < DIRECTIONS.size(); ++direction) {
                const Vector2i offset = DIRECTIONS[direction];
                const Vector2i matter_cell = cell + offset;
                const Vector2i matter_coordinate = world_to_chunk(matter_cell);
                if (cached_matter_coordinates[direction] != matter_coordinate) {
                    cached_matter_coordinates[direction] = matter_coordinate;
                    cached_matter_chunks[direction] = get_chunk(matter_coordinate);
                }
                Chunk *matter_chunk = cached_matter_chunks[direction];
                if (matter_chunk == nullptr) continue;
                const int32_t matter_index = local_index(world_to_local(matter_cell));
                const int32_t matter = matter_chunk->material[matter_index];
                if (matter == 0) continue;
                ++last_pipe_heat_edges_;
                const int32_t temperature_delta = static_cast<int32_t>(segment.temperature) - matter_chunk->temperature[matter_index];
                if (std::abs(temperature_delta) < 2) continue;
                last_pipe_phase_checks_ += 2;
                const int64_t pipe_capacity_value = pipe_heat_capacity(segment);
                const int64_t matter_capacity = thermal_capacity(matter, material_amount_at(*matter_chunk, matter_index));
                const int32_t conductivity = std::min<int32_t>(32, thermal_material_definitions()[matter].conductivity);
                const int64_t equilibrium = static_cast<int64_t>(std::abs(temperature_delta)) * pipe_capacity_value * matter_capacity /
                        std::max<int64_t>(1, pipe_capacity_value + matter_capacity);
                const int64_t transfer = std::min<int64_t>(equilibrium / 2,
                        std::max<int64_t>(1, static_cast<int64_t>(std::abs(temperature_delta)) * std::min(pipe_capacity_value, matter_capacity) * conductivity / 65536));
                const int64_t signed_transfer = temperature_delta > 0 ? transfer : -transfer;
                const int64_t pipe_before = pipe_enthalpy(key, segment);
                const int64_t matter_before = cell_enthalpy(*matter_chunk, matter_index);
                const int32_t preferred_fluid = segment.fluid_type;
                const int64_t pipe_after = set_pipe_enthalpy(key, segment, pipe_before - signed_transfer, preferred_fluid);
                set_cell_enthalpy(matter_cell, matter_before + signed_transfer, matter);
                thermal_rounding_reservoir_ += pipe_before + matter_before - pipe_after - cell_enthalpy(*matter_chunk, matter_index);
                activate_thermal_world_cell(matter_cell, 1);
                changed = true;
            }
        }
        ++last_pipe_damage_checks_;
        update_pipe_damage(cell, segment);
        if (segment.type_id == STRUCTURE_BASIC_PUMP && (segment.flags & FLAG_DISABLED) == 0) ++last_pipe_pump_work_;
        if (segment.type_id == STRUCTURE_PIPE_VALVE) ++last_pipe_valve_work_;
        if (changed || segment.mass > 0 || is_pipe_device(segment.type_id)) pipe_keep_active_buffer_[key_index] = 1;
    }
    last_pipe_state_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - state_started).count();
    const auto flow_started = std::chrono::steady_clock::now();
    const bool reverse = (tick_index_ & 1) != 0;
    auto queue_pipe_key = [&](uint64_t queued_key) {
        if (!pipe_segments_.contains(queued_key)) return;
        const auto current = std::lower_bound(keys.begin(), keys.end(), queued_key);
        if (current != keys.end() && *current == queued_key) pipe_keep_active_buffer_[static_cast<size_t>(current - keys.begin())] = 1;
        else pipe_next_active_buffer_.push_back(queued_key);
    };
    for (size_t key_index = 0; key_index < keys.size(); ++key_index) {
        const uint64_t key = keys[key_index];
        PipeSegment &current_segment = *active_pipe_record_cache_[key_index];
        const Vector2i cell = cell_from_key(key);
        for (int32_t order = 0; order < 4; ++order) {
            const int32_t direction_index_value = reverse ? 3 - order : order;
            if ((current_segment.connection_mask & (1u << direction_index_value)) == 0) continue;
            const Vector2i direction = DIRECTIONS[direction_index_value];
            const Vector2i neighbor_cell = cell + direction;
            const uint64_t neighbor_key = cell_key(neighbor_cell);
            if (key >= neighbor_key && active_pipe_segments_.contains(neighbor_key)) continue;
            auto neighbor = pipe_segments_.find(neighbor_key);
            if (neighbor == pipe_segments_.end()) continue;
            const PipeSegment &first_segment = current_segment;
            const PipeSegment &second_segment = neighbor->second;
            if ((first_segment.flags & FLAG_BREACHED) != 0 || (second_segment.flags & FLAG_BREACHED) != 0) continue;
            if ((first_segment.type_id == STRUCTURE_PIPE_VALVE && (first_segment.flags & FLAG_VALVE_CLOSED) != 0) ||
                (second_segment.type_id == STRUCTURE_PIPE_VALVE && (second_segment.flags & FLAG_VALVE_CLOSED) != 0)) continue;
            if ((second_segment.connection_mask & (1u << ((direction_index_value + 2) & 3))) == 0) continue;
            ++last_pipe_pressure_edges_;
            if (current_segment.mass > 0 && neighbor->second.mass > 0) {
                if (current_segment.pressure > neighbor->second.pressure + 8) neighbor->second.pressure = static_cast<uint16_t>(current_segment.pressure - 8);
                else if (neighbor->second.pressure > current_segment.pressure + 8) current_segment.pressure = static_cast<uint16_t>(neighbor->second.pressure - 8);
            }
            int32_t delta = pipe_potential(cell, current_segment, direction) - pipe_potential(neighbor_cell, neighbor->second, -direction);
            Vector2i source = cell;
            Vector2i destination = neighbor_cell;
            if (delta < -PRESSURE_DEADBAND) { delta = -delta; source = neighbor_cell; destination = cell; }
            if (delta <= PRESSURE_DEADBAND) continue;
            PipeSegment &source_segment = source == cell ? current_segment : neighbor->second;
            PipeSegment &destination_segment = destination == cell ? current_segment : neighbor->second;
            const uint64_t source_key = source == cell ? key : neighbor_key;
            const uint64_t destination_key = destination == cell ? key : neighbor_key;
            const bool steam_source = source_segment.fluid_type == STEAM_ID;
            int32_t rate = PASSIVE_RATE;
            if (source_segment.type_id == STRUCTURE_BASIC_PUMP && (source_segment.flags & FLAG_DISABLED) == 0 &&
                destination - source == facing(source_segment.orientation))
                rate = (has_research("fluid.pressurized_transport") ? UPGRADED_PUMP_RATE : BASIC_PUMP_RATE) +
                       4096 * electric_satisfaction(STRUCTURE_BASIC_PUMP, 0, source) / 1000;
            const int32_t amount = transfer_pipe_mass_indexed(source_key, source_segment, source,
                    destination_key, destination_segment, destination, std::min(rate, delta / 4));
            if (amount <= 0) continue;
            last_pipe_phase_checks_ += 2;
            last_pipe_automation_hooks_ += 2;
            ++last_pipe_transfers_;
            last_pipe_mass_transferred_ += amount;
            record_production_flow(ProductionFlowKind::PIPE_THROUGHPUT, amount);
            if (steam_source) record_production_flow(ProductionFlowKind::STEAM_PIPE_THROUGHPUT, amount);
            pipe_keep_active_buffer_[key_index] = 1;
            queue_pipe_key(source_key);
            queue_pipe_key(destination_key);
        }
    }
    last_pipe_flow_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - flow_started).count();
    const auto schedule_started = std::chrono::steady_clock::now();
    std::sort(pipe_next_active_buffer_.begin(), pipe_next_active_buffer_.end());
    pipe_next_active_buffer_.erase(std::unique(pipe_next_active_buffer_.begin(), pipe_next_active_buffer_.end()), pipe_next_active_buffer_.end());
    pipe_candidate_active_buffer_.clear();
    if (pipe_candidate_active_buffer_.capacity() < keys.size() + pipe_next_active_buffer_.size())
        pipe_candidate_active_buffer_.reserve(keys.size() + pipe_next_active_buffer_.size());
    for (size_t key_index = 0; key_index < keys.size(); ++key_index)
        if (pipe_keep_active_buffer_[key_index] != 0) pipe_candidate_active_buffer_.push_back(keys[key_index]);
    const size_t active_candidate_count = pipe_candidate_active_buffer_.size();
    pipe_candidate_active_buffer_.insert(pipe_candidate_active_buffer_.end(), pipe_next_active_buffer_.begin(), pipe_next_active_buffer_.end());
    std::inplace_merge(pipe_candidate_active_buffer_.begin(), pipe_candidate_active_buffer_.begin() + active_candidate_count,
                       pipe_candidate_active_buffer_.end());
    pipe_filtered_active_buffer_.clear();
    if (pipe_filtered_active_buffer_.capacity() < pipe_candidate_active_buffer_.size()) pipe_filtered_active_buffer_.reserve(pipe_candidate_active_buffer_.size());
    for (const uint64_t key : pipe_candidate_active_buffer_) {
        auto found = pipe_segments_.find(key);
        if (found == pipe_segments_.end()) continue;
        PipeSegment &segment = found->second;
        const bool dynamic_device = segment.type_id == STRUCTURE_FLUID_INTAKE || segment.type_id == STRUCTURE_FLUID_OUTLET ||
                                    segment.type_id == STRUCTURE_BASIC_PUMP || (segment.flags & FLAG_BREACHED) != 0;
        const bool moving = (segment.flags & FLAG_FLOWING) != 0 || segment.last_flow != 0;
        const uint8_t quiet = moving ? 0 : static_cast<uint8_t>(quiet_ticks(segment.flags) + 1);
        set_quiet(segment.flags, quiet);
        if (moving || quiet < 8 || (dynamic_device && segment.mass > 0)) pipe_filtered_active_buffer_.push_back(key);
        else { segment.flags &= static_cast<uint8_t>(~FLAG_FLOWING); segment.last_flow = 0; }
    }
    if (pipe_filtered_active_buffer_ != active_pipe_sorted_cache_) {
        active_pipe_segments_.clear();
        active_pipe_segments_.reserve(pipe_filtered_active_buffer_.size() * 2);
        for (const uint64_t key : pipe_filtered_active_buffer_) active_pipe_segments_.insert(key);
        active_pipe_sorted_cache_ = pipe_filtered_active_buffer_;
        active_pipe_record_cache_.clear();
        active_pipe_record_cache_.reserve(active_pipe_sorted_cache_.size());
        for (const uint64_t key : active_pipe_sorted_cache_) active_pipe_record_cache_.push_back(&pipe_segments_.at(key));
    }
    last_pipe_schedule_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - schedule_started).count();
    last_pipe_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

int32_t NativeSandWorld::set_pipe_mass(Vector2i world_cell, int32_t mass, int32_t temperature) {
    return set_pipe_fluid(world_cell, WATER_ID, mass, temperature);
}

int32_t NativeSandWorld::set_pipe_fluid(Vector2i world_cell, int32_t fluid_type, int32_t mass, int32_t temperature) {
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end() || (fluid_type != WATER_ID && fluid_type != STEAM_ID) || mass < 0 || mass > PIPE_CAPACITY || temperature < 0 || temperature > TEMPERATURE_MAX) return 31;
    PipeSegment &segment = found->second;
    segment.mass = static_cast<uint16_t>(mass);
    segment.fluid_type = mass > 0 ? static_cast<uint16_t>(fluid_type) : 0;
    segment.temperature = mass > 0 ? static_cast<uint16_t>(temperature) : TEMPERATURE_AMBIENT;
    const uint64_t key = cell_key(world_cell);
    if (!pipe_phase_energy_.empty()) pipe_phase_energy_.erase(key);
    if (mass > 0) {
        const int64_t requested_enthalpy = pipe_enthalpy(key, segment);
        set_pipe_enthalpy(key, segment, requested_enthalpy, fluid_type);
    }
    ++pipe_revision_;
    wake_pipe_neighbors(world_cell);
    notify_automation_cell_change(world_cell);
    return 0;
}

Dictionary NativeSandWorld::get_pipe_state(Vector2i world_cell) const {
    Dictionary result;
    const auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end()) return result;
    const PipeSegment &segment = found->second;
    result["fluid_type"] = segment.fluid_type;
    result["mass"] = segment.mass;
    result["capacity"] = PIPE_CAPACITY;
    result["fill_per_mille"] = static_cast<int32_t>(segment.mass) * 1000 / PIPE_CAPACITY;
    result["temperature"] = segment.temperature;
    const int32_t steam_pressure = segment.fluid_type == STEAM_ID ? 16000 + std::max(0, static_cast<int32_t>(segment.temperature) - WATER_BOIL) * 12 : 0;
    result["pressure"] = std::clamp<int32_t>(static_cast<int32_t>(segment.mass) * 48000 / PIPE_CAPACITY + segment.pressure + steam_pressure, 0, 65535);
    const auto phase = pipe_phase_energy_.find(cell_key(world_cell));
    result["phase_energy"] = phase == pipe_phase_energy_.end() ? 0 : phase->second;
    result["enthalpy"] = pipe_enthalpy(found->first, segment);
    result["flow"] = segment.last_flow;
    result["health"] = segment.health;
    result["connections"] = segment.connection_mask;
    result["enabled"] = (segment.flags & FLAG_DISABLED) == 0;
    result["open"] = (segment.flags & FLAG_VALVE_CLOSED) == 0;
    result["breached"] = (segment.flags & FLAG_BREACHED) != 0;
    result["type_id"] = segment.type_id;
    result["orientation"] = segment.orientation;
    return result;
}

Dictionary NativeSandWorld::get_pipe_statistics() const {
    Dictionary result;
    int64_t breached = 0, pumps = 0, valves = 0, intakes = 0, outlets = 0, steam_mass = 0, water_mass = 0;
    for (const auto &[key, segment] : pipe_segments_) {
        (void)key;
        breached += (segment.flags & FLAG_BREACHED) != 0 ? 1 : 0;
        pumps += segment.type_id == STRUCTURE_BASIC_PUMP ? 1 : 0;
        valves += segment.type_id == STRUCTURE_PIPE_VALVE ? 1 : 0;
        intakes += segment.type_id == STRUCTURE_FLUID_INTAKE ? 1 : 0;
        outlets += segment.type_id == STRUCTURE_FLUID_OUTLET ? 1 : 0;
        water_mass += segment.fluid_type == WATER_ID ? segment.mass : 0;
        steam_mass += segment.fluid_type == STEAM_ID ? segment.mass : 0;
    }
    result["segments_total"] = static_cast<int64_t>(pipe_segments_.size());
    result["segments_active"] = static_cast<int64_t>(active_pipe_segments_.size());
    result["segments_visited"] = last_pipe_visited_;
    result["transfers"] = last_pipe_transfers_;
    result["mass_transferred"] = last_pipe_mass_transferred_;
    result["mass_total"] = get_total_pipe_water_mass();
    result["water_mass"] = water_mass; result["steam_mass"] = steam_mass;
    result["pumps"] = pumps; result["valves"] = valves; result["intakes"] = intakes; result["outlets"] = outlets;
    result["pump_work"] = last_pipe_pump_work_; result["valve_work"] = last_pipe_valve_work_;
    result["intake_mass"] = last_pipe_intake_mass_; result["outlet_mass"] = last_pipe_outlet_mass_;
    result["leak_mass"] = last_pipe_leak_mass_; result["leak_mass_total"] = total_pipe_leak_mass_;
    result["breached_segments"] = breached; result["breaches"] = last_pipe_breaches_;
    result["pipe_usec"] = last_pipe_usec_;
    result["gather_usec"] = last_pipe_gather_usec_;
    result["state_usec"] = last_pipe_state_usec_;
    result["flow_usec"] = last_pipe_flow_usec_;
    result["schedule_usec"] = last_pipe_schedule_usec_;
    result["pressure_edges"] = last_pipe_pressure_edges_;
    result["damage_checks"] = last_pipe_damage_checks_;
    result["phase_checks"] = last_pipe_phase_checks_;
    result["heat_edges"] = last_pipe_heat_edges_;
    result["automation_hooks"] = last_pipe_automation_hooks_;
    result["record_bytes"] = static_cast<int64_t>(pipe_segments_.size() * sizeof(PipeSegment));
    result["scheduler_key_bytes"] = static_cast<int64_t>(active_pipe_segments_.size() * sizeof(uint64_t));
    result["scheduler_buffer_capacity_bytes"] = static_cast<int64_t>(
            (active_pipe_sorted_cache_.capacity() + pipe_next_active_buffer_.capacity() +
             pipe_candidate_active_buffer_.capacity() + pipe_filtered_active_buffer_.capacity()) * sizeof(uint64_t) +
            pipe_keep_active_buffer_.capacity() * sizeof(uint8_t));
    result["thermal_scale_lookup_bytes"] = static_cast<int64_t>(pipe_mass_scales().size() * sizeof(PipeMassScale));
    result["phase_energy_entries"] = static_cast<int64_t>(pipe_phase_energy_.size());
    result["phase_energy_backing_bytes"] = static_cast<int64_t>(pipe_phase_energy_.size() * (sizeof(uint64_t) + sizeof(int64_t)));
    result["revision"] = static_cast<int64_t>(pipe_revision_);
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_pipe_segments(Rect2i chunk_area) const {
    PackedInt32Array result;
    const Rect2i cell_area(chunk_area.position * CHUNK_SIZE, chunk_area.size * CHUNK_SIZE);
    std::vector<uint64_t> keys;
    for (const auto &[key, segment] : pipe_segments_) { (void)segment; if (cell_area.has_point(cell_from_key(key))) keys.push_back(key); }
    std::sort(keys.begin(), keys.end());
    for (const uint64_t key : keys) {
        const Vector2i cell = cell_from_key(key);
        const PipeSegment &segment = pipe_segments_.at(key);
        result.push_back(cell.x); result.push_back(cell.y); result.push_back(segment.type_id); result.push_back(segment.orientation);
        result.push_back(segment.mass); result.push_back(segment.last_flow); result.push_back(segment.flags & 0x0f); result.push_back(segment.health);
        const int32_t steam_pressure = segment.fluid_type == STEAM_ID ? 16000 + std::max(0, static_cast<int32_t>(segment.temperature) - WATER_BOIL) * 12 : 0;
        result.push_back(segment.connection_mask); result.push_back(std::clamp<int32_t>(segment.pressure + steam_pressure, 0, 65535)); result.push_back(segment.temperature);
    }
    return result;
}

Dictionary NativeSandWorld::get_infrastructure_render_page(Vector2i chunk_coordinate) const {
    Dictionary result;
    const Chunk *chunk = get_chunk(chunk_coordinate);
    int32_t infrastructure_count = 0;
    int32_t pipe_count = 0;
    int32_t min_x = CHUNK_SIZE, min_y = CHUNK_SIZE, max_x = -1, max_y = -1;
    if (chunk != nullptr && chunk->structures != nullptr) {
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const uint8_t type_id = (*chunk->structures)[index] & 0x7fu;
            if (!(type_id == 1 || type_id == 2 || is_pipe_structure(type_id))) continue;
            const int32_t local_x = index % CHUNK_SIZE;
            const int32_t local_y = index / CHUNK_SIZE;
            min_x = std::min(min_x, local_x); min_y = std::min(min_y, local_y);
            max_x = std::max(max_x, local_x); max_y = std::max(max_y, local_y);
            ++infrastructure_count;
        }
    }
    const int32_t width = infrastructure_count > 0 ? max_x - min_x + 1 : 0;
    const int32_t height = infrastructure_count > 0 ? max_y - min_y + 1 : 0;
    PackedByteArray topology;
    PackedByteArray dynamic;
    topology.resize(width * height * 4);
    dynamic.resize(width * height * 4);
    uint8_t *topology_bytes = topology.ptrw();
    uint8_t *dynamic_bytes = dynamic.ptrw();
    std::fill(topology_bytes, topology_bytes + topology.size(), uint8_t{0});
    std::fill(dynamic_bytes, dynamic_bytes + dynamic.size(), uint8_t{0});
    if (chunk != nullptr && chunk->structures != nullptr) {
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const uint8_t type_id = (*chunk->structures)[index] & 0x7fu;
            if (!(type_id == 1 || type_id == 2 || is_pipe_structure(type_id))) continue;
            const int32_t local_x = index % CHUNK_SIZE;
            const int32_t local_y = index / CHUNK_SIZE;
            const int32_t byte = ((local_y - min_y) * width + local_x - min_x) * 4;
            topology_bytes[byte] = type_id;
            topology_bytes[byte + 3] = 255;
            if (!is_pipe_structure(type_id)) continue;
            const Vector2i local(local_x, local_y);
            const Vector2i cell = chunk_coordinate * CHUNK_SIZE + local;
            const auto found = pipe_segments_.find(cell_key(cell));
            if (found == pipe_segments_.end()) continue;
            const PipeSegment &segment = found->second;
            topology_bytes[byte + 1] = static_cast<uint8_t>(segment.connection_mask * 17u);
            topology_bytes[byte + 2] = segment.orientation;
            dynamic_bytes[byte] = static_cast<uint8_t>((static_cast<uint32_t>(segment.mass) * 255u) / PIPE_CAPACITY);
            dynamic_bytes[byte + 1] = static_cast<uint8_t>(std::clamp<int32_t>(segment.last_flow / 64 + 128, 0, 255));
            dynamic_bytes[byte + 2] = static_cast<uint8_t>((segment.flags & 0x0fu) * 17u);
            dynamic_bytes[byte + 3] = static_cast<uint8_t>((static_cast<uint32_t>(segment.health) * 255u) / 65535u);
            ++pipe_count;
        }
    }
    result["topology"] = topology;
    result["dynamic"] = dynamic;
    result["infrastructure_count"] = infrastructure_count;
    result["pipe_count"] = pipe_count;
    result["width"] = width;
    result["height"] = height;
    result["cell_position"] = chunk_coordinate * CHUNK_SIZE + Vector2i(min_x, min_y);
    return result;
}

int64_t NativeSandWorld::get_total_pipe_water_mass() const {
    int64_t total = 0;
    for (const auto &[key, segment] : pipe_segments_) { (void)key; if (segment.fluid_type == WATER_ID) total += segment.mass; }
    return total;
}

int64_t NativeSandWorld::get_total_conserved_water_mass() const { return get_total_water_mass() + get_total_pipe_water_mass(); }

int64_t NativeSandWorld::get_total_pipe_water_phase_mass() const {
    int64_t total = 0;
    for (const auto &[key, segment] : pipe_segments_) {
        (void)key;
        if (segment.fluid_type == WATER_ID || segment.fluid_type == STEAM_ID) total += segment.mass;
    }
    return total;
}

int64_t NativeSandWorld::get_total_conserved_water_phase_mass() const {
    return get_total_phase_family_mass(1) + get_total_pipe_water_phase_mass();
}

bool NativeSandWorld::set_pipe_device_enabled(Vector2i world_cell, bool enabled) {
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end() || (found->second.type_id != STRUCTURE_BASIC_PUMP && found->second.type_id != STRUCTURE_FLUID_INTAKE && found->second.type_id != STRUCTURE_FLUID_OUTLET)) return false;
    if (enabled) found->second.flags &= static_cast<uint8_t>(~FLAG_DISABLED); else found->second.flags |= FLAG_DISABLED;
    ++pipe_revision_; wake_pipe_neighbors(world_cell); notify_automation_cell_change(world_cell); return true;
}

bool NativeSandWorld::set_pipe_valve_open(Vector2i world_cell, bool open) {
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end() || found->second.type_id != STRUCTURE_PIPE_VALVE) return false;
    if (open) found->second.flags &= static_cast<uint8_t>(~FLAG_VALVE_CLOSED); else found->second.flags |= FLAG_VALVE_CLOSED;
    ++pipe_revision_; wake_pipe_neighbors(world_cell); notify_automation_cell_change(world_cell); return true;
}

int32_t NativeSandWorld::damage_pipe(Vector2i world_cell, int32_t damage, int32_t cause) {
    (void)cause;
    auto found = pipe_segments_.find(cell_key(world_cell));
    if (found == pipe_segments_.end() || damage <= 0) return -1;
    PipeSegment &segment = found->second;
    segment.health = static_cast<uint16_t>(std::max(0, static_cast<int32_t>(segment.health) - damage));
    if (segment.health == 0 && (segment.flags & FLAG_BREACHED) == 0) {
        segment.flags |= FLAG_BREACHED;
        ++last_pipe_breaches_;
        refresh_pipe_connections(world_cell);
    }
    ++pipe_revision_; wake_pipe_neighbors(world_cell); notify_automation_cell_change(world_cell); return segment.health;
}

String NativeSandWorld::pipe_state_hash() const {
    uint32_t hash = 2166136261u;
    auto mix = [&hash](uint32_t value) { hash ^= value; hash *= 16777619u; };
    std::vector<uint64_t> keys;
    for (const auto &[key, segment] : pipe_segments_) { (void)segment; keys.push_back(key); }
    std::sort(keys.begin(), keys.end());
    for (const uint64_t key : keys) {
        const PipeSegment &segment = pipe_segments_.at(key);
        mix(static_cast<uint32_t>(key >> 32u)); mix(static_cast<uint32_t>(key)); mix(segment.fluid_type); mix(segment.mass);
        mix(segment.temperature); mix(segment.pressure); mix(segment.health); mix(segment.flags & 0x0f); mix(segment.connection_mask);
        mix(segment.type_id); mix(segment.orientation);
    }
    char buffer[9]; std::snprintf(buffer, sizeof(buffer), "%08x", hash); return String(buffer);
}

Dictionary NativeSandWorld::get_wet_processing_statistics() const {
    Dictionary result;
    int64_t total = 0;
    for (const auto &[id, processor] : physical_processors_) { (void)id; if (processor.type_id == 17) ++total; }
    result["sluices_total"] = total;
    result["sluices_active"] = static_cast<int64_t>(active_wet_sluices_.size());
    result["cells_visited"] = last_wet_cells_visited_;
    result["grains_moved"] = last_wet_grains_moved_;
    result["heavy_captured"] = last_wet_heavy_captured_;
    result["light_output"] = last_wet_light_output_;
    result["wet_usec"] = last_wet_usec_;
    return result;
}

} // namespace godot
