#include "native_sand_world.hpp"

#include <algorithm>

namespace godot {

void NativeSandWorld::configure_thermal_candidate(int32_t width, int32_t height, int32_t workers) {
    width = std::clamp(width, 64, 2048);
    height = std::clamp(height, 64, 2048);
    thermal_candidate_ = std::make_unique<koalasand_core::ThermalPrototype>(width, height, workers);
    thermal_candidate_->set_material(1, {64, 48, 0, 65535, false});
    thermal_candidate_->set_material(2, {32, 32, 0, 65535, false});
    thermal_candidate_->set_material(3, {48, 128, 1092, 1492, true});
    thermal_candidate_->set_material(10, {24, 40, 0, 5873, false});
    thermal_candidate_->set_material(11, {192, 56, 0, 7245, false});
    thermal_candidate_->fill(1, koalasand_core::ThermalPrototype::Ambient);
    std::vector<koalasand_core::HeatSource> sources;
    for (int32_t index = 0; index < 16; ++index) {
        sources.push_back({96 + (index % 8) * 112, 128 + (index / 8) * std::max(1, height - 292), 4, 384, 1, true});
    }
    thermal_candidate_->set_heat_sources(sources);
    thermal_candidate_->rebuild_activity();
    thermal_candidate_statistics_.clear();
}

Dictionary NativeSandWorld::step_thermal_candidate(int32_t cadence_scale) {
    if (thermal_candidate_ == nullptr) return Dictionary();
    const koalasand_core::ThermalStats stats = thermal_candidate_->tick(std::clamp(cadence_scale, 1, 4));
    thermal_candidate_statistics_["active_cells"] = stats.active_cells;
    thermal_candidate_statistics_["visited_cells"] = stats.visited_cells;
    thermal_candidate_statistics_["exchanges"] = stats.exchanges;
    thermal_candidate_statistics_["source_cells"] = stats.source_cells;
    thermal_candidate_statistics_["source_energy"] = stats.source_energy;
    thermal_candidate_statistics_["thermal_usec"] = stats.thermal_usec;
    thermal_candidate_statistics_["barrier_usec"] = stats.barrier_usec;
    thermal_candidate_statistics_["workers_used"] = stats.workers_used;
    thermal_candidate_statistics_["hash"] = String::num_uint64(thermal_candidate_->hash(), 16);
    thermal_candidate_statistics_["activity_bytes"] = static_cast<int64_t>(thermal_candidate_->activity_bytes());
    thermal_candidate_statistics_["scratch_bytes"] = static_cast<int64_t>(thermal_candidate_->scratch_bytes());
    return thermal_candidate_statistics_;
}

Dictionary NativeSandWorld::get_thermal_candidate_statistics() const { return thermal_candidate_statistics_; }

} // namespace godot
