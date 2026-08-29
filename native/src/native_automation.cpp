#include "native_sand_world.hpp"

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <limits>
#include <queue>

namespace godot {

namespace {
constexpr int32_t AUTO_MANUAL_SWITCH = 1;
constexpr int32_t AUTO_MATERIAL_SENSOR = 2;
constexpr int32_t AUTO_LEVEL_SENSOR = 3;
constexpr int32_t AUTO_NOT = 4;
constexpr int32_t AUTO_AND = 5;
constexpr int32_t AUTO_OR = 6;
constexpr int32_t AUTO_COMPARATOR = 7;
constexpr int32_t AUTO_MACHINE_SENSOR = 8;
constexpr int32_t AUTO_TIMER = 9;
constexpr int32_t AUTO_LATCH = 10;
constexpr int32_t AUTO_CONVEYOR_CONTROL = 11;
constexpr int32_t AUTO_MACHINE_CONTROL = 12;
constexpr int32_t AUTO_GATE_CONTROL = 13;
constexpr int32_t AUTO_PUMP_CONTROL = 14;
constexpr int32_t AUTO_VALVE_CONTROL = 15;
constexpr int32_t AUTO_FLOW_METER = 16;
constexpr int32_t AUTO_PIPE_FILL_SENSOR = 17;
constexpr int32_t AUTO_TEMPERATURE_SENSOR = 18;
constexpr int32_t AUTO_PIPE_TEMPERATURE_SENSOR = 19;
constexpr int32_t AUTO_PIPE_PRESSURE_SENSOR = 20;
constexpr int32_t AUTO_THERMAL_SWITCH_CONTROL = 21;
constexpr int32_t AUTO_POWER_NETWORK_SENSOR = 22;
constexpr int32_t AUTO_SHAFT_SPEED_SENSOR = 23;
constexpr int32_t AUTO_POWER_SWITCH_CONTROL = 24;
constexpr int32_t STRUCTURE_GATE = 9;
constexpr int32_t MACHINE_DISABLED = 10;

} // namespace

const std::vector<NativeSandWorld::AutomationDefinition> &NativeSandWorld::automation_definitions() {
    static const std::vector<AutomationDefinition> definitions{
        {AUTO_MANUAL_SWITCH, "manual_switch", "Manual Switch", "automation.basic_sensing", 0, 1, false, false, true},
        {AUTO_MATERIAL_SENSOR, "material_sensor", "Material Sensor", "automation.basic_sensing", 0, 1, true, false, true},
        {AUTO_LEVEL_SENSOR, "level_sensor", "Level Sensor", "automation.basic_sensing", 0, 1, true, false, false},
        {AUTO_NOT, "not", "NOT", "automation.logic_control", 1, 1, false, false, false},
        {AUTO_AND, "and", "AND", "automation.logic_control", 2, 1, false, false, false},
        {AUTO_OR, "or", "OR", "automation.logic_control", 2, 1, false, false, false},
        {AUTO_COMPARATOR, "comparator", "Comparator", "automation.logic_control", 1, 1, false, false, false},
        {AUTO_MACHINE_SENSOR, "machine_state_sensor", "Machine State Sensor", "automation.machine_control", 0, 1, true, false, false},
        {AUTO_TIMER, "timer", "Timer", "automation.timed_control", 1, 1, false, false, true},
        {AUTO_LATCH, "latch", "Memory Latch", "automation.timed_control", 2, 1, false, false, true},
        {AUTO_CONVEYOR_CONTROL, "conveyor_control", "Conveyor Control", "automation.machine_control", 1, 0, false, true, false},
        {AUTO_MACHINE_CONTROL, "machine_control", "Machine Enable", "automation.machine_control", 1, 0, false, true, false},
        {AUTO_GATE_CONTROL, "control_gate", "Control Gate", "automation.advanced_routing", 1, 0, false, true, true},
        {AUTO_PUMP_CONTROL, "pump_enable", "Pump Enable", "fluid.flow_control", 1, 0, false, true, false},
        {AUTO_VALVE_CONTROL, "pipe_valve", "Pipe Valve Control", "fluid.flow_control", 1, 0, false, true, true},
        {AUTO_FLOW_METER, "flow_meter", "Flow Meter", "fluid.flow_control", 0, 1, true, false, true},
        {AUTO_PIPE_FILL_SENSOR, "pipe_fill_sensor", "Pipe Fill Sensor", "fluid.flow_control", 0, 1, true, false, false},
        {AUTO_TEMPERATURE_SENSOR, "temperature_sensor", "Temperature Sensor", "thermal.basic_thermodynamics", 0, 1, true, false, false},
        {AUTO_PIPE_TEMPERATURE_SENSOR, "pipe_temperature_sensor", "Pipe Temperature Sensor", "thermal.steam_handling", 0, 1, true, false, false},
        {AUTO_PIPE_PRESSURE_SENSOR, "pipe_pressure_sensor", "Pipe Pressure Sensor", "thermal.steam_handling", 0, 1, true, false, false},
        {AUTO_THERMAL_SWITCH_CONTROL, "thermal_switch", "Thermal Switch Control", "thermal.basic_thermodynamics", 1, 0, false, true, true},
        {AUTO_POWER_NETWORK_SENSOR, "power_network_sensor", "Power Network Sensor", "power.electrical_distribution", 0, 1, true, false, false},
        {AUTO_SHAFT_SPEED_SENSOR, "shaft_speed_sensor", "Shaft Speed Sensor", "power.grid_control", 0, 1, true, false, false},
        {AUTO_POWER_SWITCH_CONTROL, "power_switch", "Power Switch Control", "power.grid_control", 1, 0, false, true, true},
    };
    return definitions;
}

const NativeSandWorld::AutomationDefinition *NativeSandWorld::automation_definition(int32_t type_id) {
    const auto &definitions = automation_definitions();
    const auto found = std::find_if(definitions.begin(), definitions.end(), [type_id](const AutomationDefinition &definition) {
        return definition.type_id == type_id;
    });
    return found == definitions.end() ? nullptr : &*found;
}

uint64_t NativeSandWorld::automation_input_key(uint64_t component_id, int32_t port) {
    return (component_id << 2u) | static_cast<uint64_t>(port & 3);
}

bool NativeSandWorld::automation_unlocked(int32_t type_id) const {
    const AutomationDefinition *definition = automation_definition(type_id);
    return definition != nullptr && (game_mode_ == 1 || has_research(definition->unlock_key));
}

Array NativeSandWorld::get_automation_definitions() const {
    Array result;
    for (const AutomationDefinition &definition : automation_definitions()) {
        Dictionary item;
        item["type_id"] = definition.type_id;
        item["id"] = definition.stable_id;
        item["display_name"] = definition.display_name;
        item["unlock_key"] = definition.unlock_key;
        item["input_count"] = definition.input_count;
        item["output_count"] = definition.output_count;
        item["sensor"] = definition.sensor;
        item["actuator"] = definition.actuator;
        item["stateful"] = definition.stateful;
        item["unlocked"] = automation_unlocked(definition.type_id);
        result.push_back(item);
    }
    return result;
}

void NativeSandWorld::reset_automation() {
    next_automation_component_id_ = 1;
    next_automation_connection_id_ = 1;
    automation_revision_ = 0;
    automation_components_.clear();
    automation_connections_.clear();
    automation_outgoing_.clear();
    automation_input_sources_.clear();
    automation_cell_watchers_.clear();
    automation_machine_watchers_.clear();
    automation_dirty_.clear();
    automation_scheduled_.clear();
    controlled_belts_.clear();
    open_gate_cells_.clear();
    blocked_gate_components_.clear();
    last_automation_awake_ = last_automation_signals_changed_ = 0;
    last_automation_sensor_evaluations_ = last_automation_logic_evaluations_ = 0;
    last_automation_actuator_changes_ = last_automation_usec_ = last_automation_topology_usec_ = 0;
}

void NativeSandWorld::unregister_component_watchers(const AutomationComponent &component) {
    for (const uint64_t key : component.watched_cells) {
        auto found = automation_cell_watchers_.find(key);
        if (found == automation_cell_watchers_.end()) continue;
        std::erase(found->second, component.id);
        if (found->second.empty()) automation_cell_watchers_.erase(found);
    }
    if (component.target_machine_id != 0) {
        auto found = automation_machine_watchers_.find(component.target_machine_id);
        if (found != automation_machine_watchers_.end()) {
            std::erase(found->second, component.id);
            if (found->second.empty()) automation_machine_watchers_.erase(found);
        }
    }
}

uint64_t NativeSandWorld::machine_id_at(Vector2i world_cell) const {
    for (const auto &[id, machine] : machine_entities_) {
        const StructureDefinition *definition = structure_definition(machine.type_id);
        if (definition == nullptr) continue;
        for (const Vector2i occupied : transformed_occupied(*definition, machine.origin, machine.orientation)) {
            if (occupied == world_cell) return id;
        }
    }
    return 0;
}

void NativeSandWorld::rebuild_component_watchers(AutomationComponent &component) {
    component.watched_cells.clear();
    if (component.type_id == AUTO_MATERIAL_SENSOR || component.type_id == AUTO_LEVEL_SENSOR || component.type_id == AUTO_TEMPERATURE_SENSOR) {
        const int32_t width = std::clamp(component.probe_size.x, 1, component.type_id == AUTO_MATERIAL_SENSOR ? 3 : 64);
        const int32_t height = std::clamp(component.probe_size.y, 1, component.type_id == AUTO_MATERIAL_SENSOR ? 3 : 64);
        const int32_t orientation = ((component.orientation % 4) + 4) % 4;
        for (int32_t y = 0; y < height; ++y) {
            for (int32_t x = 0; x < width; ++x) {
                Vector2i offset{x, y};
                if (orientation == 1) offset = {-y, x};
                else if (orientation == 2) offset = {-x, -y};
                else if (orientation == 3) offset = {y, -x};
                const Vector2i cell = component.target_position + offset;
                const uint64_t key = cell_key(cell);
                component.watched_cells.push_back(key);
                automation_cell_watchers_[key].push_back(component.id);
            }
        }
    } else if (component.type_id == AUTO_GATE_CONTROL || component.type_id == AUTO_PUMP_CONTROL ||
               component.type_id == AUTO_VALVE_CONTROL || component.type_id == AUTO_FLOW_METER ||
               component.type_id == AUTO_PIPE_FILL_SENSOR || component.type_id == AUTO_PIPE_TEMPERATURE_SENSOR ||
               component.type_id == AUTO_PIPE_PRESSURE_SENSOR || component.type_id == AUTO_THERMAL_SWITCH_CONTROL) {
        const uint64_t key = cell_key(component.target_position);
        component.watched_cells.push_back(key);
        automation_cell_watchers_[key].push_back(component.id);
    } else if (component.type_id == AUTO_POWER_NETWORK_SENSOR || component.type_id == AUTO_SHAFT_SPEED_SENSOR || component.type_id == AUTO_POWER_SWITCH_CONTROL) {
        const uint64_t key = cell_key(component.target_position);
        component.watched_cells.push_back(key);
        automation_cell_watchers_[key].push_back(component.id);
    } else if (component.type_id == AUTO_MACHINE_SENSOR) {
        component.target_machine_id = machine_id_at(component.target_position);
        if (component.target_machine_id != 0) automation_machine_watchers_[component.target_machine_id].push_back(component.id);
    }
}

int64_t NativeSandWorld::create_automation_component(int32_t type_id, Vector2i position, Dictionary configuration) {
    const auto started = std::chrono::steady_clock::now();
    const AutomationDefinition *definition = automation_definition(type_id);
    if (definition == nullptr || !automation_unlocked(type_id)) return 0;
    AutomationComponent component;
    component.id = next_automation_component_id_++;
    component.type_id = type_id;
    component.position = position;
    component.target_position = position;
    automation_components_.emplace(component.id, component);
    if (!configure_automation_component(static_cast<int64_t>(component.id), configuration)) {
        automation_components_.erase(component.id);
        return 0;
    }
    ++automation_revision_;
    last_automation_topology_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return static_cast<int64_t>(component.id);
}

bool NativeSandWorld::configure_automation_component(int64_t component_id, Dictionary configuration) {
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end()) return false;
    AutomationComponent &component = found->second;
    unregister_component_watchers(component);
    component.orientation = static_cast<int32_t>(configuration.get("orientation", component.orientation));
    component.mode = static_cast<int32_t>(configuration.get("mode", component.mode));
    component.material_id = static_cast<int32_t>(configuration.get("material_id", component.material_id));
    component.probe_size = configuration.get("probe_size", component.probe_size);
    if (component.type_id == AUTO_MATERIAL_SENSOR) {
        component.probe_size.x = component.probe_size.x >= 3 ? 3 : 1;
        component.probe_size.y = component.probe_size.y >= 3 ? 3 : 1;
        component.pulse_pending = false;
    }
    component.threshold = static_cast<int32_t>(configuration.get("threshold", component.threshold));
    component.compare_op = static_cast<int32_t>(configuration.get("operator", component.compare_op));
    component.period_ticks = std::max(1, static_cast<int32_t>(configuration.get("period_ticks", component.period_ticks)));
    component.on_ticks = std::clamp(static_cast<int32_t>(configuration.get("on_ticks", component.on_ticks)), 1, component.period_ticks);
    component.target_position = configuration.get("target_position", component.target_position);
    component.target_machine_id = static_cast<uint64_t>(static_cast<int64_t>(configuration.get("target_machine_id", static_cast<int64_t>(component.target_machine_id))));
    component.manual_state = static_cast<bool>(configuration.get("enabled", component.manual_state));
    if (component.type_id == AUTO_TIMER && component.mode == 0 && component.timer_remaining == 0) component.timer_remaining = component.period_ticks;
    rebuild_component_watchers(component);
    automation_dirty_.insert(component.id);
    ++automation_revision_;
    return true;
}

bool NativeSandWorld::set_manual_switch(int64_t component_id, bool enabled) {
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end() || found->second.type_id != AUTO_MANUAL_SWITCH) return false;
    if (found->second.manual_state != enabled) {
        found->second.manual_state = enabled;
        automation_dirty_.insert(found->first);
        ++automation_revision_;
    }
    return true;
}

bool NativeSandWorld::set_automation_input_for_test(int64_t component_id, int32_t port, int32_t value) {
    if (game_mode_ != 1 || port < 0 || port >= 2) return false;
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end()) return false;
    const AutomationDefinition *definition = automation_definition(found->second.type_id);
    if (definition == nullptr || port >= definition->input_count || automation_input_sources_.contains(automation_input_key(found->first, port))) return false;
    found->second.inputs[port] = value;
    found->second.target_connected = true;
    automation_dirty_.insert(found->first);
    return true;
}

int64_t NativeSandWorld::create_automation_connection(int64_t source_component, int32_t source_port, int64_t target_component, int32_t target_port) {
    const auto started = std::chrono::steady_clock::now();
    const auto source = automation_components_.find(static_cast<uint64_t>(source_component));
    const auto target = automation_components_.find(static_cast<uint64_t>(target_component));
    if (source == automation_components_.end() || target == automation_components_.end()) return 0;
    const AutomationDefinition *source_definition = automation_definition(source->second.type_id);
    const AutomationDefinition *target_definition = automation_definition(target->second.type_id);
    if (source_definition == nullptr || target_definition == nullptr || source_port < 0 || source_port >= source_definition->output_count ||
        target_port < 0 || target_port >= target_definition->input_count) return 0;
    const uint64_t input_key = automation_input_key(target->first, target_port);
    if (automation_input_sources_.contains(input_key)) return 0;
    AutomationConnection connection;
    connection.id = next_automation_connection_id_++;
    connection.source_component = source->first;
    connection.source_port = static_cast<uint8_t>(source_port);
    connection.target_component = target->first;
    connection.target_port = static_cast<uint8_t>(target_port);
    automation_connections_.emplace(connection.id, connection);
    automation_outgoing_[source->first].push_back(connection.id);
    automation_input_sources_[input_key] = connection.id;
    target->second.inputs[target_port] = source->second.output;
    target->second.target_connected = true;
    automation_dirty_.insert(target->first);
    ++automation_revision_;
    last_automation_topology_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return static_cast<int64_t>(connection.id);
}

bool NativeSandWorld::remove_automation_connection(int64_t connection_id) {
    const auto started = std::chrono::steady_clock::now();
    const auto found = automation_connections_.find(static_cast<uint64_t>(connection_id));
    if (found == automation_connections_.end()) return false;
    const AutomationConnection connection = found->second;
    automation_input_sources_.erase(automation_input_key(connection.target_component, connection.target_port));
    auto outgoing = automation_outgoing_.find(connection.source_component);
    if (outgoing != automation_outgoing_.end()) {
        std::erase(outgoing->second, connection.id);
        if (outgoing->second.empty()) automation_outgoing_.erase(outgoing);
    }
    auto target = automation_components_.find(connection.target_component);
    if (target != automation_components_.end()) {
        target->second.inputs[connection.target_port] = 0;
        target->second.target_connected = false;
        for (int32_t port = 0; port < 2; ++port) {
            if (automation_input_sources_.contains(automation_input_key(target->first, port))) target->second.target_connected = true;
        }
        automation_dirty_.insert(target->first);
    }
    automation_connections_.erase(found);
    ++automation_revision_;
    last_automation_topology_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return true;
}

int32_t NativeSandWorld::remove_component_connections(int64_t component_id) {
    std::vector<uint64_t> ids;
    for (const auto &[id, connection] : automation_connections_) {
        if (connection.source_component == static_cast<uint64_t>(component_id) || connection.target_component == static_cast<uint64_t>(component_id)) ids.push_back(id);
    }
    for (const uint64_t id : ids) remove_automation_connection(static_cast<int64_t>(id));
    return static_cast<int32_t>(ids.size());
}

bool NativeSandWorld::remove_automation_component(int64_t component_id) {
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end()) return false;
    remove_component_connections(component_id);
    unregister_component_watchers(found->second);
    controlled_belts_.erase(cell_key(found->second.target_position));
    open_gate_cells_.erase(cell_key(found->second.target_position));
    blocked_gate_components_.erase(found->first);
    automation_dirty_.erase(found->first);
    automation_scheduled_.erase(found->first);
    automation_components_.erase(found);
    ++automation_revision_;
    return true;
}

Array NativeSandWorld::get_automation_component_ports(int64_t component_id) const {
    Array result;
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end()) return result;
    const AutomationDefinition *definition = automation_definition(found->second.type_id);
    for (int32_t port = 0; port < definition->input_count; ++port) {
        Dictionary item;
        item["port_id"] = port;
        item["direction"] = 0;
        item["value"] = found->second.inputs[port];
        item["connected"] = automation_input_sources_.contains(automation_input_key(found->first, port));
        result.push_back(item);
    }
    for (int32_t port = 0; port < definition->output_count; ++port) {
        Dictionary item;
        item["port_id"] = port;
        item["direction"] = 1;
        item["value"] = found->second.output;
        item["connected"] = automation_outgoing_.contains(found->first);
        result.push_back(item);
    }
    return result;
}

Dictionary NativeSandWorld::get_automation_component_state(int64_t component_id) const {
    Dictionary result;
    const auto found = automation_components_.find(static_cast<uint64_t>(component_id));
    if (found == automation_components_.end()) return result;
    const AutomationComponent &component = found->second;
    result["id"] = static_cast<int64_t>(component.id);
    result["type_id"] = component.type_id;
    result["position"] = component.position;
    result["orientation"] = component.orientation;
    result["input_a"] = component.inputs[0];
    result["input_b"] = component.inputs[1];
    result["output"] = component.output;
    result["mode"] = component.mode;
    result["material_id"] = component.material_id;
    result["probe_size"] = component.probe_size;
    result["threshold"] = component.threshold;
    result["operator"] = component.compare_op;
    result["period_ticks"] = component.period_ticks;
    result["on_ticks"] = component.on_ticks;
    result["timer_remaining"] = component.timer_remaining;
    result["pulse_pending"] = component.pulse_pending;
    result["stored_state"] = component.stored_state;
    result["enabled"] = component.manual_state;
    result["target_position"] = component.target_position;
    result["target_machine_id"] = static_cast<int64_t>(component.target_machine_id);
    result["target_connected"] = component.target_connected;
    result["gate_desired_open"] = component.gate_desired_open;
    result["gate_actual_open"] = component.gate_actual_open;
    result["gate_close_blocked"] = component.gate_close_blocked;
    return result;
}

Dictionary NativeSandWorld::get_automation_subgraph(int64_t component_id, int32_t max_components) const {
    Dictionary result;
    Array components;
    Array connections;
    if (!automation_components_.contains(static_cast<uint64_t>(component_id)) || max_components <= 0) {
        result["components"] = components;
        result["connections"] = connections;
        return result;
    }
    std::queue<uint64_t> pending;
    std::unordered_set<uint64_t> visited;
    pending.push(static_cast<uint64_t>(component_id));
    visited.insert(static_cast<uint64_t>(component_id));
    while (!pending.empty() && static_cast<int32_t>(visited.size()) <= max_components) {
        const uint64_t current = pending.front();
        pending.pop();
        components.push_back(get_automation_component_state(static_cast<int64_t>(current)));
        for (const auto &[id, connection] : automation_connections_) {
            if (connection.source_component != current && connection.target_component != current) continue;
            Dictionary edge;
            edge["id"] = static_cast<int64_t>(id);
            edge["source"] = static_cast<int64_t>(connection.source_component);
            edge["source_port"] = connection.source_port;
            edge["target"] = static_cast<int64_t>(connection.target_component);
            edge["target_port"] = connection.target_port;
            connections.push_back(edge);
            const uint64_t neighbor = connection.source_component == current ? connection.target_component : connection.source_component;
            if (static_cast<int32_t>(visited.size()) < max_components && visited.insert(neighbor).second) pending.push(neighbor);
        }
    }
    result["components"] = components;
    result["connections"] = connections;
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_automation_components(Rect2i cell_area) const {
    PackedInt32Array result;
    std::vector<const AutomationComponent *> visible;
    for (const auto &[id, component] : automation_components_) {
        (void)id;
        if (cell_area.has_point(component.position)) visible.push_back(&component);
    }
    std::sort(visible.begin(), visible.end(), [](const AutomationComponent *a, const AutomationComponent *b) { return a->id < b->id; });
    for (const AutomationComponent *component : visible) {
        result.push_back(static_cast<int32_t>(component->id));
        result.push_back(component->position.x);
        result.push_back(component->position.y);
        result.push_back(component->type_id);
        result.push_back(component->output);
        result.push_back(component->inputs[0]);
        result.push_back(component->inputs[1]);
    }
    return result;
}

PackedInt32Array NativeSandWorld::get_visible_automation_connections(Rect2i cell_area) const {
    PackedInt32Array result;
    std::vector<const AutomationConnection *> visible;
    for (const auto &[id, connection] : automation_connections_) {
        (void)id;
        const auto source = automation_components_.find(connection.source_component);
        const auto target = automation_components_.find(connection.target_component);
        if (source == automation_components_.end() || target == automation_components_.end()) continue;
        if (cell_area.has_point(source->second.position) || cell_area.has_point(target->second.position)) visible.push_back(&connection);
    }
    std::sort(visible.begin(), visible.end(), [](const AutomationConnection *a, const AutomationConnection *b) { return a->id < b->id; });
    for (const AutomationConnection *connection : visible) {
        const AutomationComponent &source = automation_components_.at(connection->source_component);
        const AutomationComponent &target = automation_components_.at(connection->target_component);
        result.push_back(static_cast<int32_t>(connection->id));
        result.push_back(source.position.x);
        result.push_back(source.position.y);
        result.push_back(target.position.x);
        result.push_back(target.position.y);
        result.push_back(source.output);
    }
    return result;
}

void NativeSandWorld::notify_automation_cell_change(Vector2i world_cell) {
    if (automation_cell_watchers_.empty() && blocked_gate_components_.empty()) return;
    const uint64_t key = cell_key(world_cell);
    const auto watchers = automation_cell_watchers_.find(key);
    if (watchers != automation_cell_watchers_.end()) {
        for (const uint64_t id : watchers->second) {
            auto component = automation_components_.find(id);
            if (component != automation_components_.end() && component->second.type_id == AUTO_MATERIAL_SENSOR &&
                component->second.mode == 2 && get_cell(world_cell) == component->second.material_id) {
                component->second.pulse_pending = true;
            }
            automation_dirty_.insert(id);
        }
    }
}

void NativeSandWorld::notify_automation_machine_change(uint64_t machine_id) {
    if (automation_machine_watchers_.empty()) return;
    const auto watchers = automation_machine_watchers_.find(machine_id);
    if (watchers == automation_machine_watchers_.end()) return;
    for (const uint64_t id : watchers->second) automation_dirty_.insert(id);
}

int32_t NativeSandWorld::sample_material_sensor(AutomationComponent &component) const {
    int32_t count = 0;
    int32_t water_mass = 0;
    for (const uint64_t key : component.watched_cells) {
        const Vector2i cell = cell_from_key(key);
        if (get_cell(cell) == component.material_id) {
            ++count;
            if (component.material_id == 3) water_mass += get_liquid_mass(cell);
        }
    }
    if (component.mode == 0) return count > 0 ? 1 : 0;
    if (component.mode == 1) return count;
    if (component.mode == 3 && component.material_id == 3) return water_mass;
    return count > component.previous_sample ? 1 : 0;
}

int32_t NativeSandWorld::sample_level_sensor(AutomationComponent &component) const {
    int64_t fill_mass = 0;
    for (const uint64_t key : component.watched_cells) {
        const Vector2i cell = cell_from_key(key);
        const int32_t material = get_cell(cell);
        if (material == 3) fill_mass += get_liquid_mass(cell);
        else if (material != 0) fill_mass += 255;
    }
    if (component.mode == 0) return static_cast<int32_t>(fill_mass / 255);
    const int32_t capacity = std::max(1, static_cast<int32_t>(component.watched_cells.size()));
    const int32_t fill = static_cast<int32_t>((fill_mass * 1000) / (static_cast<int64_t>(capacity) * 255));
    if (component.mode == 1) return fill;
    if (component.mode == 2) return fill >= component.threshold ? 1 : 0;
    return fill <= component.threshold ? 1 : 0;
}

int32_t NativeSandWorld::evaluate_automation_component(AutomationComponent &component) {
    const int32_t input_a = component.inputs[0];
    const int32_t input_b = component.inputs[1];
    switch (component.type_id) {
        case AUTO_MANUAL_SWITCH: return component.manual_state ? 1 : 0;
        case AUTO_MATERIAL_SENSOR: {
            if (component.mode == 2) {
                const int32_t pulse = component.pulse_pending ? 1 : 0;
                component.pulse_pending = false;
                return pulse;
            }
            return sample_material_sensor(component);
        }
        case AUTO_LEVEL_SENSOR: return sample_level_sensor(component);
        case AUTO_FLOW_METER: {
            const Dictionary state = get_pipe_state(component.target_position);
            return state.is_empty() ? 0 : std::abs(static_cast<int32_t>(state.get("flow", 0)));
        }
        case AUTO_PIPE_FILL_SENSOR: {
            const Dictionary state = get_pipe_state(component.target_position);
            return state.is_empty() ? 0 : static_cast<int32_t>(state.get("fill_per_mille", 0));
        }
        case AUTO_TEMPERATURE_SENSOR: {
            if (component.watched_cells.empty()) return 0;
            int64_t total = 0;
            for (uint64_t key : component.watched_cells) total += get_temperature(cell_from_key(key));
            return static_cast<int32_t>(total / static_cast<int64_t>(component.watched_cells.size()));
        }
        case AUTO_PIPE_TEMPERATURE_SENSOR: {
            const Dictionary state = get_pipe_state(component.target_position);
            return state.is_empty() ? 0 : static_cast<int32_t>(state.get("temperature", 0));
        }
        case AUTO_PIPE_PRESSURE_SENSOR: {
            const Dictionary state = get_pipe_state(component.target_position);
            return state.is_empty() ? 0 : static_cast<int32_t>(state.get("pressure", 0));
        }
        case AUTO_POWER_NETWORK_SENSOR: {
            const Dictionary power = get_power_state_at(component.target_position);
            const int64_t network_id = power.get("power_network_id", static_cast<int64_t>(0));
            const Dictionary network = get_power_network_state(network_id);
            if (network.is_empty()) return 0;
            const int64_t demand = network.get("demand", static_cast<int64_t>(0));
            if (component.mode == 0) return demand <= 0 ? 1000 : static_cast<int32_t>(std::min<int64_t>(1000, static_cast<int64_t>(network.get("delivered", static_cast<int64_t>(0))) * 1000 / demand));
            if (component.mode == 1) return static_cast<int32_t>(std::min<int64_t>(std::numeric_limits<int32_t>::max(), network.get("generation", static_cast<int64_t>(0))));
            if (component.mode == 2) return static_cast<int32_t>(std::min<int64_t>(std::numeric_limits<int32_t>::max(), demand));
            if (component.mode == 3) return static_cast<int32_t>(std::min<int64_t>(std::numeric_limits<int32_t>::max(), network.get("surplus", static_cast<int64_t>(0))));
            const int64_t capacity = network.get("storage_capacity", static_cast<int64_t>(0));
            return capacity <= 0 ? 0 : static_cast<int32_t>(static_cast<int64_t>(network.get("storage", static_cast<int64_t>(0))) * 1000 / capacity);
        }
        case AUTO_SHAFT_SPEED_SENSOR: return static_cast<int32_t>(std::min<int64_t>(std::numeric_limits<int32_t>::max(), get_power_state_at(component.target_position).get("speed_millirpm", static_cast<int64_t>(0))));
        case AUTO_NOT: return input_a == 0 ? 1 : 0;
        case AUTO_AND: return input_a != 0 && input_b != 0 ? 1 : 0;
        case AUTO_OR: return input_a != 0 || input_b != 0 ? 1 : 0;
        case AUTO_COMPARATOR:
            switch (component.compare_op) {
                case 0: return input_a > component.threshold ? 1 : 0;
                case 1: return input_a >= component.threshold ? 1 : 0;
                case 2: return input_a < component.threshold ? 1 : 0;
                case 3: return input_a <= component.threshold ? 1 : 0;
                case 4: return input_a == component.threshold ? 1 : 0;
                default: return input_a != component.threshold ? 1 : 0;
            }
        case AUTO_MACHINE_SENSOR: {
            const auto machine = machine_entities_.find(component.target_machine_id);
            if (machine == machine_entities_.end()) return 0;
            const Dictionary power = get_power_state_at(component.target_position);
            const int32_t state = power.has("state") ? static_cast<int32_t>(power.get("state", 0)) : machine->second.state;
            return state == component.mode ? 1 : 0;
        }
        case AUTO_TIMER: {
            if (component.mode == 0) {
                if (input_a == 0) { component.timer_remaining = component.period_ticks; automation_scheduled_.erase(component.id); return 0; }
                automation_scheduled_.insert(component.id);
                if (component.timer_remaining > 0) --component.timer_remaining;
                return component.timer_remaining == 0 ? 1 : 0;
            }
            if (component.mode == 1) {
                if (input_a != 0 && component.previous_sample == 0) component.timer_remaining = component.on_ticks;
                component.previous_sample = input_a;
                const int32_t output = component.timer_remaining > 0 ? 1 : 0;
                if (component.timer_remaining > 0) --component.timer_remaining;
                if (component.timer_remaining > 0) automation_scheduled_.insert(component.id); else automation_scheduled_.erase(component.id);
                return output;
            }
            if (input_a == 0) { component.timer_remaining = 0; automation_scheduled_.erase(component.id); return 0; }
            automation_scheduled_.insert(component.id);
            component.timer_remaining = (component.timer_remaining + 1) % component.period_ticks;
            return component.timer_remaining < component.on_ticks ? 1 : 0;
        }
        case AUTO_LATCH:
            if (input_b != 0) component.stored_state = false;
            else if (input_a != 0) component.stored_state = true;
            return component.stored_state ? 1 : 0;
        case AUTO_CONVEYOR_CONTROL:
        case AUTO_MACHINE_CONTROL:
        case AUTO_GATE_CONTROL:
        case AUTO_PUMP_CONTROL:
        case AUTO_VALVE_CONTROL:
        case AUTO_THERMAL_SWITCH_CONTROL:
        case AUTO_POWER_SWITCH_CONTROL:
            return input_a;
        default: return 0;
    }
}

void NativeSandWorld::apply_automation_actuator(AutomationComponent &component) {
    const bool enabled = component.type_id == AUTO_GATE_CONTROL ? component.inputs[0] != 0 : !component.target_connected || component.inputs[0] != 0;
    if (component.type_id == AUTO_CONVEYOR_CONTROL) {
        const uint64_t key = cell_key(component.target_position);
        const auto previous = controlled_belts_.find(key);
        if (previous == controlled_belts_.end() || previous->second != enabled) {
            controlled_belts_[key] = enabled;
            Chunk *chunk = get_chunk(world_to_chunk(component.target_position));
            if (chunk != nullptr && chunk->structures != nullptr) {
                uint8_t &record = (*chunk->structures)[local_index(world_to_local(component.target_position))];
                const uint8_t type_id = record & 0x7fu;
                if (type_id == 1 || type_id == 2) record = enabled ? type_id : static_cast<uint8_t>(type_id | 0x80u);
            }
            if (enabled) active_belts_.insert(key);
            ++last_automation_actuator_changes_;
        }
    } else if (component.type_id == AUTO_MACHINE_CONTROL) {
        uint64_t id = component.target_machine_id != 0 ? component.target_machine_id : machine_id_at(component.target_position);
        auto machine = machine_entities_.find(id);
        if (machine != machine_entities_.end() && (!machine->second.control_connected || machine->second.control_enabled != enabled)) {
            machine->second.control_connected = component.target_connected;
            machine->second.control_enabled = enabled;
            if (machine->second.type_id == 5) active_heaters_.insert(id);
            else if (machine->second.type_id == 6) active_screens_.insert(id);
            else if (machine->second.type_id == 7) active_magnets_.insert(id);
            else active_machines_.insert(id);
            if (turbines_.contains(id)) turbines_.at(id).enabled = enabled;
            if (generators_.contains(id)) generators_.at(id).enabled = enabled;
            ++last_automation_actuator_changes_;
        }
    } else if (component.type_id == AUTO_PUMP_CONTROL) {
        if (set_pipe_device_enabled(component.target_position, enabled)) ++last_automation_actuator_changes_;
    } else if (component.type_id == AUTO_VALVE_CONTROL) {
        if (set_pipe_valve_open(component.target_position, enabled)) ++last_automation_actuator_changes_;
    } else if (component.type_id == AUTO_THERMAL_SWITCH_CONTROL) {
        if (set_thermal_switch_open(component.target_position, enabled)) ++last_automation_actuator_changes_;
    } else if (component.type_id == AUTO_POWER_SWITCH_CONTROL) {
        if (set_power_switch_closed(component.target_position, enabled)) ++last_automation_actuator_changes_;
    } else if (component.type_id == AUTO_GATE_CONTROL) {
        component.gate_desired_open = enabled;
        const uint64_t key = cell_key(component.target_position);
        bool actual_open = enabled;
        bool blocked = false;
        if (!enabled && get_cell(component.target_position) != 0) {
            actual_open = true;
            blocked = true;
        }
        if (component.gate_actual_open != actual_open || component.gate_close_blocked != blocked) {
            component.gate_actual_open = actual_open;
            component.gate_close_blocked = blocked;
            if (actual_open) open_gate_cells_.insert(key); else open_gate_cells_.erase(key);
            if (blocked) blocked_gate_components_.insert(component.id); else blocked_gate_components_.erase(component.id);
            wake_after_structure_change(component.target_position);
            mark_structure_chunk_dirty(world_to_chunk(component.target_position));
            ++last_automation_actuator_changes_;
        }
    }
}

void NativeSandWorld::process_automation() {
    if (automation_dirty_.empty() && automation_scheduled_.empty() && blocked_gate_components_.empty()) {
        last_automation_awake_ = last_automation_signals_changed_ = 0;
        last_automation_sensor_evaluations_ = last_automation_logic_evaluations_ = 0;
        last_automation_actuator_changes_ = last_automation_usec_ = 0;
        return;
    }
    const auto started = std::chrono::steady_clock::now();
    for (const uint64_t id : automation_scheduled_) automation_dirty_.insert(id);
    for (const uint64_t id : blocked_gate_components_) {
        const auto found = automation_components_.find(id);
        if (found != automation_components_.end() && get_cell(found->second.target_position) == 0) automation_dirty_.insert(id);
    }
    std::vector<uint64_t> dirty(automation_dirty_.begin(), automation_dirty_.end());
    std::sort(dirty.begin(), dirty.end());
    automation_dirty_.clear();
    last_automation_awake_ = static_cast<int64_t>(dirty.size());
    last_automation_signals_changed_ = last_automation_sensor_evaluations_ = 0;
    last_automation_logic_evaluations_ = last_automation_actuator_changes_ = 0;
    std::vector<uint64_t> changed;
    for (const uint64_t id : dirty) {
        auto found = automation_components_.find(id);
        if (found == automation_components_.end()) continue;
        AutomationComponent &component = found->second;
        const AutomationDefinition *definition = automation_definition(component.type_id);
        if (definition->sensor) ++last_automation_sensor_evaluations_;
        else if (!definition->actuator) ++last_automation_logic_evaluations_;
        component.next_output = evaluate_automation_component(component);
        if (component.type_id == AUTO_MATERIAL_SENSOR && component.mode == 2 && component.next_output != 0) automation_dirty_.insert(component.id);
        if (definition->actuator) apply_automation_actuator(component);
        if (component.next_output != component.output) changed.push_back(id);
    }
    for (const uint64_t id : changed) automation_components_.at(id).output = automation_components_.at(id).next_output;
    for (const uint64_t id : changed) {
        const auto outgoing = automation_outgoing_.find(id);
        if (outgoing == automation_outgoing_.end()) continue;
        const int32_t value = automation_components_.at(id).output;
        for (const uint64_t connection_id : outgoing->second) {
            const auto edge = automation_connections_.find(connection_id);
            if (edge == automation_connections_.end()) continue;
            auto target = automation_components_.find(edge->second.target_component);
            if (target == automation_components_.end()) continue;
            if (target->second.inputs[edge->second.target_port] != value) {
                target->second.inputs[edge->second.target_port] = value;
                automation_dirty_.insert(target->first);
            }
        }
    }
    last_automation_signals_changed_ = static_cast<int64_t>(changed.size());
    last_automation_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
}

Dictionary NativeSandWorld::get_automation_statistics() const {
    Dictionary result;
    result["components_total"] = static_cast<int64_t>(automation_components_.size());
    result["components_awake"] = last_automation_awake_;
    result["wires_total"] = static_cast<int64_t>(automation_connections_.size());
    result["dirty_nodes"] = static_cast<int64_t>(automation_dirty_.size());
    result["signals_changed"] = last_automation_signals_changed_;
    result["sensor_evaluations"] = last_automation_sensor_evaluations_;
    result["logic_evaluations"] = last_automation_logic_evaluations_;
    result["actuator_changes"] = last_automation_actuator_changes_;
    result["circuit_ms"] = static_cast<double>(last_automation_usec_) / 1000.0;
    result["topology_rebuild_ms"] = static_cast<double>(last_automation_topology_usec_) / 1000.0;
    result["revision"] = static_cast<int64_t>(automation_revision_);
    result["record_bytes"] = static_cast<int64_t>(automation_components_.size() * sizeof(AutomationComponent) + automation_connections_.size() * sizeof(AutomationConnection));
    return result;
}

Dictionary NativeSandWorld::serialize_automation_state() const {
    Dictionary state;
    state["schema_version"] = AUTOMATION_SCHEMA_VERSION;
    state["next_component_id"] = static_cast<int64_t>(next_automation_component_id_);
    state["next_connection_id"] = static_cast<int64_t>(next_automation_connection_id_);
    Array components;
    std::vector<uint64_t> component_ids;
    for (const auto &[id, component] : automation_components_) { (void)component; component_ids.push_back(id); }
    std::sort(component_ids.begin(), component_ids.end());
    for (const uint64_t id : component_ids) components.push_back(get_automation_component_state(static_cast<int64_t>(id)));
    Array connections;
    std::vector<uint64_t> connection_ids;
    for (const auto &[id, connection] : automation_connections_) { (void)connection; connection_ids.push_back(id); }
    std::sort(connection_ids.begin(), connection_ids.end());
    for (const uint64_t id : connection_ids) {
        const AutomationConnection &connection = automation_connections_.at(id);
        Dictionary item;
        item["id"] = static_cast<int64_t>(id);
        item["source"] = static_cast<int64_t>(connection.source_component);
        item["source_port"] = connection.source_port;
        item["target"] = static_cast<int64_t>(connection.target_component);
        item["target_port"] = connection.target_port;
        connections.push_back(item);
    }
    state["components"] = components;
    state["connections"] = connections;
    return state;
}

bool NativeSandWorld::deserialize_automation_state(Dictionary state) {
    if (static_cast<int32_t>(state.get("schema_version", 0)) != AUTOMATION_SCHEMA_VERSION) return false;
    reset_automation();
    const Array components = state.get("components", Array());
    for (const Variant &value : components) {
        const Dictionary item = value;
        AutomationComponent component;
        component.id = static_cast<uint64_t>(static_cast<int64_t>(item.get("id", 0)));
        component.type_id = static_cast<int32_t>(item.get("type_id", 0));
        if (component.id == 0 || automation_definition(component.type_id) == nullptr) { reset_automation(); return false; }
        component.position = item.get("position", Vector2i());
        component.orientation = static_cast<int32_t>(item.get("orientation", 0));
        component.inputs[0] = static_cast<int32_t>(item.get("input_a", 0));
        component.inputs[1] = static_cast<int32_t>(item.get("input_b", 0));
        component.output = static_cast<int32_t>(item.get("output", 0));
        component.next_output = component.output;
        component.mode = static_cast<int32_t>(item.get("mode", 0));
        component.material_id = static_cast<int32_t>(item.get("material_id", 0));
        component.probe_size = item.get("probe_size", Vector2i(1, 1));
        component.threshold = static_cast<int32_t>(item.get("threshold", 0));
        component.compare_op = static_cast<int32_t>(item.get("operator", 0));
        component.period_ticks = static_cast<int32_t>(item.get("period_ticks", 30));
        component.on_ticks = static_cast<int32_t>(item.get("on_ticks", 1));
        component.timer_remaining = static_cast<int32_t>(item.get("timer_remaining", 0));
        component.pulse_pending = static_cast<bool>(item.get("pulse_pending", false));
        component.stored_state = static_cast<bool>(item.get("stored_state", false));
        component.manual_state = static_cast<bool>(item.get("enabled", false));
        component.target_position = item.get("target_position", component.position);
        component.target_machine_id = static_cast<uint64_t>(static_cast<int64_t>(item.get("target_machine_id", 0)));
        component.target_connected = static_cast<bool>(item.get("target_connected", false));
        component.gate_desired_open = static_cast<bool>(item.get("gate_desired_open", false));
        component.gate_actual_open = static_cast<bool>(item.get("gate_actual_open", false));
        component.gate_close_blocked = static_cast<bool>(item.get("gate_close_blocked", false));
        automation_components_[component.id] = component;
        rebuild_component_watchers(automation_components_.at(component.id));
        automation_dirty_.insert(component.id);
        if (component.gate_actual_open) open_gate_cells_.insert(cell_key(component.target_position));
        if (component.gate_close_blocked) blocked_gate_components_.insert(component.id);
    }
    next_automation_component_id_ = static_cast<uint64_t>(static_cast<int64_t>(state.get("next_component_id", static_cast<int64_t>(1))));
    const Array connections = state.get("connections", Array());
    for (const Variant &value : connections) {
        const Dictionary item = value;
        AutomationConnection connection;
        connection.id = static_cast<uint64_t>(static_cast<int64_t>(item.get("id", 0)));
        connection.source_component = static_cast<uint64_t>(static_cast<int64_t>(item.get("source", 0)));
        connection.source_port = static_cast<uint8_t>(static_cast<int32_t>(item.get("source_port", 0)));
        connection.target_component = static_cast<uint64_t>(static_cast<int64_t>(item.get("target", 0)));
        connection.target_port = static_cast<uint8_t>(static_cast<int32_t>(item.get("target_port", 0)));
        if (connection.id == 0 || !automation_components_.contains(connection.source_component) || !automation_components_.contains(connection.target_component)) { reset_automation(); return false; }
        automation_connections_[connection.id] = connection;
        automation_outgoing_[connection.source_component].push_back(connection.id);
        automation_input_sources_[automation_input_key(connection.target_component, connection.target_port)] = connection.id;
    }
    next_automation_connection_id_ = static_cast<uint64_t>(static_cast<int64_t>(state.get("next_connection_id", static_cast<int64_t>(1))));
    ++automation_revision_;
    return true;
}

String NativeSandWorld::automation_state_hash() const {
    uint32_t hash = 2166136261u;
    auto mix = [&hash](uint32_t value) { hash ^= value; hash *= 16777619u; };
    std::vector<uint64_t> ids;
    for (const auto &[id, component] : automation_components_) { (void)component; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const AutomationComponent &component = automation_components_.at(id);
        mix(static_cast<uint32_t>(id)); mix(static_cast<uint32_t>(id >> 32u)); mix(component.type_id);
        mix(component.position.x); mix(component.position.y); mix(component.inputs[0]); mix(component.inputs[1]); mix(component.output);
        mix(component.timer_remaining); mix(component.pulse_pending ? 1u : 0u); mix(component.stored_state ? 1u : 0u); mix(component.gate_actual_open ? 1u : 0u);
    }
    ids.clear();
    for (const auto &[id, connection] : automation_connections_) { (void)connection; ids.push_back(id); }
    std::sort(ids.begin(), ids.end());
    for (const uint64_t id : ids) {
        const AutomationConnection &connection = automation_connections_.at(id);
        mix(static_cast<uint32_t>(id)); mix(static_cast<uint32_t>(connection.source_component)); mix(static_cast<uint32_t>(connection.target_component));
        mix(connection.source_port); mix(connection.target_port);
    }
    char buffer[9];
    std::snprintf(buffer, sizeof(buffer), "%08x", hash);
    return String(buffer);
}

} // namespace godot
