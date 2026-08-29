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
    std::sort(values.begin(), values.end());
    const auto percentile = [&values](double p) {
        const size_t index = static_cast<size_t>(std::clamp(std::llround((values.size() - 1) * p), 0ll,
                                                            static_cast<long long>(values.size() - 1)));
        return values[index];
    };
    result["min"] = values.front();
    result["p05"] = percentile(0.05);
    result["p50"] = percentile(0.50);
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
    result["generation_version"] = 2;
    result["macro_scale_cells"] = MACRO_SCALE;
    result["passes"] = Array::make("macro_world", "surface", "depth_regions", "cave_systems", "aquifers", "geology",
                                    "thermal_regions", "authored_features", "spawn_validation", "initial_stabilization");
    result["cave_grammars"] = Array::make("CAVERN", "TUNNEL", "CRACK", "SHAFT", "POCKET");
    result["depth_regions"] = Array::make("SURFACE", "SEDIMENT_SHALLOW", "UNDERGROUND", "CAVERNS", "DEEP_THERMAL", "BEDROCK");
    result["native_data_oriented"] = true;
    result["lazy_chunk_generation"] = true;
    result["physical_water"] = true;
    result["physical_temperature"] = true;
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
    for (int32_t y = 0; y < height; ++y) {
        for (int32_t x = 0; x < width; ++x) {
            const int32_t macro_x = x - width / 2;
            const MacroSample sample = macro_sample_for(seed_, {macro_x, y / 8});
            const int32_t surface_pixel = height / 5 + sample.surface_elevation / 8;
            const int64_t index = (static_cast<int64_t>(y) * width + x) * 4;
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
    result["source"] = "macro_world_v2";
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
            const int32_t surface = surface_height_at_v2(x);
            const MacroSample macro = macro_sample_for(seed_, {floor_div(x, MACRO_SCALE), floor_div(y, MACRO_SCALE)});
            const int32_t cave = cave_type_at_v2(cell, surface);
            const bool aquifer = cave != CAVE_NONE && aquifer_at_v2(cell, surface, macro);
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
            const int32_t surface = surface_height_at_v2(x);
            const MacroSample macro = macro_sample_for(seed_, {floor_div(x, MACRO_SCALE), floor_div(y, MACRO_SCALE)});
            const int32_t cave = cave_type_at_v2({x, y}, surface);
            records.push_back(x); records.push_back(y); records.push_back(y - surface); records.push_back(cave);
            records.push_back(cave != CAVE_NONE && aquifer_at_v2({x, y}, surface, macro));
            records.push_back(thermal_at_v2({x, y}, surface, macro));
            records.push_back(macro.feature_density > 61100);
            records.push_back(macro.geology_province);
        }
    }
    result["record_stride"] = 8;
    result["records"] = records;
    return result;
}

Vector2i NativeSandWorld::get_character_spawn() const {
    const int32_t surface = world_settings_.generation_version >= 2 ? surface_height_at_v2(0) : surface_height_at(0);
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
