#include "native_sand_world.hpp"
#include "physical_traits.hpp"

#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>

namespace godot {
namespace {
constexpr int32_t EMPTY_ID = 0;
constexpr int32_t SAND_ID = 2;
constexpr int32_t FINE_SAND_ID = 6;
constexpr int32_t HEAVY_CONCENTRATE_ID = 7;
constexpr int32_t IRON_CONCENTRATE_ID = 8;
constexpr int32_t IRON_ID = 11;
constexpr int32_t WATER_ID = 3;
constexpr int32_t COAL_CHUNK_ID = 14;
constexpr int32_t WOOD_ID = 21;
constexpr int32_t CHARCOAL_ID = 23;
constexpr int32_t STRUCTURE_SCREEN = 6;
constexpr int32_t STRUCTURE_OVERBELT_MAGNET = 7;
constexpr int32_t STRUCTURE_RADIANT_FURNACE = 5;
constexpr int32_t STRUCTURE_WASH_SLUICE = 17;
constexpr int32_t CONSTITUENT_IRON_BEARING = 1;
constexpr int32_t CONSTITUENT_HEAVY = 2;
}

bool NativeSandWorld::is_physical_processor(int32_t type_id) {
    return type_id == STRUCTURE_RADIANT_FURNACE || type_id == STRUCTURE_SCREEN || type_id == STRUCTURE_OVERBELT_MAGNET || type_id == STRUCTURE_WASH_SLUICE;
}

int32_t NativeSandWorld::grain_size_class(int32_t material_id, int32_t profile_id, uint16_t signature) const {
	if (!material_transportable(material_id)) return 2;
	return koalasand_core::grain_size_class(material_id, static_cast<uint16_t>(profile_id), signature);
}

int32_t NativeSandWorld::magnetic_susceptibility(int32_t material_id, int32_t profile_id, uint16_t signature) const {
	return koalasand_core::magnetic_susceptibility(material_id, static_cast<uint16_t>(profile_id), signature);
}

int32_t NativeSandWorld::get_grain_size_class(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return -1;
    const int32_t index = local_index(world_to_local(world_cell));
    return grain_size_class(chunk->material[index], chunk->provenance[index], chunk->mineral_signature[index]);
}

int32_t NativeSandWorld::get_magnetic_susceptibility(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return 0;
    const int32_t index = local_index(world_to_local(world_cell));
    return magnetic_susceptibility(chunk->material[index], chunk->provenance[index], chunk->mineral_signature[index]);
}

int32_t NativeSandWorld::get_temperature(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    return chunk == nullptr ? TEMPERATURE_AMBIENT : chunk->temperature[local_index(world_to_local(world_cell))];
}

void NativeSandWorld::register_physical_processor(const MachineEntity &entity) {
    if (!is_physical_processor(entity.type_id)) return;
    const int32_t normalized = ((entity.orientation % 4) + 4) % 4;
    PhysicalProcessor processor;
    processor.id = entity.id;
    processor.type_id = entity.type_id;
    processor.origin = entity.origin;
    processor.orientation = normalized;
    processor.transport_direction = normalized == 2 ? -1 : 1;
    if (entity.type_id == STRUCTURE_WASH_SLUICE) {
        processor.interaction_area = Rect2i(entity.origin + Vector2i(1, 1), Vector2i(16, 4));
        processor.transport_direction = normalized == 2 ? -1 : 1;
    } else if (entity.type_id == STRUCTURE_RADIANT_FURNACE) {
        processor.interaction_area = Rect2i(entity.origin + Vector2i(1, 1), Vector2i(8, 3));
        processor.field_strength = 2500;
    } else if (entity.type_id == STRUCTURE_SCREEN) {
        processor.interaction_area = Rect2i(entity.origin + Vector2i(1, 1), Vector2i(8, 3));
        processor.aperture = 0;
    } else {
        processor.interaction_area = Rect2i(entity.origin + Vector2i(-1, 1), Vector2i(14, 5));
        processor.field_strength = 1200;
    }
    physical_processors_[processor.id] = processor;
    const Vector2i first = world_to_chunk(processor.interaction_area.position - Vector2i(1, 1));
    const Vector2i last = world_to_chunk(processor.interaction_area.position + processor.interaction_area.size);
    for (int32_t cy = first.y; cy <= last.y; ++cy) {
        for (int32_t cx = first.x; cx <= last.x; ++cx) physical_chunk_watchers_[chunk_key({cx, cy})].push_back(processor.id);
    }
    if (physical_region_has_material(processor)) {
        if (entity.type_id == STRUCTURE_SCREEN) active_screens_.insert(entity.id);
        else if (entity.type_id == STRUCTURE_OVERBELT_MAGNET) active_magnets_.insert(entity.id);
        else if (entity.type_id == STRUCTURE_WASH_SLUICE) active_wet_sluices_.insert(entity.id);
        else active_heaters_.insert(entity.id);
    }
}

void NativeSandWorld::unregister_physical_processor(uint64_t entity_id) {
    physical_processors_.erase(entity_id);
    active_magnets_.erase(entity_id);
    active_screens_.erase(entity_id);
    active_heaters_.erase(entity_id);
    active_wet_sluices_.erase(entity_id);
    for (auto it = physical_chunk_watchers_.begin(); it != physical_chunk_watchers_.end();) {
        auto &ids = it->second;
        ids.erase(std::remove(ids.begin(), ids.end(), entity_id), ids.end());
        if (ids.empty()) it = physical_chunk_watchers_.erase(it); else ++it;
    }
}

void NativeSandWorld::activate_physical_near(Vector2i world_cell) {
    for (int32_t cy = -1; cy <= 1; ++cy) {
        for (int32_t cx = -1; cx <= 1; ++cx) {
            const auto found = physical_chunk_watchers_.find(chunk_key(world_to_chunk(world_cell) + Vector2i(cx, cy)));
            if (found == physical_chunk_watchers_.end()) continue;
            for (const uint64_t id : found->second) {
                const auto processor = physical_processors_.find(id);
                if (processor == physical_processors_.end()) continue;
                if (processor->second.type_id == STRUCTURE_SCREEN) active_screens_.insert(id);
                else if (processor->second.type_id == STRUCTURE_OVERBELT_MAGNET) active_magnets_.insert(id);
                else if (processor->second.type_id == STRUCTURE_WASH_SLUICE) active_wet_sluices_.insert(id);
                else active_heaters_.insert(id);
            }
        }
    }
}

bool NativeSandWorld::physical_region_has_material(const PhysicalProcessor &processor) const {
    const Rect2i area = processor.interaction_area.grow(1);
    const Vector2i end = area.position + area.size;
    for (int32_t y = area.position.y; y < end.y; ++y) {
        for (int32_t x = area.position.x; x < end.x; ++x) if (get_cell({x, y}) > 0) return true;
    }
    return false;
}

bool NativeSandWorld::is_permeable_screen_cell(Vector2i world_cell) const {
    const auto found = physical_chunk_watchers_.find(chunk_key(world_to_chunk(world_cell)));
    if (found == physical_chunk_watchers_.end()) return false;
    for (const uint64_t id : found->second) {
        const auto processor = physical_processors_.find(id);
        if (processor == physical_processors_.end() || processor->second.type_id != STRUCTURE_SCREEN) continue;
        const PhysicalProcessor &screen = processor->second;
        if (screen.orientation != 0 && screen.orientation != 2) continue;
        if (world_cell.y == screen.origin.y + 3 && world_cell.x >= screen.origin.x && world_cell.x < screen.origin.x + 10) return true;
    }
    return false;
}

bool NativeSandWorld::magnetic_capture_supports(Vector2i world_cell) const {
    const auto found = physical_chunk_watchers_.find(chunk_key(world_to_chunk(world_cell)));
    if (found == physical_chunk_watchers_.end()) return false;
    for (const uint64_t id : found->second) {
        const auto processor = physical_processors_.find(id);
        if (processor == physical_processors_.end() || processor->second.type_id != STRUCTURE_OVERBELT_MAGNET) continue;
        const PhysicalProcessor &magnet = processor->second;
        if (!magnet.interaction_area.has_point(world_cell)) continue;
        const int32_t susceptibility = get_magnetic_susceptibility(world_cell);
        const int32_t distance = world_cell.y - magnet.interaction_area.position.y;
        const int32_t electric_bonus = 1000 * electric_satisfaction(STRUCTURE_OVERBELT_MAGNET, magnet.id, magnet.origin) / 1000;
        const int32_t local_strength = std::max(0, static_cast<int32_t>(magnet.field_strength) + electric_bonus - distance * 180);
        if (susceptibility + local_strength >= 1050) return true;
    }
    return false;
}

void NativeSandWorld::process_physical_fields() {
    const auto started = std::chrono::steady_clock::now();
    last_magnets_active_ = static_cast<int64_t>(active_magnets_.size());
    last_magnetic_cells_tested_ = last_magnetic_moves_ = 0;
    std::vector<uint64_t> ids(active_magnets_.begin(), active_magnets_.end());
    std::sort(ids.begin(), ids.end());
    std::unordered_set<uint64_t> next_active;
    for (const uint64_t id : ids) {
        const auto found = physical_processors_.find(id);
        if (found == physical_processors_.end()) continue;
        const PhysicalProcessor &magnet = found->second;
        const auto entity_found = machine_entities_.find(id);
        if (entity_found == machine_entities_.end()) continue;
        MachineEntity &entity = entity_found->second;
        const int32_t previous_state = entity.state;
        if (entity.control_connected && !entity.control_enabled) {
            entity.state = 10;
            if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            continue;
        }
        entity.state = 3;
        const Rect2i area = magnet.interaction_area;
        const int32_t top = area.position.y;
        const int32_t first_x = magnet.transport_direction > 0 ? area.position.x + area.size.x - 1 : area.position.x;
        const int32_t last_x = magnet.transport_direction > 0 ? area.position.x - 1 : area.position.x + area.size.x;
        for (int32_t x = first_x; x != last_x; x -= magnet.transport_direction) {
            const Vector2i source{x, top};
            if (!material_transportable(get_cell(source)) || moved_this_tick(source) || get_magnetic_susceptibility(source) <= 0) continue;
            ++last_magnetic_cells_tested_;
            if (move_if_empty(source, source + Vector2i(magnet.transport_direction, 0))) ++last_magnetic_moves_;
        }
        for (int32_t y = top + 1; y < area.position.y + area.size.y; ++y) {
            for (int32_t x = area.position.x; x < area.position.x + area.size.x; ++x) {
                const Vector2i source{x, y};
                if (!material_transportable(get_cell(source)) || moved_this_tick(source)) continue;
                ++last_magnetic_cells_tested_;
                const int32_t susceptibility = get_magnetic_susceptibility(source);
                const int32_t distance = y - top;
                const int32_t electric_bonus = 1000 * electric_satisfaction(STRUCTURE_OVERBELT_MAGNET, magnet.id, magnet.origin) / 1000;
                const int32_t local_strength = std::max(0, static_cast<int32_t>(magnet.field_strength) + electric_bonus - distance * 180);
                if (susceptibility + local_strength < 1050) continue;
                const Vector2i destination = source + Vector2i(0, -1);
                if (move_if_empty(source, destination)) {
                    Chunk *chunk = get_chunk(world_to_chunk(destination));
                    const int32_t index = local_index(world_to_local(destination));
                    if (chunk != nullptr && chunk->material[index] == HEAVY_CONCENTRATE_ID && susceptibility >= 800) chunk->material[index] = IRON_CONCENTRATE_ID;
                    ++last_magnetic_moves_;
                }
            }
        }
        if (physical_region_has_material(magnet)) next_active.insert(id); else entity.state = 1;
        if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
    }
    active_magnets_.swap(next_active);
    total_magnetic_moves_ += last_magnetic_moves_;
    last_magnets_active_ = static_cast<int64_t>(active_magnets_.size());
    last_magnetic_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::process_vibrating_screens() {
    const auto started = std::chrono::steady_clock::now();
    last_screens_active_ = static_cast<int64_t>(active_screens_.size());
    last_screen_grains_tested_ = last_screen_vibration_evaluations_ = 0;
    std::vector<uint64_t> ids(active_screens_.begin(), active_screens_.end());
    std::sort(ids.begin(), ids.end());
    std::unordered_set<uint64_t> next_active;
    for (const uint64_t id : ids) {
        const auto found = physical_processors_.find(id);
        if (found == physical_processors_.end()) continue;
        const PhysicalProcessor &screen = found->second;
        const auto entity_found = machine_entities_.find(id);
        if (entity_found == machine_entities_.end()) continue;
        MachineEntity &entity = entity_found->second;
        const int32_t previous_state = entity.state;
        if (entity.control_connected && !entity.control_enabled) {
            entity.state = 10;
            if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            continue;
        }
        entity.state = 3;
        const int32_t deck_y = screen.origin.y + 3;
        const int32_t direction = screen.transport_direction;
        const int32_t first_x = direction > 0 ? screen.origin.x + 8 : screen.origin.x + 1;
        const int32_t last_x = direction > 0 ? screen.origin.x : screen.origin.x + 9;
        for (int32_t x = first_x; x != last_x; x -= direction) {
            const Vector2i source{x, deck_y - 1};
            if (!material_transportable(get_cell(source)) || moved_this_tick(source)) continue;
            ++last_screen_grains_tested_;
            ++last_screen_vibration_evaluations_;
            const uint32_t impulse = hash_2d(seed_ ^ static_cast<int64_t>(id), source, static_cast<int32_t>(tick_index_));
            const int32_t powered_opportunity = 500 + electric_satisfaction(STRUCTURE_SCREEN, id, screen.origin) / 2;
            if (static_cast<int32_t>(impulse % 1000u) >= powered_opportunity) continue;
            const Vector2i destination = source + Vector2i(direction, 0);
            if (move_if_empty(source, destination) && !screen.interaction_area.has_point(destination)) {
                Chunk *chunk = get_chunk(world_to_chunk(destination));
                const int32_t index = local_index(world_to_local(destination));
                if (chunk != nullptr && chunk->material[index] == SAND_ID) chunk->material[index] = HEAVY_CONCENTRATE_ID;
            }
        }
        if (physical_region_has_material(screen)) next_active.insert(id); else entity.state = 1;
        if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
    }
    active_screens_.swap(next_active);
    last_screens_active_ = static_cast<int64_t>(active_screens_.size());
    last_screen_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::apply_heat_source(const NativeHeatSource &source) {
    if (!source.enabled) return;
    const Vector2i end = source.region.position + source.region.size;
    for (int32_t y = source.region.position.y; y < end.y; ++y) {
        for (int32_t x = source.region.position.x; x < end.x; ++x) {
            const Vector2i cell{x, y};
            Chunk *chunk = get_chunk(world_to_chunk(cell));
            if (chunk == nullptr) continue;
            const int32_t index = local_index(world_to_local(cell));
            const int32_t material = chunk->material[index];
            const int32_t distance = y - source.region.position.y;
            const int32_t heat = std::max(source.minimum_heat, source.heat_rate - distance * source.attenuation_per_row);
            if (is_pipe_structure(get_structure(cell))) {
                damage_pipe(cell, std::max(1, heat / 160), 3);
                auto pipe = pipe_segments_.find(cell_key(cell));
                if (pipe != pipe_segments_.end() && pipe->second.mass > 0) {
                    const int64_t before = pipe_enthalpy(pipe->first, pipe->second);
                    const int64_t energy = static_cast<int64_t>(heat) * pipe_heat_capacity(pipe->second);
                    const int32_t preferred_fluid = pipe->second.fluid_type;
                    set_pipe_enthalpy(pipe->first, pipe->second, before + energy, preferred_fluid);
                    thermal_rounding_reservoir_ += before + energy - pipe_enthalpy(pipe->first, pipe->second);
                    last_thermal_source_energy_ += energy;
                    total_thermal_source_energy_ += energy;
                    wake_pipe(cell);
                }
                continue;
            }
            if (source.target_mode == 1 && material == 0) continue;
            ++last_heated_cells_;
            const int64_t energy = static_cast<int64_t>(heat) * thermal_capacity(material, material_amount_at(*chunk, index));
            add_cell_energy(cell, energy);
            last_thermal_source_energy_ += energy;
            total_thermal_source_energy_ += energy;
            if (chunk->temperature[index] < TEMPERATURE_REACTION || !(material == SAND_ID || (material >= FINE_SAND_ID && material <= 9))) continue;
            const int32_t process_id = 301 + material;
            const int32_t result = processing_result(material, chunk->provenance[index], chunk->mineral_signature[index], process_id);
            if (result == material) continue;
            chunk->material[index] = static_cast<uint16_t>(result);
            ++chunk->revision;
            chunk->pristine = false;
            mark_render_world_cell(cell);
            notify_automation_cell_change(cell);
            ++last_heat_reactions_;
            ++total_heat_reactions_;
            ++total_furnace_processed_;
            if (result == 10) ++total_glass_;
            else if (result == 11) ++total_iron_;
            else if (result == 12) ++total_gold_;
            else ++total_residue_;
        }
    }
}

void NativeSandWorld::process_physical_heaters() {
    const auto started = std::chrono::steady_clock::now();
    last_heaters_active_ = static_cast<int64_t>(active_heaters_.size());
    last_heated_cells_ = last_heat_reactions_ = 0;
    std::vector<uint64_t> ids(active_heaters_.begin(), active_heaters_.end());
    std::sort(ids.begin(), ids.end());
    std::unordered_set<uint64_t> next_active;
    for (const uint64_t id : ids) {
        const auto found = physical_processors_.find(id);
        if (found == physical_processors_.end()) continue;
        const PhysicalProcessor &heater = found->second;
        // A processor id without a machine behind it means the two registries disagree.
        // Skipping the entity keeps the tick honest; aborting the process does not.
        const auto entity_found = machine_entities_.find(id);
        if (entity_found == machine_entities_.end()) continue;
        MachineEntity &entity = entity_found->second;
        const int32_t previous_state = entity.state;
        if (entity.control_connected && !entity.control_enabled) {
            entity.state = 10;
            if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            continue;
        }
        int64_t transferred_energy = 0;
        bool has_physical_fuel = false;
        const Vector2i bay_end = heater.interaction_area.position + heater.interaction_area.size;
        for (int32_t fuel_y = heater.interaction_area.position.y; fuel_y < bay_end.y; ++fuel_y) {
        for (int32_t fuel_x = heater.interaction_area.position.x; fuel_x < bay_end.x; ++fuel_x) {
            const Vector2i fuel_cell{fuel_x, fuel_y};
            const int32_t fuel_material = get_cell(fuel_cell);
            if (fuel_material != COAL_CHUNK_ID && fuel_material != WOOD_ID && fuel_material != CHARCOAL_ID) continue;
            has_physical_fuel = true;
            activate_reactive_cell(fuel_cell);
            Chunk *fuel_chunk = get_chunk(world_to_chunk(fuel_cell));
            if (fuel_chunk == nullptr) continue;
            const int32_t fuel_index = local_index(world_to_local(fuel_cell));
            const int32_t ignition = organic_material_definitions()[fuel_material].ignition_temperature;
            if (fuel_chunk->temperature[fuel_index] < ignition) continue;
            for (int32_t target_y = heater.interaction_area.position.y; target_y < bay_end.y; ++target_y) {
            for (int32_t target_x = heater.interaction_area.position.x; target_x < bay_end.x; ++target_x) {
                const Vector2i target{target_x, target_y};
                if (target == fuel_cell) continue;
                Chunk *target_chunk = get_chunk(world_to_chunk(target));
                if (target_chunk == nullptr) continue;
                const int32_t target_index = local_index(world_to_local(target));
                const int32_t target_material = target_chunk->material[target_index];
                if (target_material == EMPTY_ID || target_material == COAL_CHUNK_ID || target_material == WOOD_ID || target_material == CHARCOAL_ID) continue;
                const int64_t ambient_energy = phase_base_enthalpy(fuel_material, material_amount_at(*fuel_chunk, fuel_index)) +
                    static_cast<int64_t>(thermal_capacity(fuel_material, material_amount_at(*fuel_chunk, fuel_index))) * TEMPERATURE_AMBIENT;
                const int64_t available = std::max<int64_t>(0, cell_enthalpy(*fuel_chunk, fuel_index) - ambient_energy);
                const int32_t distance = std::max(1, std::abs(target_x - fuel_x) + std::abs(target_y - fuel_y));
                const int64_t divisor = (has_research("furnace.throughput_1") ? 4 : 6) * distance;
                const int64_t transfer = std::min<int64_t>(available, std::max<int64_t>(0, available / divisor));
                if (transfer <= 0) continue;
                add_cell_energy(fuel_cell, -transfer);
                add_cell_energy(target, transfer);
                transferred_energy += transfer;
                ++last_heated_cells_;
                target_chunk = get_chunk(world_to_chunk(target));
                if (target_chunk == nullptr) continue;
                const int32_t current_index = local_index(world_to_local(target));
                const int32_t current_material = target_chunk->material[current_index];
                if (target_chunk->temperature[current_index] < TEMPERATURE_REACTION ||
                    !(current_material == SAND_ID || (current_material >= FINE_SAND_ID && current_material <= 9))) continue;
                const int32_t result_material = processing_result(current_material, target_chunk->provenance[current_index],
                    target_chunk->mineral_signature[current_index], 301 + current_material);
                if (result_material == current_material) continue;
                target_chunk->material[current_index] = static_cast<uint16_t>(result_material);
                ++target_chunk->revision; target_chunk->pristine = false;
                mark_render_world_cell(target); notify_automation_cell_change(target);
                ++last_heat_reactions_; ++total_heat_reactions_; ++total_furnace_processed_;
                if (result_material == 10) ++total_glass_;
                else if (result_material == 11) ++total_iron_;
                else if (result_material == 12) ++total_gold_;
                else ++total_residue_;
            }}
        }}
        entity.state = transferred_energy > 0 ? 3 : has_physical_fuel ? 2 : 1;
        if (physical_region_has_material(heater)) next_active.insert(id);
        if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
    }
    active_heaters_.swap(next_active);
    last_heaters_active_ = static_cast<int64_t>(active_heaters_.size());
    last_heat_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::process_wet_sluices() {
    const auto started = std::chrono::steady_clock::now();
    last_wet_cells_visited_ = last_wet_grains_moved_ = last_wet_heavy_captured_ = last_wet_light_output_ = 0;
    std::vector<uint64_t> ids(active_wet_sluices_.begin(), active_wet_sluices_.end());
    std::sort(ids.begin(), ids.end());
    std::unordered_set<uint64_t> next_active;
    for (const uint64_t id : ids) {
        const auto found = physical_processors_.find(id);
        if (found == physical_processors_.end() || found->second.type_id != STRUCTURE_WASH_SLUICE) continue;
        const PhysicalProcessor &sluice = found->second;
        const auto entity_found = machine_entities_.find(id);
        if (entity_found == machine_entities_.end()) continue;
        MachineEntity &entity = entity_found->second;
        const int32_t previous_state = entity.state;
        const int32_t direction = sluice.transport_direction;
        const int32_t start_x = direction > 0 ? sluice.origin.x + 15 : sluice.origin.x + 2;
        const int32_t end_x = direction > 0 ? sluice.origin.x : sluice.origin.x + 17;
        bool has_water = false;
        bool has_grain = false;
        for (int32_t x = sluice.origin.x + 1; x < sluice.origin.x + 17; ++x) {
            has_water = has_water || get_liquid_mass({x, sluice.origin.y + 2}) > 0 || get_liquid_mass({x, sluice.origin.y + 3}) > 0 ||
                        get_liquid_mass({x, sluice.origin.y + 4}) > 0;
            for (int32_t row = 1; row <= 4; ++row) has_grain = has_grain || material_transportable(get_cell({x, sluice.origin.y + row}));
        }
        if (!has_water || !has_grain) {
            entity.state = has_water ? 1 : 2;
            if (has_water || has_grain) next_active.insert(id);
            if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
            continue;
        }
        entity.state = 3;
        for (int32_t row = 4; row >= 1; --row) for (int32_t x = start_x; x != end_x; x -= direction) {
            const Vector2i source{x, sluice.origin.y + row};
            if (!material_transportable(get_cell(source)) || moved_this_tick(source)) continue;
            ++last_wet_cells_visited_;
            const int32_t flow_mass = get_liquid_mass(source + Vector2i(0, -1)) + get_liquid_mass(source + Vector2i(-direction, -1)) +
                                      get_liquid_mass(source + Vector2i(0, 1)) + get_liquid_mass(source + Vector2i(-direction, 1)) +
                                      get_liquid_mass(source + Vector2i(direction, 1));
            if (flow_mass < 48) continue;
            Chunk *chunk = get_chunk(world_to_chunk(source));
            if (chunk == nullptr) continue;
            const int32_t index = local_index(world_to_local(source));
            const int32_t constituent = hidden_constituent(chunk->provenance[index], chunk->mineral_signature[index]);
            const bool heavy = constituent == CONSTITUENT_HEAVY || constituent == CONSTITUENT_IRON_BEARING || grain_size_class(chunk->material[index], chunk->provenance[index], chunk->mineral_signature[index]) > 1;
            const int32_t local_x = source.x - sluice.origin.x;
            const int32_t downstream_x = local_x + direction;
            const bool at_riffle = downstream_x == 4 || downstream_x == 8 || downstream_x == 12 || downstream_x == 16;
            if (heavy && at_riffle && flow_mass < 420) {
                if (chunk->material[index] == SAND_ID) { chunk->material[index] = HEAVY_CONCENTRATE_ID; ++chunk->revision; mark_render_world_cell(source); record_production_flow(ProductionFlowKind::WET_PROCESSING_THROUGHPUT, 1); }
                ++last_wet_heavy_captured_;
                continue;
            }
            const int32_t mobility_threshold = heavy ? 330 : 72;
            if (flow_mass < mobility_threshold) continue;
            Vector2i destination = source + Vector2i(direction, 0);
            if (!move_if_empty(source, destination)) {
                destination += Vector2i(0, -1);
                if (flow_mass < 180 || !move_if_empty(source, destination)) continue;
            }
            ++last_wet_grains_moved_;
            if (!sluice.interaction_area.has_point(destination)) {
                Chunk *output = get_chunk(world_to_chunk(destination));
                if (output != nullptr) {
                    const int32_t output_index = local_index(world_to_local(destination));
                    if (output->material[output_index] == SAND_ID) output->material[output_index] = FINE_SAND_ID;
                    ++output->revision;
                    mark_render_world_cell(destination);
                }
                ++last_wet_light_output_;
                record_production_flow(ProductionFlowKind::WET_PROCESSING_THROUGHPUT, 1);
            }
        }
        if (has_water || physical_region_has_material(sluice)) next_active.insert(id);
        if (entity.state != previous_state) { ++machine_visual_revision_; notify_automation_machine_change(id); }
    }
    active_wet_sluices_.swap(next_active);
    last_wet_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

Dictionary NativeSandWorld::get_physical_processing_statistics() const {
    Dictionary result;
    int64_t magnets_total = 0, screens_total = 0, heaters_total = 0;
    for (const auto &[id, processor] : physical_processors_) {
        (void)id;
        if (processor.type_id == STRUCTURE_OVERBELT_MAGNET) ++magnets_total;
        else if (processor.type_id == STRUCTURE_SCREEN) ++screens_total;
        else if (processor.type_id != STRUCTURE_WASH_SLUICE) ++heaters_total;
    }
    result["magnets_total"] = magnets_total;
    result["magnets_active"] = last_magnets_active_;
    result["magnetic_field_regions_active"] = last_magnets_active_;
    result["magnetic_cells_tested"] = last_magnetic_cells_tested_;
    result["magnetic_moves"] = last_magnetic_moves_;
    result["magnetic_moves_total"] = total_magnetic_moves_;
    result["magnetic_usec"] = last_magnetic_usec_;
    result["screens_total"] = screens_total;
    result["screens_active"] = last_screens_active_;
    result["screen_grains_tested"] = last_screen_grains_tested_;
    result["vibration_evaluations"] = last_screen_vibration_evaluations_;
    result["screen_passes"] = last_screen_passes_;
    result["screen_passes_total"] = total_screen_passes_;
    result["screen_usec"] = last_screen_usec_;
    result["registered_region_chunks"] = static_cast<int64_t>(physical_chunk_watchers_.size());
    result["heaters_total"] = heaters_total;
    result["heaters_active"] = last_heaters_active_;
    result["heated_cells"] = last_heated_cells_;
    result["heat_reactions"] = last_heat_reactions_;
    result["heat_reactions_total"] = total_heat_reactions_;
    result["heat_usec"] = last_heat_usec_;
    return result;
}

Dictionary NativeSandWorld::get_magnetic_field_sample(Rect2i cell_area, int32_t stride) const {
    Dictionary result;
    PackedInt32Array samples;
    stride = std::clamp(stride, 1, 32);
    std::vector<const PhysicalProcessor *> magnets;
    for (const auto &[id, processor] : physical_processors_) {
        (void)id;
        if (processor.type_id == STRUCTURE_OVERBELT_MAGNET && processor.interaction_area.intersects(cell_area)) magnets.push_back(&processor);
    }
    std::sort(magnets.begin(), magnets.end(), [](const PhysicalProcessor *a, const PhysicalProcessor *b) { return a->id < b->id; });
    std::unordered_map<uint64_t, int32_t> combined;
    for (const PhysicalProcessor *magnet : magnets) {
        const Rect2i area = magnet->interaction_area.intersection(cell_area);
        const Vector2i end = area.position + area.size;
        for (int32_t y = area.position.y; y < end.y; ++y) {
            if ((y % stride + stride) % stride != 0) continue;
            for (int32_t x = area.position.x; x < end.x; ++x) {
                if ((x % stride + stride) % stride != 0) continue;
                const int32_t electric_bonus = 1000 * electric_satisfaction(STRUCTURE_OVERBELT_MAGNET, magnet->id, magnet->origin) / 1000;
                combined[cell_key({x, y})] += std::max(0, static_cast<int32_t>(magnet->field_strength) + electric_bonus - (y - magnet->interaction_area.position.y) * 180);
            }
        }
    }
    std::vector<uint64_t> keys;
    keys.reserve(combined.size());
    for (const auto &[key, strength] : combined) if (strength > 0) keys.push_back(key);
    std::sort(keys.begin(), keys.end());
    for (const uint64_t key : keys) {
        const Vector2i cell = cell_from_key(key);
        const int32_t strength = combined.at(key);
        samples.push_back(cell.x); samples.push_back(cell.y); samples.push_back(0); samples.push_back(-strength); samples.push_back(strength);
    }
    result["mode"] = "MAGNETIC_FIELD";
    result["stride"] = stride;
    result["sample_stride"] = 5;
    result["samples"] = samples;
    result["legend_min"] = 0;
    result["legend_max"] = 1200;
    return result;
}

String NativeSandWorld::physical_processing_hash() const {
    uint32_t hash = 2166136261u;
    for (const Chunk *chunk : sorted_chunks()) {
        hash = content_hash_mix(hash, static_cast<uint32_t>(chunk->coordinate.x));
        hash = content_hash_mix(hash, static_cast<uint32_t>(chunk->coordinate.y));
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (chunk->material[index] == EMPTY_ID) continue;
            hash = content_hash_mix(hash, static_cast<uint32_t>(index));
            hash = content_hash_mix(hash, chunk->material[index]);
            hash = content_hash_mix(hash, chunk->provenance[index]);
            hash = content_hash_mix(hash, chunk->mineral_signature[index]);
        }
    }
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

} // namespace godot
