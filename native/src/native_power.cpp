#include "native_sand_world.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <limits>
#include <queue>

namespace godot {

namespace {
constexpr int32_t WATER_ID = 3;
constexpr int32_t STEAM_ID = 17;
constexpr int32_t WATER_FREEZE = 1092;
constexpr int32_t WATER_BOIL = 1492;
constexpr int32_t ICE_LATENT = 12000;
constexpr int32_t STEAM_LATENT = 42000;
constexpr int32_t STRUCTURE_SCREEN = 6;
constexpr int32_t STRUCTURE_MAGNET = 7;
constexpr int32_t STRUCTURE_BASIC_PUMP = 14;
constexpr int32_t STRUCTURE_SHAFT = 26;
constexpr int32_t STRUCTURE_TURBINE = 27;
constexpr int32_t STRUCTURE_GENERATOR = 28;
constexpr int32_t STRUCTURE_POWER_POLE = 29;
constexpr int32_t STRUCTURE_POWER_SWITCH = 30;
constexpr int32_t STRUCTURE_ACCUMULATOR = 31;
constexpr int32_t STRUCTURE_TRANSFORMER = 32;
constexpr int32_t STRUCTURE_FLYWHEEL = 33;
constexpr int32_t STRUCTURE_RESISTIVE_HEATER = 34;
constexpr uint64_t SHAFT_ID_MASK = UINT64_C(0x2000000000000000);
constexpr uint64_t POLE_ID_MASK = UINT64_C(0x4000000000000000);
constexpr uint64_t MACHINE_MEMBER_MASK = UINT64_C(0x8000000000000000);
constexpr uint64_t AUX_CONSUMER_MASK = UINT64_C(0x6000000000000000);
constexpr uint64_t PUMP_ENTITY_MASK = UINT64_C(0x5000000000000000);
constexpr int64_t SHAFT_INERTIA = 1000;
constexpr int64_t TURBINE_INERTIA = 18000;
constexpr int64_t GENERATOR_INERTIA = 14000;
constexpr int64_t FLYWHEEL_INERTIA = 180000;
constexpr int64_t MECHANICAL_FRICTION_DIVISOR = 200000;
constexpr int32_t POWER_TICK_DIVISOR = 2;
constexpr int32_t POWER_POLE_RANGE = 24;
constexpr int32_t POWER_COVERAGE_RADIUS = 12;
constexpr int32_t POWER_CONNECTION_LIMIT = 4;
constexpr int32_t TURBINE_OFFLINE = 0;
constexpr int32_t TURBINE_NO_STEAM = 1;
constexpr int32_t TURBINE_STARTING = 2;
constexpr int32_t TURBINE_RUNNING = 3;
constexpr int32_t TURBINE_BACKPRESSURE = 4;
constexpr int32_t TURBINE_OVERSPEED = 5;
constexpr int32_t TURBINE_EXHAUST_BLOCKED = 6;
constexpr int32_t TURBINE_DISABLED = 7;
constexpr int32_t GENERATOR_OFFLINE = 0;
constexpr int32_t GENERATOR_STARTING = 1;
constexpr int32_t GENERATOR_RUNNING = 2;
constexpr int32_t GENERATOR_NO_MECHANICAL = 3;
constexpr int32_t GENERATOR_NO_LOAD = 4;
constexpr int32_t GENERATOR_OVERLOAD = 5;
constexpr int32_t GENERATOR_DISABLED = 6;
const std::array<Vector2i, 4> DIRECTIONS{{Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)}};

uint64_t stable_edge_id(uint64_t a, uint64_t b, uint8_t kind) {
    if (a > b) std::swap(a, b);
    uint64_t value = a ^ (b + UINT64_C(0x9e3779b97f4a7c15) + (a << 6u) + (a >> 2u));
    return value ^ (static_cast<uint64_t>(kind) << 56u);
}

int64_t integer_sqrt_128(__int128 value) {
    if (value <= 0) return 0;
    uint64_t high = value > std::numeric_limits<uint64_t>::max() ? std::numeric_limits<uint64_t>::max() : static_cast<uint64_t>(value);
    uint64_t low = 0;
    while (low < high) {
        const uint64_t middle = low + (high - low + 1) / 2;
        if (static_cast<__int128>(middle) * middle <= value) low = middle;
        else high = middle - 1;
    }
    return static_cast<int64_t>(low);
}

int64_t pipe_capacity_for(int32_t fluid, int32_t mass) {
    const int32_t specific_heat = fluid == STEAM_ID ? 32 : 128;
    return std::max<int64_t>(1, (static_cast<int64_t>(specific_heat) * mass + 254) / 255);
}

int64_t scaled_latent(int32_t latent, int32_t mass) {
    return std::max<int64_t>(1, (static_cast<int64_t>(latent) * mass + 254) / 255);
}

int64_t steam_floor_enthalpy(int32_t mass) {
    if (mass <= 0) return 0;
    const int64_t ice_capacity = std::max<int64_t>(1, (static_cast<int64_t>(64) * mass + 254) / 255);
    const int64_t water_capacity = pipe_capacity_for(WATER_ID, mass);
    const int64_t water_base = ice_capacity * WATER_FREEZE + scaled_latent(ICE_LATENT, mass) - water_capacity * WATER_FREEZE;
    return water_base + water_capacity * WATER_BOIL + scaled_latent(STEAM_LATENT, mass);
}

Vector2i oriented(Vector2i origin, Vector2i local, int32_t width, int32_t height, int32_t orientation) {
    const int32_t normalized = ((orientation % 4) + 4) % 4;
    if (normalized == 1) return origin + Vector2i(height - 1 - local.y, local.x);
    if (normalized == 2) return origin + Vector2i(width - 1 - local.x, height - 1 - local.y);
    if (normalized == 3) return origin + Vector2i(local.y, width - 1 - local.x);
    return origin + local;
}

uint64_t machine_member_id(uint64_t entity_id) { return MACHINE_MEMBER_MASK | entity_id; }
uint64_t shaft_member_id(uint64_t key) { return SHAFT_ID_MASK ^ key; }
uint64_t pole_id(uint64_t key) { return POLE_ID_MASK ^ key; }
} // namespace

bool NativeSandWorld::is_power_structure(int32_t type_id) {
    return type_id >= STRUCTURE_SHAFT && type_id <= STRUCTURE_RESISTIVE_HEATER;
}

bool NativeSandWorld::is_mechanical_structure(int32_t type_id) {
    return type_id == STRUCTURE_SHAFT || type_id == STRUCTURE_TURBINE || type_id == STRUCTURE_GENERATOR || type_id == STRUCTURE_FLYWHEEL;
}

void NativeSandWorld::reset_power() {
    mechanical_members_.clear(); mechanical_networks_.clear(); turbines_.clear(); generators_.clear();
    power_poles_.clear(); power_edges_.clear(); power_consumers_.clear(); resistive_heater_consumers_.clear(); accumulators_.clear();
    power_switches_.clear(); transformers_.clear(); power_networks_.clear(); power_entity_to_consumer_.clear();
    mechanical_topology_dirty_ = false; electrical_topology_dirty_ = false;
    mechanical_revision_ = power_revision_ = 0;
    last_mechanical_usec_ = last_power_usec_ = last_power_topology_usec_ = last_mechanical_topology_usec_ = 0;
    last_mechanical_active_networks_ = last_power_active_networks_ = 0;
    thermal_energy_into_turbines_ = mechanical_energy_produced_ = turbine_losses_ = 0;
    mechanical_energy_consumed_ = electrical_energy_produced_ = electrical_energy_consumed_ = 0;
    electrical_energy_stored_ = electrical_energy_discharged_ = generator_losses_ = storage_losses_ = 0;
}

void NativeSandWorld::register_power_tile(int32_t type_id, Vector2i cell, int32_t orientation) {
    const uint64_t key = cell_key(cell);
    if (type_id == STRUCTURE_SHAFT) {
        MechanicalMember member;
        member.id = shaft_member_id(key); member.cell = cell; member.inertia = SHAFT_INERTIA; member.kind = MechanicalMemberKind::SHAFT;
        mechanical_members_[member.id] = member;
        mechanical_topology_dirty_ = true;
    } else if (type_id == STRUCTURE_POWER_POLE) {
        PowerPoleRecord pole;
        pole.id = pole_id(key); pole.cell = cell; pole.connection_range = POWER_POLE_RANGE;
        pole.coverage_radius = POWER_COVERAGE_RADIUS; pole.connection_limit = POWER_CONNECTION_LIMIT;
        power_poles_[pole.id] = pole;
        electrical_topology_dirty_ = true;
    }
    (void)orientation;
}

void NativeSandWorld::register_power_structure(const MachineEntity &entity) {
    const uint64_t member_id = machine_member_id(entity.id);
    if (entity.type_id == STRUCTURE_TURBINE) {
        MechanicalMember member;
        member.id = member_id; member.entity_id = entity.id;
        member.cell = oriented(entity.origin, {5, 2}, 6, 4, entity.orientation);
        member.inertia = TURBINE_INERTIA; member.kind = MechanicalMemberKind::TURBINE;
        mechanical_members_[member.id] = member;
        TurbineRecord turbine;
        turbine.entity_id = entity.id; turbine.mechanical_member_id = member.id;
        turbine.inlet = oriented(entity.origin, {-1, 1}, 6, 4, entity.orientation);
        turbine.exhaust = oriented(entity.origin, {6, 1}, 6, 4, entity.orientation);
        turbines_[entity.id] = turbine;
        mechanical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_GENERATOR) {
        MechanicalMember member;
        member.id = member_id; member.entity_id = entity.id;
        member.cell = oriented(entity.origin, {0, 2}, 5, 4, entity.orientation);
        member.inertia = GENERATOR_INERTIA; member.kind = MechanicalMemberKind::GENERATOR;
        mechanical_members_[member.id] = member;
        GeneratorRecord generator;
        generator.entity_id = entity.id; generator.mechanical_member_id = member.id;
        generator.tap = oriented(entity.origin, {4, 2}, 5, 4, entity.orientation);
        generators_[entity.id] = generator;
        mechanical_topology_dirty_ = electrical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_FLYWHEEL) {
        MechanicalMember member;
        member.id = member_id; member.entity_id = entity.id;
        member.cell = oriented(entity.origin, {0, 1}, 3, 3, entity.orientation);
        member.inertia = FLYWHEEL_INERTIA; member.kind = MechanicalMemberKind::FLYWHEEL;
        mechanical_members_[member.id] = member;
        mechanical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_POWER_SWITCH) {
        PowerSwitchRecord power_switch;
        power_switch.entity_id = entity.id;
        power_switch.side_a = oriented(entity.origin, {-1, 0}, 3, 1, entity.orientation);
        power_switch.side_b = oriented(entity.origin, {3, 0}, 3, 1, entity.orientation);
        power_switches_[entity.id] = power_switch;
        electrical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_ACCUMULATOR) {
        AccumulatorRecord accumulator;
        accumulator.entity_id = entity.id; accumulator.tap = oriented(entity.origin, {1, 2}, 3, 3, entity.orientation);
        accumulators_[entity.id] = accumulator;
        electrical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_TRANSFORMER) {
        TransformerRecord transformer;
        transformer.entity_id = entity.id;
        transformer.input_tap = oriented(entity.origin, {-1, 1}, 4, 3, entity.orientation);
        transformer.output_tap = oriented(entity.origin, {4, 1}, 4, 3, entity.orientation);
        transformers_[entity.id] = transformer;
        electrical_topology_dirty_ = true;
    } else if (entity.type_id == STRUCTURE_RESISTIVE_HEATER) {
        const uint64_t consumer_id = AUX_CONSUMER_MASK | entity.id;
        add_power_consumer(consumer_id, entity.id, oriented(entity.origin, {2, 1}, 3, 2, entity.orientation), 3000000, 2, PowerConsumerKind::RESISTIVE_HEATER);
        resistive_heater_consumers_.insert(consumer_id);
        power_entity_to_consumer_[entity.id] = consumer_id;
        electrical_topology_dirty_ = true;
    }
}

void NativeSandWorld::unregister_power_tile(int32_t type_id, Vector2i cell) {
    const uint64_t key = cell_key(cell);
    if (type_id == STRUCTURE_SHAFT) {
        mechanical_members_.erase(shaft_member_id(key));
        mechanical_topology_dirty_ = true;
    } else if (type_id == STRUCTURE_POWER_POLE) {
        power_poles_.erase(pole_id(key));
        electrical_topology_dirty_ = true;
    }
}

void NativeSandWorld::unregister_power_structure(uint64_t entity_id) {
    turbines_.erase(entity_id); generators_.erase(entity_id); accumulators_.erase(entity_id);
    power_switches_.erase(entity_id); transformers_.erase(entity_id);
    mechanical_members_.erase(machine_member_id(entity_id));
    const auto consumer = power_entity_to_consumer_.find(entity_id);
    if (consumer != power_entity_to_consumer_.end()) {
        resistive_heater_consumers_.erase(consumer->second);
        remove_power_consumer(consumer->second);
        power_entity_to_consumer_.erase(consumer);
    }
    mechanical_topology_dirty_ = electrical_topology_dirty_ = true;
}

uint64_t NativeSandWorld::mechanical_member_id_at(Vector2i cell) const {
    uint64_t result = 0;
    for (const auto &[id, member] : mechanical_members_) if (member.cell == cell && (result == 0 || id < result)) result = id;
    return result;
}

void NativeSandWorld::update_mechanical_speed(MechanicalNetwork &network) {
    if (network.rotational_energy <= 0 || network.total_inertia <= 0) { network.speed_millirpm = 0; return; }
    const __int128 scaled = static_cast<__int128>(network.rotational_energy) * 2 * 1000000000LL / network.total_inertia;
    network.speed_millirpm = integer_sqrt_128(scaled);
}

void NativeSandWorld::rebuild_mechanical_topology() {
    const auto started = std::chrono::steady_clock::now();
    std::unordered_map<uint64_t, int64_t> member_energy;
    for (const auto &[network_id, network] : mechanical_networks_) {
        (void)network_id;
        if (network.members.empty() || network.total_inertia <= 0 || network.rotational_energy <= 0) continue;
        std::vector<uint64_t> ids = network.members;
        std::sort(ids.begin(), ids.end());
        int64_t assigned = 0;
        for (const uint64_t id : ids) {
            const auto member = mechanical_members_.find(id);
            if (member == mechanical_members_.end()) continue;
            const int64_t share = static_cast<int64_t>(static_cast<__int128>(network.rotational_energy) * member->second.inertia / network.total_inertia);
            member_energy[id] += share; assigned += share;
        }
        if (!ids.empty()) member_energy[ids.front()] += network.rotational_energy - assigned;
    }
    mechanical_networks_.clear();
    std::unordered_map<uint64_t, std::vector<uint64_t>> at_cell;
    for (const auto &[id, member] : mechanical_members_) at_cell[cell_key(member.cell)].push_back(id);
    std::vector<uint64_t> ordered;
    ordered.reserve(mechanical_members_.size());
    for (const auto &[id, member] : mechanical_members_) { (void)member; ordered.push_back(id); }
    std::sort(ordered.begin(), ordered.end());
    std::unordered_set<uint64_t> visited;
    for (const uint64_t seed : ordered) {
        if (visited.contains(seed)) continue;
        std::vector<uint64_t> stack{seed};
        std::vector<uint64_t> component;
        visited.insert(seed);
        while (!stack.empty()) {
            const uint64_t current = stack.back(); stack.pop_back(); component.push_back(current);
            const Vector2i cell = mechanical_members_.at(current).cell;
            auto visit_cell = [&](Vector2i candidate) {
                const auto found = at_cell.find(cell_key(candidate));
                if (found == at_cell.end()) return;
                for (const uint64_t other : found->second) if (!visited.contains(other)) { visited.insert(other); stack.push_back(other); }
            };
            visit_cell(cell);
            for (const Vector2i direction : DIRECTIONS) visit_cell(cell + direction);
        }
        std::sort(component.begin(), component.end());
        MechanicalNetwork network;
        network.id = component.front(); network.members = component;
        for (const uint64_t id : component) {
            MechanicalMember &member = mechanical_members_.at(id);
            member.network_id = network.id;
            network.total_inertia += member.inertia;
            network.rotational_energy += member_energy[id];
        }
        update_mechanical_speed(network);
        mechanical_networks_[network.id] = std::move(network);
    }
    mechanical_topology_dirty_ = false; ++mechanical_revision_;
    last_mechanical_topology_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

uint64_t NativeSandWorld::nearest_power_pole(Vector2i cell, int32_t radius, uint64_t exclude) const {
    uint64_t best = 0;
    int64_t best_distance = static_cast<int64_t>(radius) * radius + 1;
    for (const auto &[id, pole] : power_poles_) {
        if (id == exclude) continue;
        const Vector2i delta = pole.cell - cell;
        const int64_t distance = static_cast<int64_t>(delta.x) * delta.x + static_cast<int64_t>(delta.y) * delta.y;
        if (distance <= static_cast<int64_t>(radius) * radius && (distance < best_distance || (distance == best_distance && id < best))) {
            best = id; best_distance = distance;
        }
    }
    return best;
}

void NativeSandWorld::rebuild_power_aggregates() {
    for (auto &[id, network] : power_networks_) {
        (void)id;
        network.demand.fill(0); network.demand_total = 0; network.storage_charge = 0; network.storage_capacity = 0;
    }
    for (const auto &[id, consumer] : power_consumers_) {
        (void)id;
        auto network = power_networks_.find(consumer.network_id);
        if (network == power_networks_.end() || !consumer.enabled || consumer.requested_rate <= 0) continue;
        network->second.demand[consumer.priority] += consumer.requested_rate;
        network->second.demand_total += consumer.requested_rate;
    }
    for (const auto &[id, accumulator] : accumulators_) {
        (void)id;
        auto network = power_networks_.find(accumulator.network_id);
        if (network == power_networks_.end()) continue;
        network->second.storage_charge += accumulator.charge;
        network->second.storage_capacity += accumulator.capacity;
    }
}

void NativeSandWorld::rebuild_electrical_topology() {
    const auto started = std::chrono::steady_clock::now();
    power_edges_.clear(); power_networks_.clear();
    std::unordered_map<uint64_t, std::vector<uint64_t>> buckets;
    for (const auto &[id, pole] : power_poles_) buckets[chunk_key({floor_div(pole.cell.x, POWER_POLE_RANGE), floor_div(pole.cell.y, POWER_POLE_RANGE)})].push_back(id);
    for (auto &[key, ids] : buckets) { (void)key; std::sort(ids.begin(), ids.end()); }
    auto candidates_near = [&](Vector2i cell, int32_t radius, uint64_t exclude) {
        std::vector<std::pair<int64_t, uint64_t>> candidates;
        const Vector2i bucket{floor_div(cell.x, POWER_POLE_RANGE), floor_div(cell.y, POWER_POLE_RANGE)};
        const int32_t span = std::max(1, (radius + POWER_POLE_RANGE - 1) / POWER_POLE_RANGE);
        for (int32_t by = -span; by <= span; ++by) for (int32_t bx = -span; bx <= span; ++bx) {
            const auto found = buckets.find(chunk_key(bucket + Vector2i(bx, by)));
            if (found == buckets.end()) continue;
            for (const uint64_t id : found->second) {
                if (id == exclude) continue;
                const Vector2i delta = power_poles_.at(id).cell - cell;
                const int64_t distance = static_cast<int64_t>(delta.x) * delta.x + static_cast<int64_t>(delta.y) * delta.y;
                if (distance <= static_cast<int64_t>(radius) * radius) candidates.emplace_back(distance, id);
            }
        }
        std::sort(candidates.begin(), candidates.end(), [](const auto &a, const auto &b) { return a.first < b.first || (a.first == b.first && a.second < b.second); });
        return candidates;
    };
    std::vector<uint64_t> pole_ids;
    for (const auto &[id, pole] : power_poles_) { (void)pole; pole_ids.push_back(id); }
    std::sort(pole_ids.begin(), pole_ids.end());
    for (const uint64_t id : pole_ids) {
        const PowerPoleRecord &pole = power_poles_.at(id);
        const auto candidates = candidates_near(pole.cell, pole.connection_range, id);
        const int32_t limit = std::min<int32_t>(pole.connection_limit, candidates.size());
        for (int32_t index = 0; index < limit; ++index) {
            const uint64_t other = candidates[index].second;
            PowerEdgeRecord edge;
            edge.id = stable_edge_id(id, other, 0); edge.from = std::min(id, other); edge.to = std::max(id, other);
            power_edges_[edge.id] = edge;
        }
    }
    for (auto &[id, power_switch] : power_switches_) {
        (void)id;
        auto a = candidates_near(power_switch.side_a, POWER_COVERAGE_RADIUS, 0);
        auto b = candidates_near(power_switch.side_b, POWER_COVERAGE_RADIUS, 0);
        power_switch.pole_a = a.empty() ? 0 : a.front().second;
        power_switch.pole_b = b.empty() ? 0 : b.front().second;
        if (power_switch.closed && power_switch.pole_a != 0 && power_switch.pole_b != 0 && power_switch.pole_a != power_switch.pole_b) {
            PowerEdgeRecord edge;
            edge.id = stable_edge_id(power_switch.pole_a, power_switch.pole_b, 1);
            edge.from = std::min(power_switch.pole_a, power_switch.pole_b); edge.to = std::max(power_switch.pole_a, power_switch.pole_b); edge.kind = 1;
            power_edges_[edge.id] = edge;
        }
    }
    std::unordered_map<uint64_t, std::vector<uint64_t>> adjacency;
    for (const auto &[id, edge] : power_edges_) { (void)id; adjacency[edge.from].push_back(edge.to); adjacency[edge.to].push_back(edge.from); }
    std::unordered_set<uint64_t> visited;
    for (const uint64_t seed : pole_ids) {
        if (visited.contains(seed)) continue;
        std::vector<uint64_t> stack{seed}, component;
        visited.insert(seed);
        while (!stack.empty()) {
            const uint64_t current = stack.back(); stack.pop_back(); component.push_back(current);
            auto neighbors = adjacency.find(current);
            if (neighbors == adjacency.end()) continue;
            std::sort(neighbors->second.begin(), neighbors->second.end());
            for (const uint64_t other : neighbors->second) if (!visited.contains(other)) { visited.insert(other); stack.push_back(other); }
        }
        std::sort(component.begin(), component.end());
        PowerNetwork network; network.id = component.front(); network.poles = component;
        for (const uint64_t id : component) power_poles_.at(id).network_id = network.id;
        power_networks_[network.id] = std::move(network);
    }
    auto nearest_local = [&](Vector2i cell, int32_t radius) -> uint64_t {
        auto candidates = candidates_near(cell, radius, 0);
        return candidates.empty() ? 0 : candidates.front().second;
    };
    for (auto &[id, generator] : generators_) { (void)id; const uint64_t pole = generator.assigned_pole_id != 0 && power_poles_.contains(generator.assigned_pole_id) ? generator.assigned_pole_id : nearest_local(generator.tap, POWER_COVERAGE_RADIUS); generator.power_network_id = pole == 0 ? 0 : power_poles_.at(pole).network_id; }
    for (auto &[id, consumer] : power_consumers_) { (void)id; const uint64_t pole = consumer.assigned_pole_id != 0 && power_poles_.contains(consumer.assigned_pole_id) ? consumer.assigned_pole_id : nearest_local(consumer.tap, POWER_COVERAGE_RADIUS); consumer.network_id = pole == 0 ? 0 : power_poles_.at(pole).network_id; }
    for (auto &[id, accumulator] : accumulators_) { (void)id; const uint64_t pole = accumulator.assigned_pole_id != 0 && power_poles_.contains(accumulator.assigned_pole_id) ? accumulator.assigned_pole_id : nearest_local(accumulator.tap, POWER_COVERAGE_RADIUS); accumulator.network_id = pole == 0 ? 0 : power_poles_.at(pole).network_id; }
    for (auto &[id, transformer] : transformers_) {
        (void)id;
        const uint64_t input = nearest_local(transformer.input_tap, POWER_COVERAGE_RADIUS);
        const uint64_t output = nearest_local(transformer.output_tap, POWER_COVERAGE_RADIUS);
        transformer.input_network_id = input == 0 ? 0 : power_poles_.at(input).network_id;
        transformer.output_network_id = output == 0 ? 0 : power_poles_.at(output).network_id;
    }
    rebuild_power_aggregates();
    electrical_topology_dirty_ = false; ++power_revision_;
    last_power_topology_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

void NativeSandWorld::add_power_consumer(uint64_t id, uint64_t entity_id, Vector2i tap, int64_t request, int32_t priority, PowerConsumerKind kind) {
    PowerConsumerRecord consumer;
    consumer.id = id; consumer.entity_id = entity_id; consumer.tap = tap;
    consumer.requested_rate = std::max<int64_t>(0, request); consumer.priority = static_cast<uint8_t>(std::clamp(priority, 0, 3)); consumer.kind = kind;
    power_consumers_[id] = consumer;
}

void NativeSandWorld::remove_power_consumer(uint64_t id) {
    power_consumers_.erase(id);
}

int64_t NativeSandWorld::mechanical_speed_for_member(uint64_t member_id) const {
    const auto member = mechanical_members_.find(member_id);
    if (member == mechanical_members_.end()) return 0;
    const auto network = mechanical_networks_.find(member->second.network_id);
    return network == mechanical_networks_.end() ? 0 : network->second.speed_millirpm;
}

int32_t NativeSandWorld::electric_satisfaction(int32_t type_id, uint64_t entity_id, Vector2i cell) const {
    if (type_id == STRUCTURE_BASIC_PUMP) entity_id = PUMP_ENTITY_MASK ^ cell_key(cell);
    const auto mapped = power_entity_to_consumer_.find(entity_id);
    if (mapped == power_entity_to_consumer_.end()) return 0;
    const auto consumer = power_consumers_.find(mapped->second);
    if (consumer == power_consumers_.end() || !consumer->second.enabled) return 0;
    const auto network = power_networks_.find(consumer->second.network_id);
    return network == power_networks_.end() ? 0 : network->second.satisfaction[consumer->second.priority];
}

void NativeSandWorld::account_local_waste_heat(Vector2i origin, int64_t energy) {
    if (energy <= 0) return;
    for (int32_t radius = 1; radius <= 5; ++radius) {
        for (int32_t y = -radius; y <= radius; ++y) for (int32_t x = -radius; x <= radius; ++x) {
            if (std::abs(x) != radius && std::abs(y) != radius) continue;
            const Vector2i cell = origin + Vector2i(x, y);
            Chunk *chunk = get_chunk(world_to_chunk(cell));
            if (chunk == nullptr) continue;
            const int32_t index = local_index(world_to_local(cell));
            const int32_t material = chunk->material[index];
            if (material == 0) continue;
            const int64_t before = cell_enthalpy(*chunk, index);
            set_cell_enthalpy(cell, before + energy, material);
            const int64_t after = cell_enthalpy(*chunk, index);
            thermal_rounding_reservoir_ += before + energy - after;
            activate_thermal_world_cell(cell, 1);
            return;
        }
    }
}

void NativeSandWorld::process_power() {
    if (mechanical_topology_dirty_) rebuild_mechanical_topology();
    if (electrical_topology_dirty_) rebuild_electrical_topology();
    if ((tick_index_ % POWER_TICK_DIVISOR) != 0) { last_mechanical_usec_ = last_power_usec_ = 0; return; }
    const auto mechanical_started = std::chrono::steady_clock::now();
    for (auto &[id, network] : mechanical_networks_) {
        (void)id;
        network.input_energy = network.requested_output = network.delivered_output = network.friction_loss = 0;
    }
    std::vector<uint64_t> turbine_ids;
    for (const auto &[id, turbine] : turbines_) { (void)turbine; turbine_ids.push_back(id); }
    std::sort(turbine_ids.begin(), turbine_ids.end());
    for (const uint64_t id : turbine_ids) {
        TurbineRecord &turbine = turbines_.at(id);
        turbine.mechanical_output = 0;
        if (!turbine.enabled) { turbine.state = TURBINE_DISABLED; continue; }
        const auto member = mechanical_members_.find(turbine.mechanical_member_id);
        if (member == mechanical_members_.end()) { turbine.state = TURBINE_OFFLINE; continue; }
        auto network = mechanical_networks_.find(member->second.network_id);
        if (network == mechanical_networks_.end()) { turbine.state = TURBINE_OFFLINE; continue; }
        const int64_t speed = network->second.speed_millirpm;
        if (speed > static_cast<int64_t>(turbine.target_millirpm) * 110 / 100) turbine.throttle = std::max(0, turbine.throttle - 80);
        else if (speed < static_cast<int64_t>(turbine.target_millirpm) * 98 / 100) turbine.throttle = std::min(turbine.max_throttle, turbine.throttle + 40);
        turbine.throttle = std::min(turbine.throttle, turbine.max_throttle);
        auto inlet = pipe_segments_.find(cell_key(turbine.inlet));
        auto exhaust = pipe_segments_.find(cell_key(turbine.exhaust));
        if (inlet == pipe_segments_.end() || inlet->second.fluid_type != STEAM_ID || inlet->second.mass == 0) { turbine.state = TURBINE_NO_STEAM; continue; }
        if (exhaust == pipe_segments_.end()) { turbine.state = TURBINE_EXHAUST_BLOCKED; continue; }
        if (exhaust->second.mass >= 65535 || (exhaust->second.mass > 0 && exhaust->second.fluid_type != STEAM_ID)) { turbine.state = TURBINE_EXHAUST_BLOCKED; continue; }
        const int32_t inlet_potential = static_cast<int32_t>(inlet->second.mass) + inlet->second.pressure + std::max(0, static_cast<int32_t>(inlet->second.temperature) - WATER_BOIL) * 8;
        const int32_t exhaust_potential = static_cast<int32_t>(exhaust->second.mass) + exhaust->second.pressure + std::max(0, static_cast<int32_t>(exhaust->second.temperature) - WATER_BOIL) * 8;
        const int32_t pressure_delta = std::max(0, inlet_potential - exhaust_potential);
        if (pressure_delta <= 64) { turbine.state = TURBINE_BACKPRESSURE; continue; }
        const int32_t pressure_ratio = std::clamp(pressure_delta * 1000 / std::max(1, turbine.rated_pressure_delta), 0, 1000);
        const int32_t admitted = std::min({turbine.rated_flow * turbine.throttle / 1000 * pressure_ratio / 1000,
                                          static_cast<int32_t>(inlet->second.mass), 65535 - static_cast<int32_t>(exhaust->second.mass)});
        if (admitted <= 0) { turbine.state = TURBINE_BACKPRESSURE; continue; }
        const int64_t inlet_before = pipe_enthalpy(inlet->first, inlet->second);
        const int64_t exhaust_before = pipe_enthalpy(exhaust->first, exhaust->second);
        const int32_t inlet_mass_before = inlet->second.mass;
        const int64_t moved_enthalpy = inlet_before * admitted / inlet_mass_before;
        const int64_t floor_enthalpy = steam_floor_enthalpy(admitted);
        const int64_t extractable = std::max<int64_t>(0, moved_enthalpy - floor_enthalpy);
        const int64_t mechanical = extractable * turbine.efficiency_permille / 1000;
        const int64_t waste = extractable - mechanical;
        const int64_t exhaust_enthalpy = moved_enthalpy - mechanical - waste;
        inlet->second.mass = static_cast<uint16_t>(inlet_mass_before - admitted);
        const int32_t source_fluid = inlet->second.fluid_type;
        const int64_t inlet_after = set_pipe_enthalpy(inlet->first, inlet->second, inlet_before - moved_enthalpy, source_fluid);
        exhaust->second.mass = static_cast<uint16_t>(exhaust->second.mass + admitted);
        const int64_t exhaust_after = set_pipe_enthalpy(exhaust->first, exhaust->second, exhaust_before + exhaust_enthalpy, STEAM_ID);
        const int64_t rounding = inlet_before + exhaust_before - inlet_after - exhaust_after - mechanical - waste;
        thermal_rounding_reservoir_ += rounding;
        inlet->second.last_flow = static_cast<int16_t>(-std::min(admitted, 32767));
        exhaust->second.last_flow = static_cast<int16_t>(std::min(admitted, 32767));
        ++pipe_revision_; wake_pipe_neighbors(turbine.inlet); wake_pipe_neighbors(turbine.exhaust);
        network->second.rotational_energy += mechanical;
        network->second.input_energy += mechanical;
        turbine.mass_throughput += admitted; turbine.mechanical_output = mechanical; turbine.waste_heat += waste;
        thermal_energy_into_turbines_ += moved_enthalpy; mechanical_energy_produced_ += mechanical; turbine_losses_ += waste;
        const auto turbine_machine = machine_entities_.find(id);
        if (turbine_machine != machine_entities_.end()) account_local_waste_heat(turbine_machine->second.origin, waste);
        turbine.state = speed > static_cast<int64_t>(turbine.target_millirpm) * 115 / 100 ? TURBINE_OVERSPEED : speed < turbine.target_millirpm / 4 ? TURBINE_STARTING : TURBINE_RUNNING;
    }
    for (auto &[id, network] : mechanical_networks_) {
        (void)id;
        network.friction_loss = network.rotational_energy / MECHANICAL_FRICTION_DIVISOR;
        network.rotational_energy -= network.friction_loss;
        update_mechanical_speed(network);
    }
    last_mechanical_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - mechanical_started).count();

    const auto power_started = std::chrono::steady_clock::now();
    for (auto &[id, network] : power_networks_) {
        (void)id;
        network.generation_available = network.generation_delivered = network.delivered_total = network.surplus = 0;
        network.storage_input = network.storage_output = 0; network.satisfaction.fill(0);
    }
    std::unordered_map<uint64_t, int64_t> remaining_need;
    for (const auto &[id, network] : power_networks_) remaining_need[id] = network.demand_total + std::max<int64_t>(0, network.storage_capacity - network.storage_charge);
    std::vector<uint64_t> generator_ids;
    for (const auto &[id, generator] : generators_) { (void)generator; generator_ids.push_back(id); }
    std::sort(generator_ids.begin(), generator_ids.end());
    for (const uint64_t id : generator_ids) {
        GeneratorRecord &generator = generators_.at(id);
        generator.last_mechanical_input = generator.last_electrical_output = 0;
        if (!generator.enabled) { generator.state = GENERATOR_DISABLED; continue; }
        auto electrical = power_networks_.find(generator.power_network_id);
        if (electrical == power_networks_.end()) { generator.state = GENERATOR_OFFLINE; continue; }
        const auto member = mechanical_members_.find(generator.mechanical_member_id);
        if (member == mechanical_members_.end()) { generator.state = GENERATOR_NO_MECHANICAL; continue; }
        auto mechanical = mechanical_networks_.find(member->second.network_id);
        // A synchronous machine begins producing below rated speed; output is
        // already reduced continuously by speed_factor. The 10% cut-in avoids
        // a hidden all-or-nothing 20% speed black box during startup.
        if (mechanical == mechanical_networks_.end() || mechanical->second.speed_millirpm < generator.rated_millirpm / 10) { generator.state = GENERATOR_NO_MECHANICAL; continue; }
        int64_t &needed = remaining_need[generator.power_network_id];
        if (needed <= 0) { generator.state = GENERATOR_NO_LOAD; continue; }
        const int64_t speed_factor = std::min<int64_t>(1000, mechanical->second.speed_millirpm * 1000 / generator.rated_millirpm);
        const int64_t output_cap = generator.max_electrical_output * speed_factor / 1000;
        const int64_t requested_electrical = std::min(needed, output_cap);
        int64_t requested_mechanical = (requested_electrical * 1000 + generator.efficiency_permille - 1) / generator.efficiency_permille;
        requested_mechanical = std::min({requested_mechanical, generator.max_mechanical_input, mechanical->second.rotational_energy});
        const int64_t produced = requested_mechanical * generator.efficiency_permille / 1000;
        const int64_t loss = requested_mechanical - produced;
        mechanical->second.requested_output += requested_mechanical;
        mechanical->second.delivered_output += requested_mechanical;
        mechanical->second.rotational_energy -= requested_mechanical;
        update_mechanical_speed(mechanical->second);
        electrical->second.generation_available += produced;
        generator.last_mechanical_input = requested_mechanical; generator.last_electrical_output = produced; generator.waste_heat += loss;
        mechanical_energy_consumed_ += requested_mechanical; electrical_energy_produced_ += produced; generator_losses_ += loss;
        const auto generator_machine = machine_entities_.find(id);
        if (generator_machine != machine_entities_.end()) account_local_waste_heat(generator_machine->second.origin, loss);
        needed -= produced;
        generator.state = produced <= 0 ? GENERATOR_NO_MECHANICAL : produced < requested_electrical ? GENERATOR_OVERLOAD : GENERATOR_RUNNING;
    }
    std::vector<uint64_t> accumulator_ids;
    for (const auto &[id, accumulator] : accumulators_) { (void)accumulator; accumulator_ids.push_back(id); }
    std::sort(accumulator_ids.begin(), accumulator_ids.end());
    for (auto &[network_id, network] : power_networks_) {
        int64_t available = network.generation_available;
        if (available < network.demand_total) {
            int64_t shortage = network.demand_total - available;
            for (const uint64_t id : accumulator_ids) {
                AccumulatorRecord &accumulator = accumulators_.at(id);
                accumulator.last_charge_input = accumulator.last_discharge_output = 0;
                if (accumulator.network_id != network_id || accumulator.charge <= 0 || shortage <= 0) continue;
                const int64_t stored_used = std::min({accumulator.charge, accumulator.max_discharge_rate,
                    (shortage * 1000 + accumulator.discharge_efficiency_permille - 1) / accumulator.discharge_efficiency_permille});
                const int64_t delivered = stored_used * accumulator.discharge_efficiency_permille / 1000;
                accumulator.charge -= stored_used; accumulator.last_discharge_output = delivered;
                available += delivered; shortage -= delivered;
                network.storage_output += delivered; electrical_energy_discharged_ += delivered;
                storage_losses_ += stored_used - delivered;
            }
        }
        int64_t remaining = available;
        for (int32_t priority = 0; priority < 4; ++priority) {
            const int64_t demand = network.demand[priority];
            if (demand <= 0) { network.satisfaction[priority] = 1000; continue; }
            const int64_t delivered = std::min(remaining, demand);
            network.satisfaction[priority] = static_cast<uint16_t>(delivered * 1000 / demand);
            network.delivered_total += delivered; remaining -= delivered;
        }
        network.generation_delivered = std::min(network.generation_available, network.delivered_total);
        electrical_energy_consumed_ += network.delivered_total;
        if (remaining > 0) {
            for (const uint64_t id : accumulator_ids) {
                AccumulatorRecord &accumulator = accumulators_.at(id);
                if (accumulator.network_id != network_id || accumulator.charge >= accumulator.capacity || remaining <= 0) continue;
                const int64_t input = std::min({remaining, accumulator.max_charge_rate,
                    (accumulator.capacity - accumulator.charge) * 1000 / accumulator.charge_efficiency_permille});
                const int64_t stored = input * accumulator.charge_efficiency_permille / 1000;
                accumulator.charge += stored; accumulator.last_charge_input = input;
                remaining -= input; network.storage_input += input; electrical_energy_stored_ += stored;
                storage_losses_ += input - stored;
            }
        }
        network.surplus = remaining;
        network.storage_charge = 0;
        for (const uint64_t id : accumulator_ids) if (accumulators_.at(id).network_id == network_id) network.storage_charge += accumulators_.at(id).charge;
    }
    // Satisfaction is a cached per-network/per-priority ratio. Do not rewrite
    // every consumer on stable 100k-node networks; only physical heaters need
    // per-tick local work. Other consumers resolve the ratio on demand.
    std::vector<uint64_t> heater_ids(resistive_heater_consumers_.begin(), resistive_heater_consumers_.end());
    std::sort(heater_ids.begin(), heater_ids.end());
    for (const uint64_t id : heater_ids) {
        auto found = power_consumers_.find(id);
        if (found == power_consumers_.end()) continue;
        PowerConsumerRecord &consumer = found->second;
        if (!consumer.enabled) continue;
        const auto network = power_networks_.find(consumer.network_id);
        const int32_t satisfaction = network == power_networks_.end() ? 0 : network->second.satisfaction[consumer.priority];
        const int64_t delivered = consumer.requested_rate * satisfaction / 1000;
        if (delivered > 0) {
            const int64_t heat = delivered * 980 / 1000;
            account_local_waste_heat(consumer.tap, heat);
            storage_losses_ += delivered - heat;
        }
    }
    last_mechanical_active_networks_ = 0;
    for (const auto &[id, network] : mechanical_networks_) { (void)id; if (network.rotational_energy > 0 || network.input_energy > 0 || network.delivered_output > 0) ++last_mechanical_active_networks_; }
    last_power_active_networks_ = 0;
    for (const auto &[id, network] : power_networks_) { (void)id; if (network.demand_total > 0 || network.generation_available > 0 || network.storage_charge > 0) ++last_power_active_networks_; }
    ++power_revision_;
    for (const auto &[component_id, component] : automation_components_) {
        if (component.type_id == 22 || component.type_id == 23 ||
            (component.type_id == 8 && (turbines_.contains(component.target_machine_id) || generators_.contains(component.target_machine_id))))
            automation_dirty_.insert(component_id);
    }
    last_power_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - power_started).count();
}

int32_t NativeSandWorld::place_mechanical_shaft_line(Vector2i from, Vector2i to) {
    if (from.x != to.x && from.y != to.y) return -1;
    std::vector<Vector2i> cells;
    if (from.y == to.y) for (int32_t x = std::min(from.x, to.x); x <= std::max(from.x, to.x); ++x) cells.push_back({x, from.y});
    else for (int32_t y = std::min(from.y, to.y); y <= std::max(from.y, to.y); ++y) cells.push_back({from.x, y});
    if (!ensure_structure_chunks_generated(cells)) return -1;
    for (const Vector2i cell : cells) if (get_cell(cell) != 0 || (get_structure(cell) != 0 && get_structure(cell) != STRUCTURE_SHAFT)) return -1;
    int32_t placed = 0;
    for (const Vector2i cell : cells) if (get_structure(cell) == 0) { set_structure_cell(cell, STRUCTURE_SHAFT); register_power_tile(STRUCTURE_SHAFT, cell, from.y == to.y ? 0 : 1); ++placed; }
    return placed;
}

bool NativeSandWorld::configure_power_structure(Vector2i world_cell, Dictionary configuration) {
    const int32_t type_id = get_structure(world_cell);
    auto configured_pole = [&]() -> uint64_t {
        if (!configuration.has("pole_position")) return UINT64_MAX;
        const uint64_t id = pole_id(cell_key(static_cast<Vector2i>(configuration["pole_position"])));
        return power_poles_.contains(id) ? id : 0;
    };
    if (type_id == STRUCTURE_POWER_SWITCH) return set_power_switch_closed(world_cell, static_cast<bool>(configuration.get("closed", true)));
    if (type_id == STRUCTURE_BASIC_PUMP || type_id == STRUCTURE_SCREEN || type_id == STRUCTURE_MAGNET) {
        uint64_t entity_id = type_id == STRUCTURE_BASIC_PUMP ? (PUMP_ENTITY_MASK ^ cell_key(world_cell)) : machine_id_at(world_cell);
        if (entity_id == 0) return false;
        const bool enabled = static_cast<bool>(configuration.get("electric_drive", true));
        const int64_t request = type_id == STRUCTURE_BASIC_PUMP ? 900000 : type_id == STRUCTURE_SCREEN ? 1200000 : 1500000;
        const uint64_t consumer_id = AUX_CONSUMER_MASK ^ entity_id;
        if (!power_consumers_.contains(consumer_id)) add_power_consumer(consumer_id, entity_id, world_cell, request, static_cast<int32_t>(configuration.get("priority", 2)), PowerConsumerKind::MACHINE_DRIVE);
        power_consumers_.at(consumer_id).enabled = enabled;
        const uint64_t assigned = configured_pole();
        if (assigned != UINT64_MAX) power_consumers_.at(consumer_id).assigned_pole_id = assigned;
        power_entity_to_consumer_[entity_id] = consumer_id;
        electrical_topology_dirty_ = true;
        return true;
    }
    const uint64_t entity_id = machine_id_at(world_cell);
    if (entity_id == 0) return false;
    if (type_id == STRUCTURE_TURBINE) {
        TurbineRecord &turbine = turbines_.at(entity_id);
        turbine.target_millirpm = std::clamp(static_cast<int32_t>(configuration.get("target_millirpm", turbine.target_millirpm)), 100000, 4000000);
        turbine.max_throttle = std::clamp(static_cast<int32_t>(configuration.get("max_throttle", turbine.max_throttle)), 0, 1000);
        turbine.enabled = static_cast<bool>(configuration.get("enabled", turbine.enabled));
        return true;
    }
    if (type_id == STRUCTURE_GENERATOR) {
        GeneratorRecord &generator = generators_.at(entity_id); generator.enabled = static_cast<bool>(configuration.get("enabled", true));
        const uint64_t assigned = configured_pole(); if (assigned != UINT64_MAX) { generator.assigned_pole_id = assigned; electrical_topology_dirty_ = true; }
        return true;
    }
    if (type_id == STRUCTURE_ACCUMULATOR) {
        AccumulatorRecord &accumulator = accumulators_.at(entity_id);
        accumulator.charge = std::clamp<int64_t>(static_cast<int64_t>(configuration.get("charge", accumulator.charge)), 0, accumulator.capacity);
        const uint64_t assigned = configured_pole(); if (assigned != UINT64_MAX) { accumulator.assigned_pole_id = assigned; electrical_topology_dirty_ = true; }
        return true;
    }
    if (type_id == STRUCTURE_TRANSFORMER) {
        TransformerRecord &transformer = transformers_.at(entity_id);
        transformer.enabled = static_cast<bool>(configuration.get("enabled", true));
        transformer.max_transfer_rate = std::max<int64_t>(0, static_cast<int64_t>(configuration.get("max_transfer_rate", transformer.max_transfer_rate)));
        return true;
    }
    if (type_id == STRUCTURE_RESISTIVE_HEATER) {
        const bool priority_ok = set_power_consumer_priority(world_cell, static_cast<int32_t>(configuration.get("priority", 2)));
        const auto mapped = power_entity_to_consumer_.find(entity_id);
        const uint64_t assigned = configured_pole();
        if (mapped != power_entity_to_consumer_.end() && assigned != UINT64_MAX) { power_consumers_.at(mapped->second).assigned_pole_id = assigned; electrical_topology_dirty_ = true; }
        return priority_ok;
    }
    return false;
}

bool NativeSandWorld::set_power_switch_closed(Vector2i world_cell, bool closed) {
    const uint64_t entity_id = machine_id_at(world_cell);
    auto found = power_switches_.find(entity_id);
    if (found == power_switches_.end()) return false;
    if (found->second.closed == closed) return true;
    found->second.closed = closed; electrical_topology_dirty_ = true;
    return true;
}

bool NativeSandWorld::set_power_consumer_priority(Vector2i world_cell, int32_t priority) {
    if (priority < 0 || priority > 3) return false;
    const int32_t type_id = get_structure(world_cell);
    const uint64_t entity_id = type_id == STRUCTURE_BASIC_PUMP ? (PUMP_ENTITY_MASK ^ cell_key(world_cell)) : machine_id_at(world_cell);
    const auto mapped = power_entity_to_consumer_.find(entity_id);
    if (mapped == power_entity_to_consumer_.end()) return false;
    power_consumers_.at(mapped->second).priority = static_cast<uint8_t>(priority);
    rebuild_power_aggregates(); ++power_revision_;
    return true;
}

Dictionary NativeSandWorld::get_power_state_at(Vector2i world_cell) const {
    Dictionary result;
    const int32_t type_id = get_structure(world_cell);
    uint64_t entity_id = type_id == STRUCTURE_BASIC_PUMP ? (PUMP_ENTITY_MASK ^ cell_key(world_cell)) : machine_id_at(world_cell);
    result["type_id"] = type_id; result["entity_id"] = static_cast<int64_t>(entity_id);
    if (type_id == STRUCTURE_SHAFT) entity_id = shaft_member_id(cell_key(world_cell));
    const auto member = mechanical_members_.find(type_id == STRUCTURE_SHAFT ? entity_id : machine_member_id(entity_id));
    if (member != mechanical_members_.end()) {
        result["mechanical_network_id"] = static_cast<int64_t>(member->second.network_id);
        result["speed_millirpm"] = mechanical_speed_for_member(member->first);
        const auto network = mechanical_networks_.find(member->second.network_id);
        if (network != mechanical_networks_.end()) { result["rotational_energy"] = network->second.rotational_energy; result["inertia"] = network->second.total_inertia; }
    }
    if (type_id == STRUCTURE_POWER_POLE) {
        const auto pole = power_poles_.find(pole_id(cell_key(world_cell)));
        if (pole != power_poles_.end()) result["power_network_id"] = static_cast<int64_t>(pole->second.network_id);
    }
    if (turbines_.contains(entity_id)) {
        const TurbineRecord &turbine = turbines_.at(entity_id);
        result["state"] = turbine.state; result["throttle"] = turbine.throttle; result["target_millirpm"] = turbine.target_millirpm;
        result["steam_mass_throughput"] = turbine.mass_throughput; result["mechanical_output"] = turbine.mechanical_output;
        result["inlet"] = turbine.inlet; result["exhaust"] = turbine.exhaust;
    } else if (generators_.contains(entity_id)) {
        const GeneratorRecord &generator = generators_.at(entity_id);
        result["state"] = generator.state; result["power_network_id"] = static_cast<int64_t>(generator.power_network_id);
        result["mechanical_input"] = generator.last_mechanical_input; result["electrical_output"] = generator.last_electrical_output;
    } else if (accumulators_.contains(entity_id)) {
        const AccumulatorRecord &accumulator = accumulators_.at(entity_id);
        result["power_network_id"] = static_cast<int64_t>(accumulator.network_id); result["charge"] = accumulator.charge; result["capacity"] = accumulator.capacity;
    } else if (power_switches_.contains(entity_id)) {
        const PowerSwitchRecord &power_switch = power_switches_.at(entity_id);
        result["closed"] = power_switch.closed; result["pole_a"] = static_cast<int64_t>(power_switch.pole_a); result["pole_b"] = static_cast<int64_t>(power_switch.pole_b);
    }
    const auto mapped = power_entity_to_consumer_.find(entity_id);
    if (mapped != power_entity_to_consumer_.end() && power_consumers_.contains(mapped->second)) {
        const PowerConsumerRecord &consumer = power_consumers_.at(mapped->second);
        result["power_network_id"] = static_cast<int64_t>(consumer.network_id); result["priority"] = consumer.priority;
        result["assigned_pole_id"] = static_cast<int64_t>(consumer.assigned_pole_id);
        const auto network = power_networks_.find(consumer.network_id);
        const int32_t satisfaction = network == power_networks_.end() || !consumer.enabled ? 0 : network->second.satisfaction[consumer.priority];
        result["requested_rate"] = consumer.requested_rate;
        result["delivered_rate"] = consumer.requested_rate * satisfaction / 1000;
        result["satisfaction"] = satisfaction;
    }
    return result;
}

Dictionary NativeSandWorld::get_power_network_state(int64_t network_id) const {
    Dictionary result;
    const auto found = power_networks_.find(static_cast<uint64_t>(network_id));
    if (found == power_networks_.end()) return result;
    const PowerNetwork &network = found->second;
    result["network_id"] = network_id; result["poles"] = static_cast<int64_t>(network.poles.size());
    result["generation"] = network.generation_available; result["delivered"] = network.delivered_total; result["demand"] = network.demand_total;
    result["surplus"] = network.surplus; result["storage"] = network.storage_charge; result["storage_capacity"] = network.storage_capacity;
    PackedInt32Array satisfaction; for (const uint16_t value : network.satisfaction) satisfaction.push_back(value); result["satisfaction_by_priority"] = satisfaction;
    return result;
}

Dictionary NativeSandWorld::get_power_statistics() const {
    Dictionary result;
    int64_t demand = 0, delivered = 0, generation = 0, storage = 0, capacity = 0, edges = power_edges_.size();
    int64_t brownout_networks = 0, overloaded_generators = 0, overspeed_turbines = 0, backpressure_turbines = 0, turbine_steam_throughput = 0;
    std::array<int64_t, 4> demand_by_priority{{0, 0, 0, 0}}, delivered_by_priority{{0, 0, 0, 0}};
    for (const auto &[id, network] : power_networks_) {
        (void)id; demand += network.demand_total; delivered += network.delivered_total; generation += network.generation_available; storage += network.storage_charge; capacity += network.storage_capacity;
        if (network.delivered_total < network.demand_total) ++brownout_networks;
        for (int32_t priority = 0; priority < 4; ++priority) {
            demand_by_priority[priority] += network.demand[priority];
            delivered_by_priority[priority] += network.demand[priority] * network.satisfaction[priority] / 1000;
        }
    }
    for (const auto &[id, generator] : generators_) { (void)id; if (generator.state == GENERATOR_OVERLOAD) ++overloaded_generators; }
    for (const auto &[id, turbine] : turbines_) { (void)id; turbine_steam_throughput += turbine.mass_throughput; if (turbine.state == TURBINE_OVERSPEED) ++overspeed_turbines; if (turbine.state == TURBINE_BACKPRESSURE || turbine.state == TURBINE_EXHAUST_BLOCKED) ++backpressure_turbines; }
    int64_t machine_drive_consumers = 0, heater_consumers = 0;
    for (const auto &[id, consumer] : power_consumers_) { (void)id; if (consumer.kind == PowerConsumerKind::RESISTIVE_HEATER) ++heater_consumers; else ++machine_drive_consumers; }
    result["networks"] = static_cast<int64_t>(power_networks_.size()); result["active_networks"] = last_power_active_networks_;
    result["poles"] = static_cast<int64_t>(power_poles_.size()); result["edges"] = edges; result["consumers"] = static_cast<int64_t>(power_consumers_.size());
    result["generators"] = static_cast<int64_t>(generators_.size()); result["accumulators"] = static_cast<int64_t>(accumulators_.size()); result["transformers"] = static_cast<int64_t>(transformers_.size());
    result["demand"] = demand; result["delivered"] = delivered; result["generation"] = generation; result["storage"] = storage; result["storage_capacity"] = capacity;
    result["brownout_networks"] = brownout_networks; result["overloaded_generators"] = overloaded_generators;
    result["overspeed_turbines"] = overspeed_turbines; result["backpressure_turbines"] = backpressure_turbines;
    Array demand_classes, delivered_classes;
    for (int32_t priority = 0; priority < 4; ++priority) { demand_classes.push_back(demand_by_priority[priority]); delivered_classes.push_back(delivered_by_priority[priority]); }
    result["demand_by_priority"] = demand_classes; result["delivered_by_priority"] = delivered_classes;
    result["machine_drive_consumers"] = machine_drive_consumers; result["heater_consumers"] = heater_consumers;
    result["turbine_steam_throughput"] = turbine_steam_throughput;
    result["power_usec"] = last_power_usec_; result["topology_usec"] = last_power_topology_usec_; result["revision"] = static_cast<int64_t>(power_revision_);
    result["pole_record_bytes"] = static_cast<int64_t>(sizeof(PowerPoleRecord)); result["edge_record_bytes"] = static_cast<int64_t>(sizeof(PowerEdgeRecord));
    result["network_record_bytes"] = static_cast<int64_t>(sizeof(PowerNetwork)); result["consumer_record_bytes"] = static_cast<int64_t>(sizeof(PowerConsumerRecord));
    return result;
}

Dictionary NativeSandWorld::get_mechanical_statistics() const {
    Dictionary result;
    int64_t energy = 0, inertia = 0;
    for (const auto &[id, network] : mechanical_networks_) { (void)id; energy += network.rotational_energy; inertia += network.total_inertia; }
    result["segments"] = static_cast<int64_t>(std::count_if(mechanical_members_.begin(), mechanical_members_.end(), [](const auto &entry) { return entry.second.kind == MechanicalMemberKind::SHAFT; }));
    result["members"] = static_cast<int64_t>(mechanical_members_.size()); result["networks"] = static_cast<int64_t>(mechanical_networks_.size()); result["active_networks"] = last_mechanical_active_networks_;
    result["rotational_energy"] = energy; result["inertia"] = inertia; result["mechanical_usec"] = last_mechanical_usec_; result["topology_usec"] = last_mechanical_topology_usec_; result["revision"] = static_cast<int64_t>(mechanical_revision_);
    result["shaft_segment_bytes"] = static_cast<int64_t>(sizeof(MechanicalMember)); result["network_record_bytes"] = static_cast<int64_t>(sizeof(MechanicalNetwork));
    return result;
}

Dictionary NativeSandWorld::get_energy_accounting() const {
    Dictionary result;
    result["thermal_into_turbines"] = thermal_energy_into_turbines_; result["mechanical_produced"] = mechanical_energy_produced_;
    result["turbine_losses"] = turbine_losses_; result["mechanical_consumed"] = mechanical_energy_consumed_;
    result["electrical_produced"] = electrical_energy_produced_; result["electrical_consumed"] = electrical_energy_consumed_;
    result["electrical_stored"] = electrical_energy_stored_; result["electrical_discharged"] = electrical_energy_discharged_;
    result["generator_losses"] = generator_losses_; result["storage_losses"] = storage_losses_;
    return result;
}

Dictionary NativeSandWorld::get_phase10_architecture() const {
    Dictionary result;
    result["schema"] = POWER_SCHEMA_VERSION; result["energy_quantum"] = "one conserved integer quantum across thermal, mechanical and electrical domains";
    result["power_rate"] = "energy quanta per authoritative 30 Hz power tick"; result["mechanical_tick_hz"] = 30; result["electrical_tick_hz"] = 30;
    result["mechanical_topology"] = "event-driven cached N/E/S/W connected components; minimum stable member ID";
    result["electrical_topology"] = "event-driven cached pole graph; four nearest compatible poles in range; stable ID tie-break";
    result["allocation"] = "CRITICAL,HIGH,NORMAL,LOW then equal fixed-point satisfaction per class";
    result["automation_separate"] = true; result["authoritative_floats"] = false; result["transformer_boundary"] = true;
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_power_elements(Rect2i cell_area) const {
    PackedInt32Array result;
    for (const auto &[id, pole] : power_poles_) if (cell_area.has_point(pole.cell)) {
        result.push_back(1); result.push_back(pole.cell.x); result.push_back(pole.cell.y); result.push_back(static_cast<int32_t>(id)); result.push_back(static_cast<int32_t>(pole.network_id)); result.push_back(0);
    }
    for (const auto &[id, edge] : power_edges_) {
        (void)id;
        const auto a = power_poles_.find(edge.from), b = power_poles_.find(edge.to);
        if (a == power_poles_.end() || b == power_poles_.end() || (!cell_area.has_point(a->second.cell) && !cell_area.has_point(b->second.cell))) continue;
        result.push_back(2); result.push_back(a->second.cell.x); result.push_back(a->second.cell.y); result.push_back(b->second.cell.x); result.push_back(b->second.cell.y); result.push_back(edge.kind);
    }
    for (const auto &[id, network] : mechanical_networks_) {
        (void)id;
        for (const uint64_t member_id : network.members) {
            const MechanicalMember &member = mechanical_members_.at(member_id);
            if (!cell_area.has_point(member.cell)) continue;
            result.push_back(3); result.push_back(member.cell.x); result.push_back(member.cell.y); result.push_back(static_cast<int32_t>(network.id)); result.push_back(static_cast<int32_t>(network.speed_millirpm)); result.push_back(static_cast<int32_t>(member.kind));
        }
    }
    return result;
}

String NativeSandWorld::power_state_hash() const {
    uint32_t hash = 0x4b535031u;
    auto mix = [&hash](uint64_t value) { hash ^= static_cast<uint32_t>(value); hash *= 16777619u; hash ^= static_cast<uint32_t>(value >> 32u); hash *= 16777619u; };
    std::vector<uint64_t> ids;
    for (const auto &[id, network] : mechanical_networks_) { (void)network; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { const MechanicalNetwork &n = mechanical_networks_.at(id); mix(id); mix(n.rotational_energy); mix(n.total_inertia); mix(n.speed_millirpm); }
    ids.clear(); for (const auto &[id, network] : power_networks_) { (void)network; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { const PowerNetwork &n = power_networks_.at(id); mix(id); mix(n.demand_total); mix(n.delivered_total); mix(n.generation_available); mix(n.storage_charge); for (uint16_t value : n.satisfaction) mix(value); }
    ids.clear(); for (const auto &[id, accumulator] : accumulators_) { (void)accumulator; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { mix(id); mix(accumulators_.at(id).charge); }
    char buffer[16]; std::snprintf(buffer, sizeof(buffer), "%08x", hash); return String(buffer);
}

Dictionary NativeSandWorld::serialize_power_state() const {
    Dictionary state; state["schema"] = POWER_SCHEMA_VERSION;
    Array configuration;
    std::vector<uint64_t> ids;
    for (const auto &[id, turbine] : turbines_) { (void)turbine; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { Dictionary item; const TurbineRecord &t = turbines_.at(id); item["kind"] = "turbine"; item["entity_id"] = static_cast<int64_t>(id); item["target_millirpm"] = t.target_millirpm; item["max_throttle"] = t.max_throttle; item["enabled"] = t.enabled; configuration.push_back(item); }
    ids.clear(); for (const auto &[id, power_switch] : power_switches_) { (void)power_switch; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { Dictionary item; item["kind"] = "switch"; item["entity_id"] = static_cast<int64_t>(id); item["closed"] = power_switches_.at(id).closed; configuration.push_back(item); }
    state["configuration"] = configuration;
    Array mechanical_runtime;
    ids.clear(); for (const auto &[id, network] : mechanical_networks_) { (void)network; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { Dictionary item; item["network_id"] = static_cast<int64_t>(id); item["rotational_energy"] = mechanical_networks_.at(id).rotational_energy; mechanical_runtime.push_back(item); }
    state["mechanical_runtime"] = mechanical_runtime;
    Array electrical_runtime;
    ids.clear(); for (const auto &[id, network] : power_networks_) { (void)network; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const PowerNetwork &network = power_networks_.at(id); Dictionary item;
        item["network_id"] = static_cast<int64_t>(id); item["demand_total"] = network.demand_total;
        item["delivered_total"] = network.delivered_total; item["generation_available"] = network.generation_available;
        item["storage_charge"] = network.storage_charge;
        PackedInt32Array satisfaction; satisfaction.resize(network.satisfaction.size());
        for (int32_t index = 0; index < static_cast<int32_t>(network.satisfaction.size()); ++index) satisfaction[index] = network.satisfaction[index];
        item["satisfaction"] = satisfaction; electrical_runtime.push_back(item);
    }
    state["electrical_runtime"] = electrical_runtime;
    Array accumulator_runtime;
    ids.clear(); for (const auto &[id, accumulator] : accumulators_) { (void)accumulator; ids.push_back(id); } std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) { Dictionary item; item["entity_id"] = static_cast<int64_t>(id); item["charge"] = accumulators_.at(id).charge; accumulator_runtime.push_back(item); }
    state["accumulator_runtime"] = accumulator_runtime;
    state["energy_accounting"] = get_energy_accounting();
    return state;
}

bool NativeSandWorld::deserialize_power_state(Dictionary state) {
    if (static_cast<int32_t>(state.get("schema", 0)) != POWER_SCHEMA_VERSION) return false;
    if (mechanical_topology_dirty_) rebuild_mechanical_topology();
    if (electrical_topology_dirty_) rebuild_electrical_topology();
    for (const Variant &value : static_cast<Array>(state.get("configuration", Array{}))) {
        const Dictionary item = value;
        const uint64_t id = static_cast<uint64_t>(static_cast<int64_t>(item.get("entity_id", 0)));
        const String kind = item.get("kind", "");
        if (kind == "turbine" && turbines_.contains(id)) {
            turbines_.at(id).target_millirpm = static_cast<int32_t>(item.get("target_millirpm", 1800000));
            turbines_.at(id).max_throttle = static_cast<int32_t>(item.get("max_throttle", 1000)); turbines_.at(id).enabled = static_cast<bool>(item.get("enabled", true));
        } else if (kind == "switch" && power_switches_.contains(id)) { power_switches_.at(id).closed = static_cast<bool>(item.get("closed", true)); electrical_topology_dirty_ = true; }
    }
    for (const Variant &value : static_cast<Array>(state.get("mechanical_runtime", Array{}))) {
        const Dictionary item = value; const uint64_t id = static_cast<uint64_t>(static_cast<int64_t>(item.get("network_id", 0)));
        if (mechanical_networks_.contains(id)) { MechanicalNetwork &network = mechanical_networks_.at(id); network.rotational_energy = item.get("rotational_energy", int64_t{0}); update_mechanical_speed(network); }
    }
    for (const Variant &value : static_cast<Array>(state.get("electrical_runtime", Array{}))) {
        const Dictionary item = value; const uint64_t id = static_cast<uint64_t>(static_cast<int64_t>(item.get("network_id", 0)));
        if (!power_networks_.contains(id)) continue;
        PowerNetwork &network = power_networks_.at(id);
        network.demand_total = item.get("demand_total", int64_t{0}); network.delivered_total = item.get("delivered_total", int64_t{0});
        network.generation_available = item.get("generation_available", int64_t{0}); network.storage_charge = item.get("storage_charge", int64_t{0});
        const PackedInt32Array satisfaction = item.get("satisfaction", PackedInt32Array{});
        if (satisfaction.size() == static_cast<int32_t>(network.satisfaction.size()))
            for (int32_t index = 0; index < satisfaction.size(); ++index) network.satisfaction[index] = static_cast<uint16_t>(std::clamp(satisfaction[index], 0, 1000));
    }
    for (const Variant &value : static_cast<Array>(state.get("accumulator_runtime", Array{}))) {
        const Dictionary item = value; const uint64_t id = static_cast<uint64_t>(static_cast<int64_t>(item.get("entity_id", 0)));
        if (accumulators_.contains(id)) accumulators_.at(id).charge = std::clamp<int64_t>(item.get("charge", int64_t{0}), 0, accumulators_.at(id).capacity);
    }
    const Dictionary accounting = state.get("energy_accounting", Dictionary{});
    thermal_energy_into_turbines_ = accounting.get("thermal_into_turbines", int64_t{0}); mechanical_energy_produced_ = accounting.get("mechanical_produced", int64_t{0});
    turbine_losses_ = accounting.get("turbine_losses", int64_t{0}); mechanical_energy_consumed_ = accounting.get("mechanical_consumed", int64_t{0});
    electrical_energy_produced_ = accounting.get("electrical_produced", int64_t{0}); electrical_energy_consumed_ = accounting.get("electrical_consumed", int64_t{0});
    electrical_energy_stored_ = accounting.get("electrical_stored", int64_t{0}); electrical_energy_discharged_ = accounting.get("electrical_discharged", int64_t{0});
    generator_losses_ = accounting.get("generator_losses", int64_t{0}); storage_losses_ = accounting.get("storage_losses", int64_t{0});
    return true;
}

Dictionary NativeSandWorld::configure_power_benchmark(int32_t scenario, int32_t count) {
    if (count < 0 || count > 250000) return Dictionary{};
    reset_power();
    if (scenario == 0 || scenario == 1) {
        for (int32_t index = 0; index < count; ++index) {
            MechanicalMember member; member.id = shaft_member_id(static_cast<uint64_t>(index + 1));
            member.cell = scenario == 0 ? Vector2i(index, 0) : Vector2i(index * 2, 0); member.inertia = SHAFT_INERTIA; member.kind = MechanicalMemberKind::SHAFT;
            mechanical_members_[member.id] = member;
        }
        mechanical_topology_dirty_ = true; rebuild_mechanical_topology();
        if (scenario == 1) for (auto &[id, network] : mechanical_networks_) { (void)id; network.rotational_energy = 1000000; update_mechanical_speed(network); }
    } else {
        const int32_t width = std::max(1, static_cast<int32_t>(std::sqrt(static_cast<double>(count))));
        for (int32_t index = 0; index < count; ++index) {
            const int32_t spacing = scenario == 4 ? POWER_POLE_RANGE + 2 : 8;
            PowerPoleRecord pole; pole.id = pole_id(static_cast<uint64_t>(index + 1)); pole.cell = {index % width * spacing, index / width * spacing}; power_poles_[pole.id] = pole;
            PowerConsumerRecord consumer; consumer.id = AUX_CONSUMER_MASK | static_cast<uint64_t>(index + 1); consumer.tap = pole.cell; consumer.requested_rate = 1000; consumer.priority = static_cast<uint8_t>(index & 3); power_consumers_[consumer.id] = consumer;
        }
        electrical_topology_dirty_ = true; rebuild_electrical_topology();
        if (scenario == 3) {
            for (auto &[id, consumer] : power_consumers_) { (void)id; consumer.requested_rate = 2000; }
            rebuild_power_aggregates();
        }
    }
    Dictionary result = get_power_statistics();
    result.merge(get_mechanical_statistics());
    return result;
}

} // namespace godot
