#include "thermal_prototype.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <limits>
#include <numeric>

namespace koalasand_core {

ThermalPrototype::ThermalPrototype(std::int32_t width, std::int32_t height, std::int32_t workers)
    : width_(width), height_(height), executor_(workers), material_(width * height), mass_(width * height, 255),
      temperature_(width * height, Ambient), energy_(width * height), right_transfer_(width * height),
      down_transfer_(width * height), candidate_marks_(width * height), next_marks_(width * height),
      candidate_min_x_(height, width), candidate_max_x_(height, -1), next_min_x_(height, width), next_max_x_(height, -1) {
    materials_[0] = {0, 1, 0, 65535, false};
    fill(0, Ambient);
}

void ThermalPrototype::set_material(std::uint8_t id, ThermalMaterial material) { materials_[id] = material; }

std::int32_t ThermalPrototype::capacity(std::int32_t cell) const {
    const ThermalMaterial &property = materials_[material_[cell]];
    if (property.conductivity == 0) return 1;
    return std::max(1, property.mass_weighted ? static_cast<std::int32_t>(property.specific_heat) * mass_[cell] / 255
                                               : static_cast<std::int32_t>(property.specific_heat));
}

void ThermalPrototype::fill(std::uint8_t material, std::uint16_t temperature, std::uint8_t mass) {
    std::fill(material_.begin(), material_.end(), material);
    std::fill(mass_.begin(), mass_.end(), mass);
    std::fill(temperature_.begin(), temperature_.end(), temperature);
    for (std::int32_t i = 0; i < static_cast<std::int32_t>(energy_.size()); ++i) energy_[i] = static_cast<std::int64_t>(temperature) * capacity(i);
    active_.clear();
}

void ThermalPrototype::set_cell(std::int32_t x, std::int32_t y, std::uint8_t material, std::uint16_t temperature, std::uint8_t mass) {
    if (!inside(x, y)) return;
    const std::int32_t cell = index(x, y);
    material_[cell] = material;
    mass_[cell] = mass;
    temperature_[cell] = temperature;
    energy_[cell] = static_cast<std::int64_t>(temperature) * capacity(cell);
}

std::uint16_t ThermalPrototype::temperature(std::int32_t x, std::int32_t y) const { return inside(x, y) ? temperature_[index(x, y)] : Ambient; }
std::int64_t ThermalPrototype::total_energy() const { return std::accumulate(energy_.begin(), energy_.end(), std::int64_t{0}); }

void ThermalPrototype::mark_with_neighbors(std::vector<std::uint8_t> &marks, std::vector<std::int16_t> &min_x,
                                           std::vector<std::int16_t> &max_x, std::int32_t cell) {
    const std::int32_t cx = cell % width_;
    const std::int32_t cy = cell / width_;
    const std::int32_t neighbors[5][2]{{cx,cy},{cx-1,cy},{cx+1,cy},{cx,cy-1},{cx,cy+1}};
    for (const auto &point : neighbors) {
        if (!inside(point[0], point[1])) continue;
        const std::int32_t candidate = index(point[0], point[1]);
        marks[candidate] = 1;
        min_x[point[1]] = static_cast<std::int16_t>(std::min<std::int32_t>(min_x[point[1]], point[0]));
        max_x[point[1]] = static_cast<std::int16_t>(std::max<std::int32_t>(max_x[point[1]], point[0]));
    }
}

void ThermalPrototype::collect_marked(std::vector<std::uint8_t> &marks, std::vector<std::int16_t> &min_x,
                                      std::vector<std::int16_t> &max_x, std::vector<std::int32_t> &output) {
    output.clear();
    for (std::int32_t y = 0; y < height_; ++y) {
        if (max_x[y] < min_x[y]) continue;
        for (std::int32_t x = min_x[y]; x <= max_x[y]; ++x) {
            const std::int32_t cell = index(x, y);
            if (marks[cell]) output.push_back(cell);
            marks[cell] = 0;
        }
        min_x[y] = static_cast<std::int16_t>(width_);
        max_x[y] = -1;
    }
}

bool ThermalPrototype::has_gradient(std::int32_t cell) const {
    if (materials_[material_[cell]].conductivity == 0) return false;
    const std::int32_t x = cell % width_;
    const std::int32_t y = cell / width_;
    const std::int32_t neighbors[4][2]{{x-1,y},{x+1,y},{x,y-1},{x,y+1}};
    for (const auto &point : neighbors) {
        if (!inside(point[0], point[1])) continue;
        const std::int32_t other = index(point[0], point[1]);
        if (materials_[material_[other]].conductivity == 0) continue;
        if (std::abs(static_cast<std::int32_t>(temperature_[cell]) - temperature_[other]) >= ActivationDelta) return true;
    }
    return false;
}

void ThermalPrototype::rebuild_activity() {
    active_.clear();
    for (std::int32_t y = 0; y < height_; ++y) for (std::int32_t x = 0; x < width_; ++x) {
        const std::int32_t cell = index(x, y);
        if (has_gradient(cell)) mark_with_neighbors(next_marks_, next_min_x_, next_max_x_, cell);
    }
    collect_marked(next_marks_, next_min_x_, next_max_x_, active_);
}

void ThermalPrototype::set_heat_sources(const std::vector<HeatSource> &sources) {
    enabled_sources_.clear();
    for (const HeatSource &source : sources) if (source.enabled && source.energy_per_tick != 0) enabled_sources_.push_back(source);
}

std::int32_t ThermalPrototype::edge_transfer(std::int32_t a, std::int32_t b, std::int32_t cadence_scale) const {
    const std::int32_t delta = static_cast<std::int32_t>(temperature_[a]) - temperature_[b];
    if (std::abs(delta) < ActivationDelta) return 0;
    const std::int32_t conductivity = std::min(materials_[material_[a]].conductivity, materials_[material_[b]].conductivity);
    if (conductivity == 0) return 0;
    const std::int64_t cap_a = capacity(a);
    const std::int64_t cap_b = capacity(b);
    const std::int64_t equilibrium = static_cast<std::int64_t>(std::abs(delta)) * cap_a * cap_b / std::max<std::int64_t>(1, cap_a + cap_b);
    const std::int64_t rate = static_cast<std::int64_t>(std::abs(delta)) * std::min(cap_a, cap_b) * conductivity * cadence_scale / 65536;
    const std::int32_t magnitude = static_cast<std::int32_t>(std::min<std::int64_t>(equilibrium / 2, std::max<std::int64_t>(1, rate)));
    return delta > 0 ? magnitude : -magnitude;
}

ThermalStats ThermalPrototype::tick(std::int32_t cadence_scale) {
    const auto started = std::chrono::steady_clock::now();
    ThermalStats stats;
    stats.active_cells = static_cast<std::int64_t>(active_.size());
    for (const HeatSource &source : enabled_sources_) {
        for (std::int32_t y = source.y - source.radius; y <= source.y + source.radius; ++y) for (std::int32_t x = source.x - source.radius; x <= source.x + source.radius; ++x) {
            if (!inside(x, y)) continue;
            const std::int32_t cell = index(x, y);
            if (source.material_filter != 0 && material_[cell] != source.material_filter) continue;
            energy_[cell] = std::max<std::int64_t>(0, energy_[cell] + static_cast<std::int64_t>(source.energy_per_tick) * cadence_scale);
            temperature_[cell] = static_cast<std::uint16_t>(std::clamp<std::int64_t>(energy_[cell] / capacity(cell), 0, 65535));
            mark_with_neighbors(candidate_marks_, candidate_min_x_, candidate_max_x_, cell);
            ++stats.source_cells;
            stats.source_energy += static_cast<std::int64_t>(source.energy_per_tick) * cadence_scale;
        }
    }
    const std::int32_t jobs = static_cast<std::int32_t>((active_.size() + 8191) / 8192);
    executor_.run(jobs, [&](std::int32_t job, std::int32_t) {
        const std::size_t begin = static_cast<std::size_t>(job) * 8192;
        const std::size_t end = std::min(active_.size(), begin + 8192);
        for (std::size_t cursor = begin; cursor < end; ++cursor) {
            const std::int32_t cell = active_[cursor];
            const std::int32_t x = cell % width_;
            const std::int32_t y = cell / width_;
            right_transfer_[cell] = x + 1 < width_ ? edge_transfer(cell, cell + 1, cadence_scale) : 0;
            down_transfer_[cell] = y + 1 < height_ ? edge_transfer(cell, cell + width_, cadence_scale) : 0;
        }
    });
    stats.barrier_usec = static_cast<std::int64_t>(executor_.wait_ns_last_run() / 1000);
    stats.workers_used = executor_.workers_used_last_run();
    const bool dense = active_.size() * 4 >= energy_.size() * 3;
    if (dense) {
        std::atomic<std::int64_t> exchanges{0};
        executor_.run(jobs, [&](std::int32_t job, std::int32_t) {
            const std::size_t begin = static_cast<std::size_t>(job) * 8192;
            const std::size_t end = std::min(active_.size(), begin + 8192);
            std::int64_t local_exchanges = 0;
            for (std::size_t cursor = begin; cursor < end; ++cursor) {
                const std::int32_t cell = active_[cursor];
                const std::int32_t x = cell % width_;
                const std::int32_t y = cell / width_;
                std::int64_t delta_energy = -static_cast<std::int64_t>(right_transfer_[cell]) - down_transfer_[cell];
                if (x > 0) delta_energy += right_transfer_[cell - 1];
                if (y > 0) delta_energy += down_transfer_[cell - width_];
                local_exchanges += right_transfer_[cell] != 0 ? 1 : 0;
                local_exchanges += down_transfer_[cell] != 0 ? 1 : 0;
                energy_[cell] += delta_energy;
                temperature_[cell] = static_cast<std::uint16_t>(std::clamp<std::int64_t>(energy_[cell] / capacity(cell), 0, 65535));
            }
            exchanges.fetch_add(local_exchanges, std::memory_order_relaxed);
        });
        stats.barrier_usec += static_cast<std::int64_t>(executor_.wait_ns_last_run() / 1000);
        stats.workers_used = std::max(stats.workers_used, executor_.workers_used_last_run());
        stats.exchanges = exchanges.load(std::memory_order_relaxed);
        stats.visited_cells = static_cast<std::int64_t>(active_.size());
        stats.thermal_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
        return stats;
    }
    for (const std::int32_t cell : active_) {
        const std::int32_t right = right_transfer_[cell];
        const std::int32_t down = down_transfer_[cell];
        if (right != 0) { energy_[cell] -= right; energy_[cell + 1] += right; ++stats.exchanges; mark_with_neighbors(candidate_marks_, candidate_min_x_, candidate_max_x_, cell); mark_with_neighbors(candidate_marks_, candidate_min_x_, candidate_max_x_, cell + 1); }
        if (down != 0) { energy_[cell] -= down; energy_[cell + width_] += down; ++stats.exchanges; mark_with_neighbors(candidate_marks_, candidate_min_x_, candidate_max_x_, cell); mark_with_neighbors(candidate_marks_, candidate_min_x_, candidate_max_x_, cell + width_); }
        right_transfer_[cell] = 0;
        down_transfer_[cell] = 0;
    }
    std::vector<std::int32_t> candidates;
    collect_marked(candidate_marks_, candidate_min_x_, candidate_max_x_, candidates);
    stats.visited_cells = static_cast<std::int64_t>(candidates.size());
    for (const std::int32_t cell : candidates) temperature_[cell] = static_cast<std::uint16_t>(std::clamp<std::int64_t>(energy_[cell] / capacity(cell), 0, 65535));
    for (const std::int32_t cell : candidates) if (has_gradient(cell)) mark_with_neighbors(next_marks_, next_min_x_, next_max_x_, cell);
    collect_marked(next_marks_, next_min_x_, next_max_x_, active_);
    stats.thermal_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return stats;
}

std::uint64_t ThermalPrototype::hash() const {
    std::uint64_t value = 1469598103934665603ull;
    for (std::uint16_t temperature : temperature_) { value ^= temperature & 0xffu; value *= 1099511628211ull; value ^= temperature >> 8u; value *= 1099511628211ull; }
    return value;
}

std::size_t ThermalPrototype::activity_bytes() const {
    return active_.capacity() * sizeof(std::int32_t) + candidate_marks_.size() + next_marks_.size() +
           (candidate_min_x_.size() + candidate_max_x_.size() + next_min_x_.size() + next_max_x_.size()) * sizeof(std::int16_t);
}
std::size_t ThermalPrototype::scratch_bytes() const { return (right_transfer_.size() + down_transfer_.size()) * sizeof(std::int32_t); }

} // namespace koalasand_core
