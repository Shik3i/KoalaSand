#pragma once

#include "worker_backend.hpp"

#include <array>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace koalasand_core {

enum class FluidCandidate : std::uint8_t {
    DiscreteFullCell = 0,
    FixedMass8 = 1,
};

struct FluidTelemetry {
    std::uint64_t allocated_cells = 0;
    std::uint64_t active_cells = 0;
    std::uint64_t visited_cells = 0;
    std::uint64_t frontier_cells = 0;
    std::uint64_t active_rows = 0;
    std::uint64_t active_spans = 0;
    std::uint64_t transfers = 0;
    std::uint64_t lateral_moves = 0;
    std::uint64_t downward_moves = 0;
    std::uint64_t blocked_liquid = 0;
    std::uint64_t sleep_transitions = 0;
    std::uint64_t wake_transitions = 0;
    std::uint64_t border_crossings = 0;
    std::uint64_t barrier_merge_ns = 0;
    std::uint32_t workers_used = 1;
};

class FluidPrototype {
public:
    static constexpr std::int32_t CHUNK_SIZE = 64;
    static constexpr std::uint16_t AMBIENT_TEMPERATURE = 1173;

    FluidPrototype(std::int32_t width, std::int32_t height, FluidCandidate candidate, std::int32_t workers = 1);
    ~FluidPrototype();
    FluidPrototype(const FluidPrototype &) = delete;
    FluidPrototype &operator=(const FluidPrototype &) = delete;

    void clear();
    void set_wall(std::int32_t x, std::int32_t y, bool wall = true);
    void set_water(std::int32_t x, std::int32_t y, std::uint8_t mass = 255, std::uint16_t temperature = AMBIENT_TEMPERATURE);
    void set_sand(std::int32_t x, std::int32_t y);
    void remove_gate(std::int32_t x, std::int32_t y);
    bool drop_sand_once(std::int32_t x, std::int32_t y);
    void wake_cell(std::int32_t x, std::int32_t y, std::int32_t radius = 1);
    void wake_all();
    void seed_stress_pattern();
    void inject_source(std::int32_t x, std::int32_t y, std::uint8_t mass = 255);
    FluidTelemetry step();

    std::uint8_t mass_at(std::int32_t x, std::int32_t y) const;
    std::uint16_t temperature_at(std::int32_t x, std::int32_t y) const;
    std::uint8_t material_at(std::int32_t x, std::int32_t y) const;
    std::uint64_t state_hash() const;
    std::uint64_t liquid_cells() const;
    std::uint64_t active_span_cells() const;
    std::uint64_t incremental_state_bytes() const;
    std::uint64_t activity_metadata_bytes() const;
    std::int32_t width() const { return width_; }
    std::int32_t height() const { return height_; }
    FluidCandidate candidate() const { return candidate_; }
    WorkerBackend backend() const { return worker_count_ == 1 ? WorkerBackend::SingleThread : WorkerBackend::NativeThreads; }

private:
    struct ActiveChunk {
        std::uint64_t rows = 0;
        std::array<std::uint8_t, CHUNK_SIZE> min_x{};
        std::array<std::uint8_t, CHUNK_SIZE> max_x{};
        ActiveChunk();
        void clear();
        void include(std::int32_t local_x, std::int32_t local_y, std::int32_t radius = 0);
    };

    class WorkerPool;
    struct WorkerCounters {
        std::uint64_t visited = 0;
        std::uint64_t transfers = 0;
        std::uint64_t lateral = 0;
        std::uint64_t downward = 0;
        std::uint64_t blocked = 0;
        std::uint64_t border = 0;
        void clear();
    };

    std::int32_t width_;
    std::int32_t height_;
    std::int32_t chunks_x_;
    std::int32_t chunks_y_;
    FluidCandidate candidate_;
    std::int32_t worker_count_;
    std::uint64_t tick_ = 0;
    std::vector<std::uint8_t> material_;
    std::vector<std::uint8_t> fluid_mass_;
    std::vector<std::uint16_t> temperature_;
    std::vector<ActiveChunk> active_;
    std::vector<std::uint8_t> quiet_passes_;
    std::vector<std::vector<ActiveChunk>> worker_activity_;
    std::vector<WorkerCounters> worker_counters_;
    std::unique_ptr<WorkerPool> workers_;

    bool inside(std::int32_t x, std::int32_t y) const;
    std::size_t index(std::int32_t x, std::int32_t y) const;
    bool blocked(std::int32_t x, std::int32_t y) const;
    std::uint8_t read_mass(std::size_t index) const;
    void write_mass(std::size_t index, std::uint8_t mass);
    void clear_worker_state();
    void include_worker(std::int32_t worker, std::int32_t x, std::int32_t y, std::int32_t radius = 1);
    std::vector<ActiveChunk> merge_worker_activity(std::uint64_t &merge_ns);
    static void merge_activity(std::vector<ActiveChunk> &target, const std::vector<ActiveChunk> &source);
    bool row_range(const std::vector<ActiveChunk> &activity, std::int32_t y, std::int32_t chunk_x,
                   std::int32_t &min_x, std::int32_t &max_x) const;
    void run_vertical(const std::vector<ActiveChunk> &input);
    void run_horizontal(const std::vector<ActiveChunk> &input);
    void exchange_vertical(std::int32_t worker, std::int32_t x, std::int32_t top_y);
    void exchange_horizontal(std::int32_t worker, std::int32_t left_x, std::int32_t y);
    void transfer_mass(std::size_t source, std::size_t destination, std::uint8_t amount);
    std::uint64_t count_active_rows() const;
};

const char *fluid_candidate_name(FluidCandidate candidate);

} // namespace koalasand_core
