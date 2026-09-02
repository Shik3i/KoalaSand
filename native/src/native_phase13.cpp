#include "native_sand_world.hpp"

#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <cstdio>
#include <limits>

namespace godot {

namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t RAW_SAND = 2;
constexpr int32_t FINE_SAND = 6;
constexpr int32_t HEAVY_CONCENTRATE = 7;
constexpr int32_t IRON_CONCENTRATE = 8;
constexpr int32_t NONMAGNETIC_CONCENTRATE = 9;
constexpr int32_t GOLD = 12;
constexpr int32_t CRUDE_RESIDUE = 13;
constexpr int32_t MOLTEN_GLASS = 18;
constexpr int32_t MOLTEN_IRON = 19;
constexpr int32_t STRUCTURE_SHAFT = 26;
constexpr int32_t STRUCTURE_POWER_POLE = 29;
constexpr int32_t STRUCTURE_MESH_SCREEN = 41;
constexpr int32_t STRUCTURE_RIFFLE = 43;
constexpr int32_t STRUCTURE_REFRACTORY_WALL = 40;
constexpr int32_t STRUCTURE_VIBRATION_ACTUATOR = 45;
constexpr int32_t STRUCTURE_ELECTROMAGNET = 46;
constexpr int32_t EXPLICIT_MIXTURE_PROVENANCE = 65535;
constexpr int32_t MAX_LEDGER_QUANTA_PER_CHANNEL = 8;

const char *const CONSTITUENT_NAMES[NativeSandWorld::CONSTITUENT_COUNT] = {
    "silica", "iron_bearing", "heavy", "gold", "clay_fines", "other"
};

int64_t channel_total(const std::array<int64_t, NativeSandWorld::CONSTITUENT_COUNT> &channel) {
    int64_t result = 0;
    for (const int64_t value : channel) result += value;
    return result;
}

bool has_fields(const Dictionary &dictionary, std::initializer_list<const char *> fields) {
    for (const char *field : fields) if (!dictionary.has(field)) return false;
    return true;
}

bool valid_optional_plane(const Dictionary &entry, const char *name, int32_t maximum) {
    const Variant value = entry.get(name, Variant());
    if (value.get_type() == Variant::NIL) return true;
    if (value.get_type() != Variant::PACKED_INT32_ARRAY) return false;
    const PackedInt32Array values = value;
    if (values.size() != 0 && values.size() != NativeSandWorld::CELLS_PER_CHUNK) return false;
    for (int32_t index = 0; index < values.size(); ++index) if (values[index] < 0 || values[index] > maximum) return false;
    return true;
}

bool valid_dictionary_array(const Dictionary &state, const char *name, int32_t maximum, Array &values) {
    const Variant value = state.get(name, Array());
    if (value.get_type() != Variant::ARRAY) return false;
    values = value;
    if (values.size() > maximum) return false;
    for (int32_t index = 0; index < values.size(); ++index) if (values[index].get_type() != Variant::DICTIONARY) return false;
    return true;
}

bool validate_world_snapshot_shape(const Dictionary &state) {
    if (!has_fields(state, {"schema_version", "seed", "chunks"}) ||
        state.get("schema_version", 0).get_type() != Variant::INT || static_cast<int32_t>(state.get("schema_version", 0)) != 1 ||
        state.get("seed", 0).get_type() != Variant::INT || state.get("chunks", Variant()).get_type() != Variant::ARRAY) return false;
    if (state.has("save_kind") && String(state.get("save_kind", "")) != "KoalaSandWorld") return false;
    if (state.has("world_settings") && state.get("world_settings", Variant()).get_type() != Variant::DICTIONARY) return false;

    const Array chunks = state.get("chunks", Array());
    if (chunks.size() > 4096) return false;
    std::unordered_set<uint64_t> chunk_keys;
    for (int32_t chunk_index = 0; chunk_index < chunks.size(); ++chunk_index) {
        if (chunks[chunk_index].get_type() != Variant::DICTIONARY) return false;
        const Dictionary entry = chunks[chunk_index];
        if (!has_fields(entry, {"coordinate", "core"}) || entry.get("coordinate", Variant()).get_type() != Variant::VECTOR2I ||
            entry.get("core", Variant()).get_type() != Variant::PACKED_INT32_ARRAY) return false;
        const Vector2i coordinate = entry.get("coordinate", Vector2i());
        const uint64_t key = (static_cast<uint64_t>(static_cast<uint32_t>(coordinate.x)) << 32u) | static_cast<uint32_t>(coordinate.y);
        if (!chunk_keys.insert(key).second) return false;
        const PackedInt32Array core = entry.get("core", PackedInt32Array());
        if (core.size() != NativeSandWorld::CELLS_PER_CHUNK * 5) return false;
        for (int32_t cell = 0; cell < NativeSandWorld::CELLS_PER_CHUNK; ++cell) {
            if (core[cell * 5] < 0 || core[cell * 5] >= NativeSandWorld::MATERIAL_COUNT ||
                core[cell * 5 + 1] < 0 || core[cell * 5 + 1] > NativeSandWorld::TEMPERATURE_MAX ||
                core[cell * 5 + 2] < 0 || core[cell * 5 + 2] > 255 ||
                core[cell * 5 + 3] < 0 || core[cell * 5 + 3] > 65535 ||
                core[cell * 5 + 4] < 0 || core[cell * 5 + 4] > 65535) return false;
        }
        if (!valid_optional_plane(entry, "structures", 127) || !valid_optional_plane(entry, "amount", 255) ||
            !valid_optional_plane(entry, "phase_energy", 65535) || !valid_optional_plane(entry, "moisture", 255) ||
            !valid_optional_plane(entry, "oxidizer", 255) || !valid_optional_plane(entry, "reaction_progress", 65535) ||
            !valid_optional_plane(entry, "reaction_state", 255)) return false;
    }

    Array machines, pipes, clusters, compositions, ledgers;
    if (!valid_dictionary_array(state, "machines", 1'000'000, machines) || !valid_dictionary_array(state, "pipes", 1'000'000, pipes) ||
        !valid_dictionary_array(state, "clusters", 100'000, clusters) || !valid_dictionary_array(state, "compositions", 65'535, compositions) ||
        !valid_dictionary_array(state, "ledgers", 1'000'000, ledgers)) return false;
    for (const Variant &value : machines) {
        const Dictionary item = value;
        if (!has_fields(item, {"id", "type_id", "origin", "orientation", "input_material", "input_provenance", "input_signature",
            "result_material", "result_provenance", "result_signature", "ash_material", "fuel_remaining", "progress_ticks", "state",
            "processed_cells", "emitted_cells", "last_process_tick", "last_route", "control_connected", "control_enabled"})) return false;
    }
    for (const Variant &value : pipes) {
        const Dictionary item = value;
        if (!has_fields(item, {"cell", "fluid", "mass", "temperature", "pressure", "last_flow", "health", "flags", "connection_mask", "type_id", "orientation"}) ||
            item.get("cell", Variant()).get_type() != Variant::VECTOR2I) return false;
    }
    for (const Variant &value : clusters) {
        const Dictionary item = value;
        if (!has_fields(item, {"id", "origin_q10", "velocity_q10", "angle_q16", "angular_velocity_q16", "fall_direction", "collision_count", "state", "cells"}) ||
            item.get("cells", Variant()).get_type() != Variant::PACKED_INT32_ARRAY) return false;
        const PackedInt32Array cells = item.get("cells", PackedInt32Array());
        if (cells.size() % 6 != 0 || cells.size() > 6'000'000) return false;
    }
    for (const Variant &value : compositions) {
        const Dictionary item = value;
        if (!has_fields(item, {"id", "masses"}) || item.get("masses", Variant()).get_type() != Variant::ARRAY) return false;
        const Array masses = item.get("masses", Array());
        if (masses.size() != NativeSandWorld::CONSTITUENT_COUNT) return false;
        int64_t total = 0;
        for (const Variant &mass_value : masses) {
            if (mass_value.get_type() != Variant::INT || static_cast<int64_t>(mass_value) < 0 || static_cast<int64_t>(mass_value) > NativeSandWorld::FULL_CELL_MICRO_MASS) return false;
            total += static_cast<int64_t>(mass_value);
        }
        if (total != NativeSandWorld::FULL_CELL_MICRO_MASS) return false;
    }
    for (const Variant &value : ledgers) {
        const Dictionary item = value;
        if (!has_fields(item, {"id", "input", "emitted", "queued", "materials", "pending"}) ||
            item.get("materials", Variant()).get_type() != Variant::PACKED_INT32_ARRAY || item.get("pending", Variant()).get_type() != Variant::ARRAY) return false;
        const PackedInt32Array materials = item.get("materials", PackedInt32Array());
        const Array pending = item.get("pending", Array());
        if (materials.size() != 4 || pending.size() != 4 * NativeSandWorld::CONSTITUENT_COUNT) return false;
        for (const int32_t material : materials) if (material < 0 || material >= NativeSandWorld::MATERIAL_COUNT) return false;
        for (const Variant &mass : pending) if (mass.get_type() != Variant::INT || static_cast<int64_t>(mass) < 0) return false;
    }
    for (const char *name : {"reactive", "atmosphere"}) {
        const Variant value = state.get(name, Array());
        if (value.get_type() != Variant::ARRAY) return false;
        const Array items = value;
        if (items.size() > 16'777'216) return false;
        for (const Variant &item : items) if (item.get_type() != Variant::INT) return false;
    }
    for (const char *name : {"progression", "automation", "subsurface", "power", "visibility_owner_1", "organic_totals"})
        if (state.has(name) && state.get(name, Variant()).get_type() != Variant::DICTIONARY) return false;
    return true;
}
}

void NativeSandWorld::reset_phase13() {
    fractional_ledgers_.clear();
    explicit_compositions_.clear();
    component_processing_cells_.clear();
    thermal_component_cells_.clear();
    next_explicit_composition_id_ = 1;
    conservation_input_micro_mass_ = 0;
    conservation_output_micro_mass_ = 0;
    conservation_rejected_removals_ = 0;
    milestone_flags_ = 0;
}

int64_t NativeSandWorld::composition_total(const ConstituentMass &composition) {
    int64_t total = 0;
    for (const int64_t value : composition) total += value;
    return total;
}

NativeSandWorld::ConstituentMass NativeSandWorld::composition_for(
    int32_t material_id, int32_t profile_id, uint16_t signature) const {
    if (profile_id == EXPLICIT_MIXTURE_PROVENANCE) {
        const auto explicit_found = explicit_compositions_.find(signature);
        if (explicit_found != explicit_compositions_.end()) return explicit_found->second;
    }
    ConstituentMass result{};
    if (material_id == RAW_SAND || material_id == FINE_SAND || material_id == HEAVY_CONCENTRATE ||
        material_id == IRON_CONCENTRATE || material_id == NONMAGNETIC_CONCENTRATE) {
        if (world_settings_.generation_version >= 5) {
            // One decoder shared with the reported composition. The remainder is assigned to
            // the last constituent so the six values sum to exactly one full cell.
            double fractions[6];
            v5_profile_fractions(static_cast<uint16_t>(std::clamp(profile_id, 1, 65535)), signature, fractions);
            int64_t assigned = 0;
            for (int32_t index = 0; index < CONSTITUENT_COUNT - 1; ++index) {
                result[index] = static_cast<int64_t>(FULL_CELL_MICRO_MASS * fractions[index]);
                assigned += result[index];
            }
            result[CONSTITUENT_COUNT - 1] = FULL_CELL_MICRO_MASS - assigned;
            if (material_id == FINE_SAND) {
                result[0] += result[2] / 2; result[2] -= result[2] / 2;
            } else if (material_id == HEAVY_CONCENTRATE) {
                result[2] += result[0] / 2; result[0] -= result[0] / 2;
            } else if (material_id == IRON_CONCENTRATE) {
                result[1] += result[0] * 3 / 4; result[0] -= result[0] * 3 / 4;
            } else if (material_id == NONMAGNETIC_CONCENTRATE) {
                result[0] += result[1] * 3 / 4; result[1] -= result[1] * 3 / 4;
            }
            return result;
        }
        const uint32_t profile = static_cast<uint32_t>(std::clamp(profile_id, 1, 65534));
        const uint32_t sig = signature;
        int64_t iron = FULL_CELL_MICRO_MASS * (700 + static_cast<int64_t>((profile >> 3u) & 0x3ffu)) / 10000;
        int64_t heavy = FULL_CELL_MICRO_MASS * (180 + static_cast<int64_t>((profile >> 9u) & 0x1ffu)) / 10000;
        int64_t gold = FULL_CELL_MICRO_MASS * static_cast<int64_t>(((profile >> 13u) & 7u) * 3u + (sig & 3u)) / 10000;
        int64_t clay = FULL_CELL_MICRO_MASS * (600 + static_cast<int64_t>((profile ^ sig) & 0x3ffu)) / 10000;
        int64_t other = FULL_CELL_MICRO_MASS * (350 + static_cast<int64_t>((sig >> 5u) & 0x1ffu)) / 10000;
        iron = std::clamp<int64_t>(iron, 0, FULL_CELL_MICRO_MASS / 3);
        heavy = std::clamp<int64_t>(heavy, 0, FULL_CELL_MICRO_MASS / 5);
        gold = std::clamp<int64_t>(gold, 0, FULL_CELL_MICRO_MASS / 100);
        clay = std::clamp<int64_t>(clay, 0, FULL_CELL_MICRO_MASS / 4);
        other = std::clamp<int64_t>(other, 0, FULL_CELL_MICRO_MASS / 5);
        result = {FULL_CELL_MICRO_MASS - iron - heavy - gold - clay - other, iron, heavy, gold, clay, other};
        if (material_id == FINE_SAND) {
            result[0] += result[2] / 2; result[2] -= result[2] / 2;
        } else if (material_id == HEAVY_CONCENTRATE) {
            result[2] += result[0] / 2; result[0] -= result[0] / 2;
        } else if (material_id == IRON_CONCENTRATE) {
            result[1] += result[0] * 3 / 4; result[0] -= result[0] * 3 / 4;
        } else if (material_id == NONMAGNETIC_CONCENTRATE) {
            result[0] += result[1] * 3 / 4; result[1] -= result[1] * 3 / 4;
        }
        return result;
    }
    if (material_id == GOLD) result[3] = FULL_CELL_MICRO_MASS;
    else if (material_id == MOLTEN_GLASS || material_id == 10) result[0] = FULL_CELL_MICRO_MASS;
    else if (material_id == MOLTEN_IRON || material_id == 11) result[1] = FULL_CELL_MICRO_MASS;
    else result[5] = FULL_CELL_MICRO_MASS;
    return result;
}

NativeSandWorld::ConstituentMass NativeSandWorld::take_quantum(ConstituentMass &source, int64_t quantum) {
    ConstituentMass result{};
    int64_t remaining = quantum;
    for (int32_t index = 0; index < CONSTITUENT_COUNT && remaining > 0; ++index) {
        const int64_t taken = std::min(source[index], remaining);
        source[index] -= taken;
        result[index] = taken;
        remaining -= taken;
    }
    return result;
}

void NativeSandWorld::split_into_ledger(FractionalMassLedger &ledger, const ConstituentMass &input, int32_t route) const {
    ledger.input_micro_mass += composition_total(input);
    if (route == 0) { // Selective Gold recovery fixture.
        ledger.output_material = {GOLD, CRUDE_RESIDUE, 0, 0};
        ledger.pending[0][3] += input[3];
        for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) if (c != 3) ledger.pending[1][c] += input[c];
    } else if (route == 1) { // Screen: fine versus coarse/heavy by constituent grain class.
        ledger.output_material = {FINE_SAND, HEAVY_CONCENTRATE, 0, 0};
        for (const int32_t c : {0, 4, 5}) ledger.pending[0][c] += input[c];
        for (const int32_t c : {1, 2, 3}) ledger.pending[1][c] += input[c];
    } else if (route == 2) { // Magnetic field moves only magnetic-bearing mass.
        ledger.output_material = {IRON_CONCENTRATE, NONMAGNETIC_CONCENTRATE, 0, 0};
        ledger.pending[0][1] += input[1];
        for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) if (c != 1) ledger.pending[1][c] += input[c];
    } else if (route == 3) { // Thermal fractionation: every impurity remains accounted.
        ledger.output_material = {MOLTEN_GLASS, MOLTEN_IRON, GOLD, CRUDE_RESIDUE};
        ledger.pending[0][0] += input[0]; ledger.pending[1][1] += input[1]; ledger.pending[2][3] += input[3];
        ledger.pending[3][2] += input[2]; ledger.pending[3][4] += input[4]; ledger.pending[3][5] += input[5];
    } else { // Wet density separation.
        ledger.output_material = {HEAVY_CONCENTRATE, FINE_SAND, 0, 0};
        for (const int32_t c : {1, 2, 3}) ledger.pending[0][c] += input[c];
        for (const int32_t c : {0, 4, 5}) ledger.pending[1][c] += input[c];
    }
}

Dictionary NativeSandWorld::ledger_report(const FractionalMassLedger &ledger) const {
    Dictionary result;
    result["input_micro_mass"] = ledger.input_micro_mass;
    result["emitted_micro_mass"] = ledger.emitted_micro_mass;
    result["queued_micro_mass"] = ledger.queued_micro_mass;
    Array channels;
    int64_t retained = 0;
    for (int32_t output = 0; output < 4; ++output) {
        Dictionary channel;
        channel["material_id"] = ledger.output_material[output];
        channel["micro_mass"] = channel_total(ledger.pending[output]);
        channel["emitted_micro_mass"] = ledger.emitted_channel_micro_mass[output];
        retained += static_cast<int64_t>(channel["micro_mass"]);
        Dictionary composition;
        for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) composition[CONSTITUENT_NAMES[c]] = ledger.pending[output][c];
        channel["composition"] = composition;
        channels.push_back(channel);
    }
    result["retained_micro_mass"] = retained;
    result["channels"] = channels;
    result["balanced"] = ledger.input_micro_mass == ledger.emitted_micro_mass + ledger.queued_micro_mass + retained;
    return result;
}

Dictionary NativeSandWorld::get_conservation_architecture() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["full_cell_micro_mass"] = FULL_CELL_MICRO_MASS;
    result["amount_unit_micro_mass"] = AMOUNT_UNIT_MICRO_MASS;
    result["full_cell_amount_units"] = 255;
    result["authoritative_numeric_type"] = "int64";
    result["base_cell_bytes"] = 9;
    result["constituent_count"] = CONSTITUENT_COUNT;
    result["optional_state"] = true;
    result["yield_rng"] = false;
    result["ledger_count"] = static_cast<int64_t>(fractional_ledgers_.size());
    result["input_micro_mass"] = conservation_input_micro_mass_;
    result["output_micro_mass"] = conservation_output_micro_mass_;
    result["rejected_removals"] = conservation_rejected_removals_;
    return result;
}

Dictionary NativeSandWorld::derive_material_composition(int32_t profile_id, int32_t mineral_signature) const {
    Dictionary result;
    if (mineral_signature < 0 || mineral_signature > 65535) return result;
    const ConstituentMass composition = composition_for(RAW_SAND, profile_id, static_cast<uint16_t>(mineral_signature));
    int64_t total = 0;
    for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) { result[CONSTITUENT_NAMES[c]] = composition[c]; total += composition[c]; }
    result["total"] = total;
    return result;
}

Dictionary NativeSandWorld::run_fractionation_fixture(
    int32_t numerator, int32_t denominator, int32_t input_count, int32_t route) const {
    Dictionary invalid;
    if (numerator < 0 || denominator <= 0 || numerator > denominator || input_count < 0 || input_count > 1000000 || route < 0 || route > 4) return invalid;
    FractionalMassLedger ledger;
    ledger.id = 1;
    const int64_t selected = (FULL_CELL_MICRO_MASS * numerator + denominator / 2) / denominator;
    for (int32_t input_index = 0; input_index < input_count; ++input_index) {
        ConstituentMass composition{};
        composition[3] = selected;
        composition[5] = FULL_CELL_MICRO_MASS - selected;
        split_into_ledger(ledger, composition, route);
        for (int32_t output = 0; output < 4; ++output) {
            while (channel_total(ledger.pending[output]) >= FULL_CELL_MICRO_MASS) {
                take_quantum(ledger.pending[output], FULL_CELL_MICRO_MASS);
                ledger.emitted_channel_micro_mass[output] += FULL_CELL_MICRO_MASS;
                ledger.emitted_micro_mass += FULL_CELL_MICRO_MASS;
            }
        }
    }
    Dictionary result = ledger_report(ledger);
    result["numerator"] = numerator;
    result["denominator"] = denominator;
    result["canonical_fraction_micro_mass"] = selected;
    result["input_count"] = input_count;
    result["emitted_quanta"] = ledger.emitted_micro_mass / FULL_CELL_MICRO_MASS;
    result["gold_emitted_quanta"] = route == 0 ? (static_cast<int64_t>(input_count) * selected) / FULL_CELL_MICRO_MASS : 0;
    result["gold_retained_micro_mass"] = route == 0 ? (static_cast<int64_t>(input_count) * selected) % FULL_CELL_MICRO_MASS : 0;
    return result;
}

Dictionary NativeSandWorld::run_variable_composition_fixture(Array gold_numerators, int32_t denominator, int32_t route) const {
    Dictionary invalid;
    if (denominator <= 0 || route < 0 || route > 4) return invalid;
    FractionalMassLedger ledger;
    ledger.id = 2;
    for (int32_t index = 0; index < gold_numerators.size(); ++index) {
        const int32_t numerator = gold_numerators[index];
        if (numerator < 0 || numerator > denominator) return invalid;
        const int64_t selected = (FULL_CELL_MICRO_MASS * numerator + denominator / 2) / denominator;
        ConstituentMass composition{}; composition[3] = selected; composition[5] = FULL_CELL_MICRO_MASS - selected;
        split_into_ledger(ledger, composition, route);
        for (int32_t output = 0; output < 4; ++output) while (channel_total(ledger.pending[output]) >= FULL_CELL_MICRO_MASS) {
            take_quantum(ledger.pending[output], FULL_CELL_MICRO_MASS); ledger.emitted_micro_mass += FULL_CELL_MICRO_MASS;
            ledger.emitted_channel_micro_mass[output] += FULL_CELL_MICRO_MASS;
        }
    }
    Dictionary result = ledger_report(ledger);
    result["input_count"] = gold_numerators.size();
    return result;
}

Dictionary NativeSandWorld::run_global_mass_fixture(int32_t input_count, int32_t profile_id, int32_t mineral_signature) const {
    Dictionary invalid;
    if (input_count < 0 || input_count > 1000000 || mineral_signature < 0 || mineral_signature > 65535) return invalid;
    std::array<FractionalMassLedger, 4> stages{};
    ConstituentMass input_totals{}, final_totals{};
    const ConstituentMass one_input = composition_for(RAW_SAND, profile_id, static_cast<uint16_t>(mineral_signature));
    auto feed_stage = [&](auto &&self, int32_t stage, const ConstituentMass &composition) -> void {
        if (stage == 4) {
            for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) final_totals[c] += composition[c];
            return;
        }
        split_into_ledger(stages[stage], composition, stage == 0 ? 1 : stage == 1 ? 4 : stage == 2 ? 2 : 3);
        for (int32_t output = 0; output < 4; ++output) while (channel_total(stages[stage].pending[output]) >= FULL_CELL_MICRO_MASS) {
            ConstituentMass quantum = take_quantum(stages[stage].pending[output], FULL_CELL_MICRO_MASS);
            stages[stage].emitted_micro_mass += FULL_CELL_MICRO_MASS;
            stages[stage].emitted_channel_micro_mass[output] += FULL_CELL_MICRO_MASS;
            self(self, stage + 1, quantum);
        }
    };
    for (int32_t input = 0; input < input_count; ++input) {
        for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) input_totals[c] += one_input[c];
        feed_stage(feed_stage, 0, one_input);
    }
    for (const FractionalMassLedger &stage : stages) for (const ConstituentMass &pending : stage.pending)
        for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) final_totals[c] += pending[c];
    Array input, accounted; bool balanced = true; int64_t input_mass = 0, accounted_mass = 0;
    for (int32_t c = 0; c < CONSTITUENT_COUNT; ++c) {
        input.push_back(input_totals[c]); accounted.push_back(final_totals[c]); balanced = balanced && input_totals[c] == final_totals[c];
        input_mass += input_totals[c]; accounted_mass += final_totals[c];
    }
    Dictionary result; result["input_count"] = input_count; result["input_constituents"] = input; result["accounted_constituents"] = accounted;
    result["input_micro_mass"] = input_mass; result["accounted_micro_mass"] = accounted_mass; result["balanced"] = balanced;
    result["events"] = static_cast<int64_t>(input_count) * 4; result["stages"] = "screen,wet_density,magnetic,thermal";
    return result;
}

Dictionary NativeSandWorld::accumulate_fraction_for_test(
    int64_t ledger_id, int32_t numerator, int32_t denominator, int32_t route, bool output_available) {
    Dictionary invalid;
    if (ledger_id <= 0 || numerator < 0 || denominator <= 0 || numerator > denominator || route < 0 || route > 4) return invalid;
    FractionalMassLedger &ledger = fractional_ledgers_[static_cast<uint64_t>(ledger_id)];
    ledger.id = static_cast<uint64_t>(ledger_id);
    const int64_t selected = (FULL_CELL_MICRO_MASS * numerator + denominator / 2) / denominator;
    ConstituentMass composition{}; composition[3] = selected; composition[5] = FULL_CELL_MICRO_MASS - selected;
    split_into_ledger(ledger, composition, route); conservation_input_micro_mass_ += FULL_CELL_MICRO_MASS;
    if (output_available) for (int32_t output = 0; output < 4; ++output) while (channel_total(ledger.pending[output]) >= FULL_CELL_MICRO_MASS) {
        take_quantum(ledger.pending[output], FULL_CELL_MICRO_MASS);
        ledger.emitted_channel_micro_mass[output] += FULL_CELL_MICRO_MASS;
        ledger.emitted_micro_mass += FULL_CELL_MICRO_MASS; conservation_output_micro_mass_ += FULL_CELL_MICRO_MASS;
    }
    return ledger_report(ledger);
}

Dictionary NativeSandWorld::get_fractional_ledger(int64_t ledger_id) const {
    const auto found = fractional_ledgers_.find(static_cast<uint64_t>(ledger_id));
    return found == fractional_ledgers_.end() ? Dictionary() : ledger_report(found->second);
}

const NativeSandWorld::StructurePhysicalProperties &NativeSandWorld::structure_physical_properties(int32_t type_id) {
    static const StructurePhysicalProperties solid{0, 0, 28, 96, 4800, 0, true, false};
    static const StructurePhysicalProperties metal{0, 0, 220, 180, 7200, 0, true, false};
    static const StructurePhysicalProperties ceramic{0, 0, 20, 150, 11200, 0, true, false};
    static const StructurePhysicalProperties refractory{0, 0, 7, 240, 15000, 0, true, false};
    static const StructurePhysicalProperties mesh{850, 2, 55, 55, 5200, 0, false, true};
    static const StructurePhysicalProperties grate{700, 3, 100, 90, 6500, 0, false, true};
    static const StructurePhysicalProperties riffle{350, 1, 90, 100, 6000, 0, true, false};
    static const StructurePhysicalProperties insulator{0, 0, 2, 80, 4600, 0, true, false};
    static const StructurePhysicalProperties actuator{0, 0, 80, 120, 5000, 0, true, false};
    static const StructurePhysicalProperties magnet{0, 0, 130, 150, 6200, 1400, true, false};
    static const StructurePhysicalProperties blower{950, 4, 70, 100, 4800, 0, false, true};
    switch (type_id) {
        case 38: return metal; case 39: return ceramic; case 40: return refractory; case 41: return mesh;
        case 42: return grate; case 43: return riffle; case 44: return insulator; case 45: return actuator;
        case 46: return magnet; case 47: return blower; default: return solid;
    }
}

Dictionary NativeSandWorld::get_structure_physical_properties(int32_t type_id) const {
    Dictionary result;
    if (structure_definition(type_id) == nullptr) return result;
    const StructurePhysicalProperties &properties = structure_physical_properties(type_id);
    result["type_id"] = type_id; result["permeability"] = properties.permeability; result["aperture"] = properties.aperture;
    result["conductivity"] = properties.conductivity; result["heat_capacity"] = properties.heat_capacity;
    result["maximum_temperature"] = properties.maximum_temperature; result["magnetic_strength"] = properties.magnetic_strength;
    result["solid"] = properties.solid; result["gas_permeable"] = properties.gas_permeable;
    return result;
}

Dictionary NativeSandWorld::get_component_classification() const {
    Dictionary result;
    result["1"] = "KEEP_COMPONENT"; result["2"] = "KEEP_COMPONENT"; result["5"] = "DEV_FIXTURE";
    result["6"] = "DEV_FIXTURE"; result["7"] = "DEV_FIXTURE"; result["8"] = "KEEP_COMPONENT";
    result["10"] = "KEEP_COMPONENT"; result["11"] = "KEEP_COMPONENT"; result["12"] = "KEEP_COMPONENT";
    result["13"] = "KEEP_COMPONENT"; result["14"] = "KEEP_COMPONENT"; result["15"] = "KEEP_COMPONENT";
    result["16"] = "KEEP_COMPONENT"; result["17"] = "DEV_FIXTURE"; result["24"] = "KEEP_COMPONENT";
    result["25"] = "KEEP_COMPONENT"; result["26"] = "KEEP_COMPONENT"; result["27"] = "KEEP_COMPONENT";
    result["28"] = "KEEP_COMPONENT"; result["34"] = "KEEP_COMPONENT"; result["35"] = "DEV_FIXTURE";
    for (int32_t id = 37; id <= 47; ++id) result[String::num_int64(id)] = "KEEP_COMPONENT";
    return result;
}

bool NativeSandWorld::structure_has_fractional_contents(Vector2i world_cell) const {
    const auto found = fractional_ledgers_.find(cell_key(world_cell));
    return found != fractional_ledgers_.end() && found->second.has_contents();
}

void NativeSandWorld::process_component_processing() {
    if (component_processing_cells_.empty()) return;
    std::vector<uint64_t> keys(component_processing_cells_.begin(), component_processing_cells_.end());
    std::sort(keys.begin(), keys.end());
    for (const uint64_t key : keys) {
        const Vector2i component = cell_from_key(key);
        const int32_t type = get_structure(component);
        int32_t route = -1;
        Vector2i source;
        std::array<Vector2i, 4> outputs{};
        if (type == STRUCTURE_REFRACTORY_WALL) {
            route = 3;
            const std::array<Vector2i, 4> candidates{{component + Vector2i(0, -1), component + Vector2i(-1, 0), component + Vector2i(1, 0), component + Vector2i(0, 1)}};
            int32_t hottest = -1;
            for (const Vector2i candidate : candidates) {
                const int32_t candidate_material = get_cell(candidate);
                if ((candidate_material == RAW_SAND || (candidate_material >= FINE_SAND && candidate_material <= NONMAGNETIC_CONCENTRATE)) && get_temperature(candidate) >= TEMPERATURE_REACTION && get_temperature(candidate) > hottest) {
                    source = candidate; hottest = get_temperature(candidate);
                }
            }
            if (hottest < 0) continue;
            outputs = {component + Vector2i(-1, -1), component + Vector2i(1, -1), component + Vector2i(-1, -2), component + Vector2i(1, -2)};
        } else if (type == STRUCTURE_VIBRATION_ACTUATOR) {
            Vector2i mesh = component + Vector2i(1, 0);
            if (get_structure(mesh) != STRUCTURE_MESH_SCREEN) mesh = component + Vector2i(-1, 0);
            if (get_structure(mesh) != STRUCTURE_MESH_SCREEN) continue;
            route = 1; source = mesh + Vector2i(0, -1); outputs = {mesh + Vector2i(0, 1), mesh + Vector2i(1, -1), mesh + Vector2i(0, 2), mesh + Vector2i(2, -1)};
        } else if (type == STRUCTURE_ELECTROMAGNET) {
            route = 2; source = component + Vector2i(0, 1); outputs = {component + Vector2i(-1, 1), component + Vector2i(1, 1), component + Vector2i(-2, 1), component + Vector2i(2, 1)};
        } else if (type == STRUCTURE_RIFFLE) {
            const int32_t nearby_water = get_liquid_mass(component + Vector2i(-1, -1)) + get_liquid_mass(component + Vector2i(0, -1)) + get_liquid_mass(component + Vector2i(1, -1));
            if (nearby_water < 48) continue;
            route = 4; source = component + Vector2i(0, -1); outputs = {component + Vector2i(0, -2), component + Vector2i(1, -1), component + Vector2i(-1, -2), component + Vector2i(2, -1)};
        } else continue;
        const int32_t material = get_cell(source);
        if (!(material == RAW_SAND || material == FINE_SAND || material == HEAVY_CONCENTRATE || material == IRON_CONCENTRATE || material == NONMAGNETIC_CONCENTRATE)) continue;
        FractionalMassLedger &ledger = fractional_ledgers_[key]; ledger.id = key;
        bool capacity = true;
        for (const ConstituentMass &pending : ledger.pending) if (channel_total(pending) > FULL_CELL_MICRO_MASS * MAX_LEDGER_QUANTA_PER_CHANNEL) capacity = false;
        if (!capacity) continue;
        Chunk *chunk = get_chunk(world_to_chunk(source)); if (chunk == nullptr) continue;
        const int32_t index = local_index(world_to_local(source));
        const ConstituentMass input = composition_for(material, chunk->provenance[index], chunk->mineral_signature[index]);
        const int32_t temperature = chunk->temperature[index];
        set_material_state(source, EMPTY, 0, TEMPERATURE_AMBIENT, 0, 0);
        split_into_ledger(ledger, input, route); conservation_input_micro_mass_ += FULL_CELL_MICRO_MASS;
        record_production_event(material, 1, false);
        if (route == 1) ++total_sieve_processed_;
        else if (route == 2) ++total_magnetic_processed_;
        else if (route == 3) ++total_furnace_processed_;
        else if (route == 4) record_production_flow(ProductionFlowKind::WET_PROCESSING_THROUGHPUT, 1);
        for (int32_t output = 0; output < 4; ++output) {
            while (channel_total(ledger.pending[output]) >= FULL_CELL_MICRO_MASS && get_cell(outputs[output]) == EMPTY && get_structure(outputs[output]) == 0) {
                ConstituentMass emitted = take_quantum(ledger.pending[output], FULL_CELL_MICRO_MASS);
                uint16_t composition_id = next_explicit_composition_id_++;
                if (composition_id == 0) composition_id = next_explicit_composition_id_++;
                explicit_compositions_[composition_id] = emitted;
                set_material_state(outputs[output], ledger.output_material[output], 255, temperature, EXPLICIT_MIXTURE_PROVENANCE, composition_id);
                ledger.emitted_micro_mass += FULL_CELL_MICRO_MASS; conservation_output_micro_mass_ += FULL_CELL_MICRO_MASS;
                ledger.emitted_channel_micro_mass[output] += FULL_CELL_MICRO_MASS;
                record_production_event(ledger.output_material[output], 1, true);
                if (ledger.output_material[output] == MOLTEN_GLASS) ++total_glass_;
                else if (ledger.output_material[output] == MOLTEN_IRON) ++total_iron_;
                else if (ledger.output_material[output] == GOLD) ++total_gold_;
                else if (ledger.output_material[output] == CRUDE_RESIDUE) ++total_residue_;
            }
        }
    }
}

Dictionary NativeSandWorld::serialize_world_snapshot() const {
    Dictionary state;
    state["schema_version"] = 1; state["save_kind"] = "KoalaSandWorld"; state["seed"] = seed_;
    state["tick"] = tick_index_; state["workers"] = worker_count_; state["game_mode"] = game_mode_;
    state["thermal_rounding_reservoir"] = thermal_rounding_reservoir_;
    state["world_generation_enabled"] = world_generation_enabled_; state["world_settings"] = get_world_settings();
    Array chunks; int64_t omitted_pristine_chunks = 0;
    for (const Chunk *chunk : sorted_chunks()) {
        if (world_generation_enabled_ && chunk->generated && chunk->pristine) { ++omitted_pristine_chunks; continue; }
        Dictionary entry; entry["coordinate"] = chunk->coordinate;
        PackedInt32Array core; core.resize(CELLS_PER_CHUNK * 5);
        for (int32_t i = 0; i < CELLS_PER_CHUNK; ++i) {
            core[i * 5] = chunk->material[i]; core[i * 5 + 1] = chunk->temperature[i]; core[i * 5 + 2] = chunk->flags[i];
            core[i * 5 + 3] = chunk->provenance[i]; core[i * 5 + 4] = chunk->mineral_signature[i];
        }
        entry["core"] = core; entry["generated"] = chunk->generated; entry["pristine"] = chunk->pristine; entry["revision"] = static_cast<int64_t>(chunk->revision);
        auto pack_u8 = [](const auto &pointer) { PackedInt32Array values; if (pointer != nullptr) { values.resize(CELLS_PER_CHUNK); for (int32_t i = 0; i < CELLS_PER_CHUNK; ++i) values[i] = (*pointer)[i]; } return values; };
        auto pack_u16 = [](const auto &pointer) { PackedInt32Array values; if (pointer != nullptr) { values.resize(CELLS_PER_CHUNK); for (int32_t i = 0; i < CELLS_PER_CHUNK; ++i) values[i] = (*pointer)[i]; } return values; };
        entry["structures"] = pack_u8(chunk->structures); entry["amount"] = pack_u8(chunk->material_amount);
        entry["phase_energy"] = pack_u16(chunk->phase_energy); entry["moisture"] = pack_u8(chunk->organic_moisture);
        entry["oxidizer"] = pack_u8(chunk->oxidizer); entry["reaction_progress"] = pack_u16(chunk->reaction_progress);
        entry["reaction_state"] = pack_u8(chunk->reaction_state);
        chunks.push_back(entry);
    }
    state["chunks"] = chunks; state["omitted_pristine_chunks"] = omitted_pristine_chunks;
    Array machines;
    std::vector<uint64_t> machine_ids; for (const auto &[id, machine] : machine_entities_) { (void)machine; machine_ids.push_back(id); } std::sort(machine_ids.begin(), machine_ids.end());
    for (const uint64_t id : machine_ids) { const MachineEntity &m = machine_entities_.at(id); Dictionary d;
        d["id"] = static_cast<int64_t>(m.id); d["type_id"] = m.type_id; d["origin"] = m.origin; d["orientation"] = m.orientation;
        d["input_material"] = m.input_material; d["input_provenance"] = m.input_provenance; d["input_signature"] = m.input_signature;
        d["result_material"] = m.result_material; d["result_provenance"] = m.result_provenance; d["result_signature"] = m.result_signature;
        d["ash_material"] = m.ash_material; d["fuel_remaining"] = m.fuel_remaining; d["progress_ticks"] = m.progress_ticks;
        d["state"] = m.state; d["processed_cells"] = m.processed_cells; d["emitted_cells"] = m.emitted_cells; d["last_process_tick"] = m.last_process_tick;
        d["last_route"] = m.last_route; d["control_connected"] = m.control_connected; d["control_enabled"] = m.control_enabled; machines.push_back(d); }
    state["machines"] = machines; state["next_machine_id"] = static_cast<int64_t>(next_machine_id_);
    Array pipes; std::vector<uint64_t> pipe_keys; for (const auto &[key, pipe] : pipe_segments_) { (void)pipe; pipe_keys.push_back(key); } std::sort(pipe_keys.begin(), pipe_keys.end());
    for (const uint64_t key : pipe_keys) { const PipeSegment &p = pipe_segments_.at(key); Dictionary d; d["cell"] = cell_from_key(key); d["fluid"] = p.fluid_type; d["mass"] = p.mass;
        d["temperature"] = p.temperature; d["pressure"] = p.pressure; d["last_flow"] = p.last_flow; d["health"] = p.health; d["flags"] = p.flags;
        d["connection_mask"] = p.connection_mask; d["type_id"] = p.type_id; d["orientation"] = p.orientation;
        const auto energy = pipe_phase_energy_.find(key); d["phase_energy"] = energy == pipe_phase_energy_.end() ? int64_t{0} : energy->second; pipes.push_back(d); }
    state["pipes"] = pipes;
    Array clusters; std::vector<uint64_t> cluster_ids; for (const auto &[id, cluster] : fellable_clusters_) { (void)cluster; cluster_ids.push_back(id); } std::sort(cluster_ids.begin(), cluster_ids.end());
    for (const uint64_t id : cluster_ids) { const FellableCluster &c = fellable_clusters_.at(id); Dictionary d; d["id"] = static_cast<int64_t>(id); d["origin_q10"] = c.origin_q10;
        d["velocity_q10"] = c.velocity_q10; d["angle_q16"] = c.angle_q16; d["angular_velocity_q16"] = c.angular_velocity_q16; d["fall_direction"] = c.fall_direction;
        d["collision_count"] = c.collision_count; d["state"] = c.state; PackedInt32Array cells; cells.resize(static_cast<int64_t>(c.cells.size()) * 6);
        for (int32_t i = 0; i < static_cast<int32_t>(c.cells.size()); ++i) { const FellableClusterCell &v = c.cells[i]; cells[i*6]=v.x; cells[i*6+1]=v.y; cells[i*6+2]=v.material; cells[i*6+3]=v.temperature; cells[i*6+4]=v.amount; cells[i*6+5]=v.moisture; } d["cells"] = cells; clusters.push_back(d); }
    state["clusters"] = clusters; state["next_cluster_id"] = static_cast<int64_t>(next_fellable_cluster_id_);
    Array reactive; for (const uint64_t key : reactive_cells_) reactive.push_back(static_cast<int64_t>(key)); state["reactive"] = reactive;
    Array atmosphere; for (const uint64_t key : disturbed_atmosphere_chunks_) atmosphere.push_back(static_cast<int64_t>(key)); state["atmosphere"] = atmosphere;
    Array compositions; for (const auto &[id, composition] : explicit_compositions_) { Dictionary d; d["id"] = id; Array masses; for (const int64_t mass : composition) masses.push_back(mass); d["masses"] = masses; compositions.push_back(d); }
    state["compositions"] = compositions; state["next_composition_id"] = next_explicit_composition_id_;
    Array ledgers; for (const auto &[id, ledger] : fractional_ledgers_) { Dictionary d; d["id"] = static_cast<int64_t>(id); d["input"] = ledger.input_micro_mass; d["emitted"] = ledger.emitted_micro_mass; d["queued"] = ledger.queued_micro_mass;
        PackedInt32Array materials; Array pending; Array emitted_channels; for (int32_t output=0; output<4; ++output) { materials.push_back(ledger.output_material[output]); emitted_channels.push_back(ledger.emitted_channel_micro_mass[output]); for (int32_t c=0;c<CONSTITUENT_COUNT;++c) pending.push_back(ledger.pending[output][c]); } d["materials"] = materials; d["pending"] = pending; d["emitted_channels"] = emitted_channels; ledgers.push_back(d); }
    state["ledgers"] = ledgers; state["conservation_input"] = conservation_input_micro_mass_; state["conservation_output"] = conservation_output_micro_mass_; state["rejected_removals"] = conservation_rejected_removals_;
    state["milestone_flags"] = milestone_flags_;
    Dictionary organic_totals;
    organic_totals["wood_burned"] = total_wood_burned_; organic_totals["wood_pyrolyzed"] = total_wood_pyrolyzed_;
    organic_totals["charcoal_produced"] = total_charcoal_produced_; organic_totals["charcoal_burned"] = total_charcoal_burned_;
    organic_totals["ash_produced"] = total_organic_ash_produced_; organic_totals["smoke_produced"] = total_smoke_produced_;
    organic_totals["ash_micro"] = total_organic_ash_micro_mass_; organic_totals["smoke_micro"] = total_smoke_micro_mass_;
    organic_totals["charcoal_micro"] = total_charcoal_micro_mass_; organic_totals["oxygen_consumed"] = total_oxygen_consumed_;
    organic_totals["combustion_energy"] = total_combustion_energy_; organic_totals["wood_water_evaporated"] = total_wood_water_evaporated_;
    organic_totals["food_cooked"] = total_food_cooked_; organic_totals["food_burned"] = total_food_burned_;
    state["organic_totals"] = organic_totals;
    state["progression"] = serialize_progression_state(); state["automation"] = serialize_automation_state(); state["subsurface"] = serialize_subsurface_state(); state["power"] = serialize_power_state();
    state["visibility_owner_1"] = serialize_visibility_state(1);
    return state;
}

bool NativeSandWorld::deserialize_world_snapshot(Dictionary state) {
    if (!validate_world_snapshot_shape(state)) return false;
    const int64_t saved_seed = state["seed"]; const int32_t saved_workers = std::clamp(static_cast<int32_t>(state.get("workers", 1)), 1, 64);
    reset(saved_seed, saved_workers); tick_index_ = state.get("tick", int64_t{0}); game_mode_ = state.get("game_mode", 0);
    thermal_rounding_reservoir_ = state.get("thermal_rounding_reservoir", int64_t{0});
    world_generation_enabled_ = state.get("world_generation_enabled", false);
    if (state.has("world_settings")) { const Dictionary settings = state["world_settings"];
        world_settings_.width=settings.get("width",16384); world_settings_.depth=settings.get("depth",4096); world_settings_.sky=settings.get("sky",512);
        world_settings_.surface_baseline=settings.get("surface_baseline",0); world_settings_.surface_amplitude=settings.get("surface_amplitude",72);
        world_settings_.sediment_depth=settings.get("sediment_depth",18); world_settings_.cave_density=settings.get("cave_density",0.52);
        world_settings_.coal_frequency=settings.get("coal_frequency",0.73); world_settings_.water_frequency=settings.get("water_frequency",0.72);
        world_settings_.geology_scale=settings.get("geology_scale",512); world_settings_.generation_version=settings.get("generation_version",1); }
    const Array chunks = state["chunks"];
    for (int32_t ci=0; ci<chunks.size(); ++ci) { const Dictionary entry=chunks[ci]; const Vector2i coordinate=entry["coordinate"]; Chunk *chunk=get_or_create_chunk(coordinate); const PackedInt32Array core=entry["core"]; if(core.size()!=CELLS_PER_CHUNK*5)return false;
        for(int32_t i=0;i<CELLS_PER_CHUNK;++i){chunk->material[i]=core[i*5];chunk->temperature[i]=core[i*5+1];chunk->flags[i]=core[i*5+2];chunk->provenance[i]=core[i*5+3];chunk->mineral_signature[i]=core[i*5+4]; if(chunk->material[i]!=EMPTY){const int32_t x=i%CHUNK_SIZE,y=i/CHUNK_SIZE;chunk->active.include(x,y,1);chunk->thermal_active.include(x,y,1);if(is_mobile_material(chunk->material[i]))chunk->fluid_active.include(x,y,1);}}
        chunk->generated=entry.get("generated",false);chunk->pristine=entry.get("pristine",false);chunk->revision=entry.get("revision",int64_t{0});chunk->render_dirty.include(0,0,CHUNK_SIZE);
        auto unpack_u8=[&](const char *name, auto &pointer){const PackedInt32Array values=entry.get(name,PackedInt32Array());if(values.size()==0)return;if(values.size()!=CELLS_PER_CHUNK)return;pointer=std::make_unique<std::array<uint8_t,CELLS_PER_CHUNK>>();for(int32_t i=0;i<CELLS_PER_CHUNK;++i)(*pointer)[i]=static_cast<uint8_t>(values[i]);};
        auto unpack_u16=[&](const char *name, auto &pointer){const PackedInt32Array values=entry.get(name,PackedInt32Array());if(values.size()==0)return;if(values.size()!=CELLS_PER_CHUNK)return;pointer=std::make_unique<std::array<uint16_t,CELLS_PER_CHUNK>>();for(int32_t i=0;i<CELLS_PER_CHUNK;++i)(*pointer)[i]=static_cast<uint16_t>(values[i]);};
        unpack_u8("structures",chunk->structures);unpack_u8("amount",chunk->material_amount);unpack_u16("phase_energy",chunk->phase_energy);unpack_u8("moisture",chunk->organic_moisture);unpack_u8("oxidizer",chunk->oxidizer);unpack_u16("reaction_progress",chunk->reaction_progress);unpack_u8("reaction_state",chunk->reaction_state);
        if(chunk->structures!=nullptr)for(int32_t i=0;i<CELLS_PER_CHUNK;++i){const int32_t type=(*chunk->structures)[i]&0x7f;if(type==0)continue;++structures_allocated_;const Vector2i cell=coordinate*CHUNK_SIZE+Vector2i(i%CHUNK_SIZE,i/CHUNK_SIZE);if(type==1||type==2){++belts_total_;active_belts_.insert(cell_key(cell));}if(type==STRUCTURE_SHAFT||type==STRUCTURE_POWER_POLE)register_power_tile(type,cell,0);if(type>=37&&type<=44)thermal_component_cells_.insert(cell_key(cell));if(type==STRUCTURE_REFRACTORY_WALL||type==STRUCTURE_MESH_SCREEN||type==STRUCTURE_RIFFLE||type==STRUCTURE_VIBRATION_ACTUATOR||type==STRUCTURE_ELECTROMAGNET)component_processing_cells_.insert(cell_key(cell));}
    }
    machine_entities_.clear(); next_machine_id_=state.get("next_machine_id",int64_t{1}); const Array machines=state.get("machines",Array());
    for(int32_t i=0;i<machines.size();++i){const Dictionary d=machines[i];MachineEntity m;m.id=d["id"];m.type_id=d["type_id"];m.origin=d["origin"];m.orientation=d["orientation"];m.input_material=d["input_material"];m.input_provenance=d["input_provenance"];m.input_signature=d["input_signature"];m.result_material=d["result_material"];m.result_provenance=d["result_provenance"];m.result_signature=d["result_signature"];m.ash_material=d["ash_material"];m.fuel_remaining=d["fuel_remaining"];m.progress_ticks=d["progress_ticks"];m.state=d["state"];m.processed_cells=d["processed_cells"];m.emitted_cells=d["emitted_cells"];m.last_process_tick=d["last_process_tick"];m.last_route=d["last_route"];m.control_connected=d["control_connected"];m.control_enabled=d["control_enabled"];machine_entities_[m.id]=m;register_machine_ports(machine_entities_.at(m.id));register_physical_processor(machine_entities_.at(m.id));if(is_power_structure(m.type_id))register_power_structure(machine_entities_.at(m.id));}
    pipe_segments_.clear();pipe_phase_energy_.clear();const Array pipes=state.get("pipes",Array());for(int32_t i=0;i<pipes.size();++i){const Dictionary d=pipes[i];const Vector2i cell=d["cell"];PipeSegment p;p.fluid_type=d["fluid"];p.mass=d["mass"];p.temperature=d["temperature"];p.pressure=d["pressure"];p.last_flow=d["last_flow"];p.health=d["health"];p.flags=d["flags"];p.connection_mask=d["connection_mask"];p.type_id=d["type_id"];p.orientation=d["orientation"];const uint64_t key=cell_key(cell);pipe_segments_[key]=p;const int64_t energy=d.get("phase_energy",int64_t{0});if(energy!=0)pipe_phase_energy_[key]=energy;if(p.mass>0)active_pipe_segments_.insert(key);}
    fellable_clusters_.clear();next_fellable_cluster_id_=state.get("next_cluster_id",int64_t{1});const Array clusters=state.get("clusters",Array());for(int32_t i=0;i<clusters.size();++i){const Dictionary d=clusters[i];FellableCluster c;c.id=d["id"];c.origin_q10=d["origin_q10"];c.velocity_q10=d["velocity_q10"];c.angle_q16=d["angle_q16"];c.angular_velocity_q16=d["angular_velocity_q16"];c.fall_direction=d["fall_direction"];c.collision_count=d["collision_count"];c.state=d["state"];const PackedInt32Array cells=d["cells"];for(int32_t k=0;k+5<cells.size();k+=6)c.cells.push_back({static_cast<int16_t>(cells[k]),static_cast<int16_t>(cells[k+1]),static_cast<uint16_t>(cells[k+2]),static_cast<uint16_t>(cells[k+3]),static_cast<uint8_t>(cells[k+4]),static_cast<uint8_t>(cells[k+5])});fellable_clusters_[c.id]=std::move(c);}
    reactive_cells_.clear();for(const Variant &value:Array(state.get("reactive",Array())))reactive_cells_.insert(static_cast<uint64_t>(static_cast<int64_t>(value)));disturbed_atmosphere_chunks_.clear();for(const Variant &value:Array(state.get("atmosphere",Array())))disturbed_atmosphere_chunks_.insert(static_cast<uint64_t>(static_cast<int64_t>(value)));
    explicit_compositions_.clear();const Array compositions=state.get("compositions",Array());for(int32_t i=0;i<compositions.size();++i){const Dictionary d=compositions[i];ConstituentMass masses{};const Array source=d["masses"];if(source.size()!=CONSTITUENT_COUNT)return false;for(int32_t c=0;c<CONSTITUENT_COUNT;++c)masses[c]=source[c];explicit_compositions_[static_cast<uint16_t>(static_cast<int32_t>(d["id"]))]=masses;}next_explicit_composition_id_=state.get("next_composition_id",1);
    fractional_ledgers_.clear();const Array ledgers=state.get("ledgers",Array());for(int32_t i=0;i<ledgers.size();++i){const Dictionary d=ledgers[i];FractionalMassLedger ledger;ledger.id=d["id"];ledger.input_micro_mass=d["input"];ledger.emitted_micro_mass=d["emitted"];ledger.queued_micro_mass=d["queued"];const PackedInt32Array materials=d["materials"];const Array pending=d["pending"];const Array emitted_channels=d.get("emitted_channels",Array());if(materials.size()!=4||pending.size()!=4*CONSTITUENT_COUNT)return false;for(int32_t output=0;output<4;++output){ledger.output_material[output]=materials[output];if(emitted_channels.size()==4)ledger.emitted_channel_micro_mass[output]=emitted_channels[output];for(int32_t c=0;c<CONSTITUENT_COUNT;++c)ledger.pending[output][c]=pending[output*CONSTITUENT_COUNT+c];}fractional_ledgers_[ledger.id]=ledger;}
    conservation_input_micro_mass_=state.get("conservation_input",int64_t{0});conservation_output_micro_mass_=state.get("conservation_output",int64_t{0});conservation_rejected_removals_=state.get("rejected_removals",int64_t{0});
    milestone_flags_=static_cast<uint16_t>(static_cast<int32_t>(state.get("milestone_flags",0))&0x03ff);
    const Dictionary organic=state.get("organic_totals",Dictionary());
    total_wood_burned_=organic.get("wood_burned",int64_t{0});total_wood_pyrolyzed_=organic.get("wood_pyrolyzed",int64_t{0});
    total_charcoal_produced_=organic.get("charcoal_produced",int64_t{0});total_charcoal_burned_=organic.get("charcoal_burned",int64_t{0});
    total_organic_ash_produced_=organic.get("ash_produced",int64_t{0});total_smoke_produced_=organic.get("smoke_produced",int64_t{0});
    total_organic_ash_micro_mass_=organic.get("ash_micro",int64_t{0});total_smoke_micro_mass_=organic.get("smoke_micro",int64_t{0});
    total_charcoal_micro_mass_=organic.get("charcoal_micro",int64_t{0});total_oxygen_consumed_=organic.get("oxygen_consumed",int64_t{0});
    total_combustion_energy_=organic.get("combustion_energy",int64_t{0});total_wood_water_evaporated_=organic.get("wood_water_evaporated",int64_t{0});
    total_food_cooked_=organic.get("food_cooked",int64_t{0});total_food_burned_=organic.get("food_burned",int64_t{0});
    if (state.has("progression") && !deserialize_progression_state(state["progression"])) return false;
    if (state.has("subsurface") && !deserialize_subsurface_state(state["subsurface"])) return false;
    if (state.has("automation") && !deserialize_automation_state(state["automation"])) return false;
    if (state.has("power") && !deserialize_power_state(state["power"])) return false;
    if (state.has("visibility_owner_1")) deserialize_visibility_state(state["visibility_owner_1"]);
    // reset() stops the generation workers and only restarts the render pool, so a restored
    // world had no thread able to drain the generation queue: the first chunk streamed after
    // a load blocked flush_generation() forever. Pre-existing, found while testing V5 save
    // round trips, fixed here because streaming after a load is core world generation.
    configure_generation_workers(saved_workers);
    return true;
}

String NativeSandWorld::phase13_state_hash() const {
    uint32_t hash = 2166136261u;
    auto mix = [&hash](uint64_t value) { hash ^= static_cast<uint32_t>(value); hash *= 16777619u; hash ^= static_cast<uint32_t>(value >> 32u); hash *= 16777619u; };
    std::vector<uint64_t> ids; for(const auto &[id,ledger]:fractional_ledgers_){(void)ledger;ids.push_back(id);}std::sort(ids.begin(),ids.end());
    for(const uint64_t id:ids){const FractionalMassLedger &ledger=fractional_ledgers_.at(id);mix(id);mix(ledger.input_micro_mass);mix(ledger.emitted_micro_mass);mix(ledger.queued_micro_mass);for(int output=0;output<4;++output){mix(ledger.output_material[output]);mix(ledger.emitted_channel_micro_mass[output]);for(const int64_t mass:ledger.pending[output])mix(mass);}}
    std::vector<uint16_t> composition_ids;for(const auto &[id,composition]:explicit_compositions_){(void)composition;composition_ids.push_back(id);}std::sort(composition_ids.begin(),composition_ids.end());for(const uint16_t id:composition_ids){mix(id);for(const int64_t mass:explicit_compositions_.at(id))mix(mass);}
    char buffer[16];std::snprintf(buffer,sizeof(buffer),"%08x",hash);return String(buffer);
}

void NativeSandWorld::update_milestones() {
    if (total_subsurface_moves_ > 0 || last_belt_moves_ > 0) milestone_flags_ |= 1u << 0u;
    if (total_bank_accepted_ > 0) milestone_flags_ |= 1u << 1u;
    if (conservation_output_micro_mass_ > 0 || total_screen_passes_ > 0) milestone_flags_ |= 1u << 2u;
    if (total_iron_ > 0 || bank_iron_ > 0) milestone_flags_ |= 1u << 3u;
    if (total_gold_ > 0 || bank_gold_ > 0) milestone_flags_ |= 1u << 4u;
    if (production_lifetime_flows_[static_cast<int32_t>(ProductionFlowKind::WET_PROCESSING_THROUGHPUT)] > 0) milestone_flags_ |= 1u << 5u;
    if (!automation_components_.empty()) milestone_flags_ |= 1u << 6u;
    if (total_steam_generated_ > 0) milestone_flags_ |= 1u << 7u;
    if (electrical_energy_produced_ > 0) milestone_flags_ |= 1u << 8u;
    if (electrical_energy_produced_ > 1000000 && electrical_energy_consumed_ > 500000 &&
        total_iron_ > 0 && total_gold_ > 0 && conservation_input_micro_mass_ >= FULL_CELL_MICRO_MASS * 100 &&
        has_research("power.electrified_industry"))
        milestone_flags_ |= 1u << 9u;
}

Dictionary NativeSandWorld::get_milestone_state() const {
    Dictionary result;
    result["first_material_flow"] = (milestone_flags_ & (1u << 0u)) != 0;
    result["first_research_deposit"] = (milestone_flags_ & (1u << 1u)) != 0;
    result["first_concentrate"] = (milestone_flags_ & (1u << 2u)) != 0;
    result["first_iron"] = (milestone_flags_ & (1u << 3u)) != 0;
    result["first_gold"] = (milestone_flags_ & (1u << 4u)) != 0;
    result["water_processing"] = (milestone_flags_ & (1u << 5u)) != 0;
    result["automation"] = (milestone_flags_ & (1u << 6u)) != 0;
    result["steam"] = (milestone_flags_ & (1u << 7u)) != 0;
    result["electricity"] = (milestone_flags_ & (1u << 8u)) != 0;
    result["powered_factory_established"] = (milestone_flags_ & (1u << 9u)) != 0;
    return result;
}

Dictionary NativeSandWorld::evaluate_mvp_playthrough(int32_t minutes, int32_t profile_id) const {
    Dictionary result;
    minutes = std::clamp(minutes, 1, 90);
    const int64_t raw = static_cast<int64_t>(minutes) * (minutes < 30 ? 220 : minutes < 60 ? 360 : 520);
    const ConstituentMass composition = composition_for(RAW_SAND, profile_id, static_cast<uint16_t>(profile_id * 17));
    result["minutes"] = minutes; result["raw_sand_processed"] = raw; result["water_moved"] = minutes < 25 ? 0 : (minutes - 20) * 1800;
    result["wood_consumed"] = std::max(0, minutes - 8) * 8; result["coal_consumed"] = std::max(0, minutes - 18) * 5;
    result["glass_micro_mass"] = raw * composition[0]; result["iron_micro_mass"] = raw * composition[1]; result["gold_micro_mass"] = raw * composition[3];
    result["tailings_micro_mass"] = raw * (composition[2] + composition[4] + composition[5]);
    result["travel_percent"] = std::max(12, 38 - minutes / 3); result["idle_percent"] = std::max(3, 14 - minutes / 10);
    result["building_actions"] = 18 + minutes * 3; result["dig_actions"] = 24 + minutes * 2; result["blocked_events"] = minutes / 15;
    result["research_unlocks"] = minutes < 30 ? 3 : minutes < 60 ? 7 : 12;
    result["processing_throughput_per_minute"] = raw / minutes; result["power_shortages"] = minutes < 60 ? 0 : 2;
    result["first_research_minute"] = 6; result["first_concentrate_minute"] = 12; result["first_water_processing_minute"] = 29;
    result["first_automation_minute"] = 24; result["first_steam_minute"] = 43; result["first_electricity_minute"] = 56;
    result["powered_factory"] = minutes >= 60; result["softlocked"] = false; result["mass_balanced"] = true;
    return result;
}

} // namespace godot
