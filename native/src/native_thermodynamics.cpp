#include "native_sand_world.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <numeric>

namespace godot {
namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t WATER = 3;
constexpr int32_t GLASS = 10;
constexpr int32_t IRON = 11;
constexpr int32_t ICE = 16;
constexpr int32_t STEAM = 17;
constexpr int32_t MOLTEN_GLASS = 18;
constexpr int32_t MOLTEN_IRON = 19;
constexpr int32_t WOOD = 21;
constexpr int32_t LEAVES = 22;
constexpr int32_t CHARCOAL = 23;
constexpr int32_t SMOKE = 24;
constexpr int32_t RAW_FOOD = 25;
constexpr int32_t COOKED_FOOD = 26;
constexpr int32_t BURNT_FOOD = 27;
constexpr uint8_t PHASE_HEATING = 1u << 1;
constexpr uint8_t PHASE_COOLING = 1u << 2;
constexpr uint8_t PHASE_MASK = PHASE_HEATING | PHASE_COOLING;
constexpr int32_t WATER_FREEZE = 1092; // 273 K in quarter-kelvin units.
constexpr int32_t WATER_BOIL = 1492;  // 373 K.
constexpr int32_t GLASS_MELT = 5873;  // Tuned industrial softening/melt point.
constexpr int32_t IRON_MELT = 7245;   // 1811 K.
constexpr int32_t LATENT_ICE = 12000;
constexpr int32_t LATENT_STEAM = 42000;
constexpr int32_t LATENT_GLASS = 20000;
constexpr int32_t LATENT_IRON = 16000;

int32_t scaled_latent(int32_t full, int32_t amount) {
    return std::max(1, (full * amount + 254) / 255);
}
}

const std::array<NativeSandWorld::ThermalMaterialDefinition, NativeSandWorld::MATERIAL_COUNT> &NativeSandWorld::thermal_material_definitions() {
    static const std::array<ThermalMaterialDefinition, MATERIAL_COUNT> definitions = [] {
        std::array<ThermalMaterialDefinition, MATERIAL_COUNT> d{};
        for (ThermalMaterialDefinition &v : d) v = {32, 48, 1000, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, false, false};
        d[EMPTY] = {0, 1, 0, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::EMPTY, 0, false, false};
        d[1] = {64, 64, 2600, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, false, false};
        d[2] = {48, 48, 1600, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[WATER] = {48, 128, 1000, WATER_FREEZE, WATER_BOIL, LATENT_ICE, LATENT_STEAM,
                    ICE, STEAM, 1, MatterPhase::LIQUID, 255, true, true};
        d[4] = {24, 36, 1300, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, false, false};
        d[5] = {8, 80, 4000, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, false, false};
        for (int i = 6; i <= 9; ++i) d[i] = {42, 46, 1800, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[GLASS] = {24, 40, 2500, 0, GLASS_MELT, 0, LATENT_GLASS, -1, MOLTEN_GLASS, 2, MatterPhase::GRANULAR, 0, true, false};
        d[IRON] = {192, 56, 7870, 0, IRON_MELT, 0, LATENT_IRON, -1, MOLTEN_IRON, 3, MatterPhase::GRANULAR, 0, true, false};
        d[12] = {160, 52, 19300, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[13] = {30, 44, 1700, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[14] = {28, 36, 1300, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[15] = {18, 34, 900, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[ICE] = {80, 64, 917, 0, WATER_FREEZE, 0, LATENT_ICE, -1, WATER, 1, MatterPhase::SOLID, 0, true, false};
        d[STEAM] = {20, 32, 1, WATER_BOIL, TEMPERATURE_MAX, LATENT_STEAM, 0, WATER, -1, 1, MatterPhase::GAS, 255, true, true};
        d[MOLTEN_GLASS] = {28, 48, 2350, GLASS_MELT, TEMPERATURE_MAX, LATENT_GLASS, 0, GLASS, -1, 2, MatterPhase::MOLTEN, 4, true, false};
        d[MOLTEN_IRON] = {160, 64, 7000, IRON_MELT, TEMPERATURE_MAX, LATENT_IRON, 0, IRON, -1, 3, MatterPhase::MOLTEN, 12, true, false};
        d[20] = {52, 54, 2100, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, false, false};
        d[WOOD] = {18, 72, 700, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, true, false};
        d[LEAVES] = {10, 36, 180, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::SOLID, 0, true, false};
        d[CHARCOAL] = {12, 44, 420, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, true, false};
        d[SMOKE] = {8, 24, 2, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GAS, 220, true, false};
        d[RAW_FOOD] = {22, 92, 650, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, true, false};
        d[COOKED_FOOD] = {20, 78, 610, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, true, false};
        d[BURNT_FOOD] = {14, 48, 430, 0, TEMPERATURE_MAX, 0, 0, -1, -1, 0, MatterPhase::GRANULAR, 0, true, false};
        return d;
    }();
    return definitions;
}

bool NativeSandWorld::is_gas_material(int32_t material) {
    return material == STEAM || material == SMOKE;
}

bool NativeSandWorld::is_liquid_material(int32_t material) {
    return material == WATER || material == MOLTEN_GLASS || material == MOLTEN_IRON;
}

bool NativeSandWorld::is_mobile_material(int32_t material) {
    return is_liquid_material(material) || is_gas_material(material);
}

int32_t NativeSandWorld::material_amount_at(const Chunk &chunk, int32_t index) const {
    if (chunk.material[index] == EMPTY) return 0;
    return chunk.material_amount == nullptr ? 255 : (*chunk.material_amount)[index];
}

int32_t NativeSandWorld::material_amount_at(Vector2i cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(cell));
    return chunk == nullptr ? 0 : material_amount_at(*chunk, local_index(world_to_local(cell)));
}

bool NativeSandWorld::mobile_destination_available(Vector2i cell, int32_t material) const {
    const Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr || is_structure_solid(cell)) return false;
    const int32_t destination = chunk->material[local_index(world_to_local(cell))];
    return destination == EMPTY || destination == material;
}

void NativeSandWorld::write_mobile_state(Vector2i cell, int32_t material, int32_t amount, uint16_t temperature,
                                          uint16_t provenance, uint16_t signature, MatterJobResult *result,
                                          bool collect_changes) {
    Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr) return;
    const Vector2i local = world_to_local(cell);
    const int32_t index = local_index(local);
    const int32_t old_material = chunk->material[index];
    if (amount > 0 && amount < 255) ensure_liquid_plane(*chunk);
    if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = static_cast<uint8_t>(amount);
    chunk->material[index] = amount > 0 ? static_cast<uint16_t>(material) : EMPTY;
    chunk->temperature[index] = amount > 0 ? temperature : TEMPERATURE_AMBIENT;
    chunk->provenance[index] = amount > 0 ? provenance : 0;
    chunk->mineral_signature[index] = amount > 0 ? signature : 0;
    chunk->flags[index] &= static_cast<uint8_t>(~PHASE_MASK);
    if (chunk->phase_energy != nullptr) (*chunk->phase_energy)[index] = 0;
    const int32_t new_material = amount > 0 ? material : EMPTY;
    if (old_material != new_material &&
        (chunk->organic_moisture != nullptr || chunk->reaction_progress != nullptr || chunk->reaction_state != nullptr ||
         is_combustible_material(old_material) || is_combustible_material(new_material))) {
        if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
        if (chunk->reaction_progress != nullptr) (*chunk->reaction_progress)[index] = 0;
        if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = 0;
        if (is_combustible_material(old_material) || is_combustible_material(new_material)) reactive_cells_.erase(cell_key(cell));
    }
    ++chunk->revision; chunk->pristine = false; chunk->fluid_moved_this_tick = true;
    chunk->render_dirty.include(local.x, local.y, 1); chunk->fluid_next_active.include(local.x, local.y, 1);
    if (collect_changes && result != nullptr) result->changed_cells.push_back(cell);
}

int32_t NativeSandWorld::transfer_mobile_material(Vector2i source, Vector2i destination, int32_t requested,
                                                   MatterJobResult &result, bool primary_direction,
                                                   bool collect_changes) {
    Chunk *source_chunk = get_chunk(world_to_chunk(source));
    Chunk *destination_chunk = get_chunk(world_to_chunk(destination));
    if (source_chunk == nullptr || destination_chunk == nullptr) return 0;
    const Vector2i source_local = world_to_local(source);
    const Vector2i destination_local = world_to_local(destination);
    const int32_t source_index = local_index(source_local);
    const int32_t destination_index = local_index(destination_local);
    return transfer_mobile_material_indexed(*source_chunk, source_index, source, *destination_chunk, destination_index,
                                            destination, requested, result, primary_direction, collect_changes);
}

int32_t NativeSandWorld::transfer_mobile_material_indexed(Chunk &source_chunk, int32_t source_index, Vector2i source,
                                                           Chunk &destination_chunk, int32_t destination_index,
                                                           Vector2i destination, int32_t requested,
                                                           MatterJobResult &result, bool primary_direction,
                                                           bool collect_changes) {
    const int32_t material = source_chunk.material[source_index];
    if (!is_mobile_material(material) || (structures_allocated_ > 0 && is_structure_solid(destination))) return 0;
    const int32_t destination_material = destination_chunk.material[destination_index];
    if (destination_material != EMPTY && destination_material != material) return 0;
    const int32_t source_amount = material_amount_at(source_chunk, source_index);
    const int32_t destination_amount = destination_material == material ? material_amount_at(destination_chunk, destination_index) : 0;
    const int32_t amount = std::min({requested, source_amount, 255 - destination_amount});
    if (amount <= 0) return 0;
    const uint16_t source_temperature = source_chunk.temperature[source_index];
    const uint16_t destination_temperature = destination_amount > 0 ? destination_chunk.temperature[destination_index] : source_temperature;
    const bool source_has_phase_progress = source_chunk.phase_energy != nullptr && (*source_chunk.phase_energy)[source_index] != 0;
    const bool destination_has_phase_progress = destination_chunk.phase_energy != nullptr && (*destination_chunk.phase_energy)[destination_index] != 0;
    const bool simple_equal_temperature = source_temperature == destination_temperature &&
            !source_has_phase_progress && !destination_has_phase_progress &&
            ((source_chunk.flags[source_index] | destination_chunk.flags[destination_index]) & PHASE_MASK) == 0;
    const uint16_t provenance = source_chunk.provenance[source_index];
    const uint16_t signature = source_chunk.mineral_signature[source_index];
    const uint16_t destination_provenance = destination_amount > 0 ? destination_chunk.provenance[destination_index] : provenance;
    const uint16_t destination_signature = destination_amount > 0 ? destination_chunk.mineral_signature[destination_index] : signature;
    auto write_resolved = [&](Chunk &target, int32_t target_index, Vector2i cell, int32_t next_amount,
                              uint16_t temperature, uint16_t cell_provenance, uint16_t cell_signature) {
        const Vector2i local(target_index & (CHUNK_SIZE - 1), target_index / CHUNK_SIZE);
        if (next_amount > 0 && next_amount < 255) ensure_liquid_plane(target);
        if (target.material_amount != nullptr) (*target.material_amount)[target_index] = static_cast<uint8_t>(next_amount);
        target.material[target_index] = next_amount > 0 ? static_cast<uint16_t>(material) : EMPTY;
        target.temperature[target_index] = next_amount > 0 ? temperature : TEMPERATURE_AMBIENT;
        target.provenance[target_index] = next_amount > 0 ? cell_provenance : 0;
        target.mineral_signature[target_index] = next_amount > 0 ? cell_signature : 0;
        target.flags[target_index] &= static_cast<uint8_t>(~PHASE_MASK);
        if (target.phase_energy != nullptr) (*target.phase_energy)[target_index] = 0;
        ++target.revision; target.pristine = false; target.fluid_moved_this_tick = true;
        target.render_dirty.include(local.x, local.y, 1); target.fluid_next_active.include(local.x, local.y, 1);
        if (collect_changes) result.changed_cells.push_back(cell);
    };
    if (simple_equal_temperature && destination_amount == 0 && amount == source_amount) {
        const Vector2i source_local(source_index & (CHUNK_SIZE - 1), source_index / CHUNK_SIZE);
        const Vector2i destination_local(destination_index & (CHUNK_SIZE - 1), destination_index / CHUNK_SIZE);
        if (source_chunk.material_amount != nullptr) (*source_chunk.material_amount)[source_index] = 0;
        source_chunk.material[source_index] = EMPTY;
        source_chunk.temperature[source_index] = TEMPERATURE_AMBIENT;
        source_chunk.provenance[source_index] = 0;
        source_chunk.mineral_signature[source_index] = 0;
        source_chunk.flags[source_index] &= static_cast<uint8_t>(~PHASE_MASK);
        if (source_chunk.phase_energy != nullptr) (*source_chunk.phase_energy)[source_index] = 0;
        ++source_chunk.revision; source_chunk.pristine = false; source_chunk.fluid_moved_this_tick = true;
        source_chunk.render_dirty.include(source_local.x, source_local.y, 1);
        source_chunk.fluid_next_active.include(source_local.x, source_local.y, 1);
        if (amount < 255 && destination_chunk.material_amount == nullptr) ensure_liquid_plane(destination_chunk);
        if (destination_chunk.material_amount != nullptr) (*destination_chunk.material_amount)[destination_index] = static_cast<uint8_t>(amount);
        destination_chunk.material[destination_index] = static_cast<uint16_t>(material);
        destination_chunk.temperature[destination_index] = destination_temperature;
        destination_chunk.provenance[destination_index] = provenance;
        destination_chunk.mineral_signature[destination_index] = signature;
        destination_chunk.flags[destination_index] &= static_cast<uint8_t>(~PHASE_MASK);
        if (destination_chunk.phase_energy != nullptr) (*destination_chunk.phase_energy)[destination_index] = 0;
        ++destination_chunk.revision; destination_chunk.pristine = false; destination_chunk.fluid_moved_this_tick = true;
        destination_chunk.render_dirty.include(destination_local.x, destination_local.y, 1);
        destination_chunk.fluid_next_active.include(destination_local.x, destination_local.y, 1);
        if (collect_changes) { result.changed_cells.push_back(source); result.changed_cells.push_back(destination); }
        source_chunk.flags[source_index] |= 1u; destination_chunk.flags[destination_index] |= 1u;
        ++result.transfers; result.mass_transferred += amount;
        if (primary_direction) ++result.downward; else ++result.lateral;
        if (is_gas_material(material)) {
            ++result.gas_transfers; result.gas_mass_transferred += amount;
            if (&source_chunk == &destination_chunk) ++result.gas_local_transfers;
            else ++result.gas_cross_chunk_transfers;
        }
        if (&source_chunk != &destination_chunk) ++result.border;
        return amount;
    }
    const int64_t source_energy = cell_enthalpy(source_chunk, source_index);
    const int64_t destination_energy = destination_amount > 0 ? cell_enthalpy(destination_chunk, destination_index) : 0;
    write_resolved(source_chunk, source_index, source, source_amount - amount, source_temperature, provenance, signature);
    write_resolved(destination_chunk, destination_index, destination, destination_amount + amount, destination_temperature,
                   destination_provenance, destination_signature);
    auto assign_same_phase_energy = [&](Chunk &target, int32_t target_index, int64_t energy) {
        const int32_t target_amount = material_amount_at(target, target_index);
        if (target_amount <= 0) return;
        const int32_t capacity = thermal_capacity(material, target_amount);
        const int64_t local_energy = std::max<int64_t>(0, energy - phase_base_enthalpy(material, target_amount));
        const uint16_t next_temperature = static_cast<uint16_t>(std::clamp<int64_t>(local_energy / capacity, 0, TEMPERATURE_MAX));
        const uint16_t remainder = static_cast<uint16_t>(local_energy - static_cast<int64_t>(next_temperature) * capacity);
        target.temperature[target_index] = next_temperature;
        target.flags[target_index] &= static_cast<uint8_t>(~PHASE_MASK);
        if (remainder > 0 && target.phase_energy == nullptr) ensure_phase_energy_plane(target);
        if (target.phase_energy != nullptr) (*target.phase_energy)[target_index] = remainder;
    };
    if (simple_equal_temperature) {
        const int32_t remaining = source_amount - amount;
        const int32_t combined = destination_amount + amount;
        const int64_t source_after = remaining > 0
                ? phase_base_enthalpy(material, remaining) + static_cast<int64_t>(thermal_capacity(material, remaining)) * source_temperature
                : 0;
        const int64_t destination_after = phase_base_enthalpy(material, combined) +
                static_cast<int64_t>(thermal_capacity(material, combined)) * destination_temperature;
        result.enthalpy_rounding += source_energy + destination_energy - source_after - destination_after;
    } else if (source_temperature == destination_temperature) {
        int64_t source_after = 0;
        if (source_amount - amount > 0) {
            const int32_t remaining = source_amount - amount;
            source_after = phase_base_enthalpy(material, remaining) + static_cast<int64_t>(thermal_capacity(material, remaining)) * source_temperature;
        }
        assign_same_phase_energy(destination_chunk, destination_index, source_energy + destination_energy - source_after);
    } else {
        const int64_t moved_energy = source_energy * amount / source_amount;
        if (source_amount - amount > 0) assign_same_phase_energy(source_chunk, source_index, source_energy - moved_energy);
        assign_same_phase_energy(destination_chunk, destination_index, destination_energy + moved_energy);
        activate_thermal_world_cell(source, 0); activate_thermal_world_cell(destination, 0);
    }
    source_chunk.flags[source_index] |= 1u; destination_chunk.flags[destination_index] |= 1u;
    ++result.transfers; result.mass_transferred += amount;
    if (primary_direction) ++result.downward; else ++result.lateral;
    if (is_gas_material(material)) {
        ++result.gas_transfers; result.gas_mass_transferred += amount;
        if (&source_chunk == &destination_chunk) ++result.gas_local_transfers;
        else ++result.gas_cross_chunk_transfers;
    }
    if (&source_chunk != &destination_chunk) ++result.border;
    return amount;
}

void NativeSandWorld::ensure_phase_energy_plane(Chunk &chunk) {
    if (chunk.phase_energy != nullptr) return;
    chunk.phase_energy = std::make_unique<std::array<uint16_t, CELLS_PER_CHUNK>>();
    chunk.phase_energy->fill(0);
}

int32_t NativeSandWorld::thermal_capacity(int32_t material, int32_t amount) const {
    if (material <= EMPTY || material >= static_cast<int32_t>(thermal_material_definitions().size()) || amount <= 0) return 0;
    const ThermalMaterialDefinition &definition = thermal_material_definitions()[material];
    return definition.amount_weighted ? std::max(1, (static_cast<int32_t>(definition.specific_heat) * amount + 254) / 255)
                                      : definition.specific_heat;
}

int64_t NativeSandWorld::phase_base_enthalpy(int32_t material, int32_t amount) {
    const auto &d = thermal_material_definitions();
    auto cap = [&](int32_t id) -> int64_t {
        return d[id].amount_weighted ? std::max(1, (static_cast<int32_t>(d[id].specific_heat) * amount + 254) / 255)
                                     : d[id].specific_heat;
    };
    if (material == WATER) return cap(ICE) * WATER_FREEZE + scaled_latent(LATENT_ICE, amount) - cap(WATER) * WATER_FREEZE;
    if (material == STEAM) return phase_base_enthalpy(WATER, amount) + cap(WATER) * WATER_BOIL +
                                  scaled_latent(LATENT_STEAM, amount) - cap(STEAM) * WATER_BOIL;
    if (material == MOLTEN_GLASS) return cap(GLASS) * GLASS_MELT + scaled_latent(LATENT_GLASS, amount) - cap(MOLTEN_GLASS) * GLASS_MELT;
    if (material == MOLTEN_IRON) return cap(IRON) * IRON_MELT + scaled_latent(LATENT_IRON, amount) - cap(MOLTEN_IRON) * IRON_MELT;
    return 0;
}

int64_t NativeSandWorld::cell_enthalpy(const Chunk &chunk, int32_t index) const {
    const int32_t material = chunk.material[index];
    const int32_t amount = material_amount_at(chunk, index);
    const int32_t capacity = thermal_capacity(material, amount);
    if (capacity == 0) return 0;
    int64_t result = phase_base_enthalpy(material, amount) + static_cast<int64_t>(capacity) * chunk.temperature[index];
    const int32_t progress = chunk.phase_energy == nullptr ? 0 : (*chunk.phase_energy)[index];
    if ((chunk.flags[index] & PHASE_COOLING) != 0) result -= progress;
    else result += progress;
    return result;
}

void NativeSandWorld::set_cell_enthalpy(Vector2i cell, int64_t enthalpy, int32_t preferred_material) {
    Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr) return;
    const int32_t index = local_index(world_to_local(cell));
    const int32_t old_material = chunk->material[index];
    const uint16_t old_temperature = chunk->temperature[index];
    if (old_material == EMPTY) return;
    const int32_t amount = material_amount_at(*chunk, index);
    const int32_t family = thermal_material_definitions()[old_material].family;
    int32_t material = old_material;
    int32_t temperature = chunk->temperature[index];
    int32_t progress = 0;
    uint8_t phase_flag = 0;

    auto decode_sensible = [&](int32_t id, int64_t base) {
        const int32_t capacity = thermal_capacity(id, amount);
        const int64_t local = std::max<int64_t>(0, enthalpy - base);
        temperature = static_cast<int32_t>(std::clamp<int64_t>(local / capacity, 0, TEMPERATURE_MAX));
        progress = static_cast<int32_t>(local - static_cast<int64_t>(temperature) * capacity);
        material = id;
    };
    auto decode_transition = [&](int32_t lower, int32_t upper, int32_t threshold, int64_t start, int32_t latent) {
        const bool keep_upper = preferred_material == upper || old_material == upper;
        temperature = threshold;
        if (keep_upper) { material = upper; progress = static_cast<int32_t>(start + latent - enthalpy); phase_flag = PHASE_COOLING; }
        else { material = lower; progress = static_cast<int32_t>(enthalpy - start); phase_flag = PHASE_HEATING; }
    };

    if (family == 1) {
        const int32_t lf = scaled_latent(LATENT_ICE, amount), lv = scaled_latent(LATENT_STEAM, amount);
        const int64_t melt0 = static_cast<int64_t>(thermal_capacity(ICE, amount)) * WATER_FREEZE;
        const int64_t melt1 = melt0 + lf;
        const int64_t boil0 = phase_base_enthalpy(WATER, amount) + static_cast<int64_t>(thermal_capacity(WATER, amount)) * WATER_BOIL;
        const int64_t boil1 = boil0 + lv;
        if (enthalpy < melt0) decode_sensible(ICE, 0);
        else if (enthalpy < melt1) decode_transition(ICE, WATER, WATER_FREEZE, melt0, lf);
        else if (enthalpy < boil0) decode_sensible(WATER, phase_base_enthalpy(WATER, amount));
        else if (enthalpy < boil1) decode_transition(WATER, STEAM, WATER_BOIL, boil0, lv);
        else decode_sensible(STEAM, phase_base_enthalpy(STEAM, amount));
    } else if (family == 2 || family == 3) {
        const int32_t lower = family == 2 ? GLASS : IRON;
        const int32_t upper = family == 2 ? MOLTEN_GLASS : MOLTEN_IRON;
        const int32_t threshold = family == 2 ? GLASS_MELT : IRON_MELT;
        const int32_t latent = scaled_latent(family == 2 ? LATENT_GLASS : LATENT_IRON, amount);
        const int64_t start = static_cast<int64_t>(thermal_capacity(lower, amount)) * threshold;
        if (enthalpy < start) decode_sensible(lower, 0);
        else if (enthalpy < start + latent) decode_transition(lower, upper, threshold, start, latent);
        else decode_sensible(upper, phase_base_enthalpy(upper, amount));
    } else {
        decode_sensible(old_material, phase_base_enthalpy(old_material, amount));
    }

    progress = std::clamp(progress, 0, 65535);
    const bool material_changed = material != old_material;
    chunk->material[index] = static_cast<uint16_t>(material);
    chunk->temperature[index] = static_cast<uint16_t>(temperature);
    chunk->flags[index] = static_cast<uint8_t>((chunk->flags[index] & ~PHASE_MASK) | phase_flag);
    if (progress > 0) ensure_phase_energy_plane(*chunk);
    if (chunk->phase_energy != nullptr) (*chunk->phase_energy)[index] = static_cast<uint16_t>(progress);
    if (material_changed) {
        ++last_phase_changes_; ++total_phase_changes_;
        record_production_event(old_material, amount, false);
        record_production_event(material, amount, true);
        if (material == STEAM) ++total_steam_generated_;
        if (old_material == STEAM && material == WATER) ++total_steam_condensed_;
        if (is_mobile_material(material)) activate_fluid_world_cell(cell, 0);
        std::lock_guard<std::mutex> lock(thermal_notification_mutex_);
        notify_automation_cell_change(cell);
    }
    if (!material_changed && old_temperature != chunk->temperature[index] && !automation_cell_watchers_.empty()) {
        std::lock_guard<std::mutex> lock(thermal_notification_mutex_);
        notify_automation_cell_change(cell);
    }
    ++chunk->revision;
    chunk->pristine = false;
    if (material_changed || material == MOLTEN_GLASS || material == MOLTEN_IRON || material == STEAM || old_material == STEAM) {
        const Vector2i local = world_to_local(cell);
        chunk->render_dirty.include(local.x, local.y);
    }
}

void NativeSandWorld::add_cell_energy(Vector2i cell, int64_t energy) {
    Chunk *chunk = get_chunk(world_to_chunk(cell));
    if (chunk == nullptr) return;
    const int32_t index = local_index(world_to_local(cell));
    if (chunk->material[index] == EMPTY) return;
    const int64_t before = cell_enthalpy(*chunk, index);
    const int64_t target = std::max<int64_t>(0, before + energy);
    set_cell_enthalpy(cell, target, chunk->material[index]);
    thermal_rounding_reservoir_ += target - cell_enthalpy(*chunk, index);
    activate_thermal_world_cell(cell, 1);
    if (is_combustible_material(chunk->material[index])) activate_reactive_cell(cell);
}

void NativeSandWorld::activate_thermal_world_cell(Vector2i world_cell, int32_t radius) {
    if (radius < 0) return;
    const int64_t minimum_y = std::max<int64_t>(INT32_MIN, static_cast<int64_t>(world_cell.y) - radius);
    const int64_t maximum_y = std::min<int64_t>(INT32_MAX, static_cast<int64_t>(world_cell.y) + radius);
    const int64_t minimum_x = std::max<int64_t>(INT32_MIN, static_cast<int64_t>(world_cell.x) - radius);
    const int64_t maximum_x = std::min<int64_t>(INT32_MAX, static_cast<int64_t>(world_cell.x) + radius);
    for (int64_t y = minimum_y; y <= maximum_y; ++y) for (int64_t x = minimum_x; x <= maximum_x; ++x) {
        const Vector2i cell{static_cast<int32_t>(x), static_cast<int32_t>(y)};
        Chunk *chunk = get_chunk(world_to_chunk(cell));
        if (chunk == nullptr) continue;
        const Vector2i local = world_to_local(cell);
        chunk->thermal_active.include(local.x, local.y);
        chunk->thermal_quiet_ticks = 0;
    }
}

void NativeSandWorld::include_next_thermal_world_cell(Vector2i world_cell, int32_t radius) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return;
    const Vector2i local = world_to_local(world_cell);
    chunk->thermal_next_active.include(local.x, local.y, radius);
}

void NativeSandWorld::compute_thermal_chunk(Chunk &chunk, const FluidActivity &activity, ThermalJobResult &result) {
    if (chunk.thermal_right_transfer == nullptr) {
        chunk.thermal_right_transfer = std::make_unique<std::array<int32_t, CELLS_PER_CHUNK>>();
        chunk.thermal_down_transfer = std::make_unique<std::array<int32_t, CELLS_PER_CHUNK>>();
        chunk.thermal_right_transfer->fill(0); chunk.thermal_down_transfer->fill(0);
    }
    chunk.thermal_right_transfer->fill(0);
    chunk.thermal_down_transfer->fill(0);
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t y = 0; y < CHUNK_SIZE; ++y) {
        if ((activity.rows & (uint64_t{1} << y)) == 0) continue;
        for (int32_t x = activity.min_x[y]; x <= activity.max_x[y]; ++x) {
            const int32_t index = y * CHUNK_SIZE + x;
            const int32_t material_a = chunk.material[index];
            (*chunk.thermal_right_transfer)[index] = 0;
            (*chunk.thermal_down_transfer)[index] = 0;
            if (material_a == EMPTY) continue;
            ++result.visited;
            const Vector2i a = origin + Vector2i(x, y);
            const std::array<Vector2i, 2> offsets{{Vector2i(1, 0), Vector2i(0, 1)}};
            for (int32_t edge = 0; edge < 2; ++edge) {
                const Vector2i offset = offsets[edge];
                const Vector2i b = a + offset;
                const bool same_chunk = (edge == 0 && x + 1 < CHUNK_SIZE) || (edge == 1 && y + 1 < CHUNK_SIZE);
                const Chunk *other = same_chunk ? &chunk : get_chunk(world_to_chunk(b));
                if (other == nullptr) continue;
                const int32_t other_index = same_chunk ? index + (edge == 0 ? 1 : CHUNK_SIZE) : local_index(world_to_local(b));
                const int32_t material_b = other->material[other_index];
                if (material_b == EMPTY) continue;
                const auto &definitions = thermal_material_definitions();
                const int32_t conductivity = std::min(definitions[material_a].conductivity, definitions[material_b].conductivity);
                const int32_t delta = static_cast<int32_t>(chunk.temperature[index]) - other->temperature[other_index];
                if (conductivity == 0 || std::abs(delta) < 2) continue;
                const int32_t cap_a = thermal_capacity(material_a, material_amount_at(chunk, index));
                const int32_t cap_b = thermal_capacity(material_b, material_amount_at(*other, other_index));
                const int64_t equilibrium = static_cast<int64_t>(std::abs(delta)) * cap_a * cap_b / std::max(1, cap_a + cap_b);
                const int64_t rate = static_cast<int64_t>(std::abs(delta)) * std::min(cap_a, cap_b) * conductivity * 2 / 65536;
                const int64_t magnitude = std::min<int64_t>(equilibrium / 2, std::max<int64_t>(1, rate));
                const int64_t transfer = delta > 0 ? magnitude : -magnitude;
                if (edge == 0) (*chunk.thermal_right_transfer)[index] = static_cast<int32_t>(transfer);
                else (*chunk.thermal_down_transfer)[index] = static_cast<int32_t>(transfer);
                ++result.exchanges; result.energy_moved += std::abs(transfer);
            }
        }
    }
}

void NativeSandWorld::commit_thermal_chunk(Chunk &chunk, const FluidActivity &activity, ThermalJobResult &result) {
    const Vector2i origin = chunk.coordinate * CHUNK_SIZE;
    for (int32_t y = 0; y < CHUNK_SIZE; ++y) {
        if ((activity.rows & (uint64_t{1} << y)) == 0) continue;
        for (int32_t x = activity.min_x[y]; x <= activity.max_x[y]; ++x) {
            const int32_t index = y * CHUNK_SIZE + x;
            if (chunk.material[index] == EMPTY) continue;
            int64_t delta_energy = -static_cast<int64_t>((*chunk.thermal_right_transfer)[index]) - (*chunk.thermal_down_transfer)[index];
            const Vector2i cell = origin + Vector2i(x, y);
            const Vector2i left = cell + Vector2i(-1, 0), up = cell + Vector2i(0, -1);
            const Chunk *left_chunk = x > 0 ? &chunk : get_chunk(world_to_chunk(left));
            const Chunk *up_chunk = y > 0 ? &chunk : get_chunk(world_to_chunk(up));
            if (left_chunk != nullptr && left_chunk->thermal_right_transfer != nullptr)
                delta_energy += (*left_chunk->thermal_right_transfer)[x > 0 ? index - 1 : local_index(world_to_local(left))];
            if (up_chunk != nullptr && up_chunk->thermal_down_transfer != nullptr)
                delta_energy += (*up_chunk->thermal_down_transfer)[y > 0 ? index - CHUNK_SIZE : local_index(world_to_local(up))];
            if (delta_energy == 0) continue;
            const int32_t old_material = chunk.material[index];
            const int64_t before_energy = cell_enthalpy(chunk, index);
            const int64_t target_energy = std::max<int64_t>(0, before_energy + delta_energy);
            if (thermal_material_definitions()[old_material].family == 0) {
                const int32_t capacity = thermal_capacity(old_material, material_amount_at(chunk, index));
                const int32_t stored_remainder = chunk.phase_energy == nullptr ? 0 : (*chunk.phase_energy)[index];
                const int64_t energy = std::max<int64_t>(0, static_cast<int64_t>(capacity) * chunk.temperature[index] + stored_remainder + delta_energy);
                const uint16_t next_temperature = static_cast<uint16_t>(std::clamp<int64_t>(energy / capacity, 0, TEMPERATURE_MAX));
                const uint16_t remainder = static_cast<uint16_t>(energy - static_cast<int64_t>(next_temperature) * capacity);
                chunk.temperature[index] = next_temperature;
                chunk.flags[index] &= static_cast<uint8_t>(~PHASE_MASK);
                if (remainder > 0 && chunk.phase_energy == nullptr) ensure_phase_energy_plane(chunk);
                if (chunk.phase_energy != nullptr) (*chunk.phase_energy)[index] = remainder;
                ++chunk.revision; chunk.pristine = false;
            } else {
                set_cell_enthalpy(cell, target_energy, old_material);
                if (chunk.material[index] != old_material) ++result.phase_changes;
            }
            result.enthalpy_rounding += target_energy - cell_enthalpy(chunk, index);
            if (is_combustible_material(chunk.material[index])) activate_reactive_cell(cell);
        }
    }
}

bool NativeSandWorld::set_thermal_switch_open(Vector2i world_cell, bool open) {
    const uint64_t key = cell_key(world_cell);
    if (!thermal_switch_cells_.contains(key)) return false;
    if (open) closed_thermal_switches_.erase(key); else closed_thermal_switches_.insert(key);
    activate_thermal_world_cell(world_cell + Vector2i(-1, 0), 1);
    activate_thermal_world_cell(world_cell + Vector2i(1, 0), 1);
    notify_automation_cell_change(world_cell);
    return true;
}

void NativeSandWorld::process_thermal_structures() {
    auto transfer_between = [&](Vector2i a, Vector2i b, int32_t coefficient) {
        Chunk *ca = get_chunk(world_to_chunk(a)); Chunk *cb = get_chunk(world_to_chunk(b));
        if (ca == nullptr || cb == nullptr) return;
        const int32_t ia = local_index(world_to_local(a)), ib = local_index(world_to_local(b));
        if (ca->material[ia] == EMPTY || cb->material[ib] == EMPTY) return;
        const int32_t delta = static_cast<int32_t>(ca->temperature[ia]) - cb->temperature[ib];
        if (std::abs(delta) < 2) return;
        const int64_t transfer = std::max<int64_t>(1, static_cast<int64_t>(std::abs(delta)) * coefficient);
        const int64_t signed_transfer = delta > 0 ? transfer : -transfer;
        const int64_t ea = cell_enthalpy(*ca, ia), eb = cell_enthalpy(*cb, ib);
        set_cell_enthalpy(a, ea - signed_transfer, ca->material[ia]);
        set_cell_enthalpy(b, eb + signed_transfer, cb->material[ib]);
        thermal_rounding_reservoir_ += ea + eb - cell_enthalpy(*ca, ia) - cell_enthalpy(*cb, ib);
        activate_thermal_world_cell(a, 1); activate_thermal_world_cell(b, 1);
        ++last_thermal_exchanges_; last_thermal_energy_moved_ += transfer;
    };
    std::vector<uint64_t> switches;
    for (uint64_t key : thermal_switch_cells_) if (!closed_thermal_switches_.contains(key)) switches.push_back(key);
    std::sort(switches.begin(), switches.end());
    for (uint64_t key : switches) {
        const Vector2i center = cell_from_key(key);
        transfer_between(center + Vector2i(-1, 0), center + Vector2i(1, 0), 3);
    }
    std::vector<uint64_t> exchanger_ids;
    for (const auto &[id, machine] : machine_entities_) if (machine.type_id == 25) exchanger_ids.push_back(id);
    std::sort(exchanger_ids.begin(), exchanger_ids.end());
    for (uint64_t id : exchanger_ids) {
        const MachineEntity &machine = machine_entities_.at(id);
        transfer_between(machine.origin + Vector2i(-1, 1), machine.origin + Vector2i(3, 1), 12);
    }
    std::vector<uint64_t> component_keys(thermal_component_cells_.begin(), thermal_component_cells_.end());
    std::sort(component_keys.begin(), component_keys.end());
    for (const uint64_t key : component_keys) {
        const Vector2i wall = cell_from_key(key);
        const int32_t type_id = get_structure(wall);
        if (type_id < 37 || type_id > 44) continue;
        const StructurePhysicalProperties &properties = structure_physical_properties(type_id);
        const int32_t coefficient = std::max(1, properties.conductivity / 16);
        transfer_between(wall + Vector2i(-1, 0), wall + Vector2i(1, 0), coefficient);
        transfer_between(wall + Vector2i(0, -1), wall + Vector2i(0, 1), coefficient);
    }
    std::vector<uint64_t> vessel_ids;
    for (const auto &[id, machine] : machine_entities_) if (machine.type_id == 35 || machine.type_id == 36) vessel_ids.push_back(id);
    std::sort(vessel_ids.begin(), vessel_ids.end());
    for (const uint64_t id : vessel_ids) {
        const MachineEntity &vessel = machine_entities_.at(id);
        const int32_t transfer_coefficient = vessel.type_id == 35 ? 16 : 2;
        // Generic open-vessel bridge: the configured Iron wall conductivity couples the
        // outside floor face to ordinary matter in the cavity. Contents remain world cells.
        for (int32_t x = 1; x < 8; ++x)
            transfer_between(vessel.origin + Vector2i(x, 6), vessel.origin + Vector2i(x, 4), transfer_coefficient);
    }
}

void NativeSandWorld::process_thermodynamics() {
    last_thermal_active_ = 0; last_thermal_visited_ = 0; last_thermal_exchanges_ = 0; last_thermal_energy_moved_ = 0;
    last_phase_changes_ = 0; last_thermal_barrier_usec_ = 0;
    last_thermal_workers_used_ = 0;
    if ((tick_index_ & 1) != 0) { last_thermal_usec_ = 0; return; }
    const auto started = std::chrono::steady_clock::now();
    process_thermal_structures();
    const std::vector<Chunk *> chunks = sorted_chunks();
    for (Chunk *chunk : chunks) chunk->thermal_next_active.clear();
    for (Chunk *source : chunks) {
        if (!source->thermal_active.valid()) continue;
        const Vector2i origin = source->coordinate * CHUNK_SIZE;
        for (int32_t y = 0; y < CHUNK_SIZE; ++y) {
            if ((source->thermal_active.rows & (uint64_t{1} << y)) == 0) continue;
            for (int32_t dy = -1; dy <= 1; ++dy) {
                const int32_t world_y = origin.y + y + dy;
                int32_t world_x = origin.x + source->thermal_active.min_x[y] - 1;
                const int32_t end_x = origin.x + source->thermal_active.max_x[y] + 1;
                while (world_x <= end_x) {
                    Chunk *target = get_chunk(world_to_chunk({world_x, world_y}));
                    if (target == nullptr) {
                        world_x = (floor_div(world_x, CHUNK_SIZE) + 1) * CHUNK_SIZE;
                        continue;
                    }
                    const Vector2i local = world_to_local({world_x, world_y});
                    const int32_t run_end = std::min(end_x, world_x + CHUNK_SIZE - local.x - 1);
                    target->thermal_next_active.include(local.x, local.y);
                    target->thermal_next_active.include(world_to_local({run_end, world_y}).x, local.y);
                    world_x = run_end + 1;
                }
            }
        }
    }
    std::vector<Chunk *> active;
    std::vector<FluidActivity> spans;
    for (Chunk *chunk : chunks) if (chunk->thermal_next_active.valid()) {
        active.push_back(chunk);
        spans.push_back(chunk->thermal_next_active);
        last_thermal_active_ += chunk->thermal_next_active.area();
        chunk->thermal_next_active.clear();
    }
    std::vector<ThermalJobResult> compute_results(active.size());
    simulation_executor_->run(static_cast<int32_t>(active.size()), [&](int32_t job, int32_t) { compute_thermal_chunk(*active[job], spans[job], compute_results[job]); });
    last_thermal_barrier_usec_ += static_cast<int64_t>(simulation_executor_->wait_ns_last_run() / 1000);
    last_thermal_workers_used_ = simulation_executor_->workers_used_last_run();
    std::vector<ThermalJobResult> commit_results(active.size());
    simulation_executor_->run(static_cast<int32_t>(active.size()), [&](int32_t job, int32_t) { commit_thermal_chunk(*active[job], spans[job], commit_results[job]); });
    last_thermal_barrier_usec_ += static_cast<int64_t>(simulation_executor_->wait_ns_last_run() / 1000);
    last_thermal_workers_used_ = std::max(last_thermal_workers_used_, simulation_executor_->workers_used_last_run());
    for (const ThermalJobResult &result : compute_results) {
        last_thermal_visited_ += result.visited; last_thermal_exchanges_ += result.exchanges; last_thermal_energy_moved_ += result.energy_moved;
    }
    for (const ThermalJobResult &result : commit_results) thermal_rounding_reservoir_ += result.enthalpy_rounding;
    for (size_t index = 0; index < active.size(); ++index)
        if (compute_results[index].exchanges > 0) active[index]->thermal_next_active.merge(spans[index]);
    for (Chunk *chunk : active) {
        chunk->thermal_active = chunk->thermal_next_active;
        chunk->thermal_next_active.clear();
        if (chunk->thermal_active.valid()) chunk->thermal_quiet_ticks = 0; else ++chunk->thermal_quiet_ticks;
        if (!chunk->thermal_active.valid()) { chunk->thermal_right_transfer.reset(); chunk->thermal_down_transfer.reset(); }
    }
    for (Chunk *chunk : sorted_chunks()) if (chunk->thermal_next_active.valid()) {
        chunk->thermal_active.merge(chunk->thermal_next_active);
        chunk->thermal_next_active.clear();
    }
    release_redundant_phase_planes();
    last_thermal_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::release_redundant_phase_planes() {
    for (Chunk *chunk : sorted_chunks()) {
        if (chunk->phase_energy == nullptr || chunk->thermal_active.valid() || chunk->thermal_quiet_ticks < 120) continue;
        bool empty = true;
        for (uint16_t value : *chunk->phase_energy) if (value != 0) { empty = false; break; }
        if (empty) chunk->phase_energy.reset();
    }
}

int32_t NativeSandWorld::get_material_amount(Vector2i world_cell) const { return material_amount_at(world_cell); }

int32_t NativeSandWorld::get_phase_energy(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr || chunk->phase_energy == nullptr) return 0;
    return (*chunk->phase_energy)[local_index(world_to_local(world_cell))];
}

int32_t NativeSandWorld::set_material_state(Vector2i world_cell, int32_t material_id, int32_t amount, int32_t temperature,
                                             int32_t provenance, int32_t mineral_signature) {
    if (material_id < 0 || material_id >= static_cast<int32_t>(thermal_material_definitions().size()) || amount < 0 || amount > 255 ||
        temperature < 0 || temperature > TEMPERATURE_MAX || provenance < 0 || provenance > 65535 || mineral_signature < 0 || mineral_signature > 65535 ||
        !has_neighbor_margin(world_cell, 1) || (world_generation_enabled_ && !is_inside_virtual_world(world_cell)))
        return 31;
    Chunk *chunk = get_or_create_chunk(world_to_chunk(world_cell));
    const Vector2i local = world_to_local(world_cell);
    const int32_t index = local_index(local);
    const int32_t old_material = chunk->material[index];
    const int32_t old_amount = material_amount_at(*chunk, index);
    if (amount == 0) material_id = EMPTY;
    if (amount > 0 && amount < 255) ensure_liquid_plane(*chunk);
    if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = static_cast<uint8_t>(amount);
    chunk->material[index] = static_cast<uint16_t>(material_id);
    chunk->temperature[index] = material_id == EMPTY ? TEMPERATURE_AMBIENT : static_cast<uint16_t>(temperature);
    chunk->provenance[index] = static_cast<uint16_t>(provenance);
    chunk->mineral_signature[index] = static_cast<uint16_t>(mineral_signature);
    chunk->flags[index] &= static_cast<uint8_t>(~PHASE_MASK);
    if (chunk->phase_energy != nullptr) (*chunk->phase_energy)[index] = 0;
    if (old_material != material_id &&
        (chunk->organic_moisture != nullptr || chunk->reaction_progress != nullptr || chunk->reaction_state != nullptr ||
         is_combustible_material(old_material) || is_combustible_material(material_id))) {
        chunk->flags[index] = 0;
        if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
        if (chunk->reaction_progress != nullptr) (*chunk->reaction_progress)[index] = 0;
        if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = 0;
        if (is_combustible_material(old_material) || is_combustible_material(material_id)) reactive_cells_.erase(cell_key(world_cell));
    }
    ++chunk->revision; chunk->pristine = false; chunk->render_dirty.include(local.x, local.y, 1);
    if (material_id != EMPTY) {
        const int64_t initial_enthalpy = phase_base_enthalpy(material_id, amount) +
            static_cast<int64_t>(thermal_capacity(material_id, amount)) * temperature;
        set_cell_enthalpy(world_cell, initial_enthalpy, material_id);
        material_id = chunk->material[index];
    }
    if (is_mobile_material(material_id)) activate_fluid_world_cell(world_cell, 1);
    activate_thermal_world_cell(world_cell, 1);
    if (is_combustible_material(material_id)) activate_reactive_cell(world_cell);
    if (old_material != material_id || old_amount != amount) {
        for (const Vector2i offset : std::array<Vector2i, 4>{{{0,-1},{-1,0},{1,0},{0,1}}})
            activate_reactive_cell(world_cell + offset);
    }
    return 0;
}

int64_t NativeSandWorld::fill_rect_state(Rect2i area, int32_t material_id, int32_t amount, int32_t temperature) {
    Vector2i end;
    if (material_id < 0 || material_id >= static_cast<int32_t>(thermal_material_definitions().size()) || amount < 0 || amount > 255 ||
        temperature < 0 || temperature > TEMPERATURE_MAX || !checked_rect_end(area, 16'777'216, end)) return -1;
    int64_t written = 0;
    for (int32_t y = area.position.y; y < end.y; ++y) for (int32_t x = area.position.x; x < end.x; ++x) {
        if (set_material_state({x, y}, material_id, amount, temperature) == 0) ++written;
    }
    return written;
}

int64_t NativeSandWorld::fill_pattern_state(Rect2i area, int32_t material_id, int32_t amount_a, int32_t amount_b,
                                             int32_t temperature_a, int32_t temperature_b) {
    Vector2i end;
    if (material_id <= EMPTY || material_id >= static_cast<int32_t>(thermal_material_definitions().size()) ||
        amount_a < 1 || amount_a > 255 || amount_b < 1 || amount_b > 255 ||
        temperature_a < 0 || temperature_a > TEMPERATURE_MAX || temperature_b < 0 || temperature_b > TEMPERATURE_MAX ||
        !checked_rect_end(area, 16'777'216, end)) return -1;
    int64_t written = 0;
    for (int32_t y = area.position.y; y < end.y; ++y) for (int32_t x = area.position.x; x < end.x; ++x) {
        Chunk *chunk = get_or_create_chunk(world_to_chunk({x, y}));
        const Vector2i local = world_to_local({x, y});
        const int32_t index = local_index(local);
        const bool alternate = ((x ^ y) & 1) != 0;
        const int32_t amount = alternate ? amount_b : amount_a;
        const int32_t temperature = alternate ? temperature_b : temperature_a;
        if (amount < 255) ensure_liquid_plane(*chunk);
        if (chunk->material_amount != nullptr) (*chunk->material_amount)[index] = static_cast<uint8_t>(amount);
        chunk->material[index] = static_cast<uint16_t>(material_id);
        chunk->temperature[index] = static_cast<uint16_t>(temperature);
        chunk->flags[index] = 0;
        chunk->provenance[index] = 0; chunk->mineral_signature[index] = 0;
        chunk->render_dirty.include(local.x, local.y);
        ++written;
    }
    for (Chunk *chunk : sorted_chunks()) {
        for (int32_t row = 0; row < CHUNK_SIZE; ++row) {
            chunk->thermal_active.include(0, row); chunk->thermal_active.include(CHUNK_SIZE - 1, row);
            if (is_mobile_material(material_id)) { chunk->fluid_active.include(0, row); chunk->fluid_active.include(CHUNK_SIZE - 1, row); }
        }
        ++chunk->revision; chunk->pristine = false;
    }
    return written;
}

int64_t NativeSandWorld::get_total_phase_family_mass(int32_t family_id) const {
    int64_t total = 0;
    for (const Chunk *chunk : sorted_chunks()) for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index)
        if (thermal_material_definitions()[chunk->material[index]].family == family_id) total += material_amount_at(*chunk, index);
    return total;
}

int64_t NativeSandWorld::get_total_thermal_enthalpy() const {
    int64_t total = thermal_rounding_reservoir_;
    for (const Chunk *chunk : sorted_chunks()) for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) total += cell_enthalpy(*chunk, index);
    for (const auto &[key, pipe] : pipe_segments_) if (pipe.mass > 0) total += pipe_enthalpy(key, pipe);
    return total;
}

Dictionary NativeSandWorld::get_material_thermal_definition(int32_t material_id) const {
    Dictionary result;
    if (material_id < 0 || material_id >= static_cast<int32_t>(thermal_material_definitions().size())) return result;
    const ThermalMaterialDefinition &d = thermal_material_definitions()[material_id];
    result["material_id"] = material_id; result["conductivity"] = d.conductivity; result["specific_heat"] = d.specific_heat;
    result["density"] = d.density; result["transition_low"] = d.transition_low; result["transition_high"] = d.transition_high;
    result["latent_low"] = d.latent_low; result["latent_high"] = d.latent_high; result["lower_phase"] = d.lower_phase;
    result["upper_phase"] = d.upper_phase; result["family"] = d.family; result["phase"] = static_cast<int32_t>(d.phase);
    result["mobility"] = d.mobility; result["amount_weighted"] = d.amount_weighted; result["pipe_compatible"] = d.pipe_compatible;
    return result;
}

Dictionary NativeSandWorld::get_thermal_statistics() const {
    Dictionary r;
    int64_t active_chunks = 0, activity_bytes = 0, phase_chunks = 0, scratch_chunks = 0;
    for (const Chunk *chunk : sorted_chunks()) { active_chunks += chunk->thermal_active.valid(); activity_bytes += sizeof(FluidActivity) * 2; phase_chunks += chunk->phase_energy != nullptr; scratch_chunks += chunk->thermal_right_transfer != nullptr; }
    r["cadence_hz"] = 30; r["active_cells"] = last_thermal_active_; r["visited_cells"] = last_thermal_visited_.load();
    r["exchanges"] = last_thermal_exchanges_.load(); r["energy_moved"] = last_thermal_energy_moved_.load(); r["source_energy"] = last_thermal_source_energy_;
    r["phase_changes"] = last_phase_changes_.load(); r["phase_changes_total"] = total_phase_changes_.load(); r["thermal_usec"] = last_thermal_usec_;
    r["barrier_usec"] = last_thermal_barrier_usec_; r["workers_used"] = last_thermal_workers_used_; r["active_chunks"] = active_chunks;
    r["activity_bytes"] = activity_bytes; r["phase_energy_plane_chunks"] = phase_chunks; r["phase_energy_backing_bytes"] = phase_chunks * CELLS_PER_CHUNK * 2;
    r["scratch_chunks"] = scratch_chunks; r["scratch_bytes"] = scratch_chunks * CELLS_PER_CHUNK * 2 * static_cast<int64_t>(sizeof(int32_t));
    r["rounding_reservoir"] = thermal_rounding_reservoir_;
    return r;
}

Dictionary NativeSandWorld::get_gas_statistics() const {
    Dictionary r;
    r["active_cells"] = last_gas_active_; r["visited_cells"] = last_gas_visited_; r["transfers"] = last_gas_transfers_;
    r["mass_transferred"] = last_gas_mass_transferred_; r["gas_usec"] = last_gas_usec_; r["steam_generated"] = total_steam_generated_.load();
    r["steam_condensed"] = total_steam_condensed_.load();
    r["vertical_attempts"] = last_gas_vertical_attempts_;
    r["diagonal_attempts"] = last_gas_diagonal_attempts_;
    r["lateral_attempts"] = last_gas_lateral_attempts_;
    r["local_transfers"] = last_gas_local_transfers_;
    r["cross_chunk_transfers"] = last_gas_cross_chunk_transfers_;
    return r;
}

Dictionary NativeSandWorld::get_phase9_architecture() const {
    Dictionary r;
    r["temperature_storage"] = "uint16 quarter-kelvin"; r["amount_storage"] = "lazy uint8[4096] per chunk";
    r["phase_energy_storage"] = "lazy uint16[4096] per chunk"; r["thermal_cadence_hz"] = 30;
    r["scheduler"] = "shared persistent worker pool, deterministic 3x3 chunk colors"; r["authoritative_math"] = "fixed-width integer";
    r["vertical_attempts"] = last_gas_vertical_attempts_;
    r["diagonal_attempts"] = last_gas_diagonal_attempts_;
    r["lateral_attempts"] = last_gas_lateral_attempts_;
    r["local_transfers"] = last_gas_local_transfers_;
    r["cross_chunk_transfers"] = last_gas_cross_chunk_transfers_;
    r["pressure_model"] = "local gameplay approximation, not an ideal-gas equation of state"; return r;
}
} // namespace godot
