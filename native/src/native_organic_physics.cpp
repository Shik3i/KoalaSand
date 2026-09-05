#include "native_sand_world.hpp"

#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <array>
#include <cstdio>
#include <deque>
#include <unordered_set>

namespace godot {
namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t WATER = 3;
constexpr int32_t ASH = 15;
constexpr int32_t STEAM = 17;
constexpr int32_t COAL_CHUNK = 14;
constexpr int32_t WOOD = 21;
constexpr int32_t LEAVES = 22;
constexpr int32_t CHARCOAL = 23;
constexpr int32_t SMOKE = 24;
constexpr int32_t RAW_FOOD = 25;
constexpr int32_t COOKED_FOOD = 26;
constexpr int32_t BURNT_FOOD = 27;
constexpr int32_t AMBIENT_OXIDIZER = 255;
constexpr int32_t LOW_OXIDIZER = 72;
constexpr int32_t FOOD_COOK_TEMPERATURE = 1372; // 343 K
constexpr int32_t FOOD_BURN_TEMPERATURE = 1972; // 493 K
constexpr int32_t Q10 = 1024;
constexpr int32_t QUARTER_TURN_Q16 = 16384;
constexpr uint8_t ORGANIC_LOOSE_FLAG = 1u << 3;

constexpr std::array<int32_t, 17> SIN_Q15{{
    0, 3212, 6393, 9512, 12539, 15446, 18204, 20787, 23170,
    25330, 27246, 28899, 30274, 31356, 32138, 32610, 32767,
}};

int32_t sin_quarter_q15(int32_t angle) {
    angle = std::clamp(angle, 0, QUARTER_TURN_Q16);
    const int32_t index = angle >> 10;
    if (index >= 16) return SIN_Q15[16];
    const int32_t fraction = angle & 1023;
    return SIN_Q15[index] + (SIN_Q15[index + 1] - SIN_Q15[index]) * fraction / 1024;
}

bool rect_contains(const Rect2i &rect, Vector2i cell) {
    const Vector2i end = rect.position + rect.size;
    return cell.x >= rect.position.x && cell.y >= rect.position.y && cell.x < end.x && cell.y < end.y;
}
}

const std::array<NativeSandWorld::OrganicMaterialDefinition, NativeSandWorld::MATERIAL_COUNT> &
NativeSandWorld::organic_material_definitions() {
    static const std::array<OrganicMaterialDefinition, MATERIAL_COUNT> definitions = [] {
        std::array<OrganicMaterialDefinition, MATERIAL_COUNT> d{};
        d[COAL_CHUNK] = {1250, 14, 48, 2572, 65535, 18000, 105, 0, 0, 20, 0, 2, true};
        d[WOOD] = {700, 18, 72, 2092, 1892, 12000, 190, 96, 96, 16, 159, 4, true};
        d[LEAVES] = {180, 10, 36, 1760, 1680, 5200, 255, 48, 16, 48, 207, 8, true};
        d[CHARCOAL] = {420, 12, 44, 2692, 65535, 24000, 150, 8, 0, 24, 0, 2, true};
        d[SMOKE] = {2, 8, 24, 65535, 65535, 0, 0, 0, 0, 0, 0, 0, false};
        d[RAW_FOOD] = {650, 22, 92, 1972, 65535, 2400, 80, 96, 0, 32, 223, 2, true};
        d[COOKED_FOOD] = {610, 20, 78, 1972, 65535, 1800, 70, 48, 0, 40, 215, 2, true};
        d[BURNT_FOOD] = {430, 14, 48, 2420, 65535, 800, 30, 0, 0, 64, 191, 1, true};
        return d;
    }();
    return definitions;
}

bool NativeSandWorld::is_organic_material(int32_t material) {
    return material >= WOOD && material <= BURNT_FOOD;
}

bool NativeSandWorld::is_combustible_material(int32_t material) {
    return material == COAL_CHUNK || material == WOOD || material == LEAVES || material == CHARCOAL ||
           material == RAW_FOOD || material == COOKED_FOOD || material == BURNT_FOOD;
}

void NativeSandWorld::ensure_moisture_plane(Chunk &chunk) {
    if (chunk.organic_moisture != nullptr) return;
    chunk.organic_moisture = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
    chunk.organic_moisture->fill(0);
}

void NativeSandWorld::ensure_atmosphere_plane(Chunk &chunk) {
    if (chunk.oxidizer != nullptr) return;
    chunk.oxidizer = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        const int32_t material = chunk.material[index];
        const int32_t amount = material_amount_at(chunk, index);
        (*chunk.oxidizer)[index] = static_cast<uint8_t>(material == EMPTY ? AMBIENT_OXIDIZER :
            is_gas_material(material) ? std::max(0, AMBIENT_OXIDIZER - amount) : 0);
    }
    disturbed_atmosphere_chunks_.insert(chunk_key(chunk.coordinate));
}

void NativeSandWorld::ensure_reaction_planes(Chunk &chunk) {
    if (chunk.reaction_progress == nullptr) {
        chunk.reaction_progress = std::make_unique<std::array<uint16_t, CELLS_PER_CHUNK>>();
        chunk.reaction_progress->fill(0);
    }
    if (chunk.reaction_state == nullptr) {
        chunk.reaction_state = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
        chunk.reaction_state->fill(0);
    }
}

void NativeSandWorld::activate_reactive_cell(Vector2i world_cell) {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return;
    const int32_t index = local_index(world_to_local(world_cell));
    const int32_t material = chunk->material[index];
    const bool has_bound_water = chunk->organic_moisture != nullptr && (*chunk->organic_moisture)[index] > 0;
    if ((material >= 0 && material < MATERIAL_COUNT && organic_material_definitions()[material].reactive) || has_bound_water)
        reactive_cells_.insert(cell_key(world_cell));
}

int32_t NativeSandWorld::oxidizer_at(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return world_cell.y < surface_height_at_v2(world_cell.x) ? AMBIENT_OXIDIZER : 0;
    const int32_t index = local_index(world_to_local(world_cell));
    if (chunk->oxidizer != nullptr) return (*chunk->oxidizer)[index];
    const int32_t material = chunk->material[index];
    if (material == EMPTY) return AMBIENT_OXIDIZER;
    if (is_gas_material(material)) return std::max(0, AMBIENT_OXIDIZER - material_amount_at(*chunk, index));
    return 0;
}

bool NativeSandWorld::write_oxidizer(Vector2i world_cell, int32_t value) {
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return false;
    ensure_atmosphere_plane(*chunk);
    const int32_t index = local_index(world_to_local(world_cell));
    const uint8_t next = static_cast<uint8_t>(std::clamp(value, 0, AMBIENT_OXIDIZER));
    if ((*chunk->oxidizer)[index] == next) return false;
    (*chunk->oxidizer)[index] = next;
    disturbed_atmosphere_chunks_.insert(chunk_key(chunk->coordinate));
    ++organic_revision_;
    return true;
}

Array NativeSandWorld::get_organic_material_definitions() const {
    static constexpr std::array<const char *, 7> names{{"Wood", "Leaves", "Charcoal", "Smoke", "Raw Mushroom", "Cooked Mushroom", "Burnt Food"}};
    Array result;
    for (int32_t material = WOOD; material <= BURNT_FOOD; ++material) {
        const OrganicMaterialDefinition &definition = organic_material_definitions()[material];
        Dictionary item;
        item["material_id"] = material;
        item["display_name"] = names[material - WOOD];
        item["density"] = definition.density;
        item["thermal_conductivity"] = definition.conductivity;
        item["specific_heat"] = definition.specific_heat;
        item["ignition_temperature"] = definition.ignition_temperature;
        item["pyrolysis_temperature"] = definition.pyrolysis_temperature;
        item["combustion_heat"] = static_cast<int64_t>(definition.combustion_heat);
        item["flammability"] = definition.flammability;
        item["moisture_capacity"] = definition.moisture_capacity;
        item["char_yield"] = definition.char_yield;
        item["ash_yield"] = definition.ash_yield;
        item["smoke_yield"] = definition.smoke_yield;
        item["burn_rate"] = definition.burn_rate;
        result.push_back(item);
    }
    return result;
}

Array NativeSandWorld::get_fuel_definitions() const {
    static constexpr std::array<int32_t, 3> materials{{COAL_CHUNK, WOOD, CHARCOAL}};
    static constexpr std::array<const char *, 3> names{{"Coal Chunk", "Wood", "Charcoal"}};
    Array result;
    for (int32_t index = 0; index < static_cast<int32_t>(materials.size()); ++index) {
        const int32_t material = materials[index];
        const OrganicMaterialDefinition &definition = organic_material_definitions()[material];
        Dictionary item;
        item["material_id"] = material;
        item["display_name"] = names[index];
        item["ignition_temperature"] = definition.ignition_temperature;
        item["energy_per_mass"] = static_cast<int64_t>(definition.combustion_heat);
        item["burn_rate"] = definition.burn_rate;
        item["ash_yield"] = definition.ash_yield;
        item["smoke_yield"] = definition.smoke_yield;
        item["physical_cell_fuel"] = true;
        result.push_back(item);
    }
    return result;
}

Dictionary NativeSandWorld::get_organic_architecture() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["ambient_oxidizer"] = AMBIENT_OXIDIZER;
    result["base_cell_bytes"] = 9;
    result["standing_tree_metadata_bytes"] = 0;
    result["moisture_plane_bytes"] = CELLS_PER_CHUNK;
    result["atmosphere_plane_bytes"] = CELLS_PER_CHUNK;
    result["reaction_progress_plane_bytes"] = CELLS_PER_CHUNK * 2;
    result["reaction_state_plane_bytes"] = CELLS_PER_CHUNK;
    result["fixed_point_position_scale"] = Q10;
    result["fixed_point_quarter_turn"] = QUARTER_TURN_Q16;
    result["cluster_threading"] = "serial_stable_id_order";
    result["implicit_ambient_air"] = true;
    result["tree_feature_template"] = "basic_tree.v1";
    result["mushroom_feature_template"] = "mushroom.v1";
    result["pot_primary_storage"] = "world_cells";
    return result;
}

Dictionary NativeSandWorld::get_thermal_vessel_definition(int32_t type_id) const {
    Dictionary result;
    if (type_id == 35) {
        result["type_id"] = 35;
        result["wall_material"] = "Iron";
        result["footprint"] = Vector2i(9, 6);
        result["cavity"] = Rect2i(Vector2i(1, 0), Vector2i(7, 5));
        result["open_top"] = true;
        result["thermal_conductivity"] = 192;
        result["specific_heat"] = 56;
        result["transfer_coefficient"] = 16;
        result["contents_are_world_cells"] = true;
        result["removal_policy"] = "CONTENTS_PRESENT_REJECTED";
    } else if (type_id == 36 || type_id == -35) {
        result["type_id"] = type_id;
        result["test_only"] = true;
        result["wall_material"] = "Ceramic test vessel";
        result["footprint"] = Vector2i(9, 6);
        result["cavity"] = Rect2i(Vector2i(1, 0), Vector2i(7, 5));
        result["open_top"] = true;
        result["thermal_conductivity"] = 24;
        result["specific_heat"] = 80;
        result["transfer_coefficient"] = 2;
        result["contents_are_world_cells"] = true;
    }
    return result;
}

int32_t NativeSandWorld::set_organic_moisture(Vector2i world_cell, int32_t moisture) {
    if (moisture < 0 || moisture > 255) return 31;
    Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return 31;
    const int32_t index = local_index(world_to_local(world_cell));
    const int32_t material = chunk->material[index];
    const bool sediment = material == 2 || (material >= 6 && material <= 9);
    if (!sediment && material != WOOD && material != LEAVES && material != RAW_FOOD && material != COOKED_FOOD) return 31;
    if (moisture > 0) ensure_moisture_plane(*chunk);
    if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = static_cast<uint8_t>(moisture);
    activate_reactive_cell(world_cell);
    ++organic_revision_;
    return 0;
}

int32_t NativeSandWorld::get_organic_moisture(Vector2i world_cell) const {
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    return chunk == nullptr || chunk->organic_moisture == nullptr ? 0 :
        (*chunk->organic_moisture)[local_index(world_to_local(world_cell))];
}

Dictionary NativeSandWorld::bind_water_to_sediment(Vector2i sediment_cell, Vector2i water_cell, int32_t requested_amount) {
    Dictionary result; result["accepted"] = 0; result["reason"] = "INVALID_INPUT";
    if (requested_amount <= 0 || requested_amount > 255 || get_cell(water_cell) != WATER) return result;
    Chunk *sediment_chunk = get_chunk(world_to_chunk(sediment_cell));
    Chunk *water_chunk = get_chunk(world_to_chunk(water_cell));
    if (sediment_chunk == nullptr || water_chunk == nullptr) return result;
    const int32_t sediment_index = local_index(world_to_local(sediment_cell));
    const int32_t sediment = sediment_chunk->material[sediment_index];
    if (!(sediment == 2 || (sediment >= 6 && sediment <= 9))) { result["reason"] = "NOT_SEDIMENT"; return result; }
    const int32_t water_index = local_index(world_to_local(water_cell));
    const int32_t water_amount = material_amount_at(*water_chunk, water_index);
    const int32_t old_bound = sediment_chunk->organic_moisture == nullptr ? 0 : (*sediment_chunk->organic_moisture)[sediment_index];
    const int32_t accepted = std::min({requested_amount, water_amount, 255 - old_bound});
    if (accepted <= 0) { result["reason"] = "SATURATED_OR_EMPTY"; return result; }
    const int32_t water_temperature = water_chunk->temperature[water_index];
    set_material_state(water_cell, water_amount == accepted ? EMPTY : WATER, water_amount - accepted,
                       water_amount == accepted ? TEMPERATURE_AMBIENT : water_temperature, 0, 0);
    ensure_moisture_plane(*sediment_chunk);
    (*sediment_chunk->organic_moisture)[sediment_index] = static_cast<uint8_t>(old_bound + accepted);
    activate_reactive_cell(sediment_cell); ++organic_revision_;
    result["accepted"] = accepted; result["reason"] = "BOUND_TO_SEDIMENT"; result["free_water_remaining"] = water_amount - accepted;
    result["bound_water"] = old_bound + accepted; result["mass_balanced"] = water_amount + old_bound == water_amount - accepted + old_bound + accepted;
    return result;
}

int64_t NativeSandWorld::get_bound_water_mass() const {
    int64_t result = 0;
    for (const Chunk *chunk : sorted_chunks()) if (chunk->organic_moisture != nullptr)
        for (const uint8_t value : *chunk->organic_moisture) result += value;
    return result;
}

int32_t NativeSandWorld::get_oxidizer(Vector2i world_cell) const { return oxidizer_at(world_cell); }

Dictionary NativeSandWorld::get_organic_state(Vector2i world_cell) const {
    Dictionary result;
    const Chunk *chunk = get_chunk(world_to_chunk(world_cell));
    if (chunk == nullptr) return result;
    const int32_t index = local_index(world_to_local(world_cell));
    result["material_id"] = chunk->material[index];
    result["amount"] = material_amount_at(*chunk, index);
    result["temperature"] = chunk->temperature[index];
    result["moisture"] = chunk->organic_moisture == nullptr ? 0 : (*chunk->organic_moisture)[index];
    result["oxidizer"] = oxidizer_at(world_cell);
    result["reaction_progress"] = chunk->reaction_progress == nullptr ? 0 : (*chunk->reaction_progress)[index];
    result["reaction_state"] = chunk->reaction_state == nullptr ? 0 : (*chunk->reaction_state)[index];
    result["loose"] = (chunk->flags[index] & ORGANIC_LOOSE_FLAG) != 0;
    return result;
}

std::vector<Vector2i> NativeSandWorld::rasterized_cluster_cells(const FellableCluster &cluster, int32_t angle_q16,
                                                                 Vector2i origin_q10) const {
    const int32_t sign = angle_q16 < 0 ? -1 : 1;
    const int32_t absolute = std::min(std::abs(angle_q16), QUARTER_TURN_Q16);
    const int32_t sine = sin_quarter_q15(absolute) * sign;
    const int32_t cosine = sin_quarter_q15(QUARTER_TURN_Q16 - absolute);
    const Vector2i origin{(origin_q10.x + Q10 / 2) / Q10, (origin_q10.y + Q10 / 2) / Q10};
    std::vector<Vector2i> result;
    result.reserve(cluster.cells.size());
    for (const FellableClusterCell &cell : cluster.cells) {
        const int32_t x = (static_cast<int32_t>(cell.x) * cosine - static_cast<int32_t>(cell.y) * sine + 16384) / 32768;
        const int32_t y = (static_cast<int32_t>(cell.x) * sine + static_cast<int32_t>(cell.y) * cosine + 16384) / 32768;
        result.push_back(origin + Vector2i(x, y));
    }
    return result;
}

Dictionary NativeSandWorld::character_cut_cell(Vector2i world_cell) {
    Dictionary result;
    result["accepted"] = false;
    result["reason"] = "NOT_VEGETATION";
    const int32_t target_material = get_cell(world_cell);
    if (target_material == RAW_FOOD) {
        activate_world_cell(world_cell, 1);
        result["accepted"] = true;
        result["reason"] = "HARVESTED_PHYSICAL_FOOD";
        result["material_id"] = RAW_FOOD;
        return result;
    }
    if (target_material != WOOD && target_material != LEAVES) return result;

    std::deque<Vector2i> queue;
    std::unordered_set<uint64_t> visited;
    std::vector<Vector2i> cells;
    queue.push_back(world_cell);
    while (!queue.empty() && cells.size() < 2048) {
        const Vector2i cell = queue.front(); queue.pop_front();
        const uint64_t key = cell_key(cell);
        if (!visited.insert(key).second) continue;
        const int32_t material = get_cell(cell);
        if (material != WOOD && material != LEAVES) continue;
        cells.push_back(cell);
        queue.push_back(cell + Vector2i(-1, 0)); queue.push_back(cell + Vector2i(1, 0));
        queue.push_back(cell + Vector2i(0, -1)); queue.push_back(cell + Vector2i(0, 1));
    }
    if (cells.empty()) return result;
    Vector2i pivot = cells.front();
    int64_t sum_x = 0;
    for (const Vector2i cell : cells) {
        sum_x += cell.x;
        if (cell.y > pivot.y || (cell.y == pivot.y && cell.x < pivot.x)) pivot = cell;
    }
    const int32_t center_x = static_cast<int32_t>(sum_x / static_cast<int64_t>(cells.size()));
    int32_t direction = world_cell.x < center_x ? 1 : world_cell.x > center_x ? -1 :
        ((hash_2d(seed_, pivot, 0x12f011) & 1u) == 0u ? -1 : 1);

    FellableCluster cluster;
    cluster.id = next_fellable_cluster_id_++;
    cluster.origin_q10 = pivot * Q10;
    cluster.fall_direction = static_cast<int8_t>(direction);
    cluster.cells.reserve(cells.size());
    int64_t mass = 0;
    for (const Vector2i cell : cells) {
        Chunk *chunk = get_chunk(world_to_chunk(cell));
        const int32_t index = local_index(world_to_local(cell));
        const int32_t material = chunk->material[index];
        const int32_t amount = material_amount_at(*chunk, index);
        const int32_t moisture = chunk->organic_moisture == nullptr ? 0 : (*chunk->organic_moisture)[index];
        cluster.cells.push_back({static_cast<int16_t>(cell.x - pivot.x), static_cast<int16_t>(cell.y - pivot.y),
                                 static_cast<uint16_t>(material), chunk->temperature[index],
                                 static_cast<uint8_t>(amount), static_cast<uint8_t>(moisture)});
        mass += amount;
        set_material_state(cell, EMPTY, 0, TEMPERATURE_AMBIENT, 0, 0);
        if (chunk->organic_moisture != nullptr) (*chunk->organic_moisture)[index] = 0;
    }
    const uint64_t id = cluster.id;
    fellable_clusters_.emplace(id, std::move(cluster));
    ++total_trees_felled_;
    ++organic_revision_;
    result["accepted"] = true;
    result["reason"] = "FELLABLE_CLUSTER_CREATED";
    result["cluster_id"] = static_cast<int64_t>(id);
    result["cells"] = static_cast<int64_t>(cells.size());
    result["organic_mass"] = mass;
    result["fall_direction"] = direction;
    return result;
}

Dictionary NativeSandWorld::clear_vegetation_rect(Rect2i area) {
    Dictionary result;
    Vector2i end;
    if (!checked_rect_end(area, 1'048'576, end)) {
        result["accepted"] = false;
        result["reason"] = "INVALID_AREA";
        return result;
    }
    int32_t trees = 0;
    int64_t cells = 0;
    std::unordered_set<uint64_t> attempted;
    for (int32_t y = area.position.y; y < end.y; ++y) for (int32_t x = area.position.x; x < end.x; ++x) {
        const Vector2i cell{x, y};
        if (get_cell(cell) != WOOD || !attempted.insert(cell_key(cell)).second) continue;
        const Dictionary cut = character_cut_cell(cell);
        if (static_cast<bool>(cut.get("accepted", false))) {
            ++trees;
            cells += static_cast<int64_t>(cut.get("cells", 0));
        }
    }
    result["accepted"] = trees > 0;
    result["trees"] = trees;
    result["cells"] = cells;
    result["command_batch"] = true;
    return result;
}

bool NativeSandWorld::settle_cluster(FellableCluster &cluster) {
    const std::vector<Vector2i> targets = rasterized_cluster_cells(cluster, cluster.angle_q16, cluster.origin_q10);
    std::unordered_set<uint64_t> occupied;
    std::vector<Vector2i> placements;
    placements.reserve(cluster.cells.size());
    for (size_t index = 0; index < cluster.cells.size(); ++index) {
        Vector2i target = targets[index];
        bool placed = false;
        for (int32_t radius = 0; radius <= 8 && !placed; ++radius) {
            for (int32_t dx = -radius; dx <= radius && !placed; ++dx) {
                const std::array<Vector2i, 2> candidates{{target + Vector2i(dx, -radius), target + Vector2i(dx, radius)}};
                for (const Vector2i candidate : candidates) {
                    const uint64_t key = cell_key(candidate);
                    if (occupied.contains(key) || get_cell(candidate) != EMPTY || is_structure_solid(candidate)) continue;
                    occupied.insert(key);
                    placements.push_back(candidate);
                    placed = true;
                    break;
                }
            }
        }
        if (!placed) return false;
    }
    int64_t wood_produced = 0;
    for (size_t index = 0; index < cluster.cells.size(); ++index) {
        const FellableClusterCell &source = cluster.cells[index];
        const Vector2i target = placements[index];
        if (set_material_state(target, source.material, source.amount, source.temperature, 0, 0) != 0) return false;
        Chunk *target_chunk = get_chunk(world_to_chunk(target));
        if (target_chunk != nullptr) target_chunk->flags[local_index(world_to_local(target))] |= ORGANIC_LOOSE_FLAG;
        if (source.moisture > 0) set_organic_moisture(target, source.moisture);
        activate_world_cell(target, 1);
        activate_reactive_cell(target);
        if (source.material == WOOD) wood_produced += source.amount;
    }
    total_wood_produced_ += wood_produced;
    return true;
}

void NativeSandWorld::process_fellable_clusters() {
    const uint64_t started = Time::get_singleton()->get_ticks_usec();
    last_cluster_collision_samples_ = 0;
    std::vector<uint64_t> ids;
    ids.reserve(fellable_clusters_.size());
    for (const auto &[id, cluster] : fellable_clusters_) { (void)cluster; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    std::vector<uint64_t> settled;
    for (const uint64_t id : ids) {
        FellableCluster &cluster = fellable_clusters_.at(id);
        cluster.angular_velocity_q16 = std::min(1536, cluster.angular_velocity_q16 + 96);
        int32_t next_angle = cluster.angle_q16 + cluster.fall_direction * cluster.angular_velocity_q16;
        next_angle = std::clamp(next_angle, -QUARTER_TURN_Q16, QUARTER_TURN_Q16);
        const std::vector<Vector2i> targets = rasterized_cluster_cells(cluster, next_angle, cluster.origin_q10 + cluster.velocity_q10);
        bool collision = false;
        for (const Vector2i cell : targets) {
            ++last_cluster_collision_samples_;
            if (get_cell(cell) != EMPTY || is_structure_solid(cell)) { collision = true; break; }
        }
        if (!collision) {
            cluster.angle_q16 = next_angle;
            cluster.origin_q10 += cluster.velocity_q10;
            cluster.velocity_q10.y = std::min(256, cluster.velocity_q10.y + 12);
        } else {
            ++cluster.collision_count;
            cluster.angular_velocity_q16 = std::max(32, cluster.angular_velocity_q16 / 4);
            cluster.velocity_q10 = Vector2i();
        }
        if (std::abs(cluster.angle_q16) >= QUARTER_TURN_Q16 || cluster.collision_count >= 2) {
            if (settle_cluster(cluster)) settled.push_back(id);
        }
    }
    for (const uint64_t id : settled) fellable_clusters_.erase(id);
    if (!ids.empty()) ++organic_revision_;
    last_cluster_usec_ = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started);
}

Array NativeSandWorld::get_visible_fellable_clusters(Rect2i cell_area) const {
    Array result;
    std::vector<uint64_t> ids;
    for (const auto &[id, cluster] : fellable_clusters_) { (void)cluster; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const FellableCluster &cluster = fellable_clusters_.at(id);
        const std::vector<Vector2i> cells = rasterized_cluster_cells(cluster, cluster.angle_q16, cluster.origin_q10);
        bool visible = false;
        PackedInt32Array packed;
        for (size_t index = 0; index < cells.size(); ++index) {
            visible = visible || rect_contains(cell_area, cells[index]);
            packed.push_back(cells[index].x); packed.push_back(cells[index].y); packed.push_back(cluster.cells[index].material);
        }
        if (!visible) continue;
        Dictionary item;
        item["id"] = static_cast<int64_t>(id);
        item["angle_q16"] = cluster.angle_q16;
        item["angular_velocity_q16"] = cluster.angular_velocity_q16;
        item["origin_q10"] = cluster.origin_q10;
        item["cells"] = packed;
        result.push_back(item);
    }
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_organic_effects(Rect2i cell_area) const {
    PackedInt32Array result;
    std::vector<uint64_t> keys(reactive_cells_.begin(), reactive_cells_.end());
    std::sort(keys.begin(), keys.end());
    for (const uint64_t key : keys) {
        const Vector2i cell = cell_from_key(key);
        if (!rect_contains(cell_area, cell)) continue;
        const Chunk *chunk = get_chunk(world_to_chunk(cell));
        if (chunk == nullptr) continue;
        const int32_t index = local_index(world_to_local(cell));
        const int32_t state = chunk->reaction_state == nullptr ? 0 : (*chunk->reaction_state)[index];
        if (state == static_cast<int32_t>(OrganicReactionState::NONE) && chunk->temperature[index] < 1760) continue;
        result.push_back(cell.x); result.push_back(cell.y); result.push_back(state); result.push_back(chunk->temperature[index]);
    }
    return result;
}

bool NativeSandWorld::emit_organic_product(Vector2i source, int32_t material, int32_t amount, int32_t temperature, bool prefer_up) {
    if (amount <= 0) return true;
    std::array<Vector2i, 16> offsets{{
        {0,-1},{-1,-1},{1,-1},{-2,-1},{2,-1},{0,-2},{-1,-2},{1,-2},
        {0,1},{-1,1},{1,1},{-2,0},{2,0},{0,2},{-1,0},{1,0},
    }};
    if (!prefer_up) std::rotate(offsets.begin(), offsets.begin() + 8, offsets.end());
    int32_t capacity = 0;
    for (const Vector2i offset : offsets) {
        const Vector2i cell = source + offset;
        if (is_structure_solid(cell)) continue;
        const int32_t existing = get_cell(cell);
        if (existing == EMPTY) capacity += 255;
        else if (existing == material) capacity += 255 - material_amount_at(cell);
    }
    if (capacity < amount) return false;
    int32_t remaining = amount;
    for (const Vector2i offset : offsets) {
        const Vector2i cell = source + offset;
        if (is_structure_solid(cell)) continue;
        const int32_t existing = get_cell(cell);
        if (existing != EMPTY && existing != material) continue;
        const int32_t old_amount = existing == material ? material_amount_at(cell) : 0;
        const int32_t accepted = std::min(remaining, 255 - old_amount);
        if (accepted <= 0) continue;
        const int32_t old_temperature = existing == material ? get_temperature(cell) : temperature;
        const int32_t mixed = (old_temperature * old_amount + temperature * accepted) / std::max(1, old_amount + accepted);
        set_material_state(cell, material, old_amount + accepted, mixed, 0, 0);
        remaining -= accepted;
        if (remaining == 0) return true;
    }
    return false;
}

Dictionary NativeSandWorld::ignite_cell(Vector2i world_cell, int32_t energy) {
    Dictionary result;
    result["accepted"] = false;
    result["reason"] = "NOT_COMBUSTIBLE";
    if (energy <= 0 || !is_combustible_material(get_cell(world_cell))) return result;
    add_cell_energy(world_cell, energy);
    activate_reactive_cell(world_cell);
    result["accepted"] = true;
    result["reason"] = "THERMAL_PULSE_APPLIED";
    result["energy"] = energy;
    result["temperature"] = get_temperature(world_cell);
    return result;
}

void NativeSandWorld::process_atmosphere() {
    const uint64_t started = Time::get_singleton()->get_ticks_usec();
    last_atmosphere_cells_ = 0;
    std::vector<uint64_t> keys(disturbed_atmosphere_chunks_.begin(), disturbed_atmosphere_chunks_.end());
    std::sort(keys.begin(), keys.end());
    disturbed_atmosphere_chunks_.clear();
    for (const uint64_t key : keys) {
        Chunk *chunk = get_chunk(Vector2i(static_cast<int32_t>(key >> 32u), static_cast<int32_t>(key & 0xffffffffu)));
        if (chunk == nullptr || chunk->oxidizer == nullptr) continue;
        std::array<uint8_t, CELLS_PER_CHUNK> next = *chunk->oxidizer;
        bool changed = false;
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        const Chunk *left_chunk = get_chunk(chunk->coordinate + Vector2i(-1, 0));
        const Chunk *right_chunk = get_chunk(chunk->coordinate + Vector2i(1, 0));
        const Chunk *up_chunk = get_chunk(chunk->coordinate + Vector2i(0, -1));
        const Chunk *down_chunk = get_chunk(chunk->coordinate + Vector2i(0, 1));
        std::array<int32_t, CHUNK_SIZE> open_sky_y{};
        for (int32_t x = 0; x < CHUNK_SIZE; ++x) open_sky_y[x] = surface_height_at_v2(origin.x + x) - 2;
        auto add_neighbor = [](const Chunk *other, int32_t other_index, int32_t &sum, int32_t &divisor) {
            if (other == nullptr || other->oxidizer == nullptr) return;
            sum += (*other->oxidizer)[other_index];
            ++divisor;
        };
        for (int32_t y = 0; y < CHUNK_SIZE; ++y) for (int32_t x = 0; x < CHUNK_SIZE; ++x) {
            const int32_t index = y * CHUNK_SIZE + x;
            const int32_t material = chunk->material[index];
            if (material != EMPTY && !is_gas_material(material)) { next[index] = 0; continue; }
            ++last_atmosphere_cells_;
            int32_t target = (*chunk->oxidizer)[index];
            if (origin.y + y <= open_sky_y[x]) target = AMBIENT_OXIDIZER;
            else {
                int32_t sum = target * 4;
                int32_t divisor = 4;
                if (x > 0) { sum += (*chunk->oxidizer)[index - 1]; ++divisor; }
                else add_neighbor(left_chunk, index + CHUNK_SIZE - 1, sum, divisor);
                if (x + 1 < CHUNK_SIZE) { sum += (*chunk->oxidizer)[index + 1]; ++divisor; }
                else add_neighbor(right_chunk, index - CHUNK_SIZE + 1, sum, divisor);
                if (y > 0) { sum += (*chunk->oxidizer)[index - CHUNK_SIZE]; ++divisor; }
                else add_neighbor(up_chunk, index + CELLS_PER_CHUNK - CHUNK_SIZE, sum, divisor);
                if (y + 1 < CHUNK_SIZE) { sum += (*chunk->oxidizer)[index + CHUNK_SIZE]; ++divisor; }
                else add_neighbor(down_chunk, index - CELLS_PER_CHUNK + CHUNK_SIZE, sum, divisor);
                target = sum / divisor;
            }
            if (is_gas_material(material)) target = std::min(target, std::max(0, AMBIENT_OXIDIZER - material_amount_at(*chunk, index)));
            const int32_t current = (*chunk->oxidizer)[index];
            const int32_t relaxed = current + (target - current) / 4;
            next[index] = static_cast<uint8_t>(std::clamp(relaxed, 0, AMBIENT_OXIDIZER));
            changed = changed || next[index] != (*chunk->oxidizer)[index];
        }
        *chunk->oxidizer = next;
        if (changed) disturbed_atmosphere_chunks_.insert(key);
    }
    last_atmosphere_usec_ = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started);
}

void NativeSandWorld::process_reactions() {
    const uint64_t started = Time::get_singleton()->get_ticks_usec();
    last_reaction_cells_ = 0;
    std::vector<uint64_t> keys(reactive_cells_.begin(), reactive_cells_.end());
    std::sort(keys.begin(), keys.end());
    reactive_cells_.clear();
    // Which chunks have room for ash or smoke.
    //
    // This was built for every resident chunk, every tick. The inner loop stops at the first
    // cell with room -- instant for open air, and all 4096 cells before giving up on solid rock,
    // which is most of an explored world. Only pristine chunks are ever evicted, so residency
    // grows with everywhere the player has been, and on a settled 1600-chunk world this cost
    // 4.40 ms of a 4.42 ms tick: the entire cost of a tick in which nothing was happening.
    //
    // It hid because process_organic_physics() reports under cluster_usec, reaction_usec and
    // atmosphere_usec rather than an organic_usec, so a probe asking for the obvious key gets
    // zero and the phase reads as free.
    //
    // The map is only ever consulted below for chunk_key(chunk->coordinate) -- the chunk holding
    // the cell that is reacting. Building it for exactly those chunks gives the same answer for
    // every lookup that happens, and does no work at all for the ones that never do. When
    // nothing is reacting, nothing is built.
    std::unordered_set<uint64_t> product_capacity_chunks;
    std::unordered_set<uint64_t> examined_chunks;
    for (const uint64_t key : keys) {
        const Vector2i chunk_coordinate = world_to_chunk(cell_from_key(key));
        const uint64_t candidate_key = chunk_key(chunk_coordinate);
        if (!examined_chunks.insert(candidate_key).second) continue;
        const Chunk *candidate_chunk = get_chunk(chunk_coordinate);
        if (candidate_chunk == nullptr) continue;
        bool has_capacity = false;
        for (int32_t candidate_index = 0; candidate_index < CELLS_PER_CHUNK; ++candidate_index) {
            const int32_t candidate_material = candidate_chunk->material[candidate_index];
            if (candidate_material == EMPTY ||
                ((candidate_material == ASH || candidate_material == SMOKE) && material_amount_at(*candidate_chunk, candidate_index) < 255)) {
                has_capacity = true;
                break;
            }
        }
        if (has_capacity) product_capacity_chunks.insert(candidate_key);
    }
    for (const uint64_t key : keys) {
        const Vector2i cell = cell_from_key(key);
        Chunk *chunk = get_chunk(world_to_chunk(cell));
        if (chunk == nullptr) continue;
        const Vector2i local = world_to_local(cell);
        const int32_t index = local_index(local);
        int32_t material = chunk->material[index];
        const bool wet_sediment = (material == 2 || (material >= 6 && material <= 9)) &&
            chunk->organic_moisture != nullptr && (*chunk->organic_moisture)[index] > 0;
        if (!is_combustible_material(material) && !wet_sediment) continue;
        ++last_reaction_cells_;
        ensure_reaction_planes(*chunk);
        int32_t temperature = chunk->temperature[index];
        int32_t amount = material_amount_at(*chunk, index);
        int32_t moisture = chunk->organic_moisture == nullptr ? 0 : (*chunk->organic_moisture)[index];
        const OrganicMaterialDefinition &definition = organic_material_definitions()[material];
        int32_t oxygen = 0;
        Vector2i oxygen_cell = cell;
        static const std::array<Vector2i, 4> OXYGEN_OFFSETS{{{0,-1},{-1,0},{1,0},{0,1}}};
        if (local.x > 0 && local.x + 1 < CHUNK_SIZE && local.y > 0 && local.y + 1 < CHUNK_SIZE && chunk->oxidizer != nullptr) {
            const std::array<int32_t, 4> neighbor_indices{{index - CHUNK_SIZE, index - 1, index + 1, index + CHUNK_SIZE}};
            for (int32_t neighbor = 0; neighbor < 4; ++neighbor) {
                const int32_t candidate = (*chunk->oxidizer)[neighbor_indices[neighbor]];
                if (candidate > oxygen) { oxygen = candidate; oxygen_cell = cell + OXYGEN_OFFSETS[neighbor]; }
            }
        } else {
            for (const Vector2i offset : OXYGEN_OFFSETS) {
                const int32_t candidate = oxidizer_at(cell + offset);
                if (candidate > oxygen) { oxygen = candidate; oxygen_cell = cell + offset; }
            }
        }
        OrganicReactionState state = OrganicReactionState::NONE;
        bool keep_active = false;

        if (moisture > 0 && temperature >= 1320) {
            state = OrganicReactionState::DRYING;
            const int32_t released = std::min(2, moisture);
            const int32_t product = temperature >= 1492 ? STEAM : WATER;
            if (emit_organic_product(cell, product, released, temperature, product == STEAM)) {
                (*chunk->organic_moisture)[index] = static_cast<uint8_t>(moisture - released);
                total_wood_water_evaporated_ += released;
                moisture -= released;
                add_cell_energy(cell, -static_cast<int64_t>(released) * 9000);
            }
            keep_active = true;
        } else if ((material == WOOD || material == LEAVES) && temperature >= definition.pyrolysis_temperature && oxygen < LOW_OXIDIZER) {
            state = OrganicReactionState::PYROLYZING;
            uint16_t &progress = (*chunk->reaction_progress)[index];
            progress = static_cast<uint16_t>(std::min(65535, static_cast<int32_t>(progress) + std::max(1, (temperature - definition.pyrolysis_temperature) / 4)));
            if (progress >= 4096) {
                FractionalMassLedger &ledger = fractional_ledgers_[key];
                ledger.id = key;
                ledger.output_material[0] = CHARCOAL;
                ledger.output_material[1] = SMOKE;
                const int64_t input_micro_mass = static_cast<int64_t>(amount) * AMOUNT_UNIT_MICRO_MASS;
                const int64_t char_micro_mass = input_micro_mass * definition.char_yield / 255;
                const int64_t smoke_micro_mass = input_micro_mass - char_micro_mass;
                const int64_t old_char_units = total_charcoal_micro_mass_ / AMOUNT_UNIT_MICRO_MASS;
                const int32_t char_mass = static_cast<int32_t>(char_micro_mass / AMOUNT_UNIT_MICRO_MASS);
                const int32_t smoke_mass = static_cast<int32_t>((composition_total(ledger.pending[1]) + smoke_micro_mass) / AMOUNT_UNIT_MICRO_MASS);
                if (emit_organic_product(cell, SMOKE, smoke_mass, temperature, true)) {
                    ledger.input_micro_mass += input_micro_mass;
                    ledger.pending[0][5] += char_micro_mass - static_cast<int64_t>(char_mass) * AMOUNT_UNIT_MICRO_MASS;
                    ledger.pending[1][5] += smoke_micro_mass - static_cast<int64_t>(smoke_mass) * AMOUNT_UNIT_MICRO_MASS;
                    ledger.emitted_channel_micro_mass[0] += static_cast<int64_t>(char_mass) * AMOUNT_UNIT_MICRO_MASS;
                    ledger.emitted_channel_micro_mass[1] += static_cast<int64_t>(smoke_mass) * AMOUNT_UNIT_MICRO_MASS;
                    ledger.emitted_micro_mass += static_cast<int64_t>(char_mass + smoke_mass) * AMOUNT_UNIT_MICRO_MASS;
                    conservation_input_micro_mass_ += input_micro_mass;
                    conservation_output_micro_mass_ += static_cast<int64_t>(char_mass + smoke_mass) * AMOUNT_UNIT_MICRO_MASS;
                    total_charcoal_micro_mass_ += char_micro_mass;
                    total_smoke_micro_mass_ += smoke_micro_mass;
                    set_material_state(cell, char_mass > 0 ? CHARCOAL : EMPTY, char_mass,
                                       char_mass > 0 ? temperature : TEMPERATURE_AMBIENT, 0, 0);
                    total_wood_pyrolyzed_ += amount;
                    const int64_t new_char_units = total_charcoal_micro_mass_ / AMOUNT_UNIT_MICRO_MASS;
                    const int64_t reported_char = new_char_units - old_char_units;
                    total_charcoal_produced_ += reported_char;
                    total_smoke_produced_ += amount - reported_char;
                    progress = 0;
                }
            }
            keep_active = true;
        } else if (material == RAW_FOOD && temperature >= FOOD_COOK_TEMPERATURE && temperature < FOOD_BURN_TEMPERATURE) {
            state = OrganicReactionState::COOKING;
            uint16_t &progress = (*chunk->reaction_progress)[index];
            progress = static_cast<uint16_t>(std::min(65535, static_cast<int32_t>(progress) + std::max(1, (temperature - FOOD_COOK_TEMPERATURE) / 3)));
            if (progress >= 3600) {
                set_material_state(cell, COOKED_FOOD, amount, temperature, 0, 0);
                ++total_food_cooked_;
                progress = 0;
            }
            keep_active = true;
        } else if ((material == RAW_FOOD || material == COOKED_FOOD) && temperature >= FOOD_BURN_TEMPERATURE) {
            state = OrganicReactionState::BURNING_FOOD;
            uint16_t &progress = (*chunk->reaction_progress)[index];
            progress = static_cast<uint16_t>(std::min(65535, static_cast<int32_t>(progress) + std::max(1, (temperature - FOOD_BURN_TEMPERATURE) / 2)));
            if (progress >= 2400) {
                set_material_state(cell, BURNT_FOOD, amount, temperature, 0, 0);
                ++total_food_burned_;
                progress = 0;
            }
            keep_active = true;
        } else if (is_combustible_material(material) && temperature >= definition.ignition_temperature && oxygen >= LOW_OXIDIZER) {
            state = OrganicReactionState::BURNING;
            const int32_t fuel = std::min(amount, static_cast<int32_t>(definition.burn_rate));
            const int32_t oxygen_mass = material == CHARCOAL ? (fuel * 3 + 3) / 4 : (fuel + 1) / 2;
            const int64_t reaction_micro_mass = static_cast<int64_t>(fuel + oxygen_mass) * AMOUNT_UNIT_MICRO_MASS;
            const int64_t ash_micro_mass = static_cast<int64_t>(fuel) * AMOUNT_UNIT_MICRO_MASS * definition.ash_yield / 255;
            const int64_t smoke_micro_mass = reaction_micro_mass - ash_micro_mass;
            const auto existing_ledger = fractional_ledgers_.find(key);
            const int64_t pending_ash = existing_ledger == fractional_ledgers_.end() ? 0 : composition_total(existing_ledger->second.pending[2]);
            const int64_t pending_smoke = existing_ledger == fractional_ledgers_.end() ? 0 : composition_total(existing_ledger->second.pending[1]);
            const int32_t ash_mass = static_cast<int32_t>((pending_ash + ash_micro_mass) / AMOUNT_UNIT_MICRO_MASS);
            const int32_t smoke_mass = static_cast<int32_t>((pending_smoke + smoke_micro_mass) / AMOUNT_UNIT_MICRO_MASS);
            int32_t ash_existing_capacity = 0, smoke_existing_capacity = 0, empty_slots = 0;
            const bool footprint_inside_chunk = local.x >= 2 && local.x + 2 < CHUNK_SIZE && local.y >= 2 && local.y + 2 < CHUNK_SIZE;
            if (footprint_inside_chunk && product_capacity_chunks.find(chunk_key(chunk->coordinate)) == product_capacity_chunks.end()) {
                // A completely full local chunk cannot accept either physical byproduct.
            } else if (footprint_inside_chunk) {
                for (int32_t y = -2; y <= 2; ++y) for (int32_t x = -2; x <= 2; ++x) {
                    if ((x == 0 && y == 0) || std::abs(x) + std::abs(y) > 3) continue;
                    const int32_t product_index = index + y * CHUNK_SIZE + x;
                    if (chunk->structures != nullptr && ((*chunk->structures)[product_index] & 0x7fu) != 0) continue;
                    const int32_t existing = chunk->material[product_index];
                    if (existing == EMPTY) ++empty_slots;
                    else if (existing == ASH) ash_existing_capacity += 255 - material_amount_at(*chunk, product_index);
                    else if (existing == SMOKE) smoke_existing_capacity += 255 - material_amount_at(*chunk, product_index);
                }
            } else {
                for (int32_t y = -2; y <= 2; ++y) for (int32_t x = -2; x <= 2; ++x) {
                    if ((x == 0 && y == 0) || std::abs(x) + std::abs(y) > 3) continue;
                    const Vector2i product_cell = cell + Vector2i(x, y);
                    if (is_structure_solid(product_cell)) continue;
                    const int32_t existing = get_cell(product_cell);
                    if (existing == EMPTY) ++empty_slots;
                    else if (existing == ASH) ash_existing_capacity += 255 - material_amount_at(product_cell);
                    else if (existing == SMOKE) smoke_existing_capacity += 255 - material_amount_at(product_cell);
                }
            }
            const int32_t ash_empty_slots = (std::max(0, ash_mass - ash_existing_capacity) + 254) / 255;
            const int32_t smoke_empty_slots = (std::max(0, smoke_mass - smoke_existing_capacity) + 254) / 255;
            const bool products_fit = ash_empty_slots + smoke_empty_slots <= empty_slots;
            if (oxygen >= oxygen_mass && products_fit && emit_organic_product(cell, ASH, ash_mass, temperature, false) &&
                emit_organic_product(cell, SMOKE, smoke_mass, temperature, true)) {
                FractionalMassLedger &ledger = fractional_ledgers_[key];
                ledger.id = key;
                ledger.output_material[2] = ASH;
                ledger.output_material[1] = SMOKE;
                const int64_t old_ash_units = total_organic_ash_micro_mass_ / AMOUNT_UNIT_MICRO_MASS;
                ledger.input_micro_mass += reaction_micro_mass;
                ledger.pending[2][5] += ash_micro_mass;
                ledger.pending[1][5] += smoke_micro_mass;
                const int64_t emitted_ash_micro = static_cast<int64_t>(ash_mass) * AMOUNT_UNIT_MICRO_MASS;
                const int64_t emitted_smoke_micro = static_cast<int64_t>(smoke_mass) * AMOUNT_UNIT_MICRO_MASS;
                ledger.pending[2][5] -= emitted_ash_micro;
                ledger.pending[1][5] -= emitted_smoke_micro;
                ledger.emitted_channel_micro_mass[2] += emitted_ash_micro;
                ledger.emitted_channel_micro_mass[1] += emitted_smoke_micro;
                ledger.emitted_micro_mass += emitted_ash_micro + emitted_smoke_micro;
                conservation_input_micro_mass_ += reaction_micro_mass;
                conservation_output_micro_mass_ += emitted_ash_micro + emitted_smoke_micro;
                total_organic_ash_micro_mass_ += ash_micro_mass;
                total_smoke_micro_mass_ += smoke_micro_mass;
                write_oxidizer(oxygen_cell, oxygen - oxygen_mass);
                total_oxygen_consumed_ += oxygen_mass;
                const int64_t heat = static_cast<int64_t>(fuel) * definition.combustion_heat;
                add_cell_energy(cell, heat);
                total_combustion_energy_ += heat;
                const int64_t new_ash_units = total_organic_ash_micro_mass_ / AMOUNT_UNIT_MICRO_MASS;
                const int64_t reported_ash = new_ash_units - old_ash_units;
                total_organic_ash_produced_ += reported_ash;
                total_smoke_produced_ += fuel + oxygen_mass - reported_ash;
                if (material == WOOD || material == LEAVES) total_wood_burned_ += fuel;
                if (material == CHARCOAL) total_charcoal_burned_ += fuel;
                amount -= fuel;
                if (amount <= 0) set_material_state(cell, EMPTY, 0, TEMPERATURE_AMBIENT, 0, 0);
                else set_material_state(cell, material, amount, get_temperature(cell), 0, 0);
                for (const Vector2i offset : std::array<Vector2i,4>{{{0,-1},{-1,0},{1,0},{0,1}}}) {
                    add_cell_energy(cell + offset, heat / 12);
                    activate_reactive_cell(cell + offset);
                }
            }
            // Fully blocked reactions sleep. Any neighboring material change wakes them through set_material_state().
            keep_active = amount > 0 && products_fit;
        }
        if (chunk->reaction_state != nullptr) (*chunk->reaction_state)[index] = static_cast<uint8_t>(state);
        if (keep_active) reactive_cells_.insert(key);
    }
    last_reaction_usec_ = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started);
}

void NativeSandWorld::process_organic_physics() {
    process_fellable_clusters();
    process_reactions();
    process_atmosphere();
}

void NativeSandWorld::reset_organic_physics() {
    next_fellable_cluster_id_ = 1;
    fellable_clusters_.clear(); reactive_cells_.clear(); disturbed_atmosphere_chunks_.clear();
    organic_revision_ = 0;
    last_cluster_usec_ = last_cluster_collision_samples_ = last_atmosphere_usec_ = last_atmosphere_cells_ = 0;
    last_reaction_usec_ = last_reaction_cells_ = 0;
    total_trees_felled_ = total_wood_produced_ = total_wood_burned_ = total_wood_pyrolyzed_ = 0;
    total_charcoal_produced_ = total_charcoal_burned_ = total_organic_ash_produced_ = total_smoke_produced_ = 0;
    total_organic_ash_micro_mass_ = total_smoke_micro_mass_ = total_charcoal_micro_mass_ = 0;
    total_wood_water_evaporated_ = total_food_cooked_ = total_food_burned_ = total_combustion_energy_ = total_oxygen_consumed_ = 0;
}

Dictionary NativeSandWorld::get_organic_statistics() const {
    Dictionary result;
    int64_t moisture_planes = 0, atmosphere_planes = 0, reaction_planes = 0;
    for (const Chunk *chunk : sorted_chunks()) {
        moisture_planes += chunk->organic_moisture != nullptr;
        atmosphere_planes += chunk->oxidizer != nullptr;
        reaction_planes += chunk->reaction_progress != nullptr;
    }
    result["revision"] = static_cast<int64_t>(organic_revision_);
    result["active_clusters"] = static_cast<int64_t>(fellable_clusters_.size());
    result["cluster_usec"] = last_cluster_usec_;
    result["cluster_collision_samples"] = last_cluster_collision_samples_;
    result["reactive_cells"] = static_cast<int64_t>(reactive_cells_.size());
    result["reaction_cells_visited"] = last_reaction_cells_;
    result["reaction_usec"] = last_reaction_usec_;
    result["atmosphere_active_chunks"] = static_cast<int64_t>(disturbed_atmosphere_chunks_.size());
    result["atmosphere_cells_visited"] = last_atmosphere_cells_;
    result["atmosphere_usec"] = last_atmosphere_usec_;
    result["moisture_planes"] = moisture_planes;
    result["moisture_bytes"] = moisture_planes * CELLS_PER_CHUNK;
    result["atmosphere_planes"] = atmosphere_planes;
    result["atmosphere_bytes"] = atmosphere_planes * CELLS_PER_CHUNK;
    result["reaction_planes"] = reaction_planes;
    result["reaction_bytes"] = reaction_planes * CELLS_PER_CHUNK * 3;
    result["trees_felled"] = total_trees_felled_;
    result["wood_produced"] = total_wood_produced_;
    result["wood_burned"] = total_wood_burned_;
    result["wood_pyrolyzed"] = total_wood_pyrolyzed_;
    result["charcoal_produced"] = total_charcoal_produced_;
    result["charcoal_burned"] = total_charcoal_burned_;
    result["ash_produced"] = total_organic_ash_produced_;
    result["smoke_produced"] = total_smoke_produced_;
    result["ash_micro_mass"] = total_organic_ash_micro_mass_;
    result["smoke_micro_mass"] = total_smoke_micro_mass_;
    result["charcoal_micro_mass"] = total_charcoal_micro_mass_;
    result["water_evaporated_from_wood"] = total_wood_water_evaporated_;
    result["food_cooked"] = total_food_cooked_;
    result["food_burned"] = total_food_burned_;
    result["combustion_energy"] = total_combustion_energy_;
    result["oxygen_consumed"] = total_oxygen_consumed_;
    return result;
}

String NativeSandWorld::organic_state_hash() const {
    uint32_t hash = 2166136261u;
    for (const Chunk *chunk : sorted_chunks()) {
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const int32_t material = chunk->material[index];
            if (!is_organic_material(material) && material != ASH) continue;
            hash = mix_int(hash, chunk->coordinate.x); hash = mix_int(hash, chunk->coordinate.y);
            hash = mix_int(hash, index); hash = mix_int(hash, material);
            hash = mix_int(hash, material_amount_at(*chunk, index)); hash = mix_int(hash, chunk->temperature[index]);
            hash = mix_int(hash, chunk->organic_moisture == nullptr ? 0 : (*chunk->organic_moisture)[index]);
            hash = mix_int(hash, chunk->oxidizer == nullptr ? AMBIENT_OXIDIZER : (*chunk->oxidizer)[index]);
            hash = mix_int(hash, chunk->reaction_progress == nullptr ? 0 : (*chunk->reaction_progress)[index]);
        }
    }
    std::vector<uint64_t> ids;
    for (const auto &[id, cluster] : fellable_clusters_) { (void)cluster; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const FellableCluster &cluster = fellable_clusters_.at(id);
        hash = mix_int(hash, static_cast<int32_t>(id)); hash = mix_int(hash, cluster.origin_q10.x);
        hash = mix_int(hash, cluster.origin_q10.y); hash = mix_int(hash, cluster.angle_q16);
        for (const FellableClusterCell &cell : cluster.cells) {
            hash = mix_int(hash, cell.x); hash = mix_int(hash, cell.y); hash = mix_int(hash, cell.material);
            hash = mix_int(hash, cell.temperature); hash = mix_int(hash, cell.amount); hash = mix_int(hash, cell.moisture);
        }
    }
    char buffer[16]; std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

Dictionary NativeSandWorld::configure_phase12_benchmark(int32_t scenario, int32_t count) {
    Dictionary result;
    count = std::clamp(count, 1, 1000000);
    result["scenario"] = scenario;
    result["requested"] = count;
    if (scenario == 0) {
        result["standing_trees"] = count;
        result["simulation_records"] = 0;
        result["idle_work"] = 0;
    } else if (scenario == 1) {
        for (int32_t i = 0; i < count; ++i) {
            FellableCluster cluster;
            cluster.id = next_fellable_cluster_id_++;
            cluster.origin_q10 = Vector2i((i % 1000) * 32, i / 1000 * 32) * Q10;
            cluster.fall_direction = (i & 1) == 0 ? 1 : -1;
            for (int32_t y = 0; y < 16; ++y) cluster.cells.push_back({0, static_cast<int16_t>(-y), WOOD, TEMPERATURE_AMBIENT, 255, 32});
            fellable_clusters_.emplace(cluster.id, std::move(cluster));
        }
        result["active_clusters"] = static_cast<int64_t>(fellable_clusters_.size());
    } else if (scenario == 2) {
        result["ambient_cells"] = count;
        result["explicit_planes"] = 0;
        result["explicit_work"] = 0;
    } else {
        const int32_t width = 512;
        const int32_t material = scenario == 3 ? EMPTY : scenario == 4 ? WOOD : scenario == 5 ? SMOKE : scenario == 6 ? WOOD : scenario == 8 ? WOOD : RAW_FOOD;
        const int32_t temperature = scenario == 4 ? 2300 : scenario == 6 ? 2100 : scenario == 7 ? 1600 : TEMPERATURE_AMBIENT;
        for (int32_t i = 0; i < count; ++i) {
            const Vector2i cell{i % width, i / width};
            set_material_state(cell, material, material == EMPTY ? 0 : 255, temperature, 0, 0);
            if (scenario == 3) write_oxidizer(cell, (i & 1) == 0 ? 64 : 192);
            if (scenario == 4) write_oxidizer(cell, AMBIENT_OXIDIZER);
            if (scenario == 4 || scenario == 6 || scenario == 7) activate_reactive_cell(cell);
        }
        result["configured_cells"] = count;
    }
    return result;
}

void NativeSandWorld::apply_organic_features_to_generated(GeneratedChunk &generated) const {
    constexpr int32_t BIN_WIDTH = 28;
    const Vector2i origin = generated.coordinate * CHUNK_SIZE;
    const int32_t first_bin = floor_div(origin.x - 32, BIN_WIDTH);
    const int32_t last_bin = floor_div(origin.x + CHUNK_SIZE + 32, BIN_WIDTH);
    for (int32_t bin = first_bin; bin <= last_bin; ++bin) {
        const int32_t anchor_x = bin * BIN_WIDTH + 5 + static_cast<int32_t>(hash_2d(seed_, {bin, 0}, 0x71b1) % 19u);
        if (std::abs(anchor_x) < 160) continue;
        const int32_t surface = surface_height_at_v2(anchor_x);
        const int32_t slope = std::abs(surface_height_at_v2(anchor_x - 2) - surface_height_at_v2(anchor_x + 2));
        const MacroSample macro = macro_sample_for(seed_, {floor_div(anchor_x, 64), 0});
        const uint32_t placement = hash_2d(seed_, {bin, static_cast<int32_t>(macro.feature_density)}, 0x71b3);
        const int32_t vegetation = static_cast<int32_t>(macro.feature_density) + static_cast<int32_t>(macro.aquifer_strength) / 3;
        if (slope > 4 || vegetation < 26000 || placement % 100u >= 63u) continue;
        const int32_t height = 12 + static_cast<int32_t>(placement % 11u);
        const int32_t thickness = height >= 19 && ((placement >> 8u) & 1u) != 0u ? 2 : 1;
        const int32_t canopy_radius = 4 + static_cast<int32_t>((placement >> 10u) % 3u);
        const int32_t moisture = 24 + static_cast<int32_t>((macro.aquifer_strength + macro.water_table * 67u) % 65u);
        for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
            const Vector2i cell = origin + Vector2i(local_x, local_y);
            bool wood = cell.y >= surface - height && cell.y < surface && cell.x >= anchor_x && cell.x < anchor_x + thickness;
            const Vector2i canopy_center{anchor_x + thickness / 2, surface - height + 2};
            const Vector2i delta = cell - canopy_center;
            bool leaves = delta.x * delta.x * 3 + delta.y * delta.y * 4 <= canopy_radius * canopy_radius * 4;
            const int32_t branch_y = surface - height / 2;
            if (cell.y == branch_y && std::abs(cell.x - anchor_x) <= 3 + static_cast<int32_t>((placement >> 15u) & 3u)) wood = true;
            if (!wood && !leaves) continue;
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            if (generated.material[index] != EMPTY) continue;
            generated.material[index] = static_cast<uint16_t>(wood ? WOOD : LEAVES);
            if (generated.organic_moisture == nullptr) {
                generated.organic_moisture = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
                generated.organic_moisture->fill(0);
            }
            (*generated.organic_moisture)[index] = static_cast<uint8_t>(wood ? moisture : moisture / 2);
        }
    }

    // Sparse physical mushroom specimens share the authored feature path and become Raw Food matter directly.
    for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
        const int32_t world_x = origin.x + local_x;
        if ((hash_2d(seed_, {world_x, generated.coordinate.y}, 0x71c1) % 257u) != 0u) continue;
        for (int32_t local_y = 1; local_y < CHUNK_SIZE - 1; ++local_y) {
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            if (generated.material[index] == EMPTY && generated.material[index + CHUNK_SIZE] != EMPTY) {
                generated.material[index] = RAW_FOOD;
                break;
            }
        }
    }
}
}
