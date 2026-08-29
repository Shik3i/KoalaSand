#pragma once

#include "parallel_executor.hpp"

#include <cstdint>
#include <vector>

namespace koalasand_core {

struct ThermalMaterial {
    std::uint16_t conductivity = 0;
    std::uint16_t specific_heat = 1;
    std::uint16_t freeze_threshold = 0;
    std::uint16_t boil_or_melt_threshold = 65535;
    bool mass_weighted = false;
};

struct HeatSource {
    std::int32_t x = 0;
    std::int32_t y = 0;
    std::int32_t radius = 0;
    std::int32_t energy_per_tick = 0;
    std::uint8_t material_filter = 0;
    bool enabled = true;
};

struct ThermalStats {
    std::int64_t active_cells = 0;
    std::int64_t visited_cells = 0;
    std::int64_t exchanges = 0;
    std::int64_t source_cells = 0;
    std::int64_t source_energy = 0;
    std::int64_t thermal_usec = 0;
    std::int64_t barrier_usec = 0;
    std::int32_t workers_used = 0;
};

class ThermalPrototype {
public:
    static constexpr std::uint16_t Ambient = 1173;
    static constexpr std::uint16_t ActivationDelta = 2;

    ThermalPrototype(std::int32_t width, std::int32_t height, std::int32_t workers);
    void set_material(std::uint8_t id, ThermalMaterial material);
    void fill(std::uint8_t material, std::uint16_t temperature, std::uint8_t mass = 255);
    void set_cell(std::int32_t x, std::int32_t y, std::uint8_t material, std::uint16_t temperature, std::uint8_t mass = 255);
    std::uint16_t temperature(std::int32_t x, std::int32_t y) const;
    std::int64_t total_energy() const;
    void rebuild_activity();
    void set_heat_sources(const std::vector<HeatSource> &sources);
    ThermalStats tick(std::int32_t cadence_scale = 1);
    std::uint64_t hash() const;
    std::size_t activity_bytes() const;
    std::size_t scratch_bytes() const;

private:
    std::int32_t index(std::int32_t x, std::int32_t y) const { return y * width_ + x; }
    bool inside(std::int32_t x, std::int32_t y) const { return x >= 0 && y >= 0 && x < width_ && y < height_; }
    std::int32_t capacity(std::int32_t index) const;
    bool has_gradient(std::int32_t index) const;
    void mark_with_neighbors(std::vector<std::uint8_t> &marks, std::vector<std::int16_t> &min_x,
                             std::vector<std::int16_t> &max_x, std::int32_t index);
    void collect_marked(std::vector<std::uint8_t> &marks, std::vector<std::int16_t> &min_x,
                        std::vector<std::int16_t> &max_x, std::vector<std::int32_t> &output);
    std::int32_t edge_transfer(std::int32_t a, std::int32_t b, std::int32_t cadence_scale) const;

    std::int32_t width_;
    std::int32_t height_;
    ParallelExecutor executor_;
    ThermalMaterial materials_[256]{};
    std::vector<std::uint8_t> material_;
    std::vector<std::uint8_t> mass_;
    std::vector<std::uint16_t> temperature_;
    std::vector<std::int64_t> energy_;
    std::vector<std::int32_t> active_;
    std::vector<std::int32_t> right_transfer_;
    std::vector<std::int32_t> down_transfer_;
    std::vector<std::uint8_t> candidate_marks_;
    std::vector<std::uint8_t> next_marks_;
    std::vector<std::int16_t> candidate_min_x_;
    std::vector<std::int16_t> candidate_max_x_;
    std::vector<std::int16_t> next_min_x_;
    std::vector<std::int16_t> next_max_x_;
    std::vector<HeatSource> enabled_sources_;
};

} // namespace koalasand_core
