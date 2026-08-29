#include "native_sand_world.hpp"

#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <cstdio>
#include <unordered_map>

namespace godot {

namespace {
constexpr int32_t BATCH_OP_PLACE = 1;
constexpr int32_t BATCH_OP_REMOVE = 2;
constexpr int32_t BATCH_ATOMIC = 0;
constexpr int32_t BATCH_REASON_INVALID = 1;
constexpr int32_t BATCH_REASON_VALIDATION = 2;
constexpr int32_t BATCH_REASON_APPLICATION = 3;
}

Dictionary NativeSandWorld::apply_structure_batch(PackedInt32Array operations, int32_t validation_mode) {
    Dictionary result;
    PackedInt32Array reasons;
    result["applied"] = 0;
    result["rejected"] = 0;
    result["reason_codes"] = reasons;
    result["affected_region"] = Rect2i();
    result["validation_usec"] = 0;
    result["application_usec"] = 0;
    if (operations.is_empty() || operations.size() % 5 != 0 || (validation_mode != 0 && validation_mode != 1)) {
        reasons.push_back(BATCH_REASON_INVALID);
        result["rejected"] = std::max<int64_t>(1, operations.size() / 5);
        result["reason_codes"] = reasons;
        return result;
    }

    const int32_t count = operations.size() / 5;
    Vector2i minimum{operations[2], operations[3]};
    Vector2i maximum = minimum;
    for (int32_t index = 0; index < count; ++index) {
        const int32_t offset = index * 5;
        const Vector2i position{operations[offset + 2], operations[offset + 3]};
        minimum.x = std::min(minimum.x, position.x);
        minimum.y = std::min(minimum.y, position.y);
        maximum.x = std::max(maximum.x, position.x);
        maximum.y = std::max(maximum.y, position.y);
    }
    result["affected_region"] = Rect2i(minimum, maximum - minimum + Vector2i(1, 1));

    const uint64_t validation_started = Time::get_singleton()->get_ticks_usec();
    std::unordered_map<uint64_t, int32_t> shadow;
    auto shadow_structure = [this, &shadow](Vector2i cell) {
        const auto found = shadow.find(cell_key(cell));
        return found == shadow.end() ? get_structure(cell) : found->second;
    };
    auto reject_atomic = [&result, &reasons, count, validation_started]() {
        reasons.push_back(BATCH_REASON_VALIDATION);
        result["applied"] = 0;
        result["rejected"] = count;
        result["reason_codes"] = reasons;
        result["validation_usec"] = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - validation_started);
        return result;
    };

    if (validation_mode == BATCH_ATOMIC) {
        for (int32_t index = 0; index < count; ++index) {
            const int32_t offset = index * 5;
            const int32_t operation = operations[offset];
            const int32_t type_id = operations[offset + 1];
            const Vector2i position{operations[offset + 2], operations[offset + 3]};
            const int32_t orientation = operations[offset + 4];
            if (operation == BATCH_OP_REMOVE) {
                const int32_t existing = shadow_structure(position);
                if (existing == 0) return reject_atomic();
                const StructureDefinition *definition = structure_definition(existing);
                if (definition == nullptr) return reject_atomic();
                if (definition->tile_like) {
                    shadow[cell_key(position)] = 0;
                    continue;
                }
                bool found_entity = false;
                for (const auto &[id, entity] : machine_entities_) {
                    (void)id;
                    if (entity.type_id != existing) continue;
                    const std::vector<Vector2i> occupied = transformed_occupied(*definition, entity.origin, entity.orientation);
                    if (std::find(occupied.begin(), occupied.end(), position) == occupied.end()) continue;
                    if (is_processing_machine(entity.type_id) &&
                        (entity.input_material != 0 || entity.result_material != 0 || entity.ash_material != 0 || entity.fuel_remaining > 0)) return reject_atomic();
                    for (const Vector2i cell : occupied) shadow[cell_key(cell)] = 0;
                    found_entity = true;
                    break;
                }
                if (!found_entity) return reject_atomic();
                continue;
            }
            if (operation != BATCH_OP_PLACE) return reject_atomic();
            const StructureDefinition *definition = structure_definition(type_id);
            if (definition == nullptr || !structure_unlocked(type_id)) return reject_atomic();
            const std::vector<Vector2i> occupied = transformed_occupied(*definition, position, orientation);
            if (!ensure_structure_chunks_generated(occupied)) return reject_atomic();
            for (const Vector2i cell : occupied) {
                if (get_cell(cell) != 0 || shadow_structure(cell) != 0) return reject_atomic();
            }
            for (const Vector2i cell : occupied) shadow[cell_key(cell)] = type_id;
        }
    }
    result["validation_usec"] = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - validation_started);

    const uint64_t application_started = Time::get_singleton()->get_ticks_usec();
    int32_t applied = 0;
    int32_t rejected = 0;
    for (int32_t index = 0; index < count; ++index) {
        const int32_t offset = index * 5;
        const int32_t operation = operations[offset];
        const int32_t type_id = operations[offset + 1];
        const Vector2i position{operations[offset + 2], operations[offset + 3]};
        const int32_t orientation = operations[offset + 4];
        bool success = false;
        if (operation == BATCH_OP_PLACE) success = place_structure(type_id, position, orientation) > 0;
        else if (operation == BATCH_OP_REMOVE) success = remove_structure_at(position) > 0;
        if (success) ++applied;
        else {
            ++rejected;
            reasons.push_back(BATCH_REASON_APPLICATION);
            if (validation_mode == BATCH_ATOMIC) break;
        }
    }
    result["applied"] = applied;
    result["rejected"] = rejected;
    result["reason_codes"] = reasons;
    result["application_usec"] = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - application_started);
    return result;
}

void NativeSandWorld::reset_subsurface_logistics() {
    next_linked_transport_id_ = 1;
    linked_transports_.clear();
    for (auto &depth : subsurface_occupancy_) depth.clear();
    subsurface_endpoint_channels_.clear();
    subsurface_cell_watchers_.clear();
    active_linked_transports_.clear();
    subsurface_revision_ = 0;
    last_subsurface_active_ = last_subsurface_visited_ = last_subsurface_moves_ = last_subsurface_blocked_ = 0;
    last_subsurface_usec_ = total_subsurface_moves_ = 0;
}

bool NativeSandWorld::subsurface_unlocked(int32_t depth) const {
    if (game_mode_ == 1) return true;
    if (depth == 0) return has_research("logistics.subsurface_1");
    if (depth == 1) return has_research("logistics.subsurface_2");
    if (depth == 2) return has_research("logistics.subsurface_3");
    return false;
}

bool NativeSandWorld::can_place_subsurface_channel(int32_t depth, Vector2i entrance, Vector2i exit) const {
    if (depth < 0 || depth >= 3 || !subsurface_unlocked(depth)) return false;
    const Vector2i delta = exit - entrance;
    if ((delta.x == 0) == (delta.y == 0)) return false;
    const int32_t distance = std::abs(delta.x) + std::abs(delta.y);
    if (distance < 2 || distance > 65) return false;
    if (world_generation_enabled_ && (!is_inside_virtual_world(entrance) || !is_inside_virtual_world(exit) ||
        !is_chunk_generated(world_to_chunk(entrance)) || !is_chunk_generated(world_to_chunk(exit)))) return false;
    if (get_cell(entrance) != 0 || get_cell(exit) != 0 || get_structure(entrance) != 0 || get_structure(exit) != 0) return false;
    const Vector2i direction{delta.x == 0 ? 0 : (delta.x > 0 ? 1 : -1), delta.y == 0 ? 0 : (delta.y > 0 ? 1 : -1)};
    for (int32_t offset = 0; offset <= distance; ++offset) {
        if (subsurface_occupancy_[depth].contains(cell_key(entrance + direction * offset))) return false;
    }
    return true;
}

int64_t NativeSandWorld::place_subsurface_channel(int32_t depth, Vector2i entrance, Vector2i exit) {
    std::vector<Vector2i> endpoint_cells{entrance, exit};
    if (!ensure_structure_chunks_generated(endpoint_cells) || !can_place_subsurface_channel(depth, entrance, exit)) return 0;
    const Vector2i delta = exit - entrance;
    const int32_t distance = std::abs(delta.x) + std::abs(delta.y);
    const Vector2i direction{delta.x == 0 ? 0 : (delta.x > 0 ? 1 : -1), delta.y == 0 ? 0 : (delta.y > 0 ? 1 : -1)};
    const int32_t orientation = direction == Vector2i(1, 0) ? 0 : direction == Vector2i(0, 1) ? 1 : direction == Vector2i(-1, 0) ? 2 : 3;
    const uint8_t entrance_type = static_cast<uint8_t>(18 + depth * 2);
    const uint8_t exit_type = static_cast<uint8_t>(19 + depth * 2);
    const uint64_t id = next_linked_transport_id_++;
    LinkedTransportRun run;
    run.id = id;
    run.entrance = entrance;
    run.exit = exit;
    run.direction = direction;
    run.depth = static_cast<uint8_t>(depth);
    run.lane.resize(distance - 1);
    run.entrance_endpoint = LinkedTransportEndpoint{id * 2, id, entrance, direction, LinkedTransportKind::SUBSURFACE,
                                                     static_cast<uint8_t>(depth), LinkedEndpointRole::ENTRANCE, 0};
    run.exit_endpoint = LinkedTransportEndpoint{id * 2 + 1, id, exit, direction, LinkedTransportKind::SUBSURFACE,
                                                 static_cast<uint8_t>(depth), LinkedEndpointRole::EXIT, 0};
    linked_transports_.emplace(id, std::move(run));
    for (int32_t offset = 0; offset <= distance; ++offset) subsurface_occupancy_[depth][cell_key(entrance + direction * offset)] = id;
    subsurface_endpoint_channels_[cell_key(entrance)] = id;
    subsurface_endpoint_channels_[cell_key(exit)] = id;
    subsurface_cell_watchers_[cell_key(entrance - direction)].push_back(id);
    subsurface_cell_watchers_[cell_key(exit + direction)].push_back(id);
    set_structure_cell(entrance, entrance_type);
    set_structure_cell(exit, exit_type);
    active_linked_transports_.insert(id);
    ++subsurface_revision_;
    (void)orientation;
    return static_cast<int64_t>(id);
}

bool NativeSandWorld::remove_subsurface_channel(int64_t channel_id, int32_t removal_policy) {
    if (channel_id <= 0 || (removal_policy != 0 && removal_policy != 1)) return false;
    const auto found = linked_transports_.find(static_cast<uint64_t>(channel_id));
    if (found == linked_transports_.end()) return false;
    const LinkedTransportRun &run = found->second;
    for (const MaterialPacket &packet : run.lane) if (packet.occupied()) return false;
    const int32_t distance = std::abs(run.exit.x - run.entrance.x) + std::abs(run.exit.y - run.entrance.y);
    for (int32_t offset = 0; offset <= distance; ++offset) subsurface_occupancy_[run.depth].erase(cell_key(run.entrance + run.direction * offset));
    subsurface_endpoint_channels_.erase(cell_key(run.entrance));
    subsurface_endpoint_channels_.erase(cell_key(run.exit));
    const std::array<Vector2i, 2> watched{{run.entrance - run.direction, run.exit + run.direction}};
    for (const Vector2i cell : watched) {
        auto watcher = subsurface_cell_watchers_.find(cell_key(cell));
        if (watcher == subsurface_cell_watchers_.end()) continue;
        auto &ids = watcher->second;
        ids.erase(std::remove(ids.begin(), ids.end(), run.id), ids.end());
        if (ids.empty()) subsurface_cell_watchers_.erase(watcher);
    }
    clear_structure_cell(run.entrance);
    clear_structure_cell(run.exit);
    active_linked_transports_.erase(run.id);
    linked_transports_.erase(found);
    ++subsurface_revision_;
    return true;
}

void NativeSandWorld::wake_subsurface_at(Vector2i world_cell) {
    const auto found = subsurface_cell_watchers_.find(cell_key(world_cell));
    if (found == subsurface_cell_watchers_.end()) return;
    for (const uint64_t id : found->second) active_linked_transports_.insert(id);
}

void NativeSandWorld::process_subsurface_logistics() {
    const uint64_t started = Time::get_singleton()->get_ticks_usec();
    std::vector<uint64_t> ids(active_linked_transports_.begin(), active_linked_transports_.end());
    std::sort(ids.begin(), ids.end());
    active_linked_transports_.clear();
    last_subsurface_active_ = static_cast<int64_t>(ids.size());
    last_subsurface_visited_ = last_subsurface_moves_ = last_subsurface_blocked_ = 0;
    for (const uint64_t id : ids) {
        auto found = linked_transports_.find(id);
        if (found == linked_transports_.end()) continue;
        LinkedTransportRun &run = found->second;
        ++last_subsurface_visited_;
        bool changed = false;
        MaterialPacket &last = run.lane.back();
        const Vector2i output = run.exit + run.direction;
        if (last.occupied()) {
            if (is_empty_for_material(output)) {
                if (set_cell_with_metadata(output, last.material, last.provenance, last.mineral_signature) == 0) {
                    Chunk *chunk = get_chunk(world_to_chunk(output));
                    if (chunk != nullptr) chunk->temperature[local_index(world_to_local(output))] = last.temperature;
                    mark_moved_this_tick(output);
                    last = MaterialPacket{};
                    ++last_subsurface_moves_;
                    changed = true;
                }
            } else {
                ++last_subsurface_blocked_;
            }
        }
        for (int32_t index = static_cast<int32_t>(run.lane.size()) - 1; index > 0; --index) {
            if (!run.lane[index].occupied() && run.lane[index - 1].occupied()) {
                run.lane[index] = run.lane[index - 1];
                run.lane[index - 1] = MaterialPacket{};
                ++last_subsurface_moves_;
                changed = true;
            }
        }
        const Vector2i input = run.entrance - run.direction;
        if (!run.lane.front().occupied() && material_transportable(get_cell(input)) && !moved_this_tick(input)) {
            Chunk *chunk = get_chunk(world_to_chunk(input));
            if (chunk != nullptr) {
                const int32_t index = local_index(world_to_local(input));
                run.lane.front() = MaterialPacket{chunk->material[index], chunk->temperature[index], chunk->provenance[index], chunk->mineral_signature[index]};
                set_cell_with_metadata(input, 0, 0, 0);
                ++last_subsurface_moves_;
                changed = true;
            }
        }
        bool occupied = false;
        for (const MaterialPacket &packet : run.lane) occupied = occupied || packet.occupied();
        if (occupied || material_transportable(get_cell(input))) active_linked_transports_.insert(id);
        if (changed) ++subsurface_revision_;
    }
    total_subsurface_moves_ += last_subsurface_moves_;
    last_subsurface_usec_ = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started);
}

Dictionary NativeSandWorld::get_subsurface_channel_state(int64_t channel_id) const {
    Dictionary result;
    const auto found = linked_transports_.find(static_cast<uint64_t>(channel_id));
    if (found == linked_transports_.end()) return result;
    const LinkedTransportRun &run = found->second;
    int32_t occupied = 0;
    for (const MaterialPacket &packet : run.lane) occupied += packet.occupied() ? 1 : 0;
    result["channel_id"] = channel_id;
    result["depth"] = static_cast<int32_t>(run.depth);
    result["depth_label"] = run.depth == 0 ? "I" : run.depth == 1 ? "II" : "III";
    result["entrance"] = run.entrance;
    result["exit"] = run.exit;
    result["direction"] = run.direction;
    result["lane_cells"] = static_cast<int32_t>(run.lane.size());
    result["occupied_packets"] = occupied;
    result["jammed"] = run.lane.back().occupied() && !is_empty_for_material(run.exit + run.direction);
    result["active"] = active_linked_transports_.contains(run.id);
    result["removal_policy"] = "MUST_DRAIN";
    result["entrance_endpoint_id"] = static_cast<int64_t>(run.entrance_endpoint.id);
    result["exit_endpoint_id"] = static_cast<int64_t>(run.exit_endpoint.id);
    result["linked_transport_kind"] = "SUBSURFACE";
    return result;
}

const NativeSandWorld::PermeabilityRule &NativeSandWorld::fine_screen_permeability_rule() {
    static const PermeabilityRule rule{static_cast<uint16_t>(1u << 2u), 0, 0, 65535, 0, 0, 0, 0, 0, 0};
    return rule;
}

bool NativeSandWorld::permeability_allows(const PermeabilityRule &rule, int32_t material_id, int32_t provenance, uint16_t signature) const {
    if (material_id < 0 || material_id >= 16) return false;
    const uint16_t bit = static_cast<uint16_t>(1u << static_cast<uint32_t>(material_id));
    if ((rule.allowed_material_mask & bit) == 0 || (rule.blocked_material_mask & bit) != 0) return false;
    if (provenance < rule.minimum_provenance || provenance > rule.maximum_provenance) return false;
    if (rule.signature_mask != 0 && (signature & rule.signature_mask) != rule.signature_value) return false;
    const int32_t grain = grain_size_class(material_id, provenance, signature);
    return grain >= rule.minimum_grain_class && grain <= rule.maximum_grain_class;
}

Dictionary NativeSandWorld::get_factory_foundation_architecture() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["material_packet_bytes"] = static_cast<int32_t>(sizeof(MaterialPacket));
    result["linked_transport_endpoint_bytes"] = static_cast<int32_t>(sizeof(LinkedTransportEndpoint));
    result["permeability_rule_bytes"] = static_cast<int32_t>(sizeof(PermeabilityRule));
    result["physical_field_source_bytes"] = static_cast<int32_t>(sizeof(PhysicalFieldSource));
    Array field_kinds;
    field_kinds.push_back("MAGNETIC"); field_kinds.push_back("AIRFLOW"); field_kinds.push_back("HEAT_SOURCE");
    field_kinds.push_back("GRAVITY_MODIFIER"); field_kinds.push_back("RADIATION");
    result["physical_field_kinds"] = field_kinds;
    Array linked_kinds;
    linked_kinds.push_back("SUBSURFACE"); linked_kinds.push_back("PORTAL_FUTURE");
    result["linked_transport_kinds"] = linked_kinds;
    result["portal_implemented"] = false;
    result["fan_implemented"] = false;
    result["heat_switch_implemented"] = true;
    result["fine_screen_rule"] = "material=SAND grain_class=0";
    return result;
}

void NativeSandWorld::reset_production_statistics() {
    production_buckets_.clear();
    production_buckets_.resize(1800);
    production_lifetime_produced_.fill(0);
    production_lifetime_consumed_.fill(0);
    production_lifetime_flows_.fill(0);
    production_events_total_ = 0;
}

void NativeSandWorld::record_production_event(int32_t material_id, int64_t amount, bool produced) {
    if (material_id <= 0 || material_id >= MATERIAL_COUNT || amount <= 0 || production_buckets_.empty()) return;
    const int64_t second = tick_index_ / 60;
    ProductionBucket &bucket = production_buckets_[static_cast<size_t>(second % static_cast<int64_t>(production_buckets_.size()))];
    if (bucket.second != second) {
        bucket.second = second;
        bucket.produced.fill(0);
        bucket.consumed.fill(0);
        bucket.flows.fill(0);
    }
    if (produced) {
        bucket.produced[material_id] += amount;
        production_lifetime_produced_[material_id] += amount;
    } else {
        bucket.consumed[material_id] += amount;
        production_lifetime_consumed_[material_id] += amount;
    }
    ++production_events_total_;
}

void NativeSandWorld::record_production_flow(ProductionFlowKind kind, int64_t amount) {
    const size_t flow = static_cast<size_t>(kind);
    if (flow >= production_lifetime_flows_.size() || amount <= 0 || production_buckets_.empty()) return;
    const int64_t second = tick_index_ / 60;
    ProductionBucket &bucket = production_buckets_[static_cast<size_t>(second % static_cast<int64_t>(production_buckets_.size()))];
    if (bucket.second != second) {
        bucket.second = second;
        bucket.produced.fill(0);
        bucket.consumed.fill(0);
        bucket.flows.fill(0);
    }
    bucket.flows[flow] += amount;
    production_lifetime_flows_[flow] += amount;
    ++production_events_total_;
}

bool NativeSandWorld::record_production_event_for_test(int32_t material_id, int64_t amount, bool produced) {
    if (material_id <= 0 || material_id >= MATERIAL_COUNT || amount <= 0) return false;
    record_production_event(material_id, amount, produced);
    return true;
}

Dictionary NativeSandWorld::get_production_statistics() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["events_total"] = production_events_total_;
    result["bucket_seconds"] = 1;
    result["retention_seconds"] = static_cast<int64_t>(production_buckets_.size());
    const int64_t now = tick_index_ / 60;
    Array materials;
    for (int32_t material = 1; material < MATERIAL_COUNT; ++material) {
        int64_t produced_1m = 0, produced_5m = 0, produced_30m = 0;
        int64_t consumed_1m = 0, consumed_5m = 0, consumed_30m = 0;
        for (const ProductionBucket &bucket : production_buckets_) {
            if (bucket.second < 0 || bucket.second > now) continue;
            const int64_t age = now - bucket.second;
            if (age < 1800) { produced_30m += bucket.produced[material]; consumed_30m += bucket.consumed[material]; }
            if (age < 300) { produced_5m += bucket.produced[material]; consumed_5m += bucket.consumed[material]; }
            if (age < 60) { produced_1m += bucket.produced[material]; consumed_1m += bucket.consumed[material]; }
        }
        Dictionary entry;
        entry["material_id"] = material;
        entry["produced_1m"] = produced_1m; entry["produced_5m"] = produced_5m; entry["produced_30m"] = produced_30m;
        entry["produced_lifetime"] = production_lifetime_produced_[material];
        entry["consumed_1m"] = consumed_1m; entry["consumed_5m"] = consumed_5m; entry["consumed_30m"] = consumed_30m;
        entry["consumed_lifetime"] = production_lifetime_consumed_[material];
        materials.push_back(entry);
    }
    result["materials"] = materials;
    static constexpr std::array<const char *, 6> FLOW_IDS{{
        "water_world_to_pipe", "water_pipe_to_world", "pipe_throughput", "wet_processing_throughput", "research_bank_deposit",
        "steam_pipe_throughput"
    }};
    Array flows;
    for (size_t flow = 0; flow < FLOW_IDS.size(); ++flow) {
        int64_t value_1m = 0, value_5m = 0, value_30m = 0;
        for (const ProductionBucket &bucket : production_buckets_) {
            if (bucket.second < 0 || bucket.second > now) continue;
            const int64_t age = now - bucket.second;
            if (age < 1800) value_30m += bucket.flows[flow];
            if (age < 300) value_5m += bucket.flows[flow];
            if (age < 60) value_1m += bucket.flows[flow];
        }
        Dictionary entry;
        entry["id"] = FLOW_IDS[flow];
        entry["value_1m"] = value_1m;
        entry["value_5m"] = value_5m;
        entry["value_30m"] = value_30m;
        entry["value_lifetime"] = production_lifetime_flows_[flow];
        flows.push_back(entry);
    }
    result["flows"] = flows;
    return result;
}

Dictionary NativeSandWorld::benchmark_production_events(int32_t event_count) {
    Dictionary result;
    event_count = std::clamp(event_count, 1, 10000000);
    const uint64_t started = Time::get_singleton()->get_ticks_usec();
    for (int32_t index = 0; index < event_count; ++index) record_production_event(1 + index % 15, 1, (index & 1) == 0);
    const int64_t elapsed = static_cast<int64_t>(Time::get_singleton()->get_ticks_usec() - started);
    result["events"] = event_count;
    result["usec"] = elapsed;
    result["nanoseconds_per_event"] = static_cast<double>(elapsed) * 1000.0 / static_cast<double>(event_count);
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_subsurface_routes(Rect2i cell_area) const {
    PackedInt32Array result;
    std::vector<uint64_t> ids;
    ids.reserve(linked_transports_.size());
    for (const auto &[id, run] : linked_transports_) { (void)run; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const LinkedTransportRun &run = linked_transports_.at(id);
        const Vector2i minimum{std::min(run.entrance.x, run.exit.x), std::min(run.entrance.y, run.exit.y)};
        const Vector2i maximum{std::max(run.entrance.x, run.exit.x), std::max(run.entrance.y, run.exit.y)};
        if (!cell_area.intersects(Rect2i(minimum, maximum - minimum + Vector2i(1, 1)))) continue;
        int32_t occupied = 0;
        for (const MaterialPacket &packet : run.lane) occupied += packet.occupied() ? 1 : 0;
        result.push_back(static_cast<int32_t>(id));
        result.push_back(static_cast<int32_t>(id >> 32u));
        result.push_back(run.depth);
        result.push_back(run.entrance.x); result.push_back(run.entrance.y);
        result.push_back(run.exit.x); result.push_back(run.exit.y);
        result.push_back(occupied);
        result.push_back(static_cast<int32_t>(run.lane.size()));
        result.push_back(active_linked_transports_.contains(id) ? 1 : 0);
    }
    return result;
}

Dictionary NativeSandWorld::get_subsurface_statistics() const {
    Dictionary result;
    int64_t packet_capacity = 0;
    int64_t occupied = 0;
    std::array<int64_t, 3> depth_runs{{0, 0, 0}};
    for (const auto &[id, run] : linked_transports_) {
        (void)id;
        ++depth_runs[run.depth];
        packet_capacity += static_cast<int64_t>(run.lane.size());
        for (const MaterialPacket &packet : run.lane) occupied += packet.occupied() ? 1 : 0;
    }
    result["channels_total"] = static_cast<int64_t>(linked_transports_.size());
    result["depth_I"] = depth_runs[0]; result["depth_II"] = depth_runs[1]; result["depth_III"] = depth_runs[2];
    result["packet_capacity"] = packet_capacity;
    result["packets_occupied"] = occupied;
    result["packet_bytes"] = static_cast<int32_t>(sizeof(MaterialPacket));
    result["packet_backing_bytes"] = packet_capacity * static_cast<int64_t>(sizeof(MaterialPacket));
    result["active"] = last_subsurface_active_;
    result["visited"] = last_subsurface_visited_;
    result["moves"] = last_subsurface_moves_;
    result["blocked"] = last_subsurface_blocked_;
    result["usec"] = last_subsurface_usec_;
    result["total_moves"] = total_subsurface_moves_;
    result["revision"] = static_cast<int64_t>(subsurface_revision_);
    return result;
}

bool NativeSandWorld::seed_subsurface_packet_for_test(int64_t channel_id, int32_t lane_index, int32_t material_id,
                                                       int32_t temperature, int32_t provenance, int32_t signature) {
    auto found = linked_transports_.find(static_cast<uint64_t>(channel_id));
    if (found == linked_transports_.end() || lane_index < 0 || lane_index >= static_cast<int32_t>(found->second.lane.size()) ||
        !material_transportable(material_id) || temperature < 0 || temperature > TEMPERATURE_MAX || provenance < 0 || provenance > 65535 || signature < 0 || signature > 65535) return false;
    MaterialPacket &packet = found->second.lane[lane_index];
    if (packet.occupied()) return false;
    packet = MaterialPacket{static_cast<uint16_t>(material_id), static_cast<uint16_t>(temperature), static_cast<uint16_t>(provenance), static_cast<uint16_t>(signature)};
    active_linked_transports_.insert(found->first);
    ++subsurface_revision_;
    return true;
}

Dictionary NativeSandWorld::serialize_subsurface_state() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["next_channel_id"] = static_cast<int64_t>(next_linked_transport_id_);
    Array channels;
    std::vector<uint64_t> ids;
    for (const auto &[id, run] : linked_transports_) { (void)run; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const LinkedTransportRun &run = linked_transports_.at(id);
        Dictionary channel;
        channel["channel_id"] = static_cast<int64_t>(id);
        channel["depth"] = static_cast<int32_t>(run.depth);
        channel["entrance"] = run.entrance;
        channel["exit"] = run.exit;
        PackedInt32Array packets;
        packets.resize(static_cast<int64_t>(run.lane.size()) * 4);
        for (int32_t index = 0; index < static_cast<int32_t>(run.lane.size()); ++index) {
            const MaterialPacket &packet = run.lane[index];
            packets[index * 4] = packet.material;
            packets[index * 4 + 1] = packet.temperature;
            packets[index * 4 + 2] = packet.provenance;
            packets[index * 4 + 3] = packet.mineral_signature;
        }
        channel["packets"] = packets;
        channels.push_back(channel);
    }
    result["channels"] = channels;
    return result;
}

bool NativeSandWorld::deserialize_subsurface_state(Dictionary state) {
    if (!state.has("schema_version") || static_cast<int32_t>(state["schema_version"]) != 1 || !state.has("channels")) return false;
    const Array channels = state["channels"];
    struct Pending { uint64_t id; int32_t depth; Vector2i entrance; Vector2i exit; PackedInt32Array packets; };
    std::vector<Pending> pending;
    pending.reserve(channels.size());
    for (int32_t index = 0; index < channels.size(); ++index) {
        const Dictionary channel = channels[index];
        if (!channel.has("channel_id") || !channel.has("depth") || !channel.has("entrance") || !channel.has("exit") || !channel.has("packets")) return false;
        Pending item{static_cast<uint64_t>(static_cast<int64_t>(channel["channel_id"])), static_cast<int32_t>(channel["depth"]),
                     static_cast<Vector2i>(channel["entrance"]), static_cast<Vector2i>(channel["exit"]), static_cast<PackedInt32Array>(channel["packets"])};
        const int32_t distance = std::abs(item.exit.x - item.entrance.x) + std::abs(item.exit.y - item.entrance.y);
        if (item.id == 0 || item.depth < 0 || item.depth > 2 || distance < 2 || distance > 65 || item.packets.size() != (distance - 1) * 4) return false;
        pending.push_back(std::move(item));
    }
    std::sort(pending.begin(), pending.end(), [](const Pending &a, const Pending &b) { return a.id < b.id; });
    for (const auto &[id, run] : linked_transports_) { (void)id; clear_structure_cell(run.entrance); clear_structure_cell(run.exit); }
    reset_subsurface_logistics();
    const int32_t previous_mode = game_mode_;
    game_mode_ = 1;
    for (const Pending &item : pending) {
        next_linked_transport_id_ = item.id;
        const int64_t created = place_subsurface_channel(item.depth, item.entrance, item.exit);
        if (created != static_cast<int64_t>(item.id)) { game_mode_ = previous_mode; return false; }
        LinkedTransportRun &run = linked_transports_.at(item.id);
        for (int32_t index = 0; index < static_cast<int32_t>(run.lane.size()); ++index) {
            const int32_t material = item.packets[index * 4];
            if (material == 0) continue;
            if (!material_transportable(material)) { game_mode_ = previous_mode; return false; }
            run.lane[index] = MaterialPacket{static_cast<uint16_t>(material), static_cast<uint16_t>(item.packets[index * 4 + 1]),
                                             static_cast<uint16_t>(item.packets[index * 4 + 2]), static_cast<uint16_t>(item.packets[index * 4 + 3])};
        }
    }
    game_mode_ = previous_mode;
    const uint64_t serialized_next = state.has("next_channel_id") ? static_cast<uint64_t>(static_cast<int64_t>(state["next_channel_id"])) : next_linked_transport_id_;
    next_linked_transport_id_ = std::max(next_linked_transport_id_, serialized_next);
    return true;
}

String NativeSandWorld::subsurface_state_hash() const {
    uint32_t hash = mix_int(0x4b535542u, static_cast<int32_t>(seed_));
    std::vector<uint64_t> ids;
    for (const auto &[id, run] : linked_transports_) { (void)run; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
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
