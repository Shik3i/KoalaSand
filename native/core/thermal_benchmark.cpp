#include "thermal_prototype.hpp"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <memory>
#include <numeric>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

using koalasand_core::HeatSource;
using koalasand_core::ThermalMaterial;
using koalasand_core::ThermalPrototype;
using koalasand_core::ThermalStats;

namespace {
void configure(ThermalPrototype &grid) {
    grid.set_material(1, ThermalMaterial{64, 48, 0, 65535, false});   // Stone
    grid.set_material(2, ThermalMaterial{32, 32, 0, 65535, false});   // Raw Sand
    grid.set_material(3, ThermalMaterial{48, 128, 1092, 1492, true}); // Water candidate thresholds only
    grid.set_material(10, ThermalMaterial{24, 40, 0, 5873, false});   // Glass
    grid.set_material(11, ThermalMaterial{192, 56, 0, 7245, false});  // Iron
}

std::string hex_hash(std::uint64_t value) {
    std::ostringstream stream;
    stream << std::hex << std::setw(16) << std::setfill('0') << value;
    return stream.str();
}

struct Aggregate {
    double average_ms = 0.0;
    double worst_ms = 0.0;
    std::int64_t active = 0;
    std::int64_t visited = 0;
    std::int64_t exchanges = 0;
    std::int64_t barrier_usec = 0;
    std::int32_t workers_used = 0;
};

Aggregate run_ticks(ThermalPrototype &grid, int ticks, int cadence_scale = 1) {
    Aggregate aggregate;
    for (int tick = 0; tick < ticks; ++tick) {
        const ThermalStats stats = grid.tick(cadence_scale);
        aggregate.average_ms += static_cast<double>(stats.thermal_usec) / 1000.0;
        aggregate.worst_ms = std::max(aggregate.worst_ms, static_cast<double>(stats.thermal_usec) / 1000.0);
        aggregate.active = stats.active_cells;
        aggregate.visited = stats.visited_cells;
        aggregate.exchanges = stats.exchanges;
        aggregate.barrier_usec = stats.barrier_usec;
        aggregate.workers_used = stats.workers_used;
    }
    aggregate.average_ms /= std::max(1, ticks);
    return aggregate;
}

std::unique_ptr<ThermalPrototype> checker(int side, int workers) {
    auto grid = std::make_unique<ThermalPrototype>(side, side, workers);
    configure(*grid);
    grid->fill(1, ThermalPrototype::Ambient);
    for (int y = 0; y < side; ++y) for (int x = 0; x < side; ++x)
        grid->set_cell(x, y, 1, static_cast<std::uint16_t>(((x + y) & 1) ? 5173 : 1173));
    grid->rebuild_activity();
    return grid;
}
} // namespace

int main() {
    int checks = 0;
    auto require = [&](bool condition, const char *label) {
        ++checks;
        if (!condition) { std::cerr << "FAIL: " << label << '\n'; std::exit(1); }
    };

    ThermalPrototype uniform(1024, 1024, 8);
    configure(uniform);
    uniform.fill(1, 4800);
    uniform.rebuild_activity();
    const auto uniform_energy = uniform.total_energy();
    const auto uniform_hash = uniform.hash();
    const Aggregate uniform_stats = run_ticks(uniform, 8);
    require(uniform_stats.active == 0 && uniform_stats.visited == 0, "uniform hot region sleeps");
    require(uniform.hash() == uniform_hash && uniform.total_energy() == uniform_energy, "uniform hot region bit stable");
    std::cout << "thermal_uniform cells=1048576 active=" << uniform_stats.active << " visited=" << uniform_stats.visited
              << " exchanges=" << uniform_stats.exchanges << " avg_ms=" << uniform_stats.average_ms << " hash=" << hex_hash(uniform.hash()) << '\n';

    ThermalPrototype cross(130, 130, 4);
    configure(cross);
    cross.fill(1, 1173);
    cross.set_cell(63, 63, 1, 12000);
    cross.rebuild_activity();
    const auto cross_energy = cross.total_energy();
    run_ticks(cross, 40);
    require(cross.temperature(64, 63) > 1173, "horizontal chunk boundary conduction");
    require(cross.temperature(63, 64) > 1173, "vertical chunk boundary conduction");
    require(cross.total_energy() == cross_energy, "cross chunk energy conservation");

    ThermalPrototype capacity_test(9, 5, 1);
    configure(capacity_test);
    capacity_test.fill(0, 1173);
    capacity_test.set_cell(2, 2, 3, 1173, 64);
    capacity_test.set_cell(6, 2, 3, 1173, 255);
    capacity_test.set_heat_sources({HeatSource{2,2,0,4096,3,true}, HeatSource{6,2,0,4096,3,true}});
    capacity_test.rebuild_activity();
    run_ticks(capacity_test, 1);
    require(capacity_test.temperature(2,2) > capacity_test.temperature(6,2), "partial Water has lower thermal mass");

    std::vector<std::uint64_t> parity_hashes;
    for (int workers : {1,2,4,8}) {
        auto grid = checker(256, workers);
        const auto before = grid->total_energy();
        const Aggregate stats = run_ticks(*grid, 24);
        require(grid->total_energy() == before, "checker conduction conserves energy");
        parity_hashes.push_back(grid->hash());
        std::cout << "thermal_worker workers=" << workers << " cells=65536 active=" << stats.active << " visited=" << stats.visited
                  << " exchanges=" << stats.exchanges << " avg_ms=" << stats.average_ms << " worst_ms=" << stats.worst_ms
                  << " barrier_us=" << stats.barrier_usec << " hash=" << hex_hash(grid->hash()) << '\n';
    }
    require(std::all_of(parity_hashes.begin(), parity_hashes.end(), [&](auto hash){ return hash == parity_hashes.front(); }), "worker parity");

    ThermalPrototype hotspot(1024, 1024, 8);
    configure(hotspot);
    hotspot.fill(1, 1173);
    for (int y = 496; y < 528; ++y) for (int x = 496; x < 528; ++x) hotspot.set_cell(x, y, 1, 12000);
    hotspot.rebuild_activity();
    const auto hotspot_energy = hotspot.total_energy();
    const Aggregate hotspot_stats = run_ticks(hotspot, 120);
    require(hotspot.total_energy() == hotspot_energy, "hotspot energy conservation");
    std::cout << "thermal_hotspot cells=1048576 active=" << hotspot_stats.active << " visited=" << hotspot_stats.visited
              << " exchanges=" << hotspot_stats.exchanges << " avg_ms=" << hotspot_stats.average_ms << " worst_ms=" << hotspot_stats.worst_ms
              << " barrier_us=" << hotspot_stats.barrier_usec << " hash=" << hex_hash(hotspot.hash()) << '\n';

    ThermalPrototype boundary(1024, 1024, 8);
    configure(boundary);
    boundary.fill(1, 1173);
    for (int y = 0; y < 1024; ++y) for (int x = 0; x < 512; ++x) boundary.set_cell(x, y, 1, 9173);
    boundary.rebuild_activity();
    const auto boundary_energy = boundary.total_energy();
    const Aggregate boundary_stats = run_ticks(boundary, 60);
    require(boundary.total_energy() == boundary_energy, "planar boundary energy conservation");
    std::cout << "thermal_boundary cells=1048576 active=" << boundary_stats.active << " visited=" << boundary_stats.visited
              << " exchanges=" << boundary_stats.exchanges << " avg_ms=" << boundary_stats.average_ms << " worst_ms=" << boundary_stats.worst_ms
              << " barrier_us=" << boundary_stats.barrier_usec << " hash=" << hex_hash(boundary.hash()) << '\n';

    for (const auto &[side, label] : std::vector<std::pair<int,std::string>>{{512,"256k"},{1024,"1m"}}) {
        for (int workers : {1,2,4,8}) {
            auto grid = checker(side, workers);
            const auto before = grid->total_energy();
            const Aggregate stats = run_ticks(*grid, side == 512 ? 20 : 10);
            require(grid->total_energy() == before, "active stress energy conservation");
            std::cout << "thermal_active label=" << label << " workers=" << workers << " cells=" << side * side
                      << " active=" << stats.active << " visited=" << stats.visited << " exchanges=" << stats.exchanges
                      << " avg_ms=" << stats.average_ms << " worst_ms=" << stats.worst_ms << " barrier_us=" << stats.barrier_usec
                      << " activity_bytes=" << grid->activity_bytes() << " scratch_bytes=" << grid->scratch_bytes()
                      << " hash=" << hex_hash(grid->hash()) << '\n';
        }
    }

    ThermalPrototype factory(1024, 512, 8);
    configure(factory);
    factory.fill(1, 1173);
    std::vector<HeatSource> sources;
    for (int index = 0; index < 16; ++index) sources.push_back(HeatSource{96 + (index % 8) * 112, 128 + (index / 8) * 220, 4, 384, 1, true});
    factory.set_heat_sources(sources);
    factory.rebuild_activity();
    const Aggregate factory_stats = run_ticks(factory, 180, 2);
    std::cout << "thermal_factory cells=524288 sources=16 active=" << factory_stats.active << " visited=" << factory_stats.visited
              << " exchanges=" << factory_stats.exchanges << " avg_ms=" << factory_stats.average_ms << " worst_ms=" << factory_stats.worst_ms
              << " barrier_us=" << factory_stats.barrier_usec << " hash=" << hex_hash(factory.hash()) << '\n';

    for (const auto &[hz, ticks, scale] : std::vector<std::tuple<int,int,int>>{{60,60,1},{30,30,2},{15,15,4}}) {
        ThermalPrototype cadence(256, 256, 4);
        configure(cadence);
        cadence.fill(1, 1173);
        for (int y = 120; y < 136; ++y) for (int x = 120; x < 136; ++x) cadence.set_cell(x, y, 1, 9173);
        cadence.rebuild_activity();
        const Aggregate stats = run_ticks(cadence, ticks, scale);
        std::cout << "thermal_cadence hz=" << hz << " ticks=" << ticks << " scale=" << scale << " avg_ms=" << stats.average_ms
                  << " active=" << stats.active << " visited=" << stats.visited << " exchanges=" << stats.exchanges
                  << " center_temperature=" << cadence.temperature(128,128) << " hash=" << hex_hash(cadence.hash()) << '\n';
    }

    ThermalPrototype disabled(128, 128, 8);
    configure(disabled);
    disabled.fill(1, 1173);
    std::vector<HeatSource> disabled_sources(10000);
    disabled.set_heat_sources(disabled_sources);
    disabled.rebuild_activity();
    const Aggregate disabled_stats = run_ticks(disabled, 100);
    require(disabled_stats.active == 0 && disabled_stats.visited == 0, "disabled heat sources are scheduler free");

    std::cout << "thermal_activity_candidates selected=row_spans_frontier bounding_rectangle=reject_overvisits_sparse_fronts frontier_queue=reject_sort_merge_cost row_spans=selected" << '\n';
    std::cout << "PASS: " << checks << " Phase 8.5 thermal checks worker_parity_hash=" << hex_hash(parity_hashes.front()) << '\n';
    return 0;
}
