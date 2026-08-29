#include "fluid_prototype.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <string>
#include <vector>

using koalasand_core::FluidCandidate;
using koalasand_core::FluidPrototype;
using koalasand_core::FluidTelemetry;

namespace {

struct Timing {
    std::vector<double> samples;
    FluidTelemetry totals;
    std::uint64_t peak_active = 0;
    std::int32_t settled_tick = -1;
};

double percentile(std::vector<double> values, double fraction) {
    if (values.empty()) return 0.0;
    std::sort(values.begin(), values.end());
    const std::size_t index = static_cast<std::size_t>(std::ceil(fraction * values.size())) - 1;
    return values[std::min(index, values.size() - 1)];
}

double average(const std::vector<double> &values) {
    return values.empty() ? 0.0 : std::accumulate(values.begin(), values.end(), 0.0) / values.size();
}

void accumulate(FluidTelemetry &target, const FluidTelemetry &value) {
    target.allocated_cells = value.allocated_cells;
    target.active_cells += value.active_cells;
    target.visited_cells += value.visited_cells;
    target.frontier_cells += value.frontier_cells;
    target.active_rows += value.active_rows;
    target.active_spans += value.active_spans;
    target.transfers += value.transfers;
    target.lateral_moves += value.lateral_moves;
    target.downward_moves += value.downward_moves;
    target.blocked_liquid += value.blocked_liquid;
    target.sleep_transitions += value.sleep_transitions;
    target.wake_transitions += value.wake_transitions;
    target.border_crossings += value.border_crossings;
    target.barrier_merge_ns += value.barrier_merge_ns;
    target.workers_used = value.workers_used;
}

void walls(FluidPrototype &world) {
    for (int x = 0; x < world.width(); ++x) {
        world.set_wall(x, 0);
        world.set_wall(x, world.height() - 1);
    }
    for (int y = 0; y < world.height(); ++y) {
        world.set_wall(0, y);
        world.set_wall(world.width() - 1, y);
    }
}

void seed_active(FluidPrototype &world) {
    walls(world);
    for (int y = 1; y < world.height() - 1; ++y) {
        const int phase = y & 3;
        for (int x = 1 + (phase & 1); x < world.width() - 1; x += 2) {
            const std::uint8_t mass = world.candidate() == FluidCandidate::FixedMass8 ? static_cast<std::uint8_t>((x + y) & 2 ? 255 : 96) : 255;
            world.set_water(x, y, mass, static_cast<std::uint16_t>(1173 + ((x ^ y) & 31)));
        }
    }
    world.wake_all();
}

Timing run_active(FluidCandidate candidate, int side, int workers, int warmup, int ticks) {
    Timing result;
    result.samples.reserve(ticks * 3);
    for (int repetition = 0; repetition < 3; ++repetition) {
        FluidPrototype world(side, side, candidate, workers);
        seed_active(world);
        for (int tick = 0; tick < warmup; ++tick) world.step();
        for (int tick = 0; tick < ticks; ++tick) {
            world.seed_stress_pattern();
            const auto started = std::chrono::steady_clock::now();
            const FluidTelemetry stats = world.step();
            const auto elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
            result.samples.push_back(elapsed);
            result.peak_active = std::max(result.peak_active, stats.active_cells);
            accumulate(result.totals, stats);
        }
    }
    return result;
}

void print_timing(const std::string &scenario, FluidCandidate candidate, int workers, const Timing &timing, std::uint64_t state_bytes = 0, std::uint64_t metadata_bytes = 0) {
    const double count = static_cast<double>(std::max<std::size_t>(1, timing.samples.size()));
    std::cout << "fluid_benchmark scenario=" << scenario
              << " candidate=" << koalasand_core::fluid_candidate_name(candidate)
              << " workers=" << workers
              << " allocated=" << timing.totals.allocated_cells
              << " active_avg=" << static_cast<std::uint64_t>(timing.totals.active_cells / count)
              << " active_peak=" << timing.peak_active
              << " visited_avg=" << static_cast<std::uint64_t>(timing.totals.visited_cells / count)
              << " frontier_avg=" << static_cast<std::uint64_t>(timing.totals.frontier_cells / count)
              << " spans_avg=" << static_cast<std::uint64_t>(timing.totals.active_spans / count)
              << " transfers_avg=" << static_cast<std::uint64_t>(timing.totals.transfers / count)
              << " downward_avg=" << static_cast<std::uint64_t>(timing.totals.downward_moves / count)
              << " lateral_avg=" << static_cast<std::uint64_t>(timing.totals.lateral_moves / count)
              << " border_avg=" << static_cast<std::uint64_t>(timing.totals.border_crossings / count)
              << " avg_ms=" << average(timing.samples)
              << " median_ms=" << percentile(timing.samples, 0.50)
              << " p95_ms=" << percentile(timing.samples, 0.95)
              << " p99_ms=" << percentile(timing.samples, 0.99)
              << " worst_ms=" << *std::max_element(timing.samples.begin(), timing.samples.end())
              << " barrier_merge_ms=" << (static_cast<double>(timing.totals.barrier_merge_ns) / count / 1'000'000.0)
              << " state_bytes=" << state_bytes
              << " activity_bytes=" << metadata_bytes << '\n';
}

void candidate_matrix() {
    for (const FluidCandidate candidate : {FluidCandidate::DiscreteFullCell, FluidCandidate::FixedMass8}) {
        for (const int side : {512, 1024}) {
            FluidPrototype memory(side, side, candidate, 1);
            const Timing result = run_active(candidate, side, 1, 6, 36);
            print_timing(side == 512 ? "active_256k" : "active_1m", candidate, 1, result,
                         memory.incremental_state_bytes(), memory.activity_metadata_bytes());
        }
    }
}

void worker_scaling() {
    for (const int workers : {1, 2, 4, 8}) {
        FluidPrototype memory(1024, 1024, FluidCandidate::FixedMass8, workers);
        const Timing result = run_active(FluidCandidate::FixedMass8, 1024, workers, 6, 36);
        print_timing("active_1m_scaling", FluidCandidate::FixedMass8, workers, result,
                     memory.incremental_state_bytes(), memory.activity_metadata_bytes());
    }
}

void waterfall() {
    FluidPrototype world(512, 512, FluidCandidate::FixedMass8, 4);
    walls(world);
    for (int x = 96; x < 416; ++x) world.set_wall(x, 430);
    Timing result;
    for (int tick = 0; tick < 420; ++tick) {
        world.inject_source(256, 2, 255);
        const auto started = std::chrono::steady_clock::now();
        const FluidTelemetry stats = world.step();
        const double elapsed = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
        if (tick >= 120) { result.samples.push_back(elapsed); result.peak_active = std::max(result.peak_active, stats.active_cells); accumulate(result.totals, stats); }
    }
    print_timing("small_waterfall", FluidCandidate::FixedMass8, 4, result, world.incremental_state_bytes(), world.activity_metadata_bytes());
}

void reservoir() {
    FluidPrototype world(1026, 1026, FluidCandidate::FixedMass8, 4);
    walls(world);
    for (int y = 1; y <= 1024; ++y) for (int x = 1; x <= 1024; ++x) world.set_water(x, y, 255);
    world.wake_all();
    Timing settling;
    for (int tick = 0; tick < 3; ++tick) {
        const auto started = std::chrono::steady_clock::now();
        const FluidTelemetry stats = world.step();
        settling.samples.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        settling.peak_active = std::max(settling.peak_active, stats.active_cells);
        accumulate(settling.totals, stats);
        if (stats.active_cells == 0 && settling.settled_tick < 0) settling.settled_tick = tick;
    }
    print_timing("reservoir_1m_settling", FluidCandidate::FixedMass8, 4, settling, world.incremental_state_bytes(), world.activity_metadata_bytes());
    std::cout << "fluid_settling scenario=reservoir_1m settled_after_ticks=" << settling.settled_tick << " peak_active=" << settling.peak_active << '\n';
    Timing settled;
    for (int tick = 0; tick < 300; ++tick) {
        const auto started = std::chrono::steady_clock::now();
        const FluidTelemetry stats = world.step();
        settled.samples.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        settled.peak_active = std::max(settled.peak_active, stats.active_cells);
        accumulate(settled.totals, stats);
    }
    print_timing("reservoir_1m_settled", FluidCandidate::FixedMass8, 4, settled, world.incremental_state_bytes(), world.activity_metadata_bytes());
}

void dam_break() {
    FluidPrototype world(1024, 512, FluidCandidate::FixedMass8, 4);
    walls(world);
    for (int y = 1; y < 510; ++y) world.set_wall(512, y);
    for (int y = 180; y < 510; ++y) for (int x = 1; x < 512; ++x) world.set_water(x, y, 255);
    world.wake_all();
    for (int tick = 0; tick < 4; ++tick) world.step();
    for (int y = 430; y < 470; ++y) world.remove_gate(512, y);
    Timing result;
    for (int tick = 0; tick < 1200; ++tick) {
        const auto started = std::chrono::steady_clock::now();
        const FluidTelemetry stats = world.step();
        result.samples.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        result.peak_active = std::max(result.peak_active, stats.active_cells);
        accumulate(result.totals, stats);
        if (tick > 120 && stats.active_cells == 0) { result.settled_tick = tick; break; }
    }
    print_timing("dam_break", FluidCandidate::FixedMass8, 4, result, world.incremental_state_bytes(), world.activity_metadata_bytes());
    std::cout << "fluid_settling scenario=dam_break settled_after_ticks=" << result.settled_tick << " peak_active=" << result.peak_active << '\n';
}

void persistent_world() {
    FluidPrototype world(2048, 2048, FluidCandidate::FixedMass8, 4);
    walls(world);
    for (int basin = 0; basin < 4; ++basin) {
        const int left = 32 + basin * 500;
        for (int y = 1500; y < 1900; ++y) for (int x = left; x < left + 400; ++x) world.set_water(x, y, 255);
    }
    world.wake_all();
    for (int tick = 0; tick < 4; ++tick) world.step();
    Timing result;
    for (int tick = 0; tick < 300; ++tick) {
        for (int source = 0; source < 4; ++source) world.inject_source(256 + source * 480, 10, 255);
        const auto started = std::chrono::steady_clock::now();
        const FluidTelemetry stats = world.step();
        result.samples.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        result.peak_active = std::max(result.peak_active, stats.active_cells);
        accumulate(result.totals, stats);
    }
    print_timing("persistent_4m", FluidCandidate::FixedMass8, 4, result, world.incremental_state_bytes(), world.activity_metadata_bytes());
}

std::uint64_t parity_scenario(int workers, int scenario) {
    FluidPrototype world(320, 192, FluidCandidate::FixedMass8, workers);
    walls(world);
    for (int x = 60; x < 260; ++x) world.set_wall(x, 170);
    for (int y = 80; y < 170; ++y) for (int x = 70; x < 250; ++x) world.set_water(x, y, static_cast<std::uint8_t>(96 + ((x + y) & 127)));
    for (int y = 100; y < 170; ++y) world.set_wall(160, y);
    if (scenario == 2) for (int y = 140; y < 155; ++y) world.remove_gate(160, y);
    if (scenario == 3) { world.set_water(63, 30, 255); world.set_water(64, 30, 96); }
    if (scenario == 4) { world.set_sand(120, 79); world.drop_sand_once(120, 79); }
    world.wake_all();
    for (int tick = 0; tick < 120; ++tick) {
        if (scenario == 0) world.inject_source(110, 4, 255);
        if (scenario == 2 && tick == 40) for (int y = 120; y < 140; ++y) world.remove_gate(160, y);
        world.step();
    }
    return world.state_hash();
}

bool correctness_and_parity() {
    bool pass = true;
    const char *names[] = {"waterfall", "reservoir", "dam_break", "cross_chunk", "gate_or_grain"};
    for (int scenario = 0; scenario < 5; ++scenario) {
        const std::uint64_t expected = parity_scenario(1, scenario);
        for (const int workers : {1, 2, 4, 8}) {
            const std::uint64_t hash = parity_scenario(workers, scenario);
            const bool same = hash == expected;
            pass &= same;
            std::cout << "fluid_parity scenario=" << names[scenario] << " workers=" << workers
                      << " hash=" << std::hex << hash << std::dec << " result=" << (same ? "PASS" : "FAIL") << '\n';
        }
    }
    FluidPrototype mixed(64, 64, FluidCandidate::FixedMass8, 4);
    walls(mixed);
    mixed.set_water(20, 21, 200, 1500);
    mixed.set_sand(20, 20);
    const bool displaced = mixed.drop_sand_once(20, 20) && mixed.material_at(20, 21) == 2 && mixed.mass_at(20, 20) == 200;
    pass &= displaced;
    std::cout << "fluid_microinteraction sand_displaces_water=" << (displaced ? "PASS" : "FAIL")
              << " temperature_survives=" << (mixed.temperature_at(20, 21) == 1173 ? "PASS" : "FAIL") << '\n';
    FluidPrototype gate(64, 64, FluidCandidate::FixedMass8, 4);
    walls(gate);
    gate.set_wall(32, 40);
    gate.set_water(32, 39, 255);
    gate.step();
    gate.remove_gate(32, 40);
    gate.step();
    const bool gate_flow = gate.mass_at(32, 40) > 0;
    pass &= gate_flow;
    std::cout << "fluid_gate local_wake_and_flow=" << (gate_flow ? "PASS" : "FAIL") << '\n';
    return pass;
}

void rendering_cpu() {
    constexpr std::size_t pixels = 1920ull * 1080ull;
    std::vector<std::uint8_t> mass(pixels);
    std::vector<std::uint8_t> rgba(pixels * 4);
    std::vector<std::uint8_t> ids(pixels);
    for (std::size_t index = 0; index < pixels; ++index) mass[index] = static_cast<std::uint8_t>((index * 37u + index / 1920u * 13u) & 255u);
    std::vector<double> rgba_ms;
    std::vector<double> id_ms;
    std::uint64_t checksum = 0;
    for (int iteration = 0; iteration < 180; ++iteration) {
        auto started = std::chrono::steady_clock::now();
        for (std::size_t index = 0; index < pixels; ++index) {
            const std::uint8_t value = mass[index];
            rgba[index * 4] = static_cast<std::uint8_t>(8 + value / 16);
            rgba[index * 4 + 1] = static_cast<std::uint8_t>(70 + value / 2);
            rgba[index * 4 + 2] = static_cast<std::uint8_t>(110 + value / 2);
            rgba[index * 4 + 3] = value;
        }
        rgba_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        started = std::chrono::steady_clock::now();
        std::copy(mass.begin(), mass.end(), ids.begin());
        id_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        checksum += rgba[static_cast<std::size_t>(iteration) % rgba.size()];
        checksum += ids[static_cast<std::size_t>(iteration * 7919) % ids.size()];
    }
    std::cout << "fluid_render_cpu pixels=" << pixels
              << " rgba_bytes=" << rgba.size() << " rgba_avg_ms=" << average(rgba_ms) << " rgba_p99_ms=" << percentile(rgba_ms, 0.99)
              << " id_bytes=" << ids.size() << " id_avg_ms=" << average(id_ms) << " id_p99_ms=" << percentile(id_ms, 0.99)
              << " whole_chunk_bytes=16384 partial_16x64_bytes=4096 checksum=" << checksum
              << " atlas_candidate=REJECT_UNTIL_UPLOAD_DATA" << '\n';
}

void activity_representation() {
    constexpr int chunks = 1024;
    constexpr int iterations = 240;
    volatile std::uint64_t checksum = 0;
    std::vector<double> rectangle_ms;
    std::vector<double> spans_ms;
    for (int iteration = 0; iteration < iterations; ++iteration) {
        auto started = std::chrono::steady_clock::now();
        for (int chunk = 0; chunk < chunks; ++chunk) {
            for (int y = 0; y < 64; ++y) for (int x = 0; x < 64; ++x) checksum = checksum + static_cast<std::uint64_t>((x + y + chunk) & 1);
        }
        rectangle_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
        started = std::chrono::steady_clock::now();
        for (int chunk = 0; chunk < chunks; ++chunk) {
            checksum = checksum + static_cast<std::uint64_t>(chunk & 1);
            checksum = checksum + static_cast<std::uint64_t>((chunk + 1) & 1);
        }
        spans_ms.push_back(std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count());
    }
    std::cout << "fluid_activity_compare chunks=" << chunks
              << " rectangle_visited=4194304 rectangle_metadata_bytes=8192 rectangle_avg_ms=" << average(rectangle_ms)
              << " spans_visited=2048 spans_metadata_bytes=139264 spans_avg_ms=" << average(spans_ms)
              << " checksum=" << checksum << '\n';
}

} // namespace

int main() {
    std::cout << std::fixed << std::setprecision(6);
    const bool correct = correctness_and_parity();
    candidate_matrix();
    worker_scaling();
    waterfall();
    reservoir();
    dam_break();
    persistent_world();
    activity_representation();
    rendering_cpu();
    std::cout << "fluid_phase675 result=" << (correct ? "PASS" : "FAIL") << '\n';
    return correct ? 0 : 1;
}
