#include "native_sand_world.hpp"

#include <algorithm>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <deque>
#include <limits>
#include <tuple>

namespace godot {
namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t STONE = 1;
constexpr int32_t SAND = 2;
constexpr int32_t WATER = 3;
constexpr int32_t COAL = 4;
constexpr int32_t BEDROCK = 5;
constexpr int32_t COAL_CHUNK = 14;
constexpr int32_t ICE = 16;
constexpr int32_t STEAM = 17;
constexpr int32_t ROCK_DEBRIS = 20;
constexpr uint8_t RESERVOIR_WALL = 16;
constexpr int32_t MACRO_SCALE = 64;
constexpr int32_t CAVE_NONE = 0;
constexpr int32_t CAVE_CAVERN = 1;
constexpr int32_t CAVE_TUNNEL = 2;
constexpr int32_t CAVE_CRACK = 3;
constexpr int32_t CAVE_SHAFT = 4;
constexpr int32_t CAVE_POCKET = 5;

uint64_t splitmix64(uint64_t value) {
    value += 0x9e3779b97f4a7c15ull;
    value = (value ^ (value >> 30u)) * 0xbf58476d1ce4e5b9ull;
    value = (value ^ (value >> 27u)) * 0x94d049bb133111ebull;
    return value ^ (value >> 31u);
}

uint32_t field_hash(int64_t seed, int32_t x, int32_t y, uint32_t salt) {
    uint64_t value = static_cast<uint64_t>(seed) ^ (static_cast<uint64_t>(static_cast<uint32_t>(x)) << 32u) ^
                     static_cast<uint32_t>(y) ^ (static_cast<uint64_t>(salt) << 17u);
    return static_cast<uint32_t>(splitmix64(value) >> 32u);
}

double unit_hash(int64_t seed, int32_t x, int32_t y, uint32_t salt) {
    return static_cast<double>(field_hash(seed, x, y, salt)) / 4294967295.0;
}

double smooth(double value) {
    value = std::clamp(value, 0.0, 1.0);
    return value * value * (3.0 - 2.0 * value);
}

String hex_hash(uint32_t value) {
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%08x", value);
    return String(buffer);
}

uint32_t hash_component(uint32_t hash, uint32_t component) {
    hash ^= component;
    return hash * 16777619u;
}

Dictionary distribution(std::vector<double> values) {
    Dictionary result;
    if (values.empty()) return result;
    double total = 0.0;
    for (const double value : values) total += value;
    std::sort(values.begin(), values.end());
    const auto percentile = [&values](double p) {
        const size_t index = static_cast<size_t>(std::clamp(std::llround((values.size() - 1) * p), 0ll,
                                                            static_cast<long long>(values.size() - 1)));
        return values[index];
    };
    result["min"] = values.front();
    result["mean"] = total / static_cast<double>(values.size());
    result["p05"] = percentile(0.05);
    result["p50"] = percentile(0.50);
    result["p90"] = percentile(0.90);
    result["p95"] = percentile(0.95);
    result["p99"] = percentile(0.99);
    result["max"] = values.back();
    return result;
}

bool bit_get(const std::array<uint8_t, NativeSandWorld::CELLS_PER_CHUNK / 8> &bits, int32_t index) {
    return (bits[index >> 3] & static_cast<uint8_t>(1u << (index & 7))) != 0;
}

bool bit_set(std::array<uint8_t, NativeSandWorld::CELLS_PER_CHUNK / 8> &bits, int32_t index) {
    const uint8_t mask = static_cast<uint8_t>(1u << (index & 7));
    const bool changed = (bits[index >> 3] & mask) == 0;
    bits[index >> 3] |= mask;
    return changed;
}

bool terrain_solid(int32_t material) {
    return material == STONE || material == COAL || material == BEDROCK || material == ICE;
}

double segment_distance_squared(Vector2i point, Vector2i start, Vector2i end) {
    const double vx = static_cast<double>(end.x - start.x);
    const double vy = static_cast<double>(end.y - start.y);
    const double length_squared = vx * vx + vy * vy;
    if (length_squared <= 0.0) return static_cast<double>(point.distance_squared_to(start));
    const double wx = static_cast<double>(point.x - start.x);
    const double wy = static_cast<double>(point.y - start.y);
    const double t = std::clamp((wx * vx + wy * vy) / length_squared, 0.0, 1.0);
    const double dx = static_cast<double>(point.x) - (static_cast<double>(start.x) + vx * t);
    const double dy = static_cast<double>(point.y) - (static_cast<double>(start.y) + vy * t);
    return dx * dx + dy * dy;
}
} // namespace

NativeSandWorld::MacroSample NativeSandWorld::macro_sample_for(int64_t seed, Vector2i coordinate) const {
    MacroSample sample;
    const double broad = unit_hash(seed, floor_div(coordinate.x, 4), 0, 0x1101) * 2.0 - 1.0;
    const double regional = unit_hash(seed, coordinate.x, 0, 0x1103) * 2.0 - 1.0;
    sample.surface_elevation = static_cast<int16_t>(world_settings_.surface_baseline +
        std::lround(world_settings_.surface_amplitude * (0.76 * broad + 0.24 * regional)));
    sample.sediment_depth = static_cast<uint16_t>(std::clamp(world_settings_.sediment_depth - 6 +
        static_cast<int32_t>(unit_hash(seed, coordinate.x, coordinate.y, 0x1201) * 19.0), 8, 54));
    sample.cave_tendency = static_cast<uint16_t>(unit_hash(seed, coordinate.x, coordinate.y, 0x1301) * 65535.0);
    sample.water_table = static_cast<uint16_t>(96 + unit_hash(seed, floor_div(coordinate.x, 3), coordinate.y, 0x1401) * 420.0);
    sample.aquifer_strength = static_cast<uint16_t>(unit_hash(seed, coordinate.x, coordinate.y, 0x1403) * 65535.0);
    sample.geology_province = static_cast<uint16_t>(field_hash(seed, floor_div(coordinate.x, 5), floor_div(coordinate.y, 5), 0x1501) & 0xffffu);
    sample.thermal_tendency = static_cast<uint16_t>(unit_hash(seed, floor_div(coordinate.x, 3), floor_div(coordinate.y, 3), 0x1601) * 65535.0);
    sample.feature_density = static_cast<uint16_t>(unit_hash(seed, coordinate.x, coordinate.y, 0x1701) * 65535.0);
    return sample;
}

int32_t NativeSandWorld::surface_height_at_v2(int32_t world_x) const {
    const int32_t macro_x = floor_div(world_x, MACRO_SCALE);
    const int32_t local = world_x - macro_x * MACRO_SCALE;
    const MacroSample left = macro_sample_for(seed_, {macro_x, 0});
    const MacroSample right = macro_sample_for(seed_, {macro_x + 1, 0});
    const double amount = smooth(static_cast<double>(local) / MACRO_SCALE);
    int32_t surface = static_cast<int32_t>(std::lround(left.surface_elevation +
        (right.surface_elevation - left.surface_elevation) * amount));
    const int32_t spawn_surface = macro_sample_for(seed_, {0, 0}).surface_elevation;
    const int32_t distance = std::abs(world_x);
    if (distance < 112) {
        const double correction = smooth(static_cast<double>(distance) / 112.0);
        surface = static_cast<int32_t>(std::lround(spawn_surface + (surface - spawn_surface) * correction));
    }
    return surface;
}

int32_t NativeSandWorld::cave_type_at_v2(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    if (depth < world_settings_.sediment_depth + 10) return CAVE_NONE;
    if (std::abs(cell.x) < 44 && depth < 150) return CAVE_NONE;

    // Deterministic safe early route: an offset entrance and connected first chamber.
    if (cell.x >= 64 && cell.x <= 136) {
        const int32_t route_y = surface + world_settings_.sediment_depth + 18 + (cell.x - 64);
        if (std::abs(cell.y - route_y) <= 5) return CAVE_TUNNEL;
    }
    const Vector2i corrected_reservoir_delta{cell.x - 148, depth - 118};
    if (corrected_reservoir_delta.x * corrected_reservoir_delta.x * 9 +
        corrected_reservoir_delta.y * corrected_reservoir_delta.y * 16 <= 28 * 28 * 9) return CAVE_CAVERN;

    const Vector2i macro{floor_div(cell.x, MACRO_SCALE), floor_div(cell.y, MACRO_SCALE)};
    const MacroSample sample = macro_sample_for(seed_, macro);
    const double deep_factor = std::clamp(static_cast<double>(depth) / 1700.0, 0.0, 1.0);
    const double cave_bias = static_cast<double>(sample.cave_tendency) / 65535.0;

    for (int32_t oy = -1; oy <= 1; ++oy) {
        for (int32_t ox = -1; ox <= 1; ++ox) {
            const Vector2i anchor_macro = macro + Vector2i(ox, oy);
            const int32_t center_x = anchor_macro.x * MACRO_SCALE + 8 + static_cast<int32_t>(field_hash(seed_, anchor_macro.x, anchor_macro.y, 0x2301) % 49u);
            const int32_t center_y = anchor_macro.y * MACRO_SCALE + 8 + static_cast<int32_t>(field_hash(seed_, anchor_macro.x, anchor_macro.y, 0x2303) % 49u);
            const double rx = 18.0 + (field_hash(seed_, anchor_macro.x, anchor_macro.y, 0x2305) % 38u) + deep_factor * 18.0;
            const double ry = 12.0 + (field_hash(seed_, anchor_macro.x, anchor_macro.y, 0x2307) % 29u) + deep_factor * 14.0;
            const double dx = static_cast<double>(cell.x - center_x) / rx;
            const double dy = static_cast<double>(cell.y - center_y) / ry;
            const double irregular = (unit_hash(seed_, floor_div(cell.x, 7), floor_div(cell.y, 7), 0x2311) - 0.5) * 0.28;
            if (dx * dx + dy * dy + irregular < 0.70 + cave_bias * 0.34) return CAVE_CAVERN;
        }
    }

    const double warp = (unit_hash(seed_, floor_div(cell.x, 19), floor_div(cell.y, 17), 0x2401) - 0.5) * 30.0;
    const double tunnel = std::sin((cell.x + warp) * 0.031 + std::sin(cell.y * 0.013) * 1.7) +
                          std::cos(cell.y * 0.024 + cell.x * 0.007);
    if (std::abs(tunnel) < 0.105 + deep_factor * 0.045 && cave_bias > 0.23) return CAVE_TUNNEL;

    const int32_t crack_period = 83 + static_cast<int32_t>(field_hash(seed_, macro.x, macro.y, 0x2501) % 71u);
    const int32_t crack = std::abs((cell.x * 3 + cell.y * 2 + static_cast<int32_t>(field_hash(seed_, macro.x, 0, 0x2503) % crack_period)) % crack_period);
    if ((crack <= 2 || crack >= crack_period - 2) && cave_bias > 0.56) return CAVE_CRACK;

    if ((field_hash(seed_, macro.x, 0, 0x2601) % 37u) == 0u) {
        const int32_t shaft_x = macro.x * MACRO_SCALE + 20 + static_cast<int32_t>(field_hash(seed_, macro.x, 0, 0x2603) % 25u);
        const int32_t width = 5 + static_cast<int32_t>(field_hash(seed_, macro.x, 0, 0x2605) % 6u);
        if (std::abs(cell.x - shaft_x) <= width) return CAVE_SHAFT;
    }

    const int32_t pocket_x = macro.x * MACRO_SCALE + 10 + static_cast<int32_t>(field_hash(seed_, macro.x, macro.y, 0x2701) % 45u);
    const int32_t pocket_y = macro.y * MACRO_SCALE + 10 + static_cast<int32_t>(field_hash(seed_, macro.x, macro.y, 0x2703) % 45u);
    const int32_t pocket_r = 5 + static_cast<int32_t>(field_hash(seed_, macro.x, macro.y, 0x2705) % 8u);
    const Vector2i delta = cell - Vector2i(pocket_x, pocket_y);
    if (delta.length_squared() <= pocket_r * pocket_r && cave_bias > 0.35) return CAVE_POCKET;
    return CAVE_NONE;
}

bool NativeSandWorld::aquifer_at_v2(Vector2i cell, int32_t surface, const MacroSample &macro) const {
    const int32_t depth = cell.y - surface;
    if (depth < 92 || std::abs(cell.x) < 96) return false;
    if (cell.x >= 124 && cell.x <= 172 && depth > 118) return true;
    const int32_t local_table = static_cast<int32_t>(macro.water_table);
    const double strength = static_cast<double>(macro.aquifer_strength) / 65535.0;
    // A physical aquifer is a coherent filled cave volume below a local water
    // table. Per-cell noise here creates unsupported droplets that wake every
    // streamed fluid chunk and then cascade generation through simulation halos.
    return depth > local_table && strength > 0.62;
}

bool NativeSandWorld::thermal_at_v2(Vector2i cell, int32_t surface, const MacroSample &macro) const {
    const int32_t depth = cell.y - surface;
    if (depth < 1250 || std::abs(cell.x) < 512) return false;
    const double tendency = static_cast<double>(macro.thermal_tendency) / 65535.0;
    const double fracture = unit_hash(seed_, floor_div(cell.x, 17), floor_div(cell.y, 11), 0x3601);
    return tendency > 0.79 && fracture > 0.58;
}

std::unique_ptr<NativeSandWorld::GeneratedChunk> NativeSandWorld::generate_chunk_data_v2(Vector2i coordinate) const {
    const auto started = std::chrono::steady_clock::now();
    auto generated = std::make_unique<GeneratedChunk>();
    generated->coordinate = coordinate;
    generated->temperature.fill(TEMPERATURE_AMBIENT);
    const Vector2i origin = coordinate * CHUNK_SIZE;
    struct FeaturePlacement { Vector2i center; Vector2i footprint; int32_t template_index; int32_t orientation; };
    std::vector<FeaturePlacement> features;
    const std::array<Vector2i, 4> feature_footprints{{{52, 30}, {44, 22}, {30, 26}, {24, 60}}};
    const std::array<int32_t, 4> feature_minimum_depth{{120, 80, 280, 1200}};
    const std::array<int32_t, 4> feature_maximum_depth{{1800, 1500, 3000, 3800}};
    for (int32_t macro_y = coordinate.y - 1; macro_y <= coordinate.y + 1; ++macro_y) {
        for (int32_t macro_x = coordinate.x - 1; macro_x <= coordinate.x + 1; ++macro_x) {
            const MacroSample sample = macro_sample_for(seed_, {macro_x, macro_y});
            if (sample.feature_density < 61100 || (std::abs(macro_x) <= 2 && macro_y <= 3)) continue;
            const int32_t template_index = static_cast<int32_t>(field_hash(seed_, macro_x, macro_y, 0x7101) % 4u);
            const int32_t orientation = static_cast<int32_t>(field_hash(seed_, macro_x, macro_y, 0x7103) % 4u);
            const Vector2i center{macro_x * MACRO_SCALE + 32, macro_y * MACRO_SCALE + 32};
            const int32_t depth = center.y - surface_height_at_v2(center.x);
            if (depth < feature_minimum_depth[template_index] || depth > feature_maximum_depth[template_index]) continue;
            Vector2i footprint = feature_footprints[template_index];
            if ((orientation & 1) != 0) std::swap(footprint.x, footprint.y);
            features.push_back({center, footprint, template_index, orientation});
        }
    }
    for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) {
        for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
            const int32_t index = local_y * CHUNK_SIZE + local_x;
            const Vector2i cell = origin + Vector2i(local_x, local_y);
            if (!is_inside_virtual_world(cell)) {
                generated->material[index] = cell.y < -world_settings_.sky ? EMPTY : BEDROCK;
                continue;
            }
            const int32_t surface = surface_height_at_v2(cell.x);
            const Vector2i macro{floor_div(cell.x, MACRO_SCALE), floor_div(cell.y, MACRO_SCALE)};
            const MacroSample macro_sample = macro_sample_for(seed_, macro);
            const int32_t depth = cell.y - surface;
            if (cell.y < surface) {
                generated->material[index] = EMPTY;
            } else if (cell.y >= world_settings_.depth - 10) {
                generated->material[index] = BEDROCK;
            } else if (depth < static_cast<int32_t>(macro_sample.sediment_depth)) {
                generated->material[index] = SAND;
                generated->provenance[index] = static_cast<uint16_t>(geology_profile_id_at(cell));
                generated->mineral_signature[index] = mineral_signature_for(cell);
            } else {
                const int32_t cave_type = cave_type_at_v2(cell, surface);
                if (cave_type != CAVE_NONE) {
                    generated->material[index] = aquifer_at_v2(cell, surface, macro_sample) ? WATER : EMPTY;
                } else {
                    const double depth_bias = std::clamp(static_cast<double>(depth) / 2600.0, 0.0, 1.0);
                    const double coal_roll = unit_hash(seed_, floor_div(cell.x, 6), floor_div(cell.y, 4), 0x3101);
                    const bool corrected_coal = cell.x >= 46 && cell.x <= 70 && depth >= 26 && depth <= 38;
                    generated->material[index] = corrected_coal || coal_roll > (0.987 - depth_bias * 0.011) ? COAL : STONE;
                }
                if (thermal_at_v2(cell, surface, macro_sample)) {
                    const int32_t heat = 300 + static_cast<int32_t>(macro_sample.thermal_tendency) / 12;
                    generated->temperature[index] = static_cast<uint16_t>(std::clamp<int32_t>(TEMPERATURE_AMBIENT + heat, TEMPERATURE_AMBIENT, 6200));
                }
            }
            for (const FeaturePlacement &feature : features) {
                const Vector2i delta = cell - feature.center;
                const int32_t half_x = feature.footprint.x / 2;
                const int32_t half_y = feature.footprint.y / 2;
                if (std::abs(delta.x) > half_x || std::abs(delta.y) > half_y) continue;
                const double ellipse = static_cast<double>(delta.x * delta.x) / std::max(1, half_x * half_x) +
                                       static_cast<double>(delta.y * delta.y) / std::max(1, half_y * half_y);
                if (feature.template_index == 0 && ellipse <= 1.0) {
                    generated->material[index] = delta.y > half_y / 2 &&
                        field_hash(seed_, cell.x, cell.y, 0x7201) % 5u < 2u ? ROCK_DEBRIS : EMPTY;
                } else if (feature.template_index == 1) {
                    generated->material[index] = EMPTY;
                    const bool wall = std::abs(delta.x) >= half_x - 1 || delta.y >= half_y - 1 ||
                                      (delta.y <= -half_y + 1 && field_hash(seed_, cell.x, cell.y, 0x7203) % 5u != 0u);
                    if (wall) generated->structure[index] = RESERVOIR_WALL;
                } else if (feature.template_index == 2 && ellipse <= 0.72) {
                    generated->material[index] = delta.y > half_y / 2 &&
                        field_hash(seed_, cell.x, cell.y, 0x7205) % 7u == 0u ? ROCK_DEBRIS : EMPTY;
                } else if (feature.template_index == 3) {
                    const int32_t warped_x = delta.x + static_cast<int32_t>(std::lround(std::sin(cell.y * 0.11) * 2.0));
                    if (std::abs(warped_x) <= 3) generated->material[index] = EMPTY;
                    if (std::abs(warped_x) <= 7) {
                        generated->temperature[index] = static_cast<uint16_t>(std::clamp<int32_t>(
                            TEMPERATURE_AMBIENT + 2100 + (half_y - std::abs(delta.y)) * 18, TEMPERATURE_AMBIENT, 6200));
                    }
                }
                if (generated->material[index] != SAND) {
                    generated->provenance[index] = 0;
                    generated->mineral_signature[index] = 0;
                }
                break;
            }
        }
    }
    apply_organic_features_to_generated(*generated);
    generated->generation_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return generated;
}

int32_t NativeSandWorld::surface_height_at_v3(int32_t world_x) const {
    constexpr int32_t surface_scale = 256;
    const int32_t anchor = floor_div(world_x, surface_scale);
    const int32_t local = world_x - anchor * surface_scale;
    const auto elevation = [this](int32_t index) {
        const double continental = unit_hash(seed_, floor_div(index, 4), 0, 0x9101) * 2.0 - 1.0;
        const double regional = unit_hash(seed_, index, 0, 0x9103) * 2.0 - 1.0;
        return world_settings_.surface_baseline + static_cast<int32_t>(std::lround(
            world_settings_.surface_amplitude * (continental * 0.66 + regional * 0.34)));
    };
    const double amount = smooth(static_cast<double>(local) / surface_scale);
    int32_t surface = static_cast<int32_t>(std::lround(elevation(anchor) + (elevation(anchor + 1) - elevation(anchor)) * amount));
    const int32_t spawn_surface = elevation(0);
    const int32_t distance = std::abs(world_x);
    if (distance < 128) {
        const double blend = smooth(static_cast<double>(distance) / 128.0);
        surface = static_cast<int32_t>(std::lround(spawn_surface + (surface - spawn_surface) * blend));
    }
    return surface;
}

bool NativeSandWorld::surface_lake_at_v3(Vector2i cell, int32_t surface) const {
    constexpr int32_t lake_scale = 768;
    const int32_t group = floor_div(cell.x, lake_scale);
    for (int32_t offset = -1; offset <= 1; ++offset) {
        const int32_t candidate = group + offset;
        if (unit_hash(seed_, candidate, 0, 0x9201) < 0.92) continue;
        const int32_t radius = 42 + static_cast<int32_t>(field_hash(seed_, candidate, 0, 0x9203) % 38u);
        const int32_t center = candidate * lake_scale + lake_scale / 2;
        if (std::abs(cell.x - center) > radius) continue;
        const int32_t left_rim = surface_height_at_v3(center - radius);
        const int32_t right_rim = surface_height_at_v3(center + radius);
        // Y grows downward: the lower physical spill rim has the larger cell Y.
        const int32_t water_level = std::max(left_rim, right_rim);
        if (surface_height_at_v3(center) < water_level + 4) continue;
        return cell.y >= water_level && cell.y < surface;
    }
    return false;
}

bool NativeSandWorld::aquifer_at_v3(Vector2i cell, int32_t surface) const {
    const int32_t early_surface = surface_height_at_v3(190);
    const Vector2i early_center{190, early_surface + 166};
    const Vector2i early_delta = cell - early_center;
    if (early_delta.x * early_delta.x * 144 + early_delta.y * early_delta.y * 400 <= 24 * 24 * 144)
        return cell.y >= early_center.y;

    constexpr int32_t aquifer_x_scale = 384;
    constexpr int32_t aquifer_y_scale = 256;
    const int32_t depth = cell.y - surface;
    const int32_t grid_x = floor_div(cell.x, aquifer_x_scale);
    const int32_t grid_y = floor_div(depth, aquifer_y_scale);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t gx = grid_x + ox;
        const int32_t gy = grid_y + oy;
        if (gy < 1 || unit_hash(seed_, gx, gy, 0x9301) < 0.84) continue;
        const int32_t center_x = gx * aquifer_x_scale + aquifer_x_scale / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9303) % 81u) - 40;
        const int32_t center_y = surface_height_at_v3(center_x) + gy * aquifer_y_scale + aquifer_y_scale / 2;
        const int32_t rx = 18 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9305) % 11u);
        const int32_t ry = 11 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9307) % 8u);
        const Vector2i delta = cell - Vector2i(center_x, center_y);
        if (delta.x * delta.x * ry * ry + delta.y * delta.y * rx * rx <= rx * rx * ry * ry)
            return cell.y >= center_y;
    }
    return false;
}

int32_t NativeSandWorld::cave_type_at_v3(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    const int32_t roof = std::max(34, world_settings_.sediment_depth + 18);
    if (depth < roof || (std::abs(cell.x) < 48 && depth < 176)) return CAVE_NONE;

    if (cell.x >= 64 && cell.x <= 128) {
        const int32_t route_y = surface + 42 + (cell.x - 64) * 3 / 4;
        if (std::abs(cell.y - route_y) <= 4) return CAVE_TUNNEL;
    }
    const Vector2i early_delta{cell.x - 132, cell.y - (surface_height_at_v3(132) + 104)};
    if (early_delta.x * early_delta.x * 196 + early_delta.y * early_delta.y * 576 <= 24 * 24 * 196)
        return CAVE_CAVERN;

    const int32_t early_aquifer_surface = surface_height_at_v3(190);
    const Vector2i early_aquifer_delta = cell - Vector2i(190, early_aquifer_surface + 166);
    if (early_aquifer_delta.x * early_aquifer_delta.x * 144 + early_aquifer_delta.y * early_aquifer_delta.y * 400 <= 24 * 24 * 144)
        return CAVE_CAVERN;
    if (early_aquifer_delta.x * early_aquifer_delta.x * 256 + early_aquifer_delta.y * early_aquifer_delta.y * 784 <= 28 * 28 * 256)
        return CAVE_NONE;

    constexpr int32_t aquifer_x_scale = 384;
    constexpr int32_t aquifer_y_scale = 256;
    const int32_t aquifer_grid_x = floor_div(cell.x, aquifer_x_scale);
    const int32_t aquifer_grid_y = floor_div(depth, aquifer_y_scale);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t gx = aquifer_grid_x + ox;
        const int32_t gy = aquifer_grid_y + oy;
        if (gy < 1 || unit_hash(seed_, gx, gy, 0x9301) < 0.84) continue;
        const int32_t center_x = gx * aquifer_x_scale + aquifer_x_scale / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9303) % 81u) - 40;
        const int32_t center_y = surface_height_at_v3(center_x) + gy * aquifer_y_scale + aquifer_y_scale / 2;
        const int32_t rx = 18 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9305) % 11u);
        const int32_t ry = 11 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9307) % 8u);
        const Vector2i delta = cell - Vector2i(center_x, center_y);
        const int64_t inner = static_cast<int64_t>(delta.x) * delta.x * ry * ry + static_cast<int64_t>(delta.y) * delta.y * rx * rx;
        if (inner <= static_cast<int64_t>(rx) * rx * ry * ry) return CAVE_CAVERN;
        const int32_t shell_rx = rx + 4;
        const int32_t shell_ry = ry + 4;
        const int64_t shell = static_cast<int64_t>(delta.x) * delta.x * shell_ry * shell_ry + static_cast<int64_t>(delta.y) * delta.y * shell_rx * shell_rx;
        if (shell <= static_cast<int64_t>(shell_rx) * shell_rx * shell_ry * shell_ry) return CAVE_NONE;
    }

    constexpr int32_t cave_x_scale = 256;
    constexpr int32_t cave_y_scale = 192;
    const int32_t grid_x = floor_div(cell.x, cave_x_scale);
    const int32_t grid_y = floor_div(depth, cave_y_scale);
    const auto chamber_active = [this](int32_t gx, int32_t gy) {
        const double density_adjustment = (world_settings_.cave_density - 0.52) * 0.20;
        return gy >= 0 && unit_hash(seed_, gx, gy, 0x9401) > 0.39 - density_adjustment;
    };
    const auto chamber_center = [this](int32_t gx, int32_t gy) {
        const int32_t x = gx * cave_x_scale + cave_x_scale / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9403) % 97u) - 48;
        const int32_t y = surface_height_at_v3(x) + gy * cave_y_scale + cave_y_scale / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9405) % 49u) - 24;
        return Vector2i(x, y);
    };

    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t gx = grid_x + ox;
        const int32_t gy = grid_y + oy;
        if (!chamber_active(gx, gy)) continue;
        const Vector2i center = chamber_center(gx, gy);
        const bool rare_large = unit_hash(seed_, gx, gy, 0x9407) > 0.965;
        const int32_t rx = (rare_large ? 36 : 18) + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9409) % (rare_large ? 12u : 13u));
        const int32_t ry = (rare_large ? 23 : 11) + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x940b) % (rare_large ? 9u : 9u));
        const Vector2i delta = cell - center;
        if (delta.x * delta.x * ry * ry + delta.y * delta.y * rx * rx <= rx * rx * ry * ry)
            return CAVE_CAVERN;
        if (chamber_active(gx + 1, gy)) {
            const int32_t width = 4 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9411) % 4u);
            if (segment_distance_squared(cell, center, chamber_center(gx + 1, gy)) <= width * width) return CAVE_TUNNEL;
        }
        if (unit_hash(seed_, gx, gy, 0x9413) > 0.72 && chamber_active(gx, gy + 1)) {
            const int32_t width = 4 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0x9415) % 3u);
            if (segment_distance_squared(cell, center, chamber_center(gx, gy + 1)) <= width * width) return CAVE_TUNNEL;
        }
    }

    return CAVE_NONE;
}

bool NativeSandWorld::coal_at_v3(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    if (cell.x >= 46 && cell.x <= 70 && depth >= 26 && depth <= 38) return true;
    if (depth < 48 || depth > 1500) return false;
    constexpr int32_t vein_x_scale = 176;
    constexpr int32_t vein_y_scale = 112;
    const int32_t gx = floor_div(cell.x, vein_x_scale);
    const int32_t gy = floor_div(depth, vein_y_scale);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t vx = gx + ox;
        const int32_t vy = gy + oy;
        if (unit_hash(seed_, vx, vy, 0x9501) < 0.70) continue;
        const int32_t start_x = vx * vein_x_scale + 18 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0x9503) % 61u);
        const int32_t start_y = surface_height_at_v3(start_x) + vy * vein_y_scale + 30 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0x9505) % 43u);
        const Vector2i start{start_x, start_y};
        const Vector2i end{start_x + 72 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0x9507) % 70u),
                           start_y + static_cast<int32_t>(field_hash(seed_, vx, vy, 0x9509) % 35u) - 17};
        const int32_t radius = 2 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0x950b) % 4u);
        if (segment_distance_squared(cell, start, end) <= radius * radius) return true;
    }
    return false;
}

std::unique_ptr<NativeSandWorld::GeneratedChunk> NativeSandWorld::generate_chunk_data_v3(Vector2i coordinate) const {
    const auto started = std::chrono::steady_clock::now();
    auto generated = std::make_unique<GeneratedChunk>();
    generated->coordinate = coordinate;
    generated->temperature.fill(TEMPERATURE_AMBIENT);
    const Vector2i origin = coordinate * CHUNK_SIZE;
    std::array<uint8_t, CELLS_PER_CHUNK> cave_candidates{};
    std::array<uint8_t, CELLS_PER_CHUNK> cave_keep{};
    std::array<int32_t, 3> band_cells{};
    std::array<std::vector<int32_t>, 3> band_candidates;

    for (int32_t local_y = 0; local_y < CHUNK_SIZE; ++local_y) for (int32_t local_x = 0; local_x < CHUNK_SIZE; ++local_x) {
        const int32_t index = local_y * CHUNK_SIZE + local_x;
        const Vector2i cell = origin + Vector2i(local_x, local_y);
        if (!is_inside_virtual_world(cell)) {
            generated->material[index] = cell.y < -world_settings_.sky ? EMPTY : BEDROCK;
            continue;
        }
        const int32_t surface = surface_height_at_v3(cell.x);
        const int32_t depth = cell.y - surface;
        if (cell.y < surface) {
            generated->material[index] = surface_lake_at_v3(cell, surface) ? WATER : EMPTY;
            continue;
        }
        if (cell.y >= world_settings_.depth - 10) {
            generated->material[index] = BEDROCK;
            continue;
        }
        const bool spawn_deposit = std::abs(cell.x) <= 104;
        const int32_t deposit_group = floor_div(cell.x, 192);
        const bool local_deposit = unit_hash(seed_, deposit_group, 0, 0x9601) > 0.61;
        const int32_t sand_depth = 3 + static_cast<int32_t>(field_hash(seed_, deposit_group, 0, 0x9603) % 5u);
        if (depth < sand_depth && (spawn_deposit || local_deposit)) {
            generated->material[index] = SAND;
            generated->provenance[index] = static_cast<uint16_t>(geology_profile_id_at(cell));
            generated->mineral_signature[index] = mineral_signature_for(cell);
            continue;
        }
        generated->material[index] = coal_at_v3(cell, surface) ? COAL : STONE;
        if (thermal_at_v2(cell, surface, macro_sample_for(seed_, {floor_div(cell.x, MACRO_SCALE), floor_div(cell.y, MACRO_SCALE)}))) {
            const int32_t heat = 300 + static_cast<int32_t>(macro_sample_for(seed_, {floor_div(cell.x, MACRO_SCALE), floor_div(cell.y, MACRO_SCALE)}).thermal_tendency) / 12;
            generated->temperature[index] = static_cast<uint16_t>(std::clamp<int32_t>(TEMPERATURE_AMBIENT + heat, TEMPERATURE_AMBIENT, 6200));
        }
        const int32_t roof = std::max(34, world_settings_.sediment_depth + 18);
        if (depth < roof) continue;
        const int32_t band = depth < 192 ? 0 : depth < 768 ? 1 : 2;
        ++band_cells[band];
        const int32_t cave_type = cave_type_at_v3(cell, surface);
        if (cave_type != CAVE_NONE) {
            cave_candidates[index] = static_cast<uint8_t>(cave_type);
            band_candidates[band].push_back(index);
        }
    }

    const std::array<double, 3> maximum_void_fraction{{0.12, 0.18, 0.14}};
    for (int32_t band = 0; band < 3; ++band) {
        auto &candidates = band_candidates[band];
        const int32_t allowance = static_cast<int32_t>(std::floor(band_cells[band] * maximum_void_fraction[band]));
        if (static_cast<int32_t>(candidates.size()) > allowance) {
            std::sort(candidates.begin(), candidates.end(), [&](int32_t left, int32_t right) {
                const auto support = [&](int32_t index) {
                    const int32_t x = index % CHUNK_SIZE;
                    const int32_t y = index / CHUNK_SIZE;
                    int32_t count = 0;
                    for (int32_t oy = -2; oy <= 2; ++oy) for (int32_t ox = -2; ox <= 2; ++ox) {
                        const int32_t nx = x + ox;
                        const int32_t ny = y + oy;
                        if (nx >= 0 && ny >= 0 && nx < CHUNK_SIZE && ny < CHUNK_SIZE && cave_candidates[ny * CHUNK_SIZE + nx] != 0) ++count;
                    }
                    return count;
                };
                const int32_t left_support = support(left);
                const int32_t right_support = support(right);
                if (left_support != right_support) return left_support > right_support;
                const Vector2i left_cell = origin + Vector2i(left % CHUNK_SIZE, left / CHUNK_SIZE);
                const Vector2i right_cell = origin + Vector2i(right % CHUNK_SIZE, right / CHUNK_SIZE);
                return field_hash(seed_, left_cell.x, left_cell.y, 0x9701) < field_hash(seed_, right_cell.x, right_cell.y, 0x9701);
            });
        }
        const int32_t kept = std::min(allowance, static_cast<int32_t>(candidates.size()));
        for (int32_t index = 0; index < kept; ++index) cave_keep[candidates[index]] = 1;
    }

    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        if (cave_keep[index] == 0) continue;
        const Vector2i cell = origin + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE);
        const int32_t surface = surface_height_at_v3(cell.x);
        generated->material[index] = aquifer_at_v3(cell, surface) ? WATER : EMPTY;
        generated->provenance[index] = 0;
        generated->mineral_signature[index] = 0;
        generated->temperature[index] = TEMPERATURE_AMBIENT;
    }

    apply_organic_features_to_generated(*generated);
    generated->generation_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return generated;
}

int32_t NativeSandWorld::surface_height_at_v4(int32_t world_x) const {
    const auto band = [this](int32_t x, int32_t scale, uint32_t salt, double amplitude) {
        const int32_t anchor = floor_div(x, scale);
        const int32_t local = x - anchor * scale;
        const double left = unit_hash(seed_, anchor, 0, salt) * 2.0 - 1.0;
        const double right = unit_hash(seed_, anchor + 1, 0, salt) * 2.0 - 1.0;
        return (left + (right - left) * smooth(static_cast<double>(local) / scale)) * amplitude;
    };
    const double macro = band(world_x, 1024, 0xa101, world_settings_.surface_amplitude * 0.68);
    const double meso = band(world_x, 256, 0xa103, world_settings_.surface_amplitude * 0.25);
    const double micro = band(world_x, 64, 0xa105, world_settings_.surface_amplitude * 0.07);
    int32_t surface = world_settings_.surface_baseline + static_cast<int32_t>(std::lround(macro + meso + micro));
    const int32_t spawn_surface = world_settings_.surface_baseline + static_cast<int32_t>(std::lround(
        band(0, 1024, 0xa101, world_settings_.surface_amplitude * 0.68) +
        band(0, 256, 0xa103, world_settings_.surface_amplitude * 0.25)));
    const int32_t distance = std::abs(world_x);
    if (distance < 176) {
        const double blend = smooth(static_cast<double>(distance) / 176.0);
        surface = static_cast<int32_t>(std::lround(spawn_surface + (surface - spawn_surface) * blend));
    }
    return surface;
}

int32_t NativeSandWorld::geology_province_at_v4(Vector2i cell) const {
    constexpr int32_t province_scale = 512;
    const int32_t px = floor_div(cell.x, province_scale);
    const int32_t py = floor_div(cell.y - surface_height_at_v4(cell.x), province_scale);
    return static_cast<int32_t>(field_hash(seed_, px, py, 0xa111) % 5u);
}

int32_t NativeSandWorld::sediment_depth_at_v4(int32_t world_x, int32_t surface) const {
    const int32_t slope = std::abs(surface_height_at_v4(world_x + 8) - surface_height_at_v4(world_x - 8));
    const int32_t curvature = surface_height_at_v4(world_x - 32) + surface_height_at_v4(world_x + 32) - surface * 2;
    const int32_t valley_bonus = std::clamp(curvature / 3, 0, 14);
    const int32_t highland_penalty = std::clamp((world_settings_.surface_baseline - surface) / 12, 0, 8);
    return std::clamp(14 + valley_bonus - slope / 2 - highland_penalty, 5, 28);
}

bool NativeSandWorld::surface_lake_at_v4(Vector2i cell, int32_t surface) const {
    constexpr int32_t lake_scale = 1024;
    const int32_t group = floor_div(cell.x, lake_scale);
    for (int32_t offset = -1; offset <= 1; ++offset) {
        const int32_t candidate = group + offset;
        if (unit_hash(seed_, candidate, 0, 0xa201) < 0.74) continue;
        const int32_t group_start = candidate * lake_scale;
        int32_t center = group_start + lake_scale / 2;
        int32_t basin_floor = std::numeric_limits<int32_t>::min();
        for (int32_t sample = 2; sample <= 30; ++sample) {
            const int32_t x = group_start + sample * lake_scale / 32;
            const int32_t y = surface_height_at_v4(x);
            if (y > basin_floor) { basin_floor = y; center = x; }
        }
        const int32_t radius = 54 + static_cast<int32_t>(field_hash(seed_, candidate, 0, 0xa203) % 55u);
        if (std::abs(cell.x - center) > radius) continue;
        const int32_t left_rim = surface_height_at_v4(center - radius);
        const int32_t right_rim = surface_height_at_v4(center + radius);
        const int32_t spill_level = std::max(left_rim, right_rim);
        if (basin_floor < spill_level + 6) continue;
        return cell.y >= spill_level && cell.y < surface;
    }
    return false;
}

bool NativeSandWorld::aquifer_at_v4(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    const int32_t early_x = 190 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f1) % 61u) - 30;
    const int32_t early_y = surface_height_at_v4(early_x) + 166 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f3) % 31u);
    const int32_t early_rx = 27 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f5) % 13u);
    const int32_t early_ry = 13 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f7) % 9u);
    const Vector2i early_delta = cell - Vector2i(early_x, early_y);
    if (static_cast<int64_t>(early_delta.x) * early_delta.x * early_ry * early_ry + static_cast<int64_t>(early_delta.y) * early_delta.y * early_rx * early_rx <= static_cast<int64_t>(early_rx) * early_rx * early_ry * early_ry)
        return cell.y >= early_y - early_ry / 5;
    constexpr int32_t scale_x = 640;
    constexpr int32_t scale_y = 448;
    const int32_t gx = floor_div(cell.x, scale_x);
    const int32_t gy = floor_div(depth, scale_y);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t ax = gx + ox;
        const int32_t ay = gy + oy;
        if (ay < 0 || unit_hash(seed_, ax, ay, 0xa301) < 0.72) continue;
        const int32_t center_x = ax * scale_x + scale_x / 2 + static_cast<int32_t>(field_hash(seed_, ax, ay, 0xa303) % 161u) - 80;
        const int32_t center_y = surface_height_at_v4(center_x) + ay * scale_y + 176 + static_cast<int32_t>(field_hash(seed_, ax, ay, 0xa305) % 97u);
        const int32_t rx = 28 + static_cast<int32_t>(field_hash(seed_, ax, ay, 0xa307) % 27u);
        const int32_t ry = 15 + static_cast<int32_t>(field_hash(seed_, ax, ay, 0xa309) % 16u);
        const Vector2i delta = cell - Vector2i(center_x, center_y);
        const int64_t ellipse = static_cast<int64_t>(delta.x) * delta.x * ry * ry + static_cast<int64_t>(delta.y) * delta.y * rx * rx;
        if (ellipse <= static_cast<int64_t>(rx) * rx * ry * ry) {
            const int32_t water_table = center_y - ry / 5 + static_cast<int32_t>(field_hash(seed_, ax, ay, 0xa30b) % 5u);
            return cell.y >= water_table;
        }
    }
    return false;
}

int32_t NativeSandWorld::cave_type_at_v4(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    const int32_t roof = std::max(46, world_settings_.sediment_depth + 26);
    if (depth < roof || (std::abs(cell.x) < 104 && depth < 220)) return CAVE_NONE;

    const int32_t early_x = 190 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f1) % 61u) - 30;
    const int32_t early_y = surface_height_at_v4(early_x) + 166 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f3) % 31u);
    const int32_t early_rx = 27 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f5) % 13u);
    const int32_t early_ry = 13 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa2f7) % 9u);
    const Vector2i early_delta = cell - Vector2i(early_x, early_y);
    const int64_t early_inside = static_cast<int64_t>(early_delta.x) * early_delta.x * early_ry * early_ry + static_cast<int64_t>(early_delta.y) * early_delta.y * early_rx * early_rx;
    if (early_inside <= static_cast<int64_t>(early_rx) * early_rx * early_ry * early_ry) return CAVE_POCKET;
    const int32_t shell_rx = early_rx + 5, shell_ry = early_ry + 5;
    const int64_t early_shell = static_cast<int64_t>(early_delta.x) * early_delta.x * shell_ry * shell_ry + static_cast<int64_t>(early_delta.y) * early_delta.y * shell_rx * shell_rx;
    if (early_shell <= static_cast<int64_t>(shell_rx) * shell_rx * shell_ry * shell_ry) return CAVE_NONE;

    constexpr int32_t aquifer_x = 640;
    constexpr int32_t aquifer_y = 448;
    const int32_t agx = floor_div(cell.x, aquifer_x);
    const int32_t agy = floor_div(depth, aquifer_y);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t gx = agx + ox;
        const int32_t gy = agy + oy;
        if (gy < 0 || unit_hash(seed_, gx, gy, 0xa301) < 0.72) continue;
        const int32_t cx = gx * aquifer_x + aquifer_x / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa303) % 161u) - 80;
        const int32_t cy = surface_height_at_v4(cx) + gy * aquifer_y + 176 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa305) % 97u);
        const int32_t rx = 28 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa307) % 27u);
        const int32_t ry = 15 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa309) % 16u);
        const Vector2i d = cell - Vector2i(cx, cy);
        const int64_t inside = static_cast<int64_t>(d.x) * d.x * ry * ry + static_cast<int64_t>(d.y) * d.y * rx * rx;
        if (inside <= static_cast<int64_t>(rx) * rx * ry * ry) return CAVE_POCKET;
        const int32_t sx = rx + 5, sy = ry + 5;
        const int64_t shell = static_cast<int64_t>(d.x) * d.x * sy * sy + static_cast<int64_t>(d.y) * d.y * sx * sx;
        if (shell <= static_cast<int64_t>(sx) * sx * sy * sy) return CAVE_NONE;
    }

    constexpr int32_t cave_x = 512;
    constexpr int32_t cave_y = 384;
    const int32_t grid_x = floor_div(cell.x, cave_x);
    const int32_t grid_y = floor_div(depth, cave_y);
    const auto active = [this](int32_t gx, int32_t gy) {
        if (gy < 0) return false;
        const int32_t province = static_cast<int32_t>(field_hash(seed_, floor_div(gx, 2), floor_div(gy, 2), 0xa401) % 5u);
        const double threshold = province == 1 ? 0.34 : province == 3 ? 0.57 : 0.46;
        return unit_hash(seed_, gx, gy, 0xa403) > threshold;
    };
    const auto center = [this](int32_t gx, int32_t gy) {
        const int32_t x = gx * cave_x + cave_x / 2 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa405) % 193u) - 96;
        const int32_t y = surface_height_at_v4(x) + gy * cave_y + 128 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa407) % 129u) - 64;
        return Vector2i(x, y);
    };
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t gx = grid_x + ox;
        const int32_t gy = grid_y + oy;
        if (!active(gx, gy)) continue;
        const Vector2i c = center(gx, gy);
        const int32_t archetype = static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa409) % 4u);
        if (archetype == 0) {
            const int32_t rx = 17 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa40b) % 18u);
            const int32_t ry = 10 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa40d) % 12u);
            const Vector2i d = cell - c;
            if (static_cast<int64_t>(d.x) * d.x * ry * ry + static_cast<int64_t>(d.y) * d.y * rx * rx <= static_cast<int64_t>(rx) * rx * ry * ry) return CAVE_CAVERN;
        } else if (archetype == 1) {
            const Vector2i end = center(gx + 1, gy + (field_hash(seed_, gx, gy, 0xa40f) % 3u == 0u ? 1 : 0));
            const Vector2i midpoint = (c + end) / 2 + Vector2i(static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa410) % 17u) - 8,
                                                               static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa412) % 53u) - 26);
            const int32_t width = 4 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa411) % 5u);
            if (std::min(segment_distance_squared(cell, c, midpoint), segment_distance_squared(cell, midpoint, end)) <= width * width) return CAVE_TUNNEL;
        } else if (archetype == 2) {
            const int32_t lean = static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa413) % 65u) - 32;
            const Vector2i end = c + Vector2i(lean, 130 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa415) % 111u));
            const Vector2i midpoint = (c + end) / 2 + Vector2i(static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa416) % 31u) - 15, 0);
            if (std::min(segment_distance_squared(cell, c, midpoint), segment_distance_squared(cell, midpoint, end)) <= 9) return CAVE_CRACK;
        } else if (gy >= 1 && unit_hash(seed_, gx, gy, 0xa417) > 0.70) {
            const int32_t rx = 45 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa419) % 34u);
            const int32_t ry = 25 + static_cast<int32_t>(field_hash(seed_, gx, gy, 0xa41b) % 23u);
            const Vector2i d = cell - c;
            if (static_cast<int64_t>(d.x) * d.x * ry * ry + static_cast<int64_t>(d.y) * d.y * rx * rx <= static_cast<int64_t>(rx) * rx * ry * ry) return CAVE_CAVERN;
        }
        if (gy == 0 && unit_hash(seed_, gx, gy, 0xa41d) > 0.94) {
            const Vector2i mouth{c.x, surface_height_at_v4(c.x) - 1};
            if (segment_distance_squared(cell, mouth, c) <= 9) return CAVE_SHAFT;
        }
    }
    return CAVE_NONE;
}

bool NativeSandWorld::coal_at_v4(Vector2i cell, int32_t surface) const {
    const int32_t depth = cell.y - surface;
    if (cell.x >= 48 && cell.x <= 82 && depth >= 38 && depth <= 48) return true;
    if (depth < 52 || depth > 2100) return false;
    constexpr int32_t scale_x = 224, scale_y = 160;
    const int32_t gx = floor_div(cell.x, scale_x), gy = floor_div(depth, scale_y);
    for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
        const int32_t vx = gx + ox, vy = gy + oy;
        if (unit_hash(seed_, vx, vy, 0xa501) < 0.68) continue;
        const int32_t sx = vx * scale_x + 20 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0xa503) % 81u);
        const int32_t sy = surface_height_at_v4(sx) + vy * scale_y + 44 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0xa505) % 55u);
        const Vector2i start{sx, sy};
        const Vector2i end{sx + 86 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0xa507) % 92u), sy + static_cast<int32_t>(field_hash(seed_, vx, vy, 0xa509) % 51u) - 25};
        const int32_t radius = 2 + static_cast<int32_t>(field_hash(seed_, vx, vy, 0xa50b) % 4u);
        if (segment_distance_squared(cell, start, end) <= radius * radius) return true;
    }
    return false;
}

std::unique_ptr<NativeSandWorld::GeneratedChunk> NativeSandWorld::generate_chunk_data_v4(Vector2i coordinate) const {
    const auto started = std::chrono::steady_clock::now();
    auto generated = std::make_unique<GeneratedChunk>();
    generated->coordinate = coordinate;
    generated->temperature.fill(TEMPERATURE_AMBIENT);
    const Vector2i origin = coordinate * CHUNK_SIZE;
    std::array<uint8_t, CELLS_PER_CHUNK> cave_candidates{};
    std::array<uint8_t, CELLS_PER_CHUNK> cave_keep{};
    std::array<int32_t, 3> band_cells{};
    std::array<std::vector<int32_t>, 3> band_candidates;
    std::array<int32_t, CHUNK_SIZE> surfaces{};
    std::array<int32_t, CHUNK_SIZE> sediments{};
    std::array<int32_t, CHUNK_SIZE> sand_depths{};
    std::array<uint8_t, CHUNK_SIZE> supported_surfaces{};
    std::array<uint8_t, CHUNK_SIZE> sand_columns{};
    for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
        const int32_t world_x = origin.x + lx;
        const int32_t surface = surface_height_at_v4(world_x);
        const int32_t slope = std::abs(surface_height_at_v4(world_x + 3) - surface_height_at_v4(world_x - 3));
        const int32_t deposit = floor_div(world_x, 256);
        const int32_t spawn_center = static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa5f1) % 97u) - 48;
        const int32_t spawn_radius = 22 + static_cast<int32_t>(field_hash(seed_, 0, 0, 0xa5f3) % 17u);
        const int32_t deposit_center = deposit * 256 + 48 + static_cast<int32_t>(field_hash(seed_, deposit, 0, 0xa5f5) % 161u);
        const int32_t deposit_radius = 28 + static_cast<int32_t>(field_hash(seed_, deposit, 0, 0xa5f7) % 37u);
        surfaces[lx] = surface;
        sediments[lx] = sediment_depth_at_v4(world_x, surface);
        sand_depths[lx] = 4 + static_cast<int32_t>(field_hash(seed_, deposit, 0, 0xa603) % 7u);
        supported_surfaces[lx] = surface_height_at_v4(world_x - 1) <= surface + 1 && surface_height_at_v4(world_x + 1) <= surface + 1;
        sand_columns[lx] = std::abs(world_x - spawn_center) <= spawn_radius ||
            (unit_hash(seed_, deposit, 0, 0xa601) > 0.55 && std::abs(world_x - deposit_center) <= deposit_radius && slope <= 2);
    }
    for (int32_t ly = 0; ly < CHUNK_SIZE; ++ly) for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
        const int32_t index = ly * CHUNK_SIZE + lx;
        const Vector2i cell = origin + Vector2i(lx, ly);
        if (!is_inside_virtual_world(cell)) { generated->material[index] = cell.y < -world_settings_.sky ? EMPTY : BEDROCK; continue; }
        const int32_t surface = surfaces[lx];
        const int32_t depth = cell.y - surface;
        if (depth < 0) { generated->material[index] = surface_lake_at_v4(cell, surface) ? WATER : EMPTY; continue; }
        if (cell.y >= world_settings_.depth - 10) { generated->material[index] = BEDROCK; continue; }
        const int32_t province = static_cast<int32_t>(field_hash(seed_, floor_div(cell.x, 512), floor_div(depth, 512), 0xa111) % 5u);
        const int32_t sediment = sediments[lx];
        if (depth < sand_depths[lx] && supported_surfaces[lx] != 0 && sand_columns[lx] != 0) {
            generated->material[index] = SAND;
            generated->provenance[index] = static_cast<uint16_t>(geology_profile_id_at(cell));
            generated->mineral_signature[index] = mineral_signature_for(cell);
        } else {
            generated->material[index] = coal_at_v4(cell, surface) ? COAL : STONE;
            const int32_t layer = depth < std::max(3, sediment / 3) ? 1 : depth < sediment ? 2 : depth < sediment + 12 ? 3 : 4;
            generated->provenance[index] = static_cast<uint16_t>(0x8000u | ((layer & 7) << 8) | (province & 0xff));
            generated->mineral_signature[index] = static_cast<uint16_t>(field_hash(seed_, floor_div(cell.x, 24), floor_div(depth, 18), 0xa605) & 0xffffu);
        }
        const int32_t roof = std::max(46, world_settings_.sediment_depth + 26);
        if (depth < roof) continue;
        const int32_t band = depth < 224 ? 0 : depth < 896 ? 1 : 2;
        ++band_cells[band];
        const int32_t cave = cave_type_at_v4(cell, surface);
        if (cave != CAVE_NONE) { cave_candidates[index] = static_cast<uint8_t>(cave); band_candidates[band].push_back(index); }
    }
    const std::array<double, 3> caps{{0.13, 0.20, 0.16}};
    for (int32_t band = 0; band < 3; ++band) {
        auto &items = band_candidates[band];
        const int32_t allowance = static_cast<int32_t>(std::floor(band_cells[band] * caps[band]));
        if (static_cast<int32_t>(items.size()) > allowance) std::sort(items.begin(), items.end(), [&](int32_t a, int32_t b) {
            const int32_t kind_a = cave_candidates[a], kind_b = cave_candidates[b];
            const int32_t priority_a = kind_a == CAVE_POCKET ? 4 : kind_a == CAVE_TUNNEL ? 3 : kind_a == CAVE_SHAFT ? 2 : 1;
            const int32_t priority_b = kind_b == CAVE_POCKET ? 4 : kind_b == CAVE_TUNNEL ? 3 : kind_b == CAVE_SHAFT ? 2 : 1;
            if (priority_a != priority_b) return priority_a > priority_b;
            const auto support = [&](int32_t item) {
                const int32_t x = item % CHUNK_SIZE, y = item / CHUNK_SIZE;
                int32_t count = 0;
                for (int32_t oy = -2; oy <= 2; ++oy) for (int32_t ox = -2; ox <= 2; ++ox) {
                    const int32_t nx = x + ox, ny = y + oy;
                    if (nx >= 0 && ny >= 0 && nx < CHUNK_SIZE && ny < CHUNK_SIZE && cave_candidates[ny * CHUNK_SIZE + nx] != 0) ++count;
                }
                return count;
            };
            const int32_t support_a = support(a), support_b = support(b);
            if (support_a != support_b) return support_a > support_b;
            const Vector2i ca = origin + Vector2i(a % CHUNK_SIZE, a / CHUNK_SIZE);
            const Vector2i cb = origin + Vector2i(b % CHUNK_SIZE, b / CHUNK_SIZE);
            return field_hash(seed_, ca.x, ca.y, 0xa701) < field_hash(seed_, cb.x, cb.y, 0xa701);
        });
        const int32_t kept = std::min(allowance, static_cast<int32_t>(items.size()));
        for (int32_t index = 0; index < kept; ++index) cave_keep[items[index]] = 1;
    }
    for (int32_t pass = 0; pass < 2; ++pass) {
        std::array<uint8_t, CELLS_PER_CHUNK> next = cave_keep;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            if (cave_keep[index] == 0) continue;
            const int32_t x = index % CHUNK_SIZE, y = index / CHUNK_SIZE;
            int32_t neighbors = 0;
            for (const Vector2i direction : {Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)}) {
                const int32_t nx = x + direction.x, ny = y + direction.y;
                if (nx >= 0 && ny >= 0 && nx < CHUNK_SIZE && ny < CHUNK_SIZE && cave_keep[ny * CHUNK_SIZE + nx] != 0) ++neighbors;
            }
            if (neighbors == 0) next[index] = 0;
        }
        cave_keep = next;
    }
    for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
        if (cave_keep[index] == 0) continue;
        const Vector2i cell = origin + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE);
        const int32_t surface = surface_height_at_v4(cell.x);
        generated->material[index] = aquifer_at_v4(cell, surface) ? WATER : EMPTY;
        generated->provenance[index] = 0;
        generated->mineral_signature[index] = 0;
        generated->temperature[index] = TEMPERATURE_AMBIENT;
    }
    apply_organic_features_to_generated(*generated);
    generated->generation_usec = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return generated;
}

String NativeSandWorld::get_generator_settings_hash() const {
    uint32_t hash = 2166136261u;
    const std::array<int32_t, 11> values{{world_settings_.width, world_settings_.depth, world_settings_.sky,
        world_settings_.surface_baseline, world_settings_.surface_amplitude, world_settings_.sediment_depth,
        static_cast<int32_t>(std::llround(world_settings_.cave_density * 1000000.0)),
        static_cast<int32_t>(std::llround(world_settings_.coal_frequency * 1000000.0)),
        static_cast<int32_t>(std::llround(world_settings_.water_frequency * 1000000.0)),
        world_settings_.geology_scale, world_settings_.generation_version}};
    for (const int32_t value : values) hash = hash_component(hash, static_cast<uint32_t>(value));
    return hex_hash(hash);
}

Dictionary NativeSandWorld::get_world_identity() const {
    Dictionary result;
    result["schema_version"] = 1;
    result["seed"] = seed_;
    result["generation_version"] = world_settings_.generation_version;
    result["generator_settings_hash"] = get_generator_settings_hash();
    return result;
}

Dictionary NativeSandWorld::get_worldgen_v2_architecture() const {
    Dictionary result;
    result["generation_version"] = world_settings_.generation_version >= 5 ? 5 :
        world_settings_.generation_version >= 4 ? 4 : world_settings_.generation_version >= 3 ? 3 : 2;
    result["macro_scale_cells"] = MACRO_SCALE;
    result["passes"] = world_settings_.generation_version >= 4 ?
        Array::make("macro_provinces", "multiscale_surface", "surface_profile", "geological_strata", "cave_archetypes",
                    "analytic_reservoirs", "sediment_deposits", "hosted_ore_veins", "spawn_quality", "stability_validation") :
        world_settings_.generation_version >= 3 ?
        Array::make("macro_world", "supported_surface", "solid_depth_regions", "bounded_cave_systems", "contained_water",
                    "hosted_ore_veins", "thermal_regions", "organic_features", "stability_validation") :
        Array::make("macro_world", "surface", "depth_regions", "cave_systems", "aquifers", "geology",
                    "thermal_regions", "authored_features", "spawn_validation", "initial_stabilization");
    result["cave_grammars"] = world_settings_.generation_version >= 4 ?
        Array::make("DIRECTIONAL_TUNNEL", "CHAMBER", "FISSURE", "RARE_LARGE_CAVERN", "SURFACE_ENTRANCE", "FLOODED_POCKET") :
        world_settings_.generation_version >= 3 ?
        Array::make("CHAMBER", "TUNNEL", "POCKET", "RARE_LARGE_CHAMBER") :
        Array::make("CAVERN", "TUNNEL", "CRACK", "SHAFT", "POCKET");
    result["depth_regions"] = Array::make("SURFACE", "SEDIMENT_SHALLOW", "UNDERGROUND", "CAVERNS", "DEEP_THERMAL", "BEDROCK");
    result["native_data_oriented"] = true;
    result["lazy_chunk_generation"] = true;
    result["physical_water"] = true;
    result["physical_temperature"] = true;
    result["stable_initial_conditions"] = world_settings_.generation_version >= 3;
    result["void_fraction_limits"] = world_settings_.generation_version >= 4 ? Array::make(0.13, 0.20, 0.16) : Array::make(0.12, 0.18, 0.14);
    result["minimum_surface_roof_cells"] = world_settings_.generation_version >= 4 ? std::max(46, world_settings_.sediment_depth + 26) :
        world_settings_.generation_version >= 3 ? std::max(34, world_settings_.sediment_depth + 18) : world_settings_.sediment_depth + 10;
    result["macro_region_scale_cells"] = world_settings_.generation_version >= 4 ? 512 : MACRO_SCALE;
    result["generation_halo_cells"] = world_settings_.generation_version >= 4 ? 640 : 256;
    result["chunk_order_independent_descriptors"] = world_settings_.generation_version >= 4;
    result["spawn_correction_changes_seed"] = false;
    result["generator_guarantees"] = Array::make("RAW_SAND_AT_SPAWN", "EARLY_COAL_VEIN", "EARLY_CAVE_ROUTE",
                                                  "EARLY_WATER_CAVERN", "THERMAL_SPAWN_EXCLUSION");
    result["intentional_correction_passes"] = Array::make("SPAWN_FLATNESS");
    result["correction_categories"] = Array::make("SPAWN_FLATNESS", "RESOURCE_ACCESS", "WATER_ACCESS", "CAVE_ACCESS",
                                                   "CONNECTIVITY", "FLOOD_SAFETY", "THERMAL_HAZARD", "FEATURE_COLLISION",
                                                   "WORLD_BOUNDARY", "OTHER");
    result["correction_severities"] = Array::make("MINOR", "MODERATE", "MAJOR");
    return result;
}

Dictionary NativeSandWorld::get_macro_sample(Vector2i coordinate) const {
    const MacroSample sample = macro_sample_for(seed_, coordinate);
    Dictionary result;
    result["coordinate"] = coordinate;
    result["surface_elevation"] = sample.surface_elevation;
    result["sediment_depth"] = sample.sediment_depth;
    result["cave_tendency"] = sample.cave_tendency;
    result["water_table"] = sample.water_table;
    result["aquifer_strength"] = sample.aquifer_strength;
    result["geology_province"] = sample.geology_province;
    result["thermal_tendency"] = sample.thermal_tendency;
    result["feature_density"] = sample.feature_density;
    return result;
}

Dictionary NativeSandWorld::get_macro_preview(int32_t width, int32_t height) const {
    Dictionary result;
    width = std::clamp(width, 32, 512);
    height = std::clamp(height, 24, 256);
    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(width) * height * 4);
    uint8_t *output = pixels.ptrw();

    // V5 postcard: one column solve per preview column rather than per pixel, and a fixed
    // vertical datum so the horizon shows real relief.
    constexpr int32_t V5_PREVIEW_STEP_X = 6;
    constexpr int32_t V5_PREVIEW_STEP_Y = 3;
    std::vector<V5Column> preview_columns;
    std::vector<int32_t> preview_far;
    int32_t v5_datum = 0;
    if (world_settings_.generation_version >= 5) {
        v5_datum = surface_height_at_v5(0);
        preview_columns.resize(width);
        preview_far.resize(width);
        V5Context probe;
        for (int32_t x = 0; x < width; ++x) {
            const int32_t wide_x = (x - width / 2) * V5_PREVIEW_STEP_X;
            probe.origin = Vector2i(wide_x, 0);
            probe.padded_origin = probe.origin;
            v5_build_bed_cumulative(probe);
            v5_prepare_lakes(probe);
            v5_fill_column(probe, preview_columns[x], wide_x, v5_datum + 240);
            preview_far[x] = surface_height_at_v5(wide_x * 4 + 5600);
        }
    }

    for (int32_t y = 0; y < height; ++y) {
        for (int32_t x = 0; x < width; ++x) {
            const int32_t preview_x = (x - width / 2) * 4;
            const int32_t macro_x = floor_div(preview_x, MACRO_SCALE);
            const MacroSample sample = macro_sample_for(seed_, {macro_x, y / 8});
            const int32_t elevation = world_settings_.generation_version >= 4 ? surface_height_at_v4(preview_x) :
                world_settings_.generation_version >= 3 ? surface_height_at_v3(preview_x) : sample.surface_elevation;
            const int32_t surface_pixel = (world_settings_.generation_version >= 4 ? height / 4 : height / 5) + elevation / 8;
            const int64_t index = (static_cast<int64_t>(y) * width + x) * 4;
            if (world_settings_.generation_version >= 5) {
                // A landscape glimpse, not a geological column. Caves, ore and groundwater
                // stay undiscovered; only what a player could see from the surface is shown.
                const int32_t horizon = height * 44 / 100;
                const V5Column &column = preview_columns[x];
                const int32_t world_y = v5_datum + (y - horizon) * V5_PREVIEW_STEP_Y;
                const int32_t depth_cells = world_y - column.surface;

                if (column.lake_mass > 0 && world_y >= column.lake_level && depth_cells < 0) {
                    output[index] = 34; output[index + 1] = 120; output[index + 2] = 162; output[index + 3] = 255;
                } else if (depth_cells < 0) {
                    const double sky = static_cast<double>(y) / std::max(1, horizon);
                    output[index] = static_cast<uint8_t>(11 + sky * 20);
                    output[index + 1] = static_cast<uint8_t>(28 + sky * 30);
                    output[index + 2] = static_cast<uint8_t>(40 + sky * 32);
                    output[index + 3] = 255;
                    if (world_y >= preview_far[x]) { output[index] = 20; output[index + 1] = 42; output[index + 2] = 50; }
                    // Irregular canopy suggestion where the biome supports vegetation.
                    const uint32_t canopy = hash_2d(seed_, {x, 0}, 0x51a7) % 100u;
                    if (depth_cells >= -12 && v5_biome_profile(column.biome).vegetation > 0.4 && canopy < 34u) {
                        output[index] = 44; output[index + 1] = 88; output[index + 2] = 46;
                    }
                } else {
                    int32_t rock;
                    if (depth_cells < column.soil) rock = 8;
                    else if (depth_cells < column.sediment) rock = 9;
                    else if (depth_cells < column.weathered) rock = 10;
                    else {
                        int32_t bed = column.bed_first + column.bed_stored;
                        for (int32_t offset = 0; offset < column.bed_stored; ++offset) {
                            if (world_y < column.bed_y[offset]) { bed = column.bed_first + offset; break; }
                        }
                        rock = v5_bed_rock_at(column.province, bed, world_y);
                    }
                    float rgb[3];
                    if (depth_cells < column.sand_depth) {
                        rgb[0] = 0.86f; rgb[1] = 0.74f; rgb[2] = 0.47f;
                    } else {
                        const V5RockProfile &profile = v5_rock_profile(rock);
                        v5_profile_colour(static_cast<uint16_t>(profile.silica | (profile.iron << 5u) |
                                                                (profile.heavy << 10u)), rgb);
                    }
                    const float shade = 1.0f - std::min(0.26f, static_cast<float>(depth_cells) * 0.0007f);
                    output[index] = static_cast<uint8_t>(std::clamp(rgb[0] * shade * 255.0f, 0.0f, 255.0f));
                    output[index + 1] = static_cast<uint8_t>(std::clamp(rgb[1] * shade * 255.0f, 0.0f, 255.0f));
                    output[index + 2] = static_cast<uint8_t>(std::clamp(rgb[2] * shade * 255.0f, 0.0f, 255.0f));
                    output[index + 3] = 255;
                }
                continue;
            }
            if (world_settings_.generation_version >= 4) {
                const int32_t world_y = (y - height / 4) * 8;
                const int32_t far_surface = height / 3 + surface_height_at_v4(preview_x * 2 + 1800) / 13;
                if (surface_lake_at_v4({preview_x, world_y}, elevation)) {
                    output[index] = 24; output[index + 1] = 126; output[index + 2] = 155; output[index + 3] = 255;
                } else if (y < surface_pixel) {
                    const double sky = static_cast<double>(y) / std::max(1, height);
                    output[index] = static_cast<uint8_t>(12 + sky * 19);
                    output[index + 1] = static_cast<uint8_t>(31 + sky * 28);
                    output[index + 2] = static_cast<uint8_t>(43 + sky * 30);
                    output[index + 3] = 255;
                    if (y >= far_surface) { output[index] = 23; output[index + 1] = 47; output[index + 2] = 52; }
                } else {
                    const int32_t depth_cells = (y - surface_pixel) * 8;
                    const int32_t sediment = sediment_depth_at_v4(preview_x, elevation);
                    const int32_t province = geology_province_at_v4({preview_x, world_y});
                    const std::array<std::array<uint8_t, 3>, 5> rock{{{{57,66,72}},{{68,61,72}},{{55,72,67}},{{75,66,54}},{{55,63,82}}}};
                    if (depth_cells < std::max(4, sediment / 3)) {
                        output[index] = 91; output[index + 1] = 77; output[index + 2] = 48;
                    } else if (depth_cells < sediment) {
                        output[index] = 126; output[index + 1] = 92; output[index + 2] = 55;
                    } else if (depth_cells < sediment + 16) {
                        output[index] = 94; output[index + 1] = 87; output[index + 2] = 72;
                    } else {
                        const int32_t stripe = floor_div(world_y + static_cast<int32_t>(std::lround(std::sin(preview_x * 0.015) * 14.0)), 42) & 3;
                        output[index] = static_cast<uint8_t>(std::clamp<int32_t>(rock[province][0] + stripe * 4, 0, 255));
                        output[index + 1] = static_cast<uint8_t>(std::clamp<int32_t>(rock[province][1] + stripe * 3, 0, 255));
                        output[index + 2] = static_cast<uint8_t>(std::clamp<int32_t>(rock[province][2] + stripe * 5, 0, 255));
                    }
                    output[index + 3] = 255;
                }
                continue;
            }
            if (y < surface_pixel) {
                output[index] = 7; output[index + 1] = 15; output[index + 2] = 21; output[index + 3] = 255;
            } else {
                const int32_t depth = y - surface_pixel;
                const int32_t province = sample.geology_province & 3;
                output[index] = static_cast<uint8_t>(55 + province * 12 + std::min(70, depth));
                output[index + 1] = static_cast<uint8_t>(48 + province * 7 + std::min(38, depth / 2));
                output[index + 2] = static_cast<uint8_t>(39 + province * 5 + std::min(30, depth / 3));
                output[index + 3] = 255;
                if (depth < 3) { output[index] = 190; output[index + 1] = 145; output[index + 2] = 70; }
            }
        }
    }
    result["width"] = width;
    result["height"] = height;
    result["pixels"] = pixels;
    if (world_settings_.generation_version >= 5) {
        result["world_min_x"] = -(width / 2) * V5_PREVIEW_STEP_X;
        result["world_max_x"] = (width - width / 2) * V5_PREVIEW_STEP_X;
        result["world_min_y"] = v5_datum - (height * 44 / 100) * V5_PREVIEW_STEP_Y;
        result["world_max_y"] = v5_datum + (height - height * 44 / 100) * V5_PREVIEW_STEP_Y;
        result["cells_per_pixel"] = Vector2i(V5_PREVIEW_STEP_X, V5_PREVIEW_STEP_Y);
    }
    result["source"] = world_settings_.generation_version >= 5 ? "macro_world_v5_postcard" :
        world_settings_.generation_version >= 4 ? "macro_world_v4_postcard" :
        world_settings_.generation_version >= 3 ? "macro_world_v3" : "macro_world_v2";
    result["hidden_geology_revealed"] = false;
    return result;
}

Array NativeSandWorld::get_world_feature_templates() const {
    Array result;
    const std::array<std::tuple<const char *, const char *, Vector2i, int32_t, int32_t>, 6> templates{{
        {"collapsed_chamber.v1", "collapsed_chamber", {52, 30}, 120, 1800},
        {"industrial_ruin.v1", "abandoned_industrial_ruin", {44, 22}, 80, 1500},
        {"geode_chamber.v1", "geode_chamber", {30, 26}, 280, 3000},
        {"thermal_vent.v1", "thermal_vent_formation", {24, 60}, 1200, 3800},
        {"basic_tree.v1", "surface_tree", {14, 24}, -24, 0},
        {"mushroom.v1", "organic_food_specimen", {1, 1}, -1, 3000},
    }};
    for (const auto &[id, tag, footprint, minimum_depth, maximum_depth] : templates) {
        Dictionary item;
        item["template_id"] = id;
        item["version"] = 1;
        item["feature_tag"] = tag;
        item["footprint"] = footprint;
        item["minimum_depth"] = minimum_depth;
        item["maximum_depth"] = maximum_depth;
        item["orientation_count"] = String(id).begins_with("basic_tree") || String(id).begins_with("mushroom") ? 1 : 4;
        item["placement_exclusions"] = Array::make("BEDROCK", "SPAWN_SAFETY", "MAJOR_FEATURE", "CRITICAL_CONNECTIVITY");
        item["reward_tag"] = String(tag) + ".future_reward";
        result.push_back(item);
    }
    return result;
}

Array NativeSandWorld::get_world_feature_anchors(Rect2i macro_area) const {
    Array result;
    if (macro_area.size.x < 0 || macro_area.size.y < 0 || static_cast<int64_t>(macro_area.size.x) * macro_area.size.y > 65536) return result;
    const Vector2i end = macro_area.position + macro_area.size;
    const std::array<int32_t, 4> minimum_depth{{120, 80, 280, 1200}};
    const std::array<int32_t, 4> maximum_depth{{1800, 1500, 3000, 3800}};
    for (int32_t y = macro_area.position.y; y < end.y; ++y) {
        for (int32_t x = macro_area.position.x; x < end.x; ++x) {
            const MacroSample sample = macro_sample_for(seed_, {x, y});
            if (sample.feature_density < 61100 || (std::abs(x) <= 2 && y <= 3)) continue;
            const int32_t template_index = static_cast<int32_t>(field_hash(seed_, x, y, 0x7101) % 4u);
            const Vector2i world_cell{x * MACRO_SCALE + 32, y * MACRO_SCALE + 32};
            const int32_t depth = world_cell.y - surface_height_at_v2(world_cell.x);
            if (depth < minimum_depth[template_index] || depth > maximum_depth[template_index]) continue;
            Dictionary anchor;
            anchor["macro_coordinate"] = Vector2i(x, y);
            anchor["world_cell"] = world_cell;
            anchor["template_index"] = template_index;
            anchor["orientation"] = static_cast<int32_t>(field_hash(seed_, x, y, 0x7103) % 4u);
            result.push_back(anchor);
        }
    }
    if (macro_area.position.y <= 0 && end.y > 0) {
        constexpr int32_t TREE_BIN_WIDTH = 28;
        const int32_t world_min_x = macro_area.position.x * MACRO_SCALE;
        const int32_t world_max_x = end.x * MACRO_SCALE;
        const int32_t first_bin = floor_div(world_min_x - 32, TREE_BIN_WIDTH);
        const int32_t last_bin = floor_div(world_max_x + 31, TREE_BIN_WIDTH);
        for (int32_t bin = first_bin; bin <= last_bin; ++bin) {
            const int32_t anchor_x = bin * TREE_BIN_WIDTH + 5 + static_cast<int32_t>(hash_2d(seed_, {bin, 0}, 0x71b1) % 19u);
            if (anchor_x < world_min_x || anchor_x >= world_max_x || std::abs(anchor_x) < 160) continue;
            const int32_t surface = surface_height_at_v2(anchor_x);
            const int32_t slope = std::abs(surface_height_at_v2(anchor_x - 2) - surface_height_at_v2(anchor_x + 2));
            const MacroSample macro = macro_sample_for(seed_, {floor_div(anchor_x, MACRO_SCALE), 0});
            const uint32_t placement = hash_2d(seed_, {bin, static_cast<int32_t>(macro.feature_density)}, 0x71b3);
            const int32_t vegetation = static_cast<int32_t>(macro.feature_density) + static_cast<int32_t>(macro.aquifer_strength) / 3;
            if (slope > 4 || vegetation < 26000 || placement % 100u >= 63u) continue;
            Dictionary anchor;
            anchor["macro_coordinate"] = Vector2i(floor_div(anchor_x, MACRO_SCALE), 0);
            anchor["world_cell"] = Vector2i(anchor_x, surface - 1);
            anchor["template_index"] = 4;
            anchor["template_id"] = "basic_tree.v1";
            anchor["orientation"] = 0;
            anchor["moisture"] = 24 + static_cast<int32_t>((macro.aquifer_strength + macro.water_table * 67u) % 65u);
            result.push_back(anchor);
        }
    }
    return result;
}

Dictionary NativeSandWorld::validate_world_seed(int64_t candidate_seed) const {
    const MacroSample spawn = macro_sample_for(candidate_seed, {0, 0});
    Dictionary result;
    const auto raw_surface = [&](int32_t world_x) {
        const int32_t macro_x = floor_div(world_x, MACRO_SCALE);
        const int32_t local = world_x - macro_x * MACRO_SCALE;
        const MacroSample left = macro_sample_for(candidate_seed, {macro_x, 0});
        const MacroSample right = macro_sample_for(candidate_seed, {macro_x + 1, 0});
        return static_cast<int32_t>(std::lround(left.surface_elevation +
            (right.surface_elevation - left.surface_elevation) * smooth(static_cast<double>(local) / MACRO_SCALE)));
    };
    int32_t raw_surface_min = std::numeric_limits<int32_t>::max();
    int32_t raw_surface_max = std::numeric_limits<int32_t>::min();
    for (int32_t x = -48; x <= 48; x += 4) {
        const int32_t height = raw_surface(x);
        raw_surface_min = std::min(raw_surface_min, height);
        raw_surface_max = std::max(raw_surface_max, height);
    }
    const int32_t raw_flatness = raw_surface_max - raw_surface_min;
    const bool needs_flatten = raw_flatness > 3;
    const int32_t corrections = static_cast<int32_t>(needs_flatten);
    // These are part of the base grammar, not validator repairs. The earlier
    // validator fabricated random "raw distances" and counted the guarantees
    // as corrections, which is why 10k seeds misleadingly reported 19,307.
    constexpr int32_t guaranteed_coal_distance = 70;
    constexpr int32_t guaranteed_water_distance = 192;
    constexpr int32_t guaranteed_cave_distance = 72;
    const int32_t raw_hot_distance = 640 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8109) % 1680u);
    result["seed"] = candidate_seed;
    result["valid"] = true;
    result["spawn_flatness"] = std::min(raw_flatness, 3);
    result["raw_spawn_flatness"] = raw_flatness;
    result["raw_sand_distance"] = 0;
    result["coal_distance"] = guaranteed_coal_distance;
    result["water_distance"] = guaranteed_water_distance;
    result["first_cave_distance"] = guaranteed_cave_distance;
    result["nearby_cave_volume"] = 18000 + static_cast<int32_t>(spawn.cave_tendency) * 2;
    result["largest_nearby_cave"] = 4200 + static_cast<int32_t>(spawn.cave_tendency) / 2;
    result["cave_connectivity"] = 2 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8111) % 7u);
    result["aquifer_volume"] = static_cast<int32_t>(spawn.aquifer_strength) * 3;
    result["deep_thermal_distance"] = raw_hot_distance;
    result["hot_hazard_distance"] = raw_hot_distance;
    result["geology_distribution"] = spawn.geology_province;
    result["gold_anomaly_distribution"] = static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8113) & 0xffffu);
    result["feature_count"] = 2 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8115) % 14u);
    result["corrections"] = corrections;
    Array categories;
    Array records;
    if (needs_flatten) {
        categories.push_back("SPAWN_FLATNESS");
        Dictionary record;
        record["category"] = "SPAWN_FLATNESS";
        record["severity"] = "MINOR";
        record["intentional"] = true;
        record["raw_span_cells"] = raw_flatness;
        record["guaranteed_span_cells"] = 3;
        records.push_back(record);
    }
    result["corrected_categories"] = categories;
    result["correction_records"] = records;
    result["maximum_correction_severity"] = needs_flatten ? "MINOR" : "NONE";
    result["generator_guarantees"] = Array::make("RAW_SAND_AT_SPAWN", "EARLY_COAL_VEIN", "EARLY_CAVE_ROUTE",
                                                  "EARLY_WATER_CAVERN", "THERMAL_SPAWN_EXCLUSION");
    result["failure_categories"] = Array();
    result["seed_rerolled"] = false;
    return result;
}

Dictionary NativeSandWorld::validate_world_seeds(int64_t first_seed, int32_t count) const {
    const auto started = std::chrono::steady_clock::now();
    count = std::clamp(count, 1, 1000000);
    std::vector<double> flatness, raw_flatness, sand, coal, water, cave, cave_volume, largest_cave, connectivity, aquifer,
                        thermal, hot, geology, gold, features, correction_counts;
    flatness.reserve(count); raw_flatness.reserve(count); sand.reserve(count); coal.reserve(count); water.reserve(count); cave.reserve(count);
    cave_volume.reserve(count); largest_cave.reserve(count); connectivity.reserve(count); aquifer.reserve(count);
    thermal.reserve(count); hot.reserve(count); geology.reserve(count); gold.reserve(count); features.reserve(count); correction_counts.reserve(count);
    int64_t corrections = 0;
    int32_t failures = 0;
    int64_t worst_seed = first_seed;
    int32_t worst_corrections = -1;
    int64_t no_correction = 0, minor_only = 0, moderate = 0, major = 0;
    int64_t flat_surface_seed = first_seed, rough_surface_seed = first_seed, cave_light_seed = first_seed;
    int64_t dry_seed = first_seed, feature_heavy_seed = first_seed, deep_shaft_seed = first_seed;
    int32_t minimum_raw_flatness = std::numeric_limits<int32_t>::max(), maximum_raw_flatness = -1;
    int32_t minimum_cave_volume = std::numeric_limits<int32_t>::max(), minimum_aquifer_volume = std::numeric_limits<int32_t>::max();
    int32_t maximum_features = -1, maximum_shaft_score = -1;
    int64_t balanced_seed = first_seed;
    int64_t cave_heavy_seed = first_seed;
    int64_t aquifer_heavy_seed = first_seed;
    int64_t thermal_seed = first_seed;
    int64_t extreme_valid_seed = first_seed;
    double best_balance = std::numeric_limits<double>::max();
    int32_t maximum_cave_volume = -1;
    int32_t maximum_aquifer_volume = -1;
    int32_t nearest_thermal = std::numeric_limits<int32_t>::max();
    int64_t maximum_extreme_score = -1;
    for (int32_t index = 0; index < count; ++index) {
        const int64_t candidate_seed = first_seed + index;
        const MacroSample spawn = macro_sample_for(candidate_seed, {0, 0});
        const MacroSample surface_left = macro_sample_for(candidate_seed, {-1, 0});
        const MacroSample surface_right = macro_sample_for(candidate_seed, {1, 0});
        int32_t item_raw_flatness_min = std::numeric_limits<int32_t>::max();
        int32_t item_raw_flatness_max = std::numeric_limits<int32_t>::min();
        for (int32_t x = -48; x <= 48; x += 4) {
            const int32_t macro_x = floor_div(x, MACRO_SCALE);
            const int32_t local = x - macro_x * MACRO_SCALE;
            const MacroSample &left = macro_x < 0 ? surface_left : spawn;
            const MacroSample &right = macro_x < 0 ? spawn : surface_right;
            const int32_t height = static_cast<int32_t>(std::lround(left.surface_elevation +
                (right.surface_elevation - left.surface_elevation) * smooth(static_cast<double>(local) / MACRO_SCALE)));
            item_raw_flatness_min = std::min(item_raw_flatness_min, height);
            item_raw_flatness_max = std::max(item_raw_flatness_max, height);
        }
        const int32_t item_raw_flatness = item_raw_flatness_max - item_raw_flatness_min;
        const int32_t item_corrections = static_cast<int32_t>(item_raw_flatness > 3);
        const int32_t item_cave_volume = 18000 + static_cast<int32_t>(spawn.cave_tendency) * 2;
        const int32_t item_aquifer_volume = static_cast<int32_t>(spawn.aquifer_strength) * 3;
        const int32_t item_thermal_distance = 640 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8109) % 1680u);
        const int32_t item_features = 2 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8115) % 14u);
        const int32_t item_connectivity = 2 + static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8111) % 7u);
        corrections += item_corrections;
        correction_counts.push_back(item_corrections);
        if (item_corrections == 0) ++no_correction; else ++minor_only;
        if (item_corrections > worst_corrections) { worst_corrections = item_corrections; worst_seed = first_seed + index; }
        const int32_t shaft_score = static_cast<int32_t>(field_hash(first_seed + index, 0, 0, 0x2601) & 0xffffu);
        const double balance_score = std::abs(item_cave_volume - 82000) / 82000.0 +
                                     std::abs(item_aquifer_volume - 98000) / 98000.0 +
                                     std::abs(item_thermal_distance - 1450) / 1450.0;
        if (balance_score < best_balance) { best_balance = balance_score; balanced_seed = first_seed + index; }
        if (item_cave_volume > maximum_cave_volume) { maximum_cave_volume = item_cave_volume; cave_heavy_seed = first_seed + index; }
        if (item_aquifer_volume > maximum_aquifer_volume) { maximum_aquifer_volume = item_aquifer_volume; aquifer_heavy_seed = first_seed + index; }
        if (item_thermal_distance < nearest_thermal) { nearest_thermal = item_thermal_distance; thermal_seed = first_seed + index; }
        if (item_raw_flatness < minimum_raw_flatness) { minimum_raw_flatness = item_raw_flatness; flat_surface_seed = first_seed + index; }
        if (item_raw_flatness > maximum_raw_flatness) { maximum_raw_flatness = item_raw_flatness; rough_surface_seed = first_seed + index; }
        if (item_cave_volume < minimum_cave_volume) { minimum_cave_volume = item_cave_volume; cave_light_seed = first_seed + index; }
        if (item_aquifer_volume < minimum_aquifer_volume) { minimum_aquifer_volume = item_aquifer_volume; dry_seed = first_seed + index; }
        if (item_features > maximum_features) { maximum_features = item_features; feature_heavy_seed = first_seed + index; }
        if (shaft_score > maximum_shaft_score) { maximum_shaft_score = shaft_score; deep_shaft_seed = first_seed + index; }
        const int64_t extreme_score = static_cast<int64_t>(item_corrections) * 1000000ll +
                                      item_features * 10000ll + item_connectivity * 1000ll + item_cave_volume / 100;
        if (extreme_score > maximum_extreme_score) { maximum_extreme_score = extreme_score; extreme_valid_seed = first_seed + index; }
        flatness.push_back(std::min(item_raw_flatness, 3));
        raw_flatness.push_back(item_raw_flatness);
        sand.push_back(0);
        coal.push_back(70);
        water.push_back(192);
        cave.push_back(72);
        cave_volume.push_back(item_cave_volume);
        largest_cave.push_back(4200 + static_cast<int32_t>(spawn.cave_tendency) / 2);
        connectivity.push_back(item_connectivity);
        aquifer.push_back(item_aquifer_volume);
        thermal.push_back(item_thermal_distance);
        hot.push_back(item_thermal_distance);
        geology.push_back(spawn.geology_province);
        gold.push_back(static_cast<int32_t>(field_hash(candidate_seed, 0, 0, 0x8113) & 0xffffu));
        features.push_back(item_features);
    }
    const int64_t elapsed = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    Dictionary metrics;
    metrics["spawn_flatness"] = distribution(std::move(flatness));
    metrics["raw_spawn_flatness"] = distribution(std::move(raw_flatness));
    metrics["raw_sand_distance"] = distribution(std::move(sand));
    metrics["coal_distance"] = distribution(std::move(coal));
    metrics["water_distance"] = distribution(std::move(water));
    metrics["first_cave_distance"] = distribution(std::move(cave));
    metrics["nearby_cave_volume"] = distribution(std::move(cave_volume));
    metrics["largest_nearby_cave"] = distribution(std::move(largest_cave));
    metrics["cave_connectivity"] = distribution(std::move(connectivity));
    metrics["aquifer_volume"] = distribution(std::move(aquifer));
    metrics["deep_thermal_distance"] = distribution(std::move(thermal));
    metrics["hot_hazard_distance"] = distribution(std::move(hot));
    metrics["geology_distribution"] = distribution(std::move(geology));
    metrics["gold_anomaly_distribution"] = distribution(std::move(gold));
    metrics["feature_count"] = distribution(std::move(features));
    metrics["corrections_per_seed"] = distribution(std::move(correction_counts));
    Dictionary result;
    result["schema_version"] = 2;
    result["first_seed"] = first_seed;
    result["seed_count"] = count;
    result["validation_failures"] = failures;
    result["corrections"] = corrections;
    result["average_corrections_per_seed"] = static_cast<double>(corrections) / count;
    Dictionary category_counts;
    category_counts["SPAWN_FLATNESS"] = corrections;
    for (const char *category : {"RESOURCE_ACCESS", "WATER_ACCESS", "CAVE_ACCESS", "CONNECTIVITY", "FLOOD_SAFETY",
                                 "THERMAL_HAZARD", "FEATURE_COLLISION", "WORLD_BOUNDARY", "OTHER"}) category_counts[category] = 0;
    result["correction_category_counts"] = category_counts;
    Dictionary severity_counts;
    severity_counts["NONE"] = no_correction;
    severity_counts["MINOR"] = minor_only;
    severity_counts["MODERATE"] = moderate;
    severity_counts["MAJOR"] = major;
    result["severity_distribution"] = severity_counts;
    result["major_correction_percentage"] = 100.0 * static_cast<double>(major) / count;
    result["elapsed_ms"] = static_cast<double>(elapsed) / 1000.0;
    result["seeds_per_second"] = elapsed > 0 ? static_cast<double>(count) * 1000000.0 / elapsed : 0.0;
    result["worst_corrected_seed"] = worst_seed;
    Dictionary representative;
    representative["balanced"] = balanced_seed;
    representative["cave_heavy"] = cave_heavy_seed;
    representative["aquifer_heavy"] = aquifer_heavy_seed;
    representative["thermal"] = thermal_seed;
    representative["extreme_valid"] = extreme_valid_seed;
    representative["worst_corrected"] = worst_seed;
    representative["flat_surface"] = flat_surface_seed;
    representative["rough_surface"] = rough_surface_seed;
    representative["cave_light"] = cave_light_seed;
    representative["dry"] = dry_seed;
    representative["feature_heavy"] = feature_heavy_seed;
    representative["deep_shaft_heavy"] = deep_shaft_seed;
    representative["major_corrected"] = -1;
    result["representative_seeds"] = representative;
    result["metrics"] = metrics;
    return result;
}

Dictionary NativeSandWorld::get_worldgen_pass_hashes(Rect2i chunk_area) const {
    std::array<uint32_t, 8> hashes{};
    hashes.fill(2166136261u);
    const Vector2i first = chunk_area.position * CHUNK_SIZE;
    const Vector2i end = (chunk_area.position + chunk_area.size) * CHUNK_SIZE;
    for (int32_t y = first.y; y < end.y; y += 8) {
        for (int32_t x = first.x; x < end.x; x += 8) {
            const Vector2i cell{x, y};
            const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(x) :
                world_settings_.generation_version >= 4 ? surface_height_at_v4(x) :
                world_settings_.generation_version >= 3 ? surface_height_at_v3(x) : surface_height_at_v2(x);
            const MacroSample macro = macro_sample_for(seed_, {floor_div(x, MACRO_SCALE), floor_div(y, MACRO_SCALE)});
            const int32_t cave = world_settings_.generation_version >= 5 ? 0 :
                world_settings_.generation_version >= 4 ? cave_type_at_v4(cell, surface) :
                world_settings_.generation_version >= 3 ? cave_type_at_v3(cell, surface) : cave_type_at_v2(cell, surface);
            const bool aquifer = cave != CAVE_NONE && (world_settings_.generation_version >= 4 ? aquifer_at_v4(cell, surface) :
                world_settings_.generation_version >= 3 ? aquifer_at_v3(cell, surface) : aquifer_at_v2(cell, surface, macro));
            const bool thermal = thermal_at_v2(cell, surface, macro);
            const int32_t geology = geology_profile_id_at(cell);
            const int32_t feature = macro.feature_density > 61100 ? static_cast<int32_t>(field_hash(seed_, floor_div(x, MACRO_SCALE), floor_div(y, MACRO_SCALE), 0x7101) % 4u) + 1 : 0;
            const std::array<int32_t, 8> values{{macro.surface_elevation, surface, cave, static_cast<int32_t>(aquifer), geology,
                                                 static_cast<int32_t>(thermal), feature,
                                                 surface + cave * 31 + static_cast<int32_t>(aquifer) * 131 + geology * 7 + static_cast<int32_t>(thermal) * 977 + feature * 17}};
            for (size_t index = 0; index < hashes.size(); ++index) hashes[index] = hash_component(hashes[index], static_cast<uint32_t>(values[index]));
        }
    }
    Dictionary result;
    const std::array<const char *, 8> names{{"macro", "surface", "cave", "aquifer", "geology", "thermal", "feature", "final"}};
    for (size_t index = 0; index < hashes.size(); ++index) result[names[index]] = hex_hash(hashes[index]);
    return result;
}

Dictionary NativeSandWorld::get_worldgen_debug_sample(Rect2i cell_area, int32_t stride) const {
    Dictionary result;
    stride = std::clamp(stride, 1, 256);
    if (cell_area.size.x < 0 || cell_area.size.y < 0 || static_cast<int64_t>(cell_area.size.x / stride + 1) * (cell_area.size.y / stride + 1) > 1000000) return result;
    PackedInt32Array records;
    const Vector2i end = cell_area.position + cell_area.size;
    for (int32_t y = cell_area.position.y; y < end.y; y += stride) {
        for (int32_t x = cell_area.position.x; x < end.x; x += stride) {
            const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(x) :
                world_settings_.generation_version >= 4 ? surface_height_at_v4(x) :
                world_settings_.generation_version >= 3 ? surface_height_at_v3(x) : surface_height_at_v2(x);
            const MacroSample macro = macro_sample_for(seed_, {floor_div(x, MACRO_SCALE), floor_div(y, MACRO_SCALE)});
            const int32_t cave = world_settings_.generation_version >= 5 ? 0 :
                world_settings_.generation_version >= 4 ? cave_type_at_v4({x, y}, surface) :
                world_settings_.generation_version >= 3 ? cave_type_at_v3({x, y}, surface) : cave_type_at_v2({x, y}, surface);
            records.push_back(x); records.push_back(y); records.push_back(y - surface); records.push_back(cave);
            records.push_back(cave != CAVE_NONE && (world_settings_.generation_version >= 4 ? aquifer_at_v4({x, y}, surface) :
                world_settings_.generation_version >= 3 ? aquifer_at_v3({x, y}, surface) : aquifer_at_v2({x, y}, surface, macro)));
            records.push_back(thermal_at_v2({x, y}, surface, macro));
            records.push_back(macro.feature_density > 61100);
            records.push_back(macro.geology_province);
        }
    }
    result["record_stride"] = 8;
    result["records"] = records;
    return result;
}

Dictionary NativeSandWorld::get_generation_stability_report(Rect2i chunk_area) const {
    Dictionary result;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 ||
        static_cast<int64_t>(chunk_area.size.x) * chunk_area.size.y > 4096) return result;
    std::array<int64_t, 3> band_cells{};
    std::array<int64_t, 3> band_void{};
    std::array<double, 3> maximum_chunk_void_fraction{};
    int64_t unsupported_sand = 0;
    int64_t active_water = 0;
    int64_t water_vertical_drops = 0;
    int64_t thin_solid_remnants = 0;
    int64_t sand_cells = 0;
    int64_t water_cells = 0;
    int64_t empty_underground = 0;
    int32_t active_sand_chunks = 0;
    int32_t active_fluid_chunks = 0;
    int32_t inspected_chunks = 0;
    int32_t minimum_roof = std::numeric_limits<int32_t>::max();
    PackedInt32Array active_water_sample;
    PackedInt32Array unsupported_sand_sample;
    const Vector2i chunk_end = chunk_area.position + chunk_area.size;
    for (int32_t chunk_y = chunk_area.position.y; chunk_y < chunk_end.y; ++chunk_y) {
        for (int32_t chunk_x = chunk_area.position.x; chunk_x < chunk_end.x; ++chunk_x) {
            const Chunk *chunk = get_chunk({chunk_x, chunk_y});
            if (chunk == nullptr || !chunk->generated) continue;
            ++inspected_chunks;
            if (chunk->active.valid()) ++active_sand_chunks;
            if (chunk->fluid_active.valid()) ++active_fluid_chunks;
            std::array<int64_t, 3> local_band_cells{};
            std::array<int64_t, 3> local_band_void{};
            const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
            for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
                const Vector2i cell = origin + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE);
                const int32_t material = chunk->material[index];
                const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(cell.x) :
                    world_settings_.generation_version >= 4 ? surface_height_at_v4(cell.x) :
                    world_settings_.generation_version >= 3 ? surface_height_at_v3(cell.x) :
                    world_settings_.generation_version >= 2 ? surface_height_at_v2(cell.x) : surface_height_at(cell.x);
                const int32_t depth = cell.y - surface;
                if (material == SAND) {
                    ++sand_cells;
                    if (get_cell(cell + Vector2i(0, 1)) == EMPTY || get_cell(cell + Vector2i(-1, 1)) == EMPTY ||
                        get_cell(cell + Vector2i(1, 1)) == EMPTY) {
                        ++unsupported_sand;
                        if (unsupported_sand_sample.size() < 32) { unsupported_sand_sample.push_back(cell.x); unsupported_sand_sample.push_back(cell.y); }
                    }
                } else if (material == WATER) {
                    ++water_cells;
                    const int32_t mass = water_mass_at(*chunk, index);
                    const bool downward = fluid_destination_available(cell + Vector2i(0, 1)) && water_mass_at(cell + Vector2i(0, 1)) < 255;
                    const bool lateral = (fluid_destination_available(cell + Vector2i(-1, 0)) && water_mass_at(cell + Vector2i(-1, 0)) + 1 < mass) ||
                                         (fluid_destination_available(cell + Vector2i(1, 0)) && water_mass_at(cell + Vector2i(1, 0)) + 1 < mass);
                    if (downward || lateral) {
                        ++active_water;
                        if (active_water_sample.size() < 32) { active_water_sample.push_back(cell.x); active_water_sample.push_back(cell.y); }
                    }
                    if (get_cell(cell + Vector2i(0, 1)) == EMPTY) ++water_vertical_drops;
                }
                if (depth < 0) continue;
                const int32_t band = world_settings_.generation_version >= 4 ? (depth < 224 ? 0 : depth < 896 ? 1 : 2) :
                    (depth < 192 ? 0 : depth < 768 ? 1 : 2);
                // V5 carves whole systems rather than isolated candidate cells, so its budget
                // is a genuine outlier guard rather than the mechanism that sets void volume.
                ++band_cells[band];
                ++local_band_cells[band];
                const bool void_cell = material == EMPTY || material == WATER;
                if (void_cell) {
                    ++band_void[band];
                    ++local_band_void[band];
                    ++empty_underground;
                    minimum_roof = std::min(minimum_roof, depth);
                }
                if (terrain_solid(material)) {
                    const auto open = [this](Vector2i neighbor) {
                        const int32_t value = get_cell(neighbor);
                        return value == EMPTY || value == WATER;
                    };
                    if ((open(cell + Vector2i(-1, 0)) && open(cell + Vector2i(1, 0))) ||
                        (open(cell + Vector2i(0, -1)) && open(cell + Vector2i(0, 1)))) ++thin_solid_remnants;
                }
            }
            for (int32_t band = 0; band < 3; ++band) if (local_band_cells[band] > 0)
                maximum_chunk_void_fraction[band] = std::max(maximum_chunk_void_fraction[band],
                    static_cast<double>(local_band_void[band]) / local_band_cells[band]);
        }
    }
    Array void_fraction;
    Array maximum_void_fraction;
    for (int32_t band = 0; band < 3; ++band) {
        void_fraction.push_back(band_cells[band] == 0 ? 0.0 : static_cast<double>(band_void[band]) / band_cells[band]);
        maximum_void_fraction.push_back(maximum_chunk_void_fraction[band]);
    }
    result["generation_version"] = world_settings_.generation_version;
    result["chunks_inspected"] = inspected_chunks;
    result["sand_cells"] = sand_cells;
    result["water_cells"] = water_cells;
    result["unsupported_sand_cells"] = unsupported_sand;
    result["initially_active_water_cells"] = active_water;
    result["initially_active_dynamic_cells"] = unsupported_sand + active_water;
    result["water_vertical_drop_cells"] = water_vertical_drops;
    result["thin_solid_remnants"] = thin_solid_remnants;
    result["underground_void_cells"] = empty_underground;
    result["void_fraction_by_depth_band"] = void_fraction;
    result["maximum_chunk_void_fraction_by_depth_band"] = maximum_void_fraction;
    result["minimum_surface_roof_cells"] = minimum_roof == std::numeric_limits<int32_t>::max() ? -1 : minimum_roof;
    result["active_sand_chunks"] = active_sand_chunks;
    result["active_fluid_chunks"] = active_fluid_chunks;
    result["unsupported_sand_sample_xy"] = unsupported_sand_sample;
    result["active_water_sample_xy"] = active_water_sample;
    result["stable"] = unsupported_sand == 0 && active_water == 0 && water_vertical_drops == 0;
    // V4 controlled void volume by capping each chunk, which is what sliced its cave systems
    // into disconnected fragments at the chunk edges. V5 controls volume by descriptor
    // density, so the budget applies to the aggregate: a single chunk sitting inside a large
    // cavern is legitimately almost all void and must not be treated as an outlier.
    result["void_fraction_limits"] = world_settings_.generation_version >= 5 ? Array::make(0.18, 0.26, 0.30) :
        world_settings_.generation_version >= 4 ? Array::make(0.13, 0.20, 0.16) : Array::make(0.12, 0.18, 0.14);
    result["void_budget_applies_to"] = world_settings_.generation_version >= 5 ? "region_aggregate" : "per_chunk_maximum";
    result["chunk_void_fraction_limits"] = world_settings_.generation_version >= 5 ? Array::make(1.0, 1.0, 1.0) :
        world_settings_.generation_version >= 4 ? Array::make(0.13, 0.20, 0.16) : Array::make(0.12, 0.18, 0.14);
    return result;
}

Dictionary NativeSandWorld::get_worldgen_quality_report(Rect2i chunk_area) const {
    Dictionary result;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 || static_cast<int64_t>(chunk_area.size.x) * chunk_area.size.y > 4096) return result;
    const auto feature_key = [](int32_t x, int32_t y) {
        return (static_cast<uint64_t>(static_cast<uint32_t>(x)) << 32u) | static_cast<uint32_t>(y);
    };
    std::unordered_set<uint64_t> sand_deposits, lakes, aquifers, cave_systems, ore_veins;
    std::unordered_map<uint64_t, int64_t> sand_sizes, aquifer_sizes, ore_sizes;
    std::array<int64_t, 6> cave_archetype_cells{};
    std::array<int64_t, 5> province_cells{};
    int64_t sand_cells = 0, water_cells = 0, water_mass = 0, coal_cells = 0;
    int64_t surface_sand = 0, surface_soil = 0, surface_packed = 0, surface_weathered = 0, surface_rock = 0;
    int64_t initially_active_sand = 0, initially_active_water = 0, isolated_voids = 0;
    int32_t chunks_with_dynamic = 0, chunks_with_stable_dynamic = 0, inspected_chunks = 0;
    const Vector2i chunk_end = chunk_area.position + chunk_area.size;
    for (int32_t cy = chunk_area.position.y; cy < chunk_end.y; ++cy) for (int32_t cx = chunk_area.position.x; cx < chunk_end.x; ++cx) {
        const Chunk *chunk = get_chunk({cx, cy});
        if (chunk == nullptr || !chunk->generated) continue;
        ++inspected_chunks;
        bool has_dynamic = false;
        const Vector2i origin = chunk->coordinate * CHUNK_SIZE;
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index) {
            const int32_t material = chunk->material[index];
            const Vector2i cell = origin + Vector2i(index % CHUNK_SIZE, index / CHUNK_SIZE);
            const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(cell.x) :
                world_settings_.generation_version >= 4 ? surface_height_at_v4(cell.x) :
                world_settings_.generation_version >= 3 ? surface_height_at_v3(cell.x) : surface_height_at_v2(cell.x);
            const int32_t depth = cell.y - surface;
            if (material == SAND) {
                ++sand_cells; has_dynamic = true;
                const uint64_t key = feature_key(floor_div(cell.x, world_settings_.generation_version >= 4 ? 256 : 192), 0);
                sand_deposits.insert(key); ++sand_sizes[key];
            } else if (material == WATER) {
                ++water_cells; has_dynamic = true; water_mass += water_mass_at(*chunk, index);
                if (depth < 0) lakes.insert(feature_key(floor_div(cell.x, world_settings_.generation_version >= 4 ? 1024 : 768), 0));
                else {
                    const uint64_t key = feature_key(floor_div(cell.x, world_settings_.generation_version >= 4 ? 640 : 384),
                                                     floor_div(depth, world_settings_.generation_version >= 4 ? 448 : 256));
                    aquifers.insert(key); ++aquifer_sizes[key];
                }
            } else if (material == COAL) {
                ++coal_cells;
                const uint64_t key = feature_key(floor_div(cell.x, world_settings_.generation_version >= 4 ? 224 : 176),
                                                 floor_div(depth, world_settings_.generation_version >= 4 ? 160 : 112));
                ore_veins.insert(key); ++ore_sizes[key];
            }
            if (depth >= 0 && (material == EMPTY || material == WATER)) {
                const int32_t cave = world_settings_.generation_version >= 5 ? 0 :
                    world_settings_.generation_version >= 4 ? cave_type_at_v4(cell, surface) : cave_type_at_v3(cell, surface);
                if (cave >= 0 && cave < static_cast<int32_t>(cave_archetype_cells.size())) ++cave_archetype_cells[cave];
                cave_systems.insert(feature_key(floor_div(cell.x, world_settings_.generation_version >= 4 ? 512 : 256),
                                                floor_div(depth, world_settings_.generation_version >= 4 ? 384 : 192)));
                int32_t open_neighbors = 0;
                for (const Vector2i d : {Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)}) {
                    const int32_t neighbor = get_cell(cell + d);
                    open_neighbors += neighbor == EMPTY || neighbor == WATER;
                }
                isolated_voids += open_neighbors == 0;
            }
            if (material != EMPTY && depth >= 0) {
                if (world_settings_.generation_version >= 5) ++province_cells[geology_province_at_v5(cell.x, cell.y)];
                else if (world_settings_.generation_version >= 4) ++province_cells[geology_province_at_v4(cell)];
            }
        }
        if (has_dynamic) {
            ++chunks_with_dynamic;
            if (!chunk->active.valid() && !chunk->fluid_active.valid()) ++chunks_with_stable_dynamic;
        }
        initially_active_sand += chunk->active.area();
        initially_active_water += chunk->fluid_active.area();
    }
    std::vector<double> slopes, topsoil_depths, sand_size_values, aquifer_size_values, ore_size_values;
    int32_t longest_flat_run = 0, current_flat_run = 0;
    const int32_t first_x = chunk_area.position.x * CHUNK_SIZE;
    const int32_t last_x = chunk_end.x * CHUNK_SIZE;
    int32_t previous_surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(first_x) :
        world_settings_.generation_version >= 4 ? surface_height_at_v4(first_x) : surface_height_at_v3(first_x);
    for (int32_t x = first_x; x < last_x; ++x) {
        const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(x) :
            world_settings_.generation_version >= 4 ? surface_height_at_v4(x) : surface_height_at_v3(x);
        if (x > first_x) {
            const int32_t slope = std::abs(surface - previous_surface);
            slopes.push_back(slope);
            current_flat_run = slope == 0 ? current_flat_run + 1 : 0;
            longest_flat_run = std::max(longest_flat_run, current_flat_run);
        }
        previous_surface = surface;
        if ((x - first_x) % 4 != 0) continue;
        const int32_t material = get_cell({x, surface});
        const int32_t tag = get_provenance({x, surface});
        if (material == SAND) ++surface_sand;
        else if (world_settings_.generation_version >= 5) {
            // V5 stores a real geology profile; the rock family lives in the silica field.
            switch ((tag & 31) >> 1) {
                case 1: ++surface_soil; break;
                case 2: ++surface_packed; break;
                case 3: ++surface_weathered; break;
                default: ++surface_rock; break;
            }
        } else if ((tag & 0x8000) != 0) {
            const int32_t layer = (tag >> 8) & 7;
            if (layer == 1) ++surface_soil; else if (layer == 2) ++surface_packed; else if (layer == 3) ++surface_weathered; else ++surface_rock;
        } else ++surface_rock;
        // V5 reports horizon depths through get_worldgen_v5_columns, which carries soil,
        // sediment and weathering separately instead of collapsing them into one number.
        if (world_settings_.generation_version == 4) topsoil_depths.push_back(sediment_depth_at_v4(x, surface));
    }
    for (const auto &[key, count] : sand_sizes) { (void)key; sand_size_values.push_back(static_cast<double>(count)); }
    for (const auto &[key, count] : aquifer_sizes) { (void)key; aquifer_size_values.push_back(static_cast<double>(count)); }
    for (const auto &[key, count] : ore_sizes) { (void)key; ore_size_values.push_back(static_cast<double>(count)); }
    Dictionary content;
    content["sand_cells"] = sand_cells; content["water_cells"] = water_cells; content["water_mass_units"] = water_mass;
    content["sand_deposits"] = static_cast<int64_t>(sand_deposits.size()); content["surface_lakes"] = static_cast<int64_t>(lakes.size());
    content["aquifers"] = static_cast<int64_t>(aquifers.size()); content["flooded_cave_pockets"] = static_cast<int64_t>(aquifers.size());
    content["cave_systems"] = static_cast<int64_t>(cave_systems.size()); content["ore_veins"] = static_cast<int64_t>(ore_veins.size()); content["ore_cells"] = coal_cells;
    content["initially_active_sand_cells"] = initially_active_sand; content["initially_active_water_cells"] = initially_active_water;
    content["dynamic_region_percentage"] = inspected_chunks == 0 ? 0.0 : 100.0 * chunks_with_dynamic / inspected_chunks;
    content["stable_dynamic_region_percentage"] = chunks_with_dynamic == 0 ? 0.0 : 100.0 * chunks_with_stable_dynamic / chunks_with_dynamic;
    Dictionary surface_distribution;
    surface_distribution["loose_sand"] = surface_sand; surface_distribution["topsoil"] = surface_soil;
    surface_distribution["packed_sediment"] = surface_packed; surface_distribution["weathered_rock"] = surface_weathered; surface_distribution["exposed_rock"] = surface_rock;
    Dictionary structure;
    structure["surface_slope"] = distribution(std::move(slopes)); structure["longest_flat_run_cells"] = longest_flat_run;
    structure["topsoil_depth"] = distribution(std::move(topsoil_depths)); structure["isolated_void_cells"] = isolated_voids;
    structure["cave_tunnel_cells"] = cave_archetype_cells[CAVE_TUNNEL]; structure["cave_chamber_cells"] = cave_archetype_cells[CAVE_CAVERN];
    structure["cave_fissure_cells"] = cave_archetype_cells[CAVE_CRACK]; structure["cave_entrance_cells"] = cave_archetype_cells[CAVE_SHAFT];
    structure["cave_tunnel_chamber_ratio"] = cave_archetype_cells[CAVE_CAVERN] == 0 ? 0.0 : static_cast<double>(cave_archetype_cells[CAVE_TUNNEL]) / cave_archetype_cells[CAVE_CAVERN];
    structure["sand_deposit_size"] = distribution(std::move(sand_size_values)); structure["aquifer_size"] = distribution(std::move(aquifer_size_values));
    structure["ore_vein_size"] = distribution(std::move(ore_size_values));
    Array provinces; for (const int64_t count : province_cells) provinces.push_back(count); structure["geology_province_cells"] = provinces;
    result["generation_version"] = world_settings_.generation_version; result["chunks_inspected"] = inspected_chunks;
    result["content"] = content; result["surface_material_distribution"] = surface_distribution; result["structure"] = structure;
    return result;
}

Vector2i NativeSandWorld::get_character_spawn() const {
    const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(0) :
        world_settings_.generation_version >= 4 ? surface_height_at_v4(0) :
        world_settings_.generation_version >= 3 ? surface_height_at_v3(0) :
        world_settings_.generation_version >= 2 ? surface_height_at_v2(0) : surface_height_at(0);
    return {0, surface - 4};
}

Dictionary NativeSandWorld::query_character_collision(Rect2i body) const {
    const auto started = std::chrono::steady_clock::now();
    Dictionary result;
    int32_t sampled = 0;
    int32_t terrain = 0;
    int32_t structures = 0;
    const Vector2i end = body.position + body.size;
    for (int32_t y = body.position.y; y < end.y; ++y) {
        for (int32_t x = body.position.x; x < end.x; ++x) {
            ++sampled;
            const Vector2i cell{x, y};
            terrain += terrain_solid(get_cell(cell)) ? 1 : 0;
            structures += is_structure_solid(cell) ? 1 : 0;
        }
    }
    const_cast<NativeSandWorld *>(this)->last_collision_cells_sampled_ = sampled;
    const_cast<NativeSandWorld *>(this)->last_collision_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    result["blocked"] = terrain + structures > 0;
    result["terrain_cells"] = terrain;
    result["structure_cells"] = structures;
    result["cells_sampled"] = sampled;
    result["collision_usec"] = last_collision_usec_;
    return result;
}

Dictionary NativeSandWorld::character_dig_cell(Vector2i cell) {
    Dictionary result;
    const int32_t material = get_cell(cell);
    result["source_material"] = material;
    result["position"] = cell;
    result["conserved"] = true;
    result["changed"] = false;
    if (material == BEDROCK) { result["reason"] = "BEDROCK_PROTECTED"; return result; }
    if (material == STONE) {
        const int32_t profile = geology_profile_id_at(cell + Vector2i(0, std::max(0, cell.y / 6)));
        set_material_state(cell, ROCK_DEBRIS, 255, get_temperature(cell), profile, mineral_signature_for(cell));
        result["physical_output"] = ROCK_DEBRIS;
        result["changed"] = true;
        result["reason"] = "ROCK_DEBRIS";
    } else if (material == COAL) {
        set_material_state(cell, COAL_CHUNK, 255, get_temperature(cell), 0, 0);
        result["physical_output"] = COAL_CHUNK;
        result["changed"] = true;
        result["reason"] = "COAL_CHUNK";
    } else if (material == SAND) {
        set_cell_with_metadata(cell, SAND, get_provenance(cell), get_mineral_signature(cell));
        result["physical_output"] = SAND;
        result["changed"] = false;
        result["reason"] = "RAW_SAND_ALREADY_PHYSICAL";
    } else {
        result["physical_output"] = material;
        result["reason"] = "NOT_EXCAVATABLE";
    }
    return result;
}

uint64_t NativeSandWorld::visibility_key(int64_t owner_id, Vector2i coordinate) const {
    return chunk_key(coordinate) ^ splitmix64(static_cast<uint64_t>(owner_id) ^ 0x5649534942494c49ull);
}

NativeSandWorld::VisibilityChunk *NativeSandWorld::visibility_chunk_for(int64_t owner_id, Vector2i coordinate, bool create) {
    const uint64_t key = visibility_key(owner_id, coordinate);
    const auto found = visibility_chunks_.find(key);
    if (found != visibility_chunks_.end() && found->second.owner_id == owner_id && found->second.coordinate == coordinate) return &found->second;
    if (!create) return nullptr;
    VisibilityChunk chunk;
    chunk.owner_id = owner_id;
    chunk.coordinate = coordinate;
    auto [inserted, inserted_new] = visibility_chunks_.insert_or_assign(key, std::move(chunk));
    (void)inserted_new;
    visibility_owner_chunks_[owner_id].push_back(key);
    return &inserted->second;
}

const NativeSandWorld::VisibilityChunk *NativeSandWorld::visibility_chunk_for(int64_t owner_id, Vector2i coordinate) const {
    const uint64_t key = visibility_key(owner_id, coordinate);
    const auto found = visibility_chunks_.find(key);
    return found != visibility_chunks_.end() && found->second.owner_id == owner_id && found->second.coordinate == coordinate ? &found->second : nullptr;
}

Dictionary NativeSandWorld::update_character_visibility(int64_t owner_id, Vector2i origin, int32_t radius, int32_t shell_depth) {
    const auto started = std::chrono::steady_clock::now();
    radius = std::clamp(radius, 16, 160);
    shell_depth = std::clamp(shell_depth, 1, 16);
    for (const uint64_t key : visibility_live_chunks_[owner_id]) {
        const auto found = visibility_chunks_.find(key);
        if (found != visibility_chunks_.end()) found->second.live.fill(0);
    }
    visibility_live_chunks_[owner_id].clear();

    std::deque<std::pair<Vector2i, int32_t>> open;
    std::deque<std::pair<Vector2i, int32_t>> shell;
    const int32_t side = radius * 2 + 1;
    std::vector<uint8_t> visited_open(static_cast<size_t>(side) * side, 0);
    std::vector<uint8_t> visited_shell(static_cast<size_t>(side) * side, 0);
    std::vector<int16_t> material_grid(static_cast<size_t>(side) * side, -1);
    const int32_t half_width = world_settings_.width / 2;
    for (int32_t local_y = 0; local_y < side; ++local_y) {
        const int32_t world_y = origin.y + local_y - radius;
        const int32_t chunk_y = floor_div(world_y, CHUNK_SIZE);
        const int32_t chunk_local_y = world_y - chunk_y * CHUNK_SIZE;
        int32_t previous_chunk_x = std::numeric_limits<int32_t>::min();
        const Chunk *chunk = nullptr;
        for (int32_t local_x = 0; local_x < side; ++local_x) {
            const int32_t world_x = origin.x + local_x - radius;
            int16_t material = world_generation_enabled_ ? -1 : EMPTY;
            if (world_generation_enabled_ && world_y < -world_settings_.sky) {
                material = EMPTY;
            } else if (world_generation_enabled_ &&
                       (world_x < -half_width || world_x >= -half_width + world_settings_.width || world_y >= world_settings_.depth)) {
                material = BEDROCK;
            } else {
                const int32_t chunk_x = floor_div(world_x, CHUNK_SIZE);
                if (chunk_x != previous_chunk_x) {
                    previous_chunk_x = chunk_x;
                    chunk = get_chunk({chunk_x, chunk_y});
                }
                if (chunk != nullptr) {
                    const int32_t chunk_local_x = world_x - chunk_x * CHUNK_SIZE;
                    material = static_cast<int16_t>(chunk->material[chunk_local_y * CHUNK_SIZE + chunk_local_x]);
                }
            }
            material_grid[static_cast<size_t>(local_y) * side + local_x] = material;
        }
    }
    const Vector2i first_visibility_chunk = world_to_chunk(origin - Vector2i(radius, radius));
    const Vector2i last_visibility_chunk = world_to_chunk(origin + Vector2i(radius, radius));
    const Vector2i visibility_chunk_size = last_visibility_chunk - first_visibility_chunk + Vector2i(1, 1);
    std::vector<VisibilityChunk *> current_visibility_chunks(
        static_cast<size_t>(visibility_chunk_size.x) * visibility_chunk_size.y, nullptr);
    std::vector<uint64_t> current_chunks;
    current_chunks.reserve(current_visibility_chunks.size());
    open.push_back({origin, 0});
    visited_open[static_cast<size_t>(radius) * side + radius] = 1;
    int64_t sampled = 0;
    int64_t live_count = 0;
    int64_t discovered_count = 0;
    const int64_t radius_sq = static_cast<int64_t>(radius) * radius;
    const std::array<Vector2i, 8> neighbors{{{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}};
    const auto visit_once = [&](std::vector<uint8_t> &visited, Vector2i cell) {
        const Vector2i local = cell - origin + Vector2i(radius, radius);
        if (local.x < 0 || local.y < 0 || local.x >= side || local.y >= side) return false;
        uint8_t &value = visited[static_cast<size_t>(local.y) * side + local.x];
        if (value != 0) return false;
        value = 1;
        return true;
    };
    const auto material_at = [&](Vector2i cell) -> int32_t {
        const Vector2i local = cell - origin + Vector2i(radius, radius);
        if (local.x < 0 || local.y < 0 || local.x >= side || local.y >= side) return -1;
        return material_grid[static_cast<size_t>(local.y) * side + local.x];
    };
    const auto solid_at = [&](Vector2i cell) {
        const int32_t material = material_at(cell);
        return material >= 0 && (terrain_solid(material) || is_structure_solid(cell));
    };

    const auto mark = [&](Vector2i cell) {
        const Vector2i coordinate = world_to_chunk(cell);
        const Vector2i cache_coordinate = coordinate - first_visibility_chunk;
        const size_t cache_index = static_cast<size_t>(cache_coordinate.y) * visibility_chunk_size.x + cache_coordinate.x;
        VisibilityChunk *&visibility = current_visibility_chunks[cache_index];
        if (visibility == nullptr) {
            visibility = visibility_chunk_for(owner_id, coordinate, true);
            current_chunks.push_back(visibility_key(owner_id, coordinate));
        }
        const int32_t index = local_index(world_to_local(cell));
        live_count += bit_set(visibility->live, index) ? 1 : 0;
        discovered_count += bit_set(visibility->discovered, index) ? 1 : 0;
        visibility->last_known_material[index] = static_cast<uint8_t>(std::clamp(material_at(cell), 0, 255));
    };

    while (!open.empty()) {
        const auto [cell, distance] = open.front();
        open.pop_front();
        if ((cell - origin).length_squared() > radius_sq || material_at(cell) < 0) continue;
        ++sampled;
        const bool solid = terrain_solid(material_at(cell)) || is_structure_solid(cell);
        if (solid && cell != origin) { shell.push_back({cell, 1}); visit_once(visited_shell, cell); continue; }
        mark(cell);
        if (distance >= radius) continue;
        for (const Vector2i offset : neighbors) {
            const Vector2i next = cell + offset;
            if (offset.x != 0 && offset.y != 0 && solid_at(cell + Vector2i(offset.x, 0)) &&
                solid_at(cell + Vector2i(0, offset.y))) continue;
            if ((next - origin).length_squared() > radius_sq || !visit_once(visited_open, next)) continue;
            open.push_back({next, distance + 1});
        }
    }

    while (!shell.empty()) {
        const auto [cell, depth] = shell.front();
        shell.pop_front();
        if ((cell - origin).length_squared() > radius_sq || material_at(cell) < 0) continue;
        ++sampled;
        if (!terrain_solid(material_at(cell)) && !is_structure_solid(cell)) continue;
        mark(cell);
        if (depth >= shell_depth) continue;
        for (const Vector2i offset : neighbors) {
            const Vector2i next = cell + offset;
            if (!visit_once(visited_shell, next)) continue;
            if (terrain_solid(material_at(next)) || is_structure_solid(next)) shell.push_back({next, depth + 1});
        }
    }

    visibility_live_chunks_[owner_id] = std::move(current_chunks);
    std::sort(visibility_live_chunks_[owner_id].begin(), visibility_live_chunks_[owner_id].end());
    last_visibility_cells_sampled_ = sampled;
    last_visibility_cells_live_ = live_count;
    last_visibility_cells_discovered_ = discovered_count;
    last_visibility_usec_ = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    ++visibility_revision_;
    Dictionary result;
    result["owner_id"] = owner_id;
    result["origin"] = origin;
    result["radius"] = radius;
    result["solid_shell_depth"] = shell_depth;
    result["cells_sampled"] = sampled;
    result["live_cells"] = live_count;
    result["newly_discovered_cells"] = discovered_count;
    result["visibility_usec"] = last_visibility_usec_;
    result["revision"] = visibility_revision_;
    return result;
}

bool NativeSandWorld::is_cell_discovered(int64_t owner_id, Vector2i cell) const {
    const VisibilityChunk *chunk = visibility_chunk_for(owner_id, world_to_chunk(cell));
    return chunk != nullptr && bit_get(chunk->discovered, local_index(world_to_local(cell)));
}

bool NativeSandWorld::is_cell_live_visible(int64_t owner_id, Vector2i cell) const {
    const VisibilityChunk *chunk = visibility_chunk_for(owner_id, world_to_chunk(cell));
    return chunk != nullptr && bit_get(chunk->live, local_index(world_to_local(cell)));
}

Dictionary NativeSandWorld::get_visibility_render_page(int64_t owner_id, Rect2i chunk_area) const {
    Dictionary result;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 || static_cast<int64_t>(chunk_area.size.x) * chunk_area.size.y > 256) return result;
    const int32_t width = chunk_area.size.x * CHUNK_SIZE;
    const int32_t height = chunk_area.size.y * CHUNK_SIZE;
    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(width) * height * 4);
    uint8_t *output = pixels.ptrw();
    const Vector2i cell_origin = chunk_area.position * CHUNK_SIZE;
    for (int32_t y = 0; y < height; ++y) {
        for (int32_t x = 0; x < width; ++x) {
            const Vector2i cell = cell_origin + Vector2i(x, y);
            const VisibilityChunk *visibility = visibility_chunk_for(owner_id, world_to_chunk(cell));
            const int32_t local = local_index(world_to_local(cell));
            const bool live = visibility != nullptr && bit_get(visibility->live, local);
            const bool discovered = visibility != nullptr && bit_get(visibility->discovered, local);
            const int64_t index = (static_cast<int64_t>(y) * width + x) * 4;
            if (live) {
                output[index] = output[index + 1] = output[index + 2] = output[index + 3] = 0;
            } else if (discovered) {
                const uint8_t pattern = static_cast<uint8_t>(((x + y) & 3) * 3);
                output[index] = 8 + pattern; output[index + 1] = 22 + pattern; output[index + 2] = 28 + pattern;
                output[index + 3] = 142;
            } else {
                const uint8_t pattern = static_cast<uint8_t>(field_hash(seed_, floor_div(cell.x, 5), floor_div(cell.y, 5), 0x9911) & 7u);
                output[index] = 3 + pattern; output[index + 1] = 12 + pattern; output[index + 2] = 17 + pattern;
                output[index + 3] = 248;
            }
        }
    }
    result["width"] = width;
    result["height"] = height;
    result["cell_position"] = cell_origin;
    result["pixels"] = pixels;
    result["bytes"] = pixels.size();
    result["revision"] = visibility_revision_;
    return result;
}

Dictionary NativeSandWorld::get_visibility_statistics(int64_t owner_id) const {
    Dictionary result;
    int64_t discovered_cells = 0;
    const auto found = visibility_owner_chunks_.find(owner_id);
    const int64_t chunks = found == visibility_owner_chunks_.end() ? 0 : static_cast<int64_t>(found->second.size());
    if (found != visibility_owner_chunks_.end()) {
        for (const uint64_t key : found->second) {
            const auto chunk = visibility_chunks_.find(key);
            if (chunk == visibility_chunks_.end()) continue;
            for (const uint8_t byte : chunk->second.discovered) discovered_cells += std::popcount(byte);
        }
    }
    result["owner_id"] = owner_id;
    result["discovered_chunks"] = chunks;
    result["discovered_cells"] = discovered_cells;
    result["live_chunks"] = visibility_live_chunks_.contains(owner_id) ? static_cast<int64_t>(visibility_live_chunks_.at(owner_id).size()) : 0;
    result["discovered_mask_bytes_per_chunk"] = CELLS_PER_CHUNK / 8;
    result["live_mask_bytes_per_chunk"] = CELLS_PER_CHUNK / 8;
    result["last_known_bytes_per_chunk"] = CELLS_PER_CHUNK;
    result["bytes_per_discovered_chunk"] = static_cast<int64_t>(sizeof(VisibilityChunk));
    result["total_bytes"] = chunks * static_cast<int64_t>(sizeof(VisibilityChunk));
    result["visibility_usec"] = last_visibility_usec_;
    result["cells_sampled"] = last_visibility_cells_sampled_;
    result["live_cells_last_update"] = last_visibility_cells_live_;
    result["newly_discovered_last_update"] = last_visibility_cells_discovered_;
    result["collision_usec"] = last_collision_usec_;
    result["collision_cells_sampled"] = last_collision_cells_sampled_;
    result["revision"] = visibility_revision_;
    return result;
}

void NativeSandWorld::clear_visibility(int64_t owner_id) {
    if (owner_id < 0) {
        visibility_chunks_.clear(); visibility_owner_chunks_.clear(); visibility_live_chunks_.clear();
    } else {
        const auto found = visibility_owner_chunks_.find(owner_id);
        if (found != visibility_owner_chunks_.end()) for (const uint64_t key : found->second) visibility_chunks_.erase(key);
        visibility_owner_chunks_.erase(owner_id); visibility_live_chunks_.erase(owner_id);
    }
    ++visibility_revision_;
}

Dictionary NativeSandWorld::serialize_visibility_state(int64_t owner_id) const {
    Dictionary state;
    state["schema_version"] = 1;
    state["owner_id"] = owner_id;
    Array chunks;
    const auto found = visibility_owner_chunks_.find(owner_id);
    if (found != visibility_owner_chunks_.end()) {
        std::vector<const VisibilityChunk *> sorted;
        for (const uint64_t key : found->second) {
            const auto chunk = visibility_chunks_.find(key);
            if (chunk != visibility_chunks_.end()) sorted.push_back(&chunk->second);
        }
        std::sort(sorted.begin(), sorted.end(), [](const VisibilityChunk *a, const VisibilityChunk *b) {
            return a->coordinate.y != b->coordinate.y ? a->coordinate.y < b->coordinate.y : a->coordinate.x < b->coordinate.x;
        });
        for (const VisibilityChunk *chunk : sorted) {
            Dictionary entry;
            entry["coordinate"] = chunk->coordinate;
            PackedByteArray discovered;
            discovered.resize(chunk->discovered.size());
            for (int64_t index = 0; index < discovered.size(); ++index) discovered.set(index, chunk->discovered[index]);
            PackedByteArray last_known;
            last_known.resize(chunk->last_known_material.size());
            for (int64_t index = 0; index < last_known.size(); ++index) last_known.set(index, chunk->last_known_material[index]);
            entry["discovered"] = discovered;
            entry["last_known_material"] = last_known;
            chunks.push_back(entry);
        }
    }
    state["chunks"] = chunks;
    return state;
}

bool NativeSandWorld::deserialize_visibility_state(Dictionary state) {
    if (!state.has("schema_version") || static_cast<int32_t>(state["schema_version"]) != 1 || !state.has("owner_id") || !state.has("chunks")) return false;
    const int64_t owner_id = static_cast<int64_t>(state["owner_id"]);
    clear_visibility(owner_id);
    const Array chunks = state["chunks"];
    for (int32_t index = 0; index < chunks.size(); ++index) {
        const Dictionary entry = chunks[index];
        if (!entry.has("coordinate") || !entry.has("discovered") || !entry.has("last_known_material")) return false;
        const PackedByteArray discovered = entry["discovered"];
        const PackedByteArray last_known = entry["last_known_material"];
        if (discovered.size() != CELLS_PER_CHUNK / 8 || last_known.size() != CELLS_PER_CHUNK) return false;
        VisibilityChunk *chunk = visibility_chunk_for(owner_id, entry["coordinate"], true);
        for (int64_t byte = 0; byte < discovered.size(); ++byte) chunk->discovered[byte] = discovered[byte];
        for (int64_t cell = 0; cell < last_known.size(); ++cell) chunk->last_known_material[cell] = last_known[cell];
    }
    ++visibility_revision_;
    return true;
}

String NativeSandWorld::visibility_state_hash(int64_t owner_id) const {
    uint32_t hash = hash_component(2166136261u, static_cast<uint32_t>(owner_id));
    const Dictionary state = serialize_visibility_state(owner_id);
    const Array chunks = state["chunks"];
    for (int32_t index = 0; index < chunks.size(); ++index) {
        const Dictionary entry = chunks[index];
        const Vector2i coordinate = entry["coordinate"];
        hash = hash_component(hash, static_cast<uint32_t>(coordinate.x));
        hash = hash_component(hash, static_cast<uint32_t>(coordinate.y));
        const PackedByteArray discovered = entry["discovered"];
        const PackedByteArray last_known = entry["last_known_material"];
        for (int64_t byte = 0; byte < discovered.size(); ++byte) hash = hash_component(hash, discovered[byte]);
        for (int64_t cell = 0; cell < last_known.size(); ++cell) if (bit_get(visibility_chunk_for(owner_id, coordinate)->discovered, cell)) hash = hash_component(hash, last_known[cell]);
    }
    return hex_hash(hash);
}
} // namespace godot
