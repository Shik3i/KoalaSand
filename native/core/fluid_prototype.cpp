#include "fluid_prototype.hpp"

#include <algorithm>
#include <atomic>
#include <bit>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <limits>
#include <mutex>
#include <thread>

namespace koalasand_core {

namespace {
constexpr std::uint8_t EMPTY = 0;
constexpr std::uint8_t WALL = 1;
constexpr std::uint8_t SAND = 2;
constexpr std::uint8_t DISCRETE_WATER = 3;
}

class FluidPrototype::WorkerPool {
public:
    explicit WorkerPool(std::int32_t count) : count_(std::max(1, count)) {
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
        count_ = 1;
#else
        if (count_ == 1) return;
        threads_.reserve(count_);
        for (std::int32_t worker = 0; worker < count_; ++worker) {
            threads_.emplace_back([this, worker] { loop(worker); });
        }
#endif
    }

    ~WorkerPool() {
#if !defined(__EMSCRIPTEN__) || defined(__EMSCRIPTEN_PTHREADS__)
        {
            std::lock_guard lock(mutex_);
            stopping_ = true;
            ++generation_;
        }
        start_.notify_all();
        for (auto &thread : threads_) thread.join();
#endif
    }

    void run(std::int32_t jobs, const std::function<void(std::int32_t, std::int32_t)> &function) {
        if (count_ == 1) {
            for (std::int32_t job = 0; job < jobs; ++job) function(0, job);
            return;
        }
        {
            std::lock_guard lock(mutex_);
            function_ = function;
            jobs_ = jobs;
            next_job_.store(0, std::memory_order_relaxed);
            completed_ = 0;
            ++generation_;
        }
        start_.notify_all();
        std::unique_lock lock(mutex_);
        done_.wait(lock, [this] { return completed_ == count_; });
        function_ = {};
    }

private:
#if !defined(__EMSCRIPTEN__) || defined(__EMSCRIPTEN_PTHREADS__)
    void loop(std::int32_t worker) {
        std::uint64_t observed = 0;
        for (;;) {
            std::function<void(std::int32_t, std::int32_t)> function;
            std::int32_t jobs = 0;
            {
                std::unique_lock lock(mutex_);
                start_.wait(lock, [this, observed] { return stopping_ || generation_ != observed; });
                if (stopping_) return;
                observed = generation_;
                function = function_;
                jobs = jobs_;
            }
            for (;;) {
                const std::int32_t job = next_job_.fetch_add(1, std::memory_order_relaxed);
                if (job >= jobs) break;
                function(worker, job);
            }
            {
                std::lock_guard lock(mutex_);
                ++completed_;
                if (completed_ == count_) done_.notify_one();
            }
        }
    }
#endif

    std::int32_t count_ = 1;
    std::vector<std::thread> threads_;
    std::mutex mutex_;
    std::condition_variable start_;
    std::condition_variable done_;
    std::function<void(std::int32_t, std::int32_t)> function_;
    std::atomic<std::int32_t> next_job_{0};
    std::int32_t jobs_ = 0;
    std::int32_t completed_ = 0;
    std::uint64_t generation_ = 0;
    bool stopping_ = false;
};

FluidPrototype::ActiveChunk::ActiveChunk() { clear(); }

void FluidPrototype::ActiveChunk::clear() {
    rows = 0;
    min_x.fill(CHUNK_SIZE - 1);
    max_x.fill(0);
}

void FluidPrototype::ActiveChunk::include(std::int32_t local_x, std::int32_t local_y, std::int32_t radius) {
    const std::int32_t first_y = std::max(0, local_y - radius);
    const std::int32_t last_y = std::min(CHUNK_SIZE - 1, local_y + radius);
    const auto first_x = static_cast<std::uint8_t>(std::max(0, local_x - radius));
    const auto last_x = static_cast<std::uint8_t>(std::min(CHUNK_SIZE - 1, local_x + radius));
    for (std::int32_t y = first_y; y <= last_y; ++y) {
        const std::uint64_t bit = std::uint64_t{1} << y;
        if ((rows & bit) == 0) {
            rows |= bit;
            min_x[y] = first_x;
            max_x[y] = last_x;
        } else {
            min_x[y] = std::min(min_x[y], first_x);
            max_x[y] = std::max(max_x[y], last_x);
        }
    }
}

void FluidPrototype::WorkerCounters::clear() { *this = {}; }

FluidPrototype::FluidPrototype(std::int32_t width, std::int32_t height, FluidCandidate candidate, std::int32_t workers)
    : width_(width), height_(height), chunks_x_((width + CHUNK_SIZE - 1) / CHUNK_SIZE),
      chunks_y_((height + CHUNK_SIZE - 1) / CHUNK_SIZE), candidate_(candidate),
      worker_count_(std::max(1, workers)), material_(static_cast<std::size_t>(width) * height, EMPTY),
      temperature_(static_cast<std::size_t>(width) * height, AMBIENT_TEMPERATURE),
      active_(static_cast<std::size_t>(chunks_x_) * chunks_y_),
      quiet_passes_(active_.size(), 0),
      worker_activity_(worker_count_, std::vector<ActiveChunk>(active_.size())), worker_counters_(worker_count_),
      workers_(std::make_unique<WorkerPool>(worker_count_)) {
    if (candidate_ == FluidCandidate::FixedMass8) fluid_mass_.resize(material_.size(), 0);
}

FluidPrototype::~FluidPrototype() = default;

bool FluidPrototype::inside(std::int32_t x, std::int32_t y) const {
    return x >= 0 && y >= 0 && x < width_ && y < height_;
}

std::size_t FluidPrototype::index(std::int32_t x, std::int32_t y) const {
    return static_cast<std::size_t>(y) * width_ + x;
}

bool FluidPrototype::blocked(std::int32_t x, std::int32_t y) const {
    return !inside(x, y) || material_[index(x, y)] == WALL || material_[index(x, y)] == SAND;
}

std::uint8_t FluidPrototype::read_mass(std::size_t cell) const {
    return candidate_ == FluidCandidate::DiscreteFullCell ? (material_[cell] == DISCRETE_WATER ? 255 : 0) : fluid_mass_[cell];
}

void FluidPrototype::write_mass(std::size_t cell, std::uint8_t mass) {
    if (candidate_ == FluidCandidate::DiscreteFullCell) {
        if (material_[cell] != WALL && material_[cell] != SAND) material_[cell] = mass == 0 ? EMPTY : DISCRETE_WATER;
    } else {
        fluid_mass_[cell] = mass;
    }
}

void FluidPrototype::clear() {
    std::fill(material_.begin(), material_.end(), EMPTY);
    std::fill(fluid_mass_.begin(), fluid_mass_.end(), 0);
    std::fill(temperature_.begin(), temperature_.end(), AMBIENT_TEMPERATURE);
    for (auto &chunk : active_) chunk.clear();
    std::fill(quiet_passes_.begin(), quiet_passes_.end(), 0);
    tick_ = 0;
}

void FluidPrototype::set_wall(std::int32_t x, std::int32_t y, bool wall) {
    if (!inside(x, y)) return;
    const auto cell = index(x, y);
    material_[cell] = wall ? WALL : EMPTY;
    if (wall && candidate_ == FluidCandidate::FixedMass8) fluid_mass_[cell] = 0;
    wake_cell(x, y, 2);
}

void FluidPrototype::set_water(std::int32_t x, std::int32_t y, std::uint8_t mass, std::uint16_t temperature) {
    if (!inside(x, y) || blocked(x, y)) return;
    const auto cell = index(x, y);
    write_mass(cell, candidate_ == FluidCandidate::DiscreteFullCell && mass > 0 ? 255 : mass);
    temperature_[cell] = temperature;
    wake_cell(x, y, 1);
}

void FluidPrototype::set_sand(std::int32_t x, std::int32_t y) {
    if (!inside(x, y)) return;
    const auto cell = index(x, y);
    material_[cell] = SAND;
    if (candidate_ == FluidCandidate::FixedMass8) fluid_mass_[cell] = 0;
    wake_cell(x, y, 1);
}

void FluidPrototype::remove_gate(std::int32_t x, std::int32_t y) { set_wall(x, y, false); }

bool FluidPrototype::drop_sand_once(std::int32_t x, std::int32_t y) {
    if (!inside(x, y) || !inside(x, y + 1) || material_[index(x, y)] != SAND || material_[index(x, y + 1)] == WALL) return false;
    const auto source = index(x, y);
    const auto destination = index(x, y + 1);
    const std::uint8_t displaced = read_mass(destination);
    material_[destination] = SAND;
    material_[source] = EMPTY;
    if (candidate_ == FluidCandidate::FixedMass8) {
        fluid_mass_[destination] = 0;
        fluid_mass_[source] = displaced;
    } else if (displaced > 0) {
        material_[source] = DISCRETE_WATER;
    }
    std::swap(temperature_[source], temperature_[destination]);
    wake_cell(x, y, 2);
    return true;
}

void FluidPrototype::wake_cell(std::int32_t x, std::int32_t y, std::int32_t radius) {
    if (!inside(x, y)) return;
    const std::int32_t chunk_x = x / CHUNK_SIZE;
    const std::int32_t chunk_y = y / CHUNK_SIZE;
    active_[static_cast<std::size_t>(chunk_y) * chunks_x_ + chunk_x].include(x % CHUNK_SIZE, y % CHUNK_SIZE, radius);
    if (x % CHUNK_SIZE < radius && chunk_x > 0) active_[static_cast<std::size_t>(chunk_y) * chunks_x_ + chunk_x - 1].include(CHUNK_SIZE - 1, y % CHUNK_SIZE, radius);
    if (x % CHUNK_SIZE >= CHUNK_SIZE - radius && chunk_x + 1 < chunks_x_) active_[static_cast<std::size_t>(chunk_y) * chunks_x_ + chunk_x + 1].include(0, y % CHUNK_SIZE, radius);
}

void FluidPrototype::wake_all() {
    for (std::int32_t cy = 0; cy < chunks_y_; ++cy) {
        for (std::int32_t cx = 0; cx < chunks_x_; ++cx) {
            auto &chunk = active_[static_cast<std::size_t>(cy) * chunks_x_ + cx];
            const std::int32_t valid_rows = std::min(CHUNK_SIZE, height_ - cy * CHUNK_SIZE);
            chunk.rows = valid_rows == 64 ? std::numeric_limits<std::uint64_t>::max() : ((std::uint64_t{1} << valid_rows) - 1);
            const auto max_x = static_cast<std::uint8_t>(std::min(CHUNK_SIZE, width_ - cx * CHUNK_SIZE) - 1);
            for (std::int32_t y = 0; y < valid_rows; ++y) { chunk.min_x[y] = 0; chunk.max_x[y] = max_x; }
        }
    }
}

void FluidPrototype::seed_stress_pattern() {
    for (std::int32_t y = 1; y < height_ - 1; ++y) {
        for (std::int32_t x = 1; x < width_ - 1; ++x) {
            const auto cell = index(x, y);
            if (material_[cell] == WALL || material_[cell] == SAND) continue;
            if (candidate_ == FluidCandidate::DiscreteFullCell) {
                material_[cell] = ((x + y + static_cast<std::int32_t>(tick_)) & 1) == 0 ? DISCRETE_WATER : EMPTY;
            } else {
                material_[cell] = EMPTY;
                fluid_mass_[cell] = static_cast<std::uint8_t>(((x ^ y ^ static_cast<std::int32_t>(tick_)) & 1) == 0 ? 255 : 31);
            }
            temperature_[cell] = static_cast<std::uint16_t>(AMBIENT_TEMPERATURE + ((x * 3 + y * 5) & 31));
        }
    }
    wake_all();
}

void FluidPrototype::inject_source(std::int32_t x, std::int32_t y, std::uint8_t mass) { set_water(x, y, mass); }

void FluidPrototype::clear_worker_state() {
    for (auto &per_worker : worker_activity_) for (auto &chunk : per_worker) chunk.clear();
    for (auto &counter : worker_counters_) counter.clear();
}

void FluidPrototype::include_worker(std::int32_t worker, std::int32_t x, std::int32_t y, std::int32_t radius) {
    if (!inside(x, y)) return;
    const std::int32_t cx = x / CHUNK_SIZE;
    const std::int32_t cy = y / CHUNK_SIZE;
    worker_activity_[worker][static_cast<std::size_t>(cy) * chunks_x_ + cx].include(x % CHUNK_SIZE, y % CHUNK_SIZE, radius);
}

void FluidPrototype::merge_activity(std::vector<ActiveChunk> &target, const std::vector<ActiveChunk> &source) {
    for (std::size_t index = 0; index < target.size(); ++index) {
        const ActiveChunk &from = source[index];
        ActiveChunk &to = target[index];
        std::uint64_t rows = from.rows;
        while (rows != 0) {
            const std::int32_t row = static_cast<std::int32_t>(std::countr_zero(rows));
            const std::uint64_t bit = std::uint64_t{1} << row;
            if ((to.rows & bit) == 0) {
                to.rows |= bit;
                to.min_x[row] = from.min_x[row];
                to.max_x[row] = from.max_x[row];
            } else {
                to.min_x[row] = std::min(to.min_x[row], from.min_x[row]);
                to.max_x[row] = std::max(to.max_x[row], from.max_x[row]);
            }
            rows &= rows - 1;
        }
    }
}

std::vector<FluidPrototype::ActiveChunk> FluidPrototype::merge_worker_activity(std::uint64_t &merge_ns) {
    const auto started = std::chrono::steady_clock::now();
    std::vector<ActiveChunk> merged(active_.size());
    for (const auto &worker : worker_activity_) merge_activity(merged, worker);
    merge_ns += static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - started).count());
    return merged;
}

bool FluidPrototype::row_range(const std::vector<ActiveChunk> &activity, std::int32_t y, std::int32_t chunk_x,
                               std::int32_t &min_x, std::int32_t &max_x) const {
    if (y < 0 || y >= height_) return false;
    const std::int32_t chunk_y = y / CHUNK_SIZE;
    const std::int32_t local_y = y % CHUNK_SIZE;
    const ActiveChunk &chunk = activity[static_cast<std::size_t>(chunk_y) * chunks_x_ + chunk_x];
    if ((chunk.rows & (std::uint64_t{1} << local_y)) == 0) return false;
    min_x = chunk_x * CHUNK_SIZE + chunk.min_x[local_y];
    max_x = std::min(width_ - 1, chunk_x * CHUNK_SIZE + chunk.max_x[local_y]);
    return true;
}

void FluidPrototype::transfer_mass(std::size_t source, std::size_t destination, std::uint8_t amount) {
    const std::uint16_t source_mass = read_mass(source);
    const std::uint16_t destination_mass = read_mass(destination);
    if (amount == 0 || amount > source_mass || destination_mass + amount > 255) return;
    const std::uint32_t mixed_heat = static_cast<std::uint32_t>(destination_mass) * temperature_[destination] +
                                     static_cast<std::uint32_t>(amount) * temperature_[source];
    write_mass(source, static_cast<std::uint8_t>(source_mass - amount));
    write_mass(destination, static_cast<std::uint8_t>(destination_mass + amount));
    if (destination_mass + amount > 0) temperature_[destination] = static_cast<std::uint16_t>(mixed_heat / (destination_mass + amount));
    if (source_mass == amount) temperature_[source] = AMBIENT_TEMPERATURE;
}

void FluidPrototype::exchange_vertical(std::int32_t worker, std::int32_t x, std::int32_t top_y) {
    auto &stats = worker_counters_[worker];
    stats.visited += 2;
    if (blocked(x, top_y)) return;
    const auto top = index(x, top_y);
    const std::uint8_t top_mass = read_mass(top);
    if (top_mass == 0) return;
    if (blocked(x, top_y + 1)) { ++stats.blocked; return; }
    const auto bottom = index(x, top_y + 1);
    const std::uint8_t bottom_mass = read_mass(bottom);
    const std::uint8_t transfer = static_cast<std::uint8_t>(std::min<int>(top_mass, 255 - bottom_mass));
    if (transfer == 0) { ++stats.blocked; return; }
    transfer_mass(top, bottom, candidate_ == FluidCandidate::DiscreteFullCell ? 255 : transfer);
    ++stats.transfers;
    ++stats.downward;
    if (top_y / CHUNK_SIZE != (top_y + 1) / CHUNK_SIZE) ++stats.border;
    include_worker(worker, x, top_y, 1);
    include_worker(worker, x, top_y + 1, 1);
}

void FluidPrototype::exchange_horizontal(std::int32_t worker, std::int32_t left_x, std::int32_t y) {
    auto &stats = worker_counters_[worker];
    stats.visited += 2;
    if (blocked(left_x, y) || blocked(left_x + 1, y)) return;
    const auto left = index(left_x, y);
    const auto right = index(left_x + 1, y);
    const std::uint8_t left_mass = read_mass(left);
    const std::uint8_t right_mass = read_mass(right);
    if (candidate_ == FluidCandidate::DiscreteFullCell) {
        const bool move_right = ((tick_ + static_cast<std::uint64_t>(y)) & 1u) == 0;
        if (move_right && left_mass == 255 && right_mass == 0) transfer_mass(left, right, 255);
        else if (!move_right && right_mass == 255 && left_mass == 0) transfer_mass(right, left, 255);
        else return;
    } else {
        const int difference = static_cast<int>(left_mass) - static_cast<int>(right_mass);
        if (std::abs(difference) < 2) return;
        const std::uint8_t amount = static_cast<std::uint8_t>(std::min(64, std::abs(difference) / 2));
        if (difference > 0) transfer_mass(left, right, amount); else transfer_mass(right, left, amount);
    }
    ++stats.transfers;
    ++stats.lateral;
    if (left_x / CHUNK_SIZE != (left_x + 1) / CHUNK_SIZE) ++stats.border;
    include_worker(worker, left_x, y, 1);
    include_worker(worker, left_x + 1, y, 1);
}

void FluidPrototype::run_vertical(const std::vector<ActiveChunk> &input) {
    const std::int32_t offset = static_cast<std::int32_t>(tick_ & 1u);
    const std::int32_t pairs = std::max(0, (height_ - 1 - offset + 1) / 2);
    workers_->run(pairs, [this, &input, offset](std::int32_t worker, std::int32_t job) {
        const std::int32_t y = offset + job * 2;
        if (y + 1 >= height_) return;
        for (std::int32_t cx = 0; cx < chunks_x_; ++cx) {
            std::int32_t min_a = 0, max_a = -1, min_b = 0, max_b = -1;
            const bool active_a = row_range(input, y, cx, min_a, max_a);
            const bool active_b = row_range(input, y + 1, cx, min_b, max_b);
            if (!active_a && !active_b) continue;
            const std::int32_t first = active_a && active_b ? std::min(min_a, min_b) : active_a ? min_a : min_b;
            const std::int32_t last = active_a && active_b ? std::max(max_a, max_b) : active_a ? max_a : max_b;
            for (std::int32_t x = first; x <= last; ++x) exchange_vertical(worker, x, y);
        }
    });
}

void FluidPrototype::run_horizontal(const std::vector<ActiveChunk> &input) {
    const std::int32_t offset = static_cast<std::int32_t>(tick_ & 1u);
    workers_->run(height_, [this, &input, offset](std::int32_t worker, std::int32_t y) {
        for (std::int32_t cx = 0; cx < chunks_x_; ++cx) {
            std::int32_t first = 0, last = -1;
            if (!row_range(input, y, cx, first, last)) continue;
            first = std::max(0, first - 1);
            last = std::min(width_ - 2, last + 1);
            if ((first & 1) != offset) ++first;
            for (std::int32_t x = first; x <= last; x += 2) exchange_horizontal(worker, x, y);
        }
    });
}

FluidTelemetry FluidPrototype::step() {
    FluidTelemetry result;
    result.allocated_cells = static_cast<std::uint64_t>(width_) * height_;
    result.active_cells = active_span_cells();
    result.frontier_cells = result.active_cells;
    result.active_rows = count_active_rows();
    result.active_spans = result.active_rows;
    result.workers_used = static_cast<std::uint32_t>(worker_count_);
    const bool had_activity = result.active_cells > 0;
    const std::vector<ActiveChunk> initial = active_;
    clear_worker_state();
    run_vertical(initial);
    std::uint64_t merge_ns = 0;
    std::vector<ActiveChunk> vertical = merge_worker_activity(merge_ns);
    for (const auto &counter : worker_counters_) {
        result.visited_cells += counter.visited;
        result.transfers += counter.transfers;
        result.downward_moves += counter.downward;
        result.blocked_liquid += counter.blocked;
        result.border_crossings += counter.border;
    }
    std::vector<ActiveChunk> horizontal_input = initial;
    merge_activity(horizontal_input, vertical);
    clear_worker_state();
    run_horizontal(horizontal_input);
    std::vector<ActiveChunk> horizontal = merge_worker_activity(merge_ns);
    merge_activity(vertical, horizontal);
    for (std::size_t chunk = 0; chunk < vertical.size(); ++chunk) {
        if (vertical[chunk].rows != 0) {
            quiet_passes_[chunk] = 0;
        } else if (initial[chunk].rows != 0 && quiet_passes_[chunk] == 0) {
            vertical[chunk] = initial[chunk];
            quiet_passes_[chunk] = 1;
        } else {
            quiet_passes_[chunk] = 0;
        }
    }
    active_.swap(vertical);
    result.barrier_merge_ns = merge_ns;
    for (const auto &counter : worker_counters_) {
        result.visited_cells += counter.visited;
        result.transfers += counter.transfers;
        result.lateral_moves += counter.lateral;
        result.blocked_liquid += counter.blocked;
        result.border_crossings += counter.border;
    }
    const bool has_activity = active_span_cells() > 0;
    result.sleep_transitions = had_activity && !has_activity ? 1 : 0;
    result.wake_transitions = !had_activity && has_activity ? 1 : 0;
    ++tick_;
    return result;
}

std::uint8_t FluidPrototype::mass_at(std::int32_t x, std::int32_t y) const {
    return inside(x, y) ? read_mass(index(x, y)) : 0;
}

std::uint16_t FluidPrototype::temperature_at(std::int32_t x, std::int32_t y) const {
    return inside(x, y) ? temperature_[index(x, y)] : AMBIENT_TEMPERATURE;
}

std::uint8_t FluidPrototype::material_at(std::int32_t x, std::int32_t y) const {
    return inside(x, y) ? material_[index(x, y)] : WALL;
}

std::uint64_t FluidPrototype::state_hash() const {
    std::uint64_t hash = 1469598103934665603ull;
    const auto mix = [&hash](std::uint64_t value) { hash ^= value; hash *= 1099511628211ull; };
    for (std::size_t i = 0; i < material_.size(); ++i) {
        mix(material_[i]);
        mix(read_mass(i));
        mix(temperature_[i]);
    }
    return hash;
}

std::uint64_t FluidPrototype::liquid_cells() const {
    std::uint64_t count = 0;
    for (std::size_t index = 0; index < material_.size(); ++index) count += read_mass(index) > 0 ? 1 : 0;
    return count;
}

std::uint64_t FluidPrototype::active_span_cells() const {
    std::uint64_t count = 0;
    for (const auto &chunk : active_) {
        std::uint64_t rows = chunk.rows;
        while (rows != 0) {
            const std::int32_t row = static_cast<std::int32_t>(std::countr_zero(rows));
            count += chunk.max_x[row] - chunk.min_x[row] + 1;
            rows &= rows - 1;
        }
    }
    return count;
}

std::uint64_t FluidPrototype::count_active_rows() const {
    std::uint64_t count = 0;
    for (const auto &chunk : active_) count += std::popcount(chunk.rows);
    return count;
}

std::uint64_t FluidPrototype::incremental_state_bytes() const {
    return candidate_ == FluidCandidate::DiscreteFullCell ? 0 : fluid_mass_.size();
}

std::uint64_t FluidPrototype::activity_metadata_bytes() const { return active_.size() * sizeof(ActiveChunk); }

const char *fluid_candidate_name(FluidCandidate candidate) {
    return candidate == FluidCandidate::DiscreteFullCell ? "discrete_full_cell" : "fixed_mass_u8";
}

} // namespace koalasand_core
