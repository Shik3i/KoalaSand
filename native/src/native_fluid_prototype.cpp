#include "native_fluid_prototype.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
#include <cstdio>

namespace godot {

void NativeFluidPrototype::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_representative", "requested_workers"), &NativeFluidPrototype::configure_representative, DEFVAL(4));
    ClassDB::bind_method(D_METHOD("step_representative"), &NativeFluidPrototype::step_representative);
    ClassDB::bind_method(D_METHOD("get_memory_statistics"), &NativeFluidPrototype::get_memory_statistics);
    ClassDB::bind_method(D_METHOD("state_hash"), &NativeFluidPrototype::state_hash);
}

void NativeFluidPrototype::configure_representative(int32_t requested_workers) {
    prototype_ = std::make_unique<koalasand_core::FluidPrototype>(1024, 1024, koalasand_core::FluidCandidate::FixedMass8,
                                                                  std::clamp(requested_workers, 1, 8));
    for (int32_t x = 0; x < 1024; ++x) {
        prototype_->set_wall(x, 0);
        prototype_->set_wall(x, 1023);
    }
    for (int32_t y = 0; y < 1024; ++y) {
        prototype_->set_wall(0, y);
        prototype_->set_wall(1023, y);
    }
    for (int32_t y = 620; y < 1023; ++y) {
        for (int32_t x = 32; x < 480; ++x) prototype_->set_water(x, y, 255);
        for (int32_t x = 544; x < 992; ++x) prototype_->set_water(x, y, 255);
    }
    for (int32_t y = 420; y < 1023; ++y) prototype_->set_wall(512, y);
    prototype_->wake_all();
    for (int32_t warmup = 0; warmup < 4; ++warmup) prototype_->step();
    tick_ = 0;
    last_step_usec_ = 0;
    last_ = {};
}

Dictionary NativeFluidPrototype::step_representative() {
    Dictionary result;
    if (!prototype_) return result;
    prototype_->inject_source(256, 4, 255);
    prototype_->inject_source(768, 4, 255);
    if (tick_ == 60) for (int32_t y = 760; y < 800; ++y) prototype_->remove_gate(512, y);
    const auto started = std::chrono::steady_clock::now();
    last_ = prototype_->step();
    last_step_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    ++tick_;
    result["tick"] = tick_;
    result["allocated_cells"] = static_cast<int64_t>(last_.allocated_cells);
    result["active_cells"] = static_cast<int64_t>(last_.active_cells);
    result["visited_cells"] = static_cast<int64_t>(last_.visited_cells);
    result["frontier_cells"] = static_cast<int64_t>(last_.frontier_cells);
    result["active_rows"] = static_cast<int64_t>(last_.active_rows);
    result["active_spans"] = static_cast<int64_t>(last_.active_spans);
    result["transfers"] = static_cast<int64_t>(last_.transfers);
    result["downward_moves"] = static_cast<int64_t>(last_.downward_moves);
    result["lateral_moves"] = static_cast<int64_t>(last_.lateral_moves);
    result["blocked_liquid"] = static_cast<int64_t>(last_.blocked_liquid);
    result["sleep_transitions"] = static_cast<int64_t>(last_.sleep_transitions);
    result["wake_transitions"] = static_cast<int64_t>(last_.wake_transitions);
    result["border_crossings"] = static_cast<int64_t>(last_.border_crossings);
    result["barrier_merge_usec"] = static_cast<double>(last_.barrier_merge_ns) / 1000.0;
    result["fluid_usec"] = last_step_usec_;
    result["workers"] = static_cast<int32_t>(last_.workers_used);
    return result;
}

Dictionary NativeFluidPrototype::get_memory_statistics() const {
    Dictionary result;
    if (!prototype_) return result;
    result["allocated_cells"] = prototype_->width() * prototype_->height();
    result["fluid_state_bytes"] = static_cast<int64_t>(prototype_->incremental_state_bytes());
    result["activity_metadata_bytes"] = static_cast<int64_t>(prototype_->activity_metadata_bytes());
    result["bytes_per_fluid_cell"] = 1;
    result["bytes_per_fluid_chunk"] = 4096;
    result["activity_bytes_per_chunk"] = 136;
    result["lazy_plane"] = false;
    return result;
}

String NativeFluidPrototype::state_hash() const {
    if (!prototype_) return String();
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%016llx", static_cast<unsigned long long>(prototype_->state_hash()));
    return String(buffer);
}

} // namespace godot
