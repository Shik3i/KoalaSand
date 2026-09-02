// KoalaSand world generation V5 - inspection, statistics, and debug artefacts.
//
// None of this runs in the live game loop. It exists so that generator quality can be
// measured rather than eyeballed: real connected-component cave topology, climate-space
// coverage, per-seed structural distributions, and deterministic debug field renders.
#include "native_sand_world.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>
#include <array>
#include <vector>

namespace godot {
namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t WATER = 3;
constexpr int32_t COAL = 4;
constexpr int32_t SAND = 2;

constexpr uint64_t V5_TAG = 0x0000563500000000ull;

inline uint64_t v5_mix(uint64_t value) {
    value += 0x9e3779b97f4a7c15ull;
    value = (value ^ (value >> 30u)) * 0xbf58476d1ce4e5b9ull;
    value = (value ^ (value >> 27u)) * 0x94d049bb133111ebull;
    return value ^ (value >> 31u);
}

inline uint32_t v5_hash(int64_t seed, uint32_t domain, int32_t x, int32_t y, uint32_t salt) {
    uint64_t value = static_cast<uint64_t>(seed) ^ V5_TAG;
    value = v5_mix(value ^ (static_cast<uint64_t>(static_cast<uint32_t>(x)) * 0xd6e8feb86659fd93ull));
    value = v5_mix(value ^ (static_cast<uint64_t>(static_cast<uint32_t>(y)) * 0xa0761d6478bd642full));
    value ^= (static_cast<uint64_t>(domain) << 40u) ^ (static_cast<uint64_t>(salt) << 12u);
    return static_cast<uint32_t>(v5_mix(value) >> 32u);
}

inline double v5_unit(int64_t seed, uint32_t domain, int32_t x, int32_t y, uint32_t salt) {
    return static_cast<double>(v5_hash(seed, domain, x, y, salt)) * (1.0 / 4294967295.0);
}

Dictionary v5_distribution(std::vector<double> values) {
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
    result["p10"] = percentile(0.10);
    result["p50"] = percentile(0.50);
    result["p90"] = percentile(0.90);
    result["p99"] = percentile(0.99);
    result["max"] = values.back();
    return result;
}

struct V5StructureKind {
    const char *name;
    int32_t region;          // candidate region size in cells
    int32_t separation;      // minimum margin from the region edge
    int32_t minimum_depth;
    int32_t maximum_depth;
    uint32_t salt;
    double rarity;
};

const V5StructureKind V5_STRUCTURES[3] = {
    {"surface_ruin", 768, 96, -14, 26, 0x1001u, 0.42},
    {"underground_facility", 1088, 128, 180, 1400, 0x1003u, 0.34},
    {"deep_vault", 2176, 256, 1200, 3400, 0x1005u, 0.22},
};

struct V5SceneKind {
    const char *name;
    int32_t minimum_depth;
    int32_t maximum_depth;
    int32_t footprint;
    uint32_t salt;
    double weight;
};

const V5SceneKind V5_SCENES[3] = {
    {"geode_pocket", 320, 3000, 26, 0x2001u, 1.00},
    {"collapsed_arch", 260, 2600, 54, 0x2003u, 0.80},
    {"mineral_exposure", 180, 2200, 40, 0x2005u, 0.90},
};

const char *V5_ARCHETYPE_NAMES[6] = {"none", "tunnel", "chamber", "fissure", "cavern", "entrance"};

// Debug palettes. Development artefacts only; these never reach player UI.
inline void write_rgb(uint8_t *out, int32_t r, int32_t g, int32_t b) {
    out[0] = static_cast<uint8_t>(std::clamp(r, 0, 255));
    out[1] = static_cast<uint8_t>(std::clamp(g, 0, 255));
    out[2] = static_cast<uint8_t>(std::clamp(b, 0, 255));
    out[3] = 255;
}

const int32_t BIOME_COLOURS[5][3] = {{92, 138, 76}, {214, 178, 92}, {132, 134, 142}, {58, 114, 122}, {166, 104, 68}};
const int32_t PROVINCE_COLOURS[5][3] = {{198, 168, 112}, {148, 190, 196}, {188, 142, 168}, {206, 118, 92}, {112, 122, 176}};
const int32_t ARCHETYPE_COLOURS[6][3] = {{22, 26, 32}, {236, 196, 84}, {104, 208, 232}, {236, 118, 108}, {170, 128, 236}, {124, 236, 148}};
} // namespace

// ---------------------------------------------------------------------------------------
// Architecture and profile description
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_worldgen_v5_architecture() const {
    Dictionary result;
    result["generation_version"] = world_settings_.generation_version;
    result["is_v5"] = world_settings_.generation_version >= 5;
    result["passes"] = Array::make("seed_domains", "climate_fields", "macro_terrain", "surface_profile",
                                   "geology_provinces", "stratigraphy", "base_geology", "cave_systems",
                                   "hydrology", "sediment", "resources", "natural_scenes", "structure_candidates",
                                   "vegetation", "stability_validation");
    result["seed_domains"] = Array::make("warp", "terrain", "terrace", "climate", "biome_dither", "province",
                                         "strata", "unconformity", "cave_coarse", "cave_fine", "tunnel",
                                         "chamber", "fissure", "cavern", "entrance", "lake", "aquifer",
                                         "table_warp", "sediment", "ore_coal", "ore_iron", "ore_gold",
                                         "structure", "scene", "vegetation", "start");
    Array archetypes;
    for (const char *name : V5_ARCHETYPE_NAMES) archetypes.push_back(String(name));
    result["cave_archetypes"] = archetypes;
    Dictionary scales;
    scales["simulation_chunk"] = CHUNK_SIZE;
    scales["generation_padding"] = V5_PAD;
    scales["cave_coarse_grid"] = Vector2i(448, 352);
    scales["cave_fine_grid"] = Vector2i(206, 166);
    scales["cave_reach"] = Vector2i(290, 148);
    scales["coal_grid"] = Vector2i(236, 188);
    scales["province_site"] = Vector2i(632, 424);
    scales["aquifer_region"] = 1408;
    scales["lake_region"] = 704;
    scales["terrain_bands"] = Array::make(4096, 2560, 1792, 448, 176, 52);
    result["macro_scales"] = scales;
    result["chunk_order_independent_descriptors"] = true;
    result["lazy_chunk_generation"] = true;
    result["surface_biome_separate_from_geology"] = true;
    result["depth_below_local_surface"] = true;
    result["fractional_liquid_levels"] = true;
    result["composition_provenance_on_stone"] = true;
    result["void_fraction_limits"] = Array::make(0.30, 0.34, 0.28);
    result["generator_guarantees"] = Array::make("RAW_SAND_AT_SPAWN", "EARLY_COAL_SEAM", "EARLY_CAVE_ROUTE",
                                                 "REACHABLE_WATER", "PROTECTED_BUILD_CORE");
    return result;
}

Dictionary NativeSandWorld::get_worldgen_v5_profiles() const {
    Dictionary result;
    Array biomes;
    for (int32_t index = 0; index < v5_biome_count(); ++index) {
        const V5BiomeProfile &profile = v5_biome_profile(index);
        Dictionary item;
        item["index"] = index;
        item["name"] = String(profile.name);
        item["climate_centre"] = Array::make(profile.temperature, profile.moisture, profile.ruggedness, profile.basinness);
        item["climate_weights"] = Array::make(profile.weight_temperature, profile.weight_moisture,
                                              profile.weight_ruggedness, profile.weight_basinness);
        item["soil_depth"] = Array::make(profile.soil_min, profile.soil_max);
        item["sediment_depth"] = Array::make(profile.sediment_min, profile.sediment_max);
        item["surface_sand"] = profile.surface_sand;
        item["lake_bias"] = profile.lake_bias;
        item["vegetation"] = profile.vegetation;
        biomes.push_back(item);
    }
    Array provinces;
    for (int32_t index = 0; index < v5_province_count(); ++index) {
        const V5ProvinceProfile &profile = v5_province_profile(index);
        Dictionary item;
        item["index"] = index;
        item["name"] = String(profile.name);
        item["weight"] = profile.weight;
        item["cave_density"] = profile.cave_density;
        item["horizontal_bias"] = profile.horizontal_bias;
        item["archetype_weights"] = Array::make(profile.tunnel_weight, profile.chamber_weight,
                                                profile.fissure_weight, profile.cavern_weight);
        item["permeability"] = profile.permeability;
        item["coal_richness"] = profile.coal_richness;
        item["iron_richness"] = profile.iron_richness;
        item["gold_richness"] = profile.gold_richness;
        item["bed_period"] = profile.bed_period;
        item["bed_thickness"] = profile.bed_thickness;
        Array sequence;
        for (int32_t bed = 0; bed < profile.bed_period && bed < 8; ++bed)
            sequence.push_back(String(v5_rock_profile(profile.rock_sequence[bed]).name));
        item["rock_sequence"] = sequence;
        provinces.push_back(item);
    }
    Array rocks;
    for (int32_t index = 0; index < v5_rock_count(); ++index) {
        const V5RockProfile &profile = v5_rock_profile(index);
        Dictionary item;
        item["index"] = index;
        item["name"] = String(profile.name);
        item["quantised_composition"] = Array::make(profile.silica, profile.iron, profile.heavy, profile.gold);
        item["family"] = profile.silica >> 1;
        rocks.push_back(item);
    }
    Array structures;
    for (const V5StructureKind &kind : V5_STRUCTURES) {
        Dictionary item;
        item["name"] = String(kind.name);
        item["region_cells"] = kind.region;
        item["separation_cells"] = kind.separation;
        item["depth_range"] = Array::make(kind.minimum_depth, kind.maximum_depth);
        item["rarity"] = kind.rarity;
        structures.push_back(item);
    }
    Array scenes;
    for (const V5SceneKind &kind : V5_SCENES) {
        Dictionary item;
        item["name"] = String(kind.name);
        item["depth_range"] = Array::make(kind.minimum_depth, kind.maximum_depth);
        item["footprint"] = kind.footprint;
        item["weight"] = kind.weight;
        scenes.push_back(item);
    }
    result["biomes"] = biomes;
    result["provinces"] = provinces;
    result["rocks"] = rocks;
    result["structure_kinds"] = structures;
    result["scene_kinds"] = scenes;
    return result;
}

// ---------------------------------------------------------------------------------------
// Column and cell inspection: "why is this cell here?"
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_worldgen_v5_columns(int32_t first_x, int32_t count, int32_t stride) const {
    Dictionary result;
    count = std::clamp(count, 1, 262144);
    stride = std::clamp(stride, 1, 4096);
    PackedInt32Array surface, biome, province, soil, sediment, weathered, sand, lake;
    PackedFloat32Array temperature, moisture, ruggedness, basinness;
    for (int32_t index = 0; index < count; ++index) {
        const int32_t world_x = first_x + index * stride;
        const V5Climate climate = climate_at_v5(world_x);
        V5Context probe;
        probe.origin = Vector2i(world_x, 0);
        probe.padded_origin = probe.origin;
        v5_build_bed_cumulative(probe);
        v5_prepare_lakes(probe);
        V5Column column;
        v5_fill_column(probe, column, world_x, surface_height_at_v5(world_x) + 320);
        surface.push_back(column.surface);
        biome.push_back(column.biome);
        province.push_back(column.province);
        soil.push_back(column.soil);
        sediment.push_back(column.sediment);
        weathered.push_back(column.weathered);
        sand.push_back(column.sand_depth);
        lake.push_back(column.lake_mass > 0 ? column.lake_level : 1);
        temperature.push_back(static_cast<float>(climate.temperature));
        moisture.push_back(static_cast<float>(climate.moisture));
        ruggedness.push_back(static_cast<float>(climate.ruggedness));
        basinness.push_back(static_cast<float>(climate.basinness));
    }
    result["first_x"] = first_x;
    result["count"] = count;
    result["stride"] = stride;
    result["surface"] = surface;
    result["biome"] = biome;
    result["province"] = province;
    result["soil_depth"] = soil;
    result["sediment_depth"] = sediment;
    result["weathering_depth"] = weathered;
    result["sand_depth"] = sand;
    result["lake_level"] = lake;
    result["temperature"] = temperature;
    result["moisture"] = moisture;
    result["ruggedness"] = ruggedness;
    result["basinness"] = basinness;
    return result;
}

Dictionary NativeSandWorld::get_worldgen_v5_cell(Vector2i world_cell) const {
    Dictionary result;
    const V5Climate climate = climate_at_v5(world_cell.x);
    V5Context probe;
    probe.origin = Vector2i(world_cell.x, world_cell.y);
    probe.padded_origin = probe.origin;
    v5_build_bed_cumulative(probe);
    v5_prepare_lakes(probe);
    V5Column column;
    v5_fill_column(probe, column, world_cell.x, world_cell.y);
    const int32_t depth = world_cell.y - column.surface;

    int32_t bed = column.bed_first + column.bed_stored;
    for (int32_t offset = 0; offset < column.bed_stored; ++offset) {
        if (world_cell.y < column.bed_y[offset]) { bed = column.bed_first + offset; break; }
    }
    const int32_t cell_province = geology_province_at_v5(world_cell.x, world_cell.y);
    int32_t rock = v5_bed_rock_at(cell_province, bed, world_cell.y);
    String horizon = "bedrock";
    if (depth < 0) horizon = "air";
    else if (depth < column.sand_depth) { horizon = "loose_sand"; rock = 8; }
    else if (depth < column.soil) { horizon = "topsoil"; rock = 8; }
    else if (depth < column.sediment) { horizon = "packed_sediment"; rock = 9; }
    else if (depth < column.weathered) { horizon = "weathered_rock"; rock = 10; }

    int32_t local = 0;
    const int32_t region = v5_table_region(world_cell.x, world_cell.y, local);
    const int32_t table = v5_region_table_mu(region);

    result["cell"] = world_cell;
    result["surface_y"] = column.surface;
    result["depth_below_surface"] = depth;
    result["biome"] = String(v5_biome_profile(column.biome).name);
    result["biome_index"] = column.biome;
    result["climate"] = Array::make(climate.temperature, climate.moisture, climate.ruggedness, climate.basinness);
    result["biome_margin"] = climate.biome_margin;
    result["province"] = String(v5_province_profile(column.province).name);
    result["province_index"] = column.province;
    result["horizon"] = horizon;
    result["bed_index"] = bed;
    result["rock"] = String(v5_rock_profile(rock).name);
    result["cave_roof_depth"] = v5_cave_roof(column);
    result["aquifer_region"] = region;
    result["water_table_y"] = table >= (1 << 28) ? -1 : table / 255;
    result["water_table_dry"] = table >= (1 << 28);
    result["geology_profile_id"] = v5_stone_profile(rock, world_cell.x, world_cell.y, std::max(0, depth), column.province);
    result["lake_level"] = column.lake_mass > 0 ? column.lake_level : 1;

    // Feature provenance. Generating the containing chunk is far too expensive for the live
    // game, which is exactly why this lives in the inspection API and stores nothing per cell.
    const Vector2i coordinate = world_to_chunk(world_cell);
    std::unique_ptr<GeneratedChunk> chunk = generate_chunk_data_v5(coordinate);
    if (chunk != nullptr) {
        const int32_t index = local_index(world_to_local(world_cell));
        const int32_t material = chunk->material[index];
        result["material"] = material;
        result["material_amount"] = chunk->material_amount == nullptr
            ? (material == 0 ? 0 : 255) : static_cast<int32_t>((*chunk->material_amount)[index]);
        result["cell_provenance"] = chunk->provenance[index];
        result["is_cave_void"] = material == 0 || material == WATER;
        result["is_ore"] = material == COAL;
        result["is_sediment"] = material == SAND;
    }
    return result;
}

// ---------------------------------------------------------------------------------------
// Cave connected-component topology.
//
// P0.5 reported real topology analysis as missing; V4's "cave systems" number was a count of
// descriptor grid keys, which cannot tell three believable networks apart from forty
// disconnected slits.
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_cave_topology_report(Rect2i chunk_area) const {
    Dictionary result;
    if (chunk_area.size.x <= 0 || chunk_area.size.y <= 0 ||
        static_cast<int64_t>(chunk_area.size.x) * chunk_area.size.y > 512) return result;

    const int32_t width = chunk_area.size.x * CHUNK_SIZE;
    const int32_t height = chunk_area.size.y * CHUNK_SIZE;
    const Vector2i first = chunk_area.position * CHUNK_SIZE;
    std::vector<uint8_t> open(static_cast<size_t>(width) * height, 0);
    std::vector<int32_t> label(static_cast<size_t>(width) * height, -1);

    int64_t void_cells = 0;
    int64_t water_cells = 0;
    for (int32_t y = 0; y < height; ++y) {
        for (int32_t x = 0; x < width; ++x) {
            const Vector2i cell{first.x + x, first.y + y};
            const int32_t material = get_cell(cell);
            if (material != EMPTY && material != WATER) continue;
            const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(cell.x)
                                  : world_settings_.generation_version >= 4 ? surface_height_at_v4(cell.x)
                                                                            : surface_height_at_v3(cell.x);
            if (cell.y < surface) continue;      // sky and surface water are not cave void
            open[static_cast<size_t>(y) * width + x] = 1;
            ++void_cells;
            water_cells += material == WATER;
        }
    }

    std::vector<double> sizes, widths, vertical_extent, horizontal_extent;
    std::vector<int32_t> stack;
    int64_t largest = 0;
    int64_t surface_connected = 0;
    int64_t dead_ends = 0;
    int64_t junctions = 0;
    int64_t chamber_cells = 0;
    int64_t tunnel_cells = 0;
    int64_t isolated_small = 0;
    int32_t components = 0;

    for (int32_t start = 0; start < width * height; ++start) {
        if (open[start] == 0 || label[start] >= 0) continue;
        const int32_t component = components++;
        stack.clear();
        stack.push_back(start);
        label[start] = component;
        int64_t area = 0;
        int32_t min_x = width, max_x = -1, min_y = height, max_y = -1;
        bool breaches = false;
        while (!stack.empty()) {
            const int32_t index = stack.back();
            stack.pop_back();
            const int32_t x = index % width;
            const int32_t y = index / width;
            ++area;
            min_x = std::min(min_x, x); max_x = std::max(max_x, x);
            min_y = std::min(min_y, y); max_y = std::max(max_y, y);
            const int32_t surface = world_settings_.generation_version >= 5 ? surface_height_at_v5(first.x + x)
                                  : world_settings_.generation_version >= 4 ? surface_height_at_v4(first.x + x)
                                                                            : surface_height_at_v3(first.x + x);
            if (first.y + y - surface <= 2) breaches = true;
            int32_t degree = 0;
            const int32_t neighbours[4] = {x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1,
                                           y > 0 ? index - width : -1, y + 1 < height ? index + width : -1};
            for (const int32_t neighbour : neighbours) {
                if (neighbour < 0 || open[neighbour] == 0) continue;
                ++degree;
                if (label[neighbour] >= 0) continue;
                label[neighbour] = component;
                stack.push_back(neighbour);
            }
            if (degree == 1) ++dead_ends;
            else if (degree >= 3) ++junctions;
        }
        sizes.push_back(static_cast<double>(area));
        vertical_extent.push_back(static_cast<double>(max_y - min_y + 1));
        horizontal_extent.push_back(static_cast<double>(max_x - min_x + 1));
        largest = std::max(largest, area);
        surface_connected += breaches ? 1 : 0;
        isolated_small += area <= 6 ? 1 : 0;
    }

    // Passage width from maximal horizontal runs; wide runs read as chamber, narrow as tunnel.
    for (int32_t y = 0; y < height; ++y) {
        int32_t run = 0;
        for (int32_t x = 0; x <= width; ++x) {
            const bool inside = x < width && open[static_cast<size_t>(y) * width + x] != 0;
            if (inside) { ++run; continue; }
            if (run > 0) {
                widths.push_back(static_cast<double>(run));
                if (run >= 11) chamber_cells += run; else tunnel_cells += run;
                run = 0;
            }
        }
    }

    result["generation_version"] = world_settings_.generation_version;
    result["sampled_cells"] = static_cast<int64_t>(width) * height;
    result["void_cells"] = void_cells;
    result["water_cells"] = water_cells;
    result["void_fraction"] = width * height == 0 ? 0.0 : static_cast<double>(void_cells) / (static_cast<double>(width) * height);
    result["components"] = components;
    result["largest_component_cells"] = largest;
    result["largest_component_fraction"] = void_cells == 0 ? 0.0 : static_cast<double>(largest) / static_cast<double>(void_cells);
    result["surface_connected_components"] = surface_connected;
    result["isolated_small_components"] = isolated_small;
    result["dead_end_cells"] = dead_ends;
    result["junction_cells"] = junctions;
    result["chamber_cells"] = chamber_cells;
    result["tunnel_cells"] = tunnel_cells;
    result["chamber_tunnel_ratio"] = tunnel_cells == 0 ? 0.0 : static_cast<double>(chamber_cells) / static_cast<double>(tunnel_cells);
    result["flooded_fraction"] = void_cells == 0 ? 0.0 : static_cast<double>(water_cells) / static_cast<double>(void_cells);
    result["component_size"] = v5_distribution(std::move(sizes));
    result["passage_width"] = v5_distribution(std::move(widths));
    result["component_vertical_extent"] = v5_distribution(std::move(vertical_extent));
    result["component_horizontal_extent"] = v5_distribution(std::move(horizontal_extent));
    return result;
}

// ---------------------------------------------------------------------------------------
// Structure and natural-scene candidates.
//
// Derivable from seed + domain + region coordinate alone: no global scan, no central list.
// ---------------------------------------------------------------------------------------
Array NativeSandWorld::get_structure_candidates(Rect2i cell_area, int32_t structure_type) const {
    Array result;
    if (cell_area.size.x <= 0 || cell_area.size.y <= 0) return result;
    structure_type = std::clamp(structure_type, 0, 2);
    const V5StructureKind &kind = V5_STRUCTURES[structure_type];
    const Vector2i end = cell_area.position + cell_area.size;
    const int32_t rx_first = floor_div(cell_area.position.x, kind.region);
    const int32_t rx_last = floor_div(end.x, kind.region);
    const int32_t ry_first = floor_div(cell_area.position.y, kind.region);
    const int32_t ry_last = floor_div(end.y, kind.region);
    if (static_cast<int64_t>(rx_last - rx_first + 1) * (ry_last - ry_first + 1) > 16384) return result;

    // A surface ruin is anchored to the ground, not to a cell of a 2-D region lattice.
    // Reporting it on the lattice meant the depth filter rejected essentially every
    // candidate, so this API returned an empty list while the generator was placing them.
    if (structure_type == 0) {
        constexpr int32_t RUIN_REGION = 768;
        for (int32_t rx = floor_div(cell_area.position.x, RUIN_REGION); rx <= floor_div(end.x, RUIN_REGION); ++rx) {
            if (v5_unit(seed_, 0x81u, rx, 0, 0x1001u) > 0.30) continue;
            const int32_t span = RUIN_REGION - 96 * 2;
            const int32_t x = rx * RUIN_REGION + 96 +
                static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, 0, 0x1002u) % static_cast<uint32_t>(span));
            if (x < cell_area.position.x || x >= end.x) continue;
            if (std::abs(x) < 620) continue;
            const int32_t centre = surface_height_at_v5(x);
            int32_t lowest = centre;
            int32_t highest = centre;
            for (int32_t offset = -56; offset <= 56; offset += 14) {
                const int32_t sample = surface_height_at_v5(x + offset);
                lowest = std::max(lowest, sample);
                highest = std::min(highest, sample);
            }
            if (lowest - highest > 7) continue;
            const int32_t y = centre + 26 + static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, 0, 0x1003u) % 14u);
            // Reported as the buried ruin the generator actually places.
            const V5Climate climate = climate_at_v5(x);
            Dictionary item;
            item["type"] = String("surface_ruin");
            item["region"] = Vector2i(rx, 0);
            item["cell"] = Vector2i(x, y);
            item["depth_below_surface"] = y - centre;
            item["biome"] = String(v5_biome_profile(climate.biome).name);
            item["province"] = String(v5_province_profile(geology_province_at_v5(x, y)).name);
            item["orientation"] = static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, 0, 0x1004u) % 4u);
            item["weight"] = v5_unit(seed_, 0x81u, rx, 0, 0x1005u);
            item["surface_relief"] = lowest - highest;
            result.push_back(item);
        }
        return result;
    }

    for (int32_t ry = ry_first; ry <= ry_last; ++ry) {
        for (int32_t rx = rx_first; rx <= rx_last; ++rx) {
            if (v5_unit(seed_, 0x81u, rx, ry, kind.salt) > kind.rarity) continue;
            const int32_t span = kind.region - kind.separation * 2;
            if (span <= 0) continue;
            const int32_t x = rx * kind.region + kind.separation +
                static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, ry, kind.salt + 1u) % static_cast<uint32_t>(span));
            const int32_t y = ry * kind.region + kind.separation +
                static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, ry, kind.salt + 2u) % static_cast<uint32_t>(span));
            if (x < cell_area.position.x || x >= end.x || y < cell_area.position.y || y >= end.y) continue;
            const int32_t surface = surface_height_at_v5(x);
            const int32_t depth = y - surface;
            if (depth < kind.minimum_depth || depth > kind.maximum_depth) continue;
            if (std::abs(x) < 140 && depth < 200) continue;   // never inside the protected start core
            const V5Climate climate = climate_at_v5(x);
            const int32_t province = geology_province_at_v5(x, y);
            Dictionary item;
            item["type"] = String(kind.name);
            item["region"] = Vector2i(rx, ry);
            item["cell"] = Vector2i(x, y);
            item["depth_below_surface"] = depth;
            item["biome"] = String(v5_biome_profile(climate.biome).name);
            item["province"] = String(v5_province_profile(province).name);
            item["orientation"] = static_cast<int32_t>(v5_hash(seed_, 0x81u, rx, ry, kind.salt + 3u) % 4u);
            item["weight"] = v5_unit(seed_, 0x81u, rx, ry, kind.salt + 4u);
            result.push_back(item);
        }
    }
    return result;
}

Array NativeSandWorld::get_natural_scene_candidates(Rect2i cell_area) const {
    Array result;
    if (cell_area.size.x <= 0 || cell_area.size.y <= 0) return result;
    constexpr int32_t SCENE_X = 1216;
    constexpr int32_t SCENE_Y = 704;
    const Vector2i end = cell_area.position + cell_area.size;
    const int32_t gx_first = floor_div(cell_area.position.x, SCENE_X);
    const int32_t gx_last = floor_div(end.x, SCENE_X);
    const int32_t gy_first = floor_div(cell_area.position.y, SCENE_Y);
    const int32_t gy_last = floor_div(end.y, SCENE_Y);
    if (static_cast<int64_t>(gx_last - gx_first + 1) * (gy_last - gy_first + 1) > 16384) return result;

    double weight_total = 0.0;
    for (const V5SceneKind &kind : V5_SCENES) weight_total += kind.weight;

    for (int32_t gy = gy_first; gy <= gy_last; ++gy) {
        for (int32_t gx = gx_first; gx <= gx_last; ++gx) {
            if (v5_unit(seed_, 0x82u, gx, gy, 0x11) > 0.46) continue;
            const int32_t x = gx * SCENE_X + static_cast<int32_t>(v5_hash(seed_, 0x82u, gx, gy, 0x13) % static_cast<uint32_t>(SCENE_X));
            const int32_t y = gy * SCENE_Y + static_cast<int32_t>(v5_hash(seed_, 0x82u, gx, gy, 0x15) % static_cast<uint32_t>(SCENE_Y));
            if (x < cell_area.position.x || x >= end.x || y < cell_area.position.y || y >= end.y) continue;
            const int32_t depth = y - surface_height_at_v5(x);
            double pick = v5_unit(seed_, 0x82u, gx, gy, 0x17) * weight_total;
            int32_t index = 0;
            for (; index < 2; ++index) {
                pick -= V5_SCENES[index].weight;
                if (pick <= 0.0) break;
            }
            const V5SceneKind &kind = V5_SCENES[index];
            if (depth < kind.minimum_depth || depth > kind.maximum_depth) continue;
            const int32_t province = geology_province_at_v5(x, y);
            Dictionary item;
            item["scene"] = String(kind.name);
            item["cell"] = Vector2i(x, y);
            item["depth_below_surface"] = depth;
            item["footprint"] = kind.footprint;
            item["province"] = String(v5_province_profile(province).name);
            item["mirrored"] = (v5_hash(seed_, 0x82u, gx, gy, 0x19) & 1u) != 0u;
            result.push_back(item);
        }
    }
    return result;
}

// ---------------------------------------------------------------------------------------
// Deterministic debug field renders
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_worldgen_debug_field(Rect2i cell_area, int32_t field_id, int32_t stride) const {
    Dictionary result;
    stride = std::clamp(stride, 1, 64);
    if (cell_area.size.x <= 0 || cell_area.size.y <= 0) return result;
    const int32_t width = cell_area.size.x / stride;
    const int32_t height = cell_area.size.y / stride;
    if (width <= 0 || height <= 0 || static_cast<int64_t>(width) * height > 4'000'000) return result;

    PackedByteArray pixels;
    pixels.resize(static_cast<int64_t>(width) * height * 4);
    uint8_t *out = pixels.ptrw();

    // Field 11 is not a map of the world at all: it is the climate space itself, drawn as a
    // 2x2 panel of temperature-by-moisture slices at low and high ruggedness and basinness.
    // Factorio visualises terrain ranges the same way to find biomes a parameter tweak has
    // quietly made unreachable.
    if (field_id == 11) {
        for (int32_t py = 0; py < height; ++py) {
            for (int32_t px = 0; px < width; ++px) {
                const int32_t panel_x = px * 2 / width;
                const int32_t panel_y = py * 2 / height;
                const double u = static_cast<double>(px * 2 % width) / std::max(1, width / 2);
                const double v = static_cast<double>(py * 2 % height) / std::max(1, height / 2);
                const double temperature = u * 2.0 - 1.0;
                const double moisture = 1.0 - v * 2.0;
                const double ruggedness = panel_x == 0 ? -0.75 : 0.75;
                const double basinness = panel_y == 0 ? -0.70 : 0.70;
                double best = 1e30;
                int32_t chosen = 0;
                for (int32_t index = 0; index < v5_biome_count(); ++index) {
                    const V5BiomeProfile &profile = v5_biome_profile(index);
                    const double dt = temperature - profile.temperature;
                    const double dm = moisture - profile.moisture;
                    const double dr = ruggedness - profile.ruggedness;
                    const double db = basinness - profile.basinness;
                    const double score = profile.weight_temperature * dt * dt + profile.weight_moisture * dm * dm +
                                         profile.weight_ruggedness * dr * dr + profile.weight_basinness * db * db;
                    if (score < best) { best = score; chosen = index; }
                }
                uint8_t *pixel = out + (static_cast<int64_t>(py) * width + px) * 4;
                const int32_t *colour = BIOME_COLOURS[std::clamp(chosen, 0, 4)];
                const bool border = (px * 2 % width) < 2 || (py * 2 % height) < 2;
                write_rgb(pixel, border ? 250 : colour[0], border ? 250 : colour[1], border ? 250 : colour[2]);
            }
        }
        result["width"] = width;
        result["height"] = height;
        result["stride"] = stride;
        result["field_id"] = field_id;
        result["pixels"] = pixels;
        result["panels"] = Array::make("low_ruggedness_low_basin", "high_ruggedness_low_basin",
                                       "low_ruggedness_high_basin", "high_ruggedness_high_basin");
        result["axes"] = Array::make("temperature_left_to_right", "moisture_top_to_bottom");
        return result;
    }

    // Field 12 renders the connected-component decomposition itself: the metric that tells
    // three believable cave systems apart from forty disconnected slits, drawn.
    if (field_id == 12) {
        std::vector<uint8_t> open(static_cast<size_t>(width) * height, 0);
        std::vector<int32_t> label(static_cast<size_t>(width) * height, -1);
        std::unique_ptr<GeneratedChunk> chunk;
        Vector2i chunk_coordinate{std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::min()};
        for (int32_t py = 0; py < height; ++py) {
            for (int32_t px = 0; px < width; ++px) {
                const Vector2i cell{cell_area.position.x + px * stride, cell_area.position.y + py * stride};
                if (cell.y < surface_height_at_v5(cell.x)) continue;
                const Vector2i coordinate = world_to_chunk(cell);
                if (coordinate != chunk_coordinate) { chunk = generate_chunk_data_v5(coordinate); chunk_coordinate = coordinate; }
                if (chunk == nullptr) continue;
                const int32_t material = chunk->material[local_index(world_to_local(cell))];
                if (material == EMPTY || material == WATER) open[static_cast<size_t>(py) * width + px] = 1;
            }
        }
        int32_t components = 0;
        std::vector<int32_t> stack;
        for (int32_t start = 0; start < width * height; ++start) {
            if (open[start] == 0 || label[start] >= 0) continue;
            const int32_t component = components++;
            stack.clear(); stack.push_back(start); label[start] = component;
            while (!stack.empty()) {
                const int32_t index = stack.back(); stack.pop_back();
                const int32_t x = index % width;
                const int32_t y = index / width;
                const int32_t neighbours[4] = {x > 0 ? index - 1 : -1, x + 1 < width ? index + 1 : -1,
                                               y > 0 ? index - width : -1, y + 1 < height ? index + width : -1};
                for (const int32_t neighbour : neighbours) {
                    if (neighbour < 0 || open[neighbour] == 0 || label[neighbour] >= 0) continue;
                    label[neighbour] = component;
                    stack.push_back(neighbour);
                }
            }
        }
        for (int32_t index = 0; index < width * height; ++index) {
            uint8_t *pixel = out + static_cast<int64_t>(index) * 4;
            if (label[index] < 0) { write_rgb(pixel, 18, 20, 24); continue; }
            const uint32_t tint = v5_hash(seed_, 0x41u, label[index], 0, 0x77);
            write_rgb(pixel, 70 + static_cast<int32_t>(tint & 0xffu) * 185 / 255,
                      70 + static_cast<int32_t>((tint >> 8u) & 0xffu) * 185 / 255,
                      70 + static_cast<int32_t>((tint >> 16u) & 0xffu) * 185 / 255);
        }
        result["width"] = width; result["height"] = height; result["stride"] = stride;
        result["field_id"] = field_id; result["pixels"] = pixels; result["components"] = components;
        return result;
    }

    const bool needs_cells = field_id == 0 || field_id == 6 || field_id == 7;
    std::unique_ptr<GeneratedChunk> cached;
    Vector2i cached_coordinate{std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::min()};
    V5Context carve;
    Vector2i carve_coordinate{std::numeric_limits<int32_t>::min(), std::numeric_limits<int32_t>::min()};

    // Chunk-major traversal for the material-backed fields. Row-major would evict the cached
    // chunk on nearly every pixel and regenerate the same chunk once per scanline.
    std::vector<int32_t> order;
    order.reserve(static_cast<size_t>(width) * height);
    if (needs_cells) {
        std::vector<std::pair<uint64_t, int32_t>> keyed;
        keyed.reserve(static_cast<size_t>(width) * height);
        for (int32_t py = 0; py < height; ++py) {
            for (int32_t px = 0; px < width; ++px) {
                const Vector2i coordinate = world_to_chunk({cell_area.position.x + px * stride,
                                                            cell_area.position.y + py * stride});
                const uint64_t key = (static_cast<uint64_t>(static_cast<uint32_t>(coordinate.y)) << 32u) |
                                     static_cast<uint32_t>(coordinate.x);
                keyed.emplace_back(key, py * width + px);
            }
        }
        std::stable_sort(keyed.begin(), keyed.end(),
                         [](const auto &a, const auto &b) { return a.first < b.first; });
        for (const auto &entry : keyed) order.push_back(entry.second);
    } else {
        // Column-major for the analytic fields so the per-column solve is reused down the
        // whole column instead of being recomputed for every pixel.
        for (int32_t px = 0; px < width; ++px)
            for (int32_t py = 0; py < height; ++py) order.push_back(py * width + px);
    }

    V5Context probe;
    V5Column column;
    int32_t probe_x = std::numeric_limits<int32_t>::min();
    int32_t probe_band = std::numeric_limits<int32_t>::min();

    for (const int32_t slot : order) {
        {
            const int32_t py = slot / width;
            const int32_t px = slot % width;
            const int32_t x = cell_area.position.x + px * stride;
            const int32_t y = cell_area.position.y + py * stride;
            uint8_t *pixel = out + (static_cast<int64_t>(py) * width + px) * 4;
            const int32_t surface = surface_height_at_v5(x);
            const int32_t depth = y - surface;

            if (needs_cells) {
                const Vector2i coordinate = world_to_chunk({x, y});
                if (coordinate != cached_coordinate) {
                    cached = generate_chunk_data_v5(coordinate);
                    cached_coordinate = coordinate;
                }
                const Vector2i local = world_to_local({x, y});
                const int32_t index = local_index(local);
                const int32_t material = cached == nullptr ? 0 : cached->material[index];
                if (field_id == 0) {
                    if (material == EMPTY) { write_rgb(pixel, depth < 0 ? 18 : 8, depth < 0 ? 30 : 10, depth < 0 ? 42 : 14); continue; }
                    if (material == WATER) { write_rgb(pixel, 40, 132, 196); continue; }
                    if (material == SAND) { write_rgb(pixel, 214, 186, 118); continue; }
                    if (material == COAL) { write_rgb(pixel, 34, 34, 38); continue; }
                    if (material == 5) { write_rgb(pixel, 46, 44, 52); continue; }
                    if (material == 21) { write_rgb(pixel, 92, 66, 42); continue; }
                    if (material == 22) { write_rgb(pixel, 72, 128, 66); continue; }
                    float rgb[3];
                    v5_profile_colour(cached->provenance[index], rgb);
                    write_rgb(pixel, static_cast<int32_t>(rgb[0] * 255.0f),
                              static_cast<int32_t>(rgb[1] * 255.0f), static_cast<int32_t>(rgb[2] * 255.0f));
                    continue;
                }
                if (field_id == 6) {
                    const bool open_cell = material == EMPTY || material == WATER;
                    if (!open_cell || depth < 0) { write_rgb(pixel, 20, 22, 26); continue; }
                    if (carve_coordinate != coordinate) { v5_debug_carve_chunk(coordinate, carve); carve_coordinate = coordinate; }
                    const Vector2i carve_local = world_to_local({x, y});
                    const int32_t archetype = carve.carve[(carve_local.y + V5_PAD) * V5_PADDED + (carve_local.x + V5_PAD)];
                    const int32_t tone = std::clamp(archetype, 0, 5);
                    const int32_t shade = material == WATER ? 2 : 0;
                    write_rgb(pixel, ARCHETYPE_COLOURS[tone][0] - shade * 40,
                              ARCHETYPE_COLOURS[tone][1] - shade * 20, ARCHETYPE_COLOURS[tone][2] + shade * 12);
                    continue;
                }
                // field 7: hydrology
                int32_t local_offset = 0;
                const int32_t region = v5_table_region(x, y, local_offset);
                const int32_t table = v5_region_table_mu(region);
                const bool wet = table < (1 << 28);
                if (material == WATER) { write_rgb(pixel, 52, 168, 232); continue; }
                if (material == EMPTY && depth >= 0) { write_rgb(pixel, 90, 90, 96); continue; }
                if (!wet) { write_rgb(pixel, 62, 54, 46); continue; }
                const int32_t level = table / 255;
                write_rgb(pixel, y >= level ? 30 : 22, y >= level ? 64 : 40, y >= level ? 96 : 52);
                continue;
            }

            // The per-column solve is reused down the column and only redone when the
            // bedding window actually moves.
            const int32_t band = y >> 7;
            if (x != probe_x || band != probe_band) {
                probe_x = x;
                probe_band = band;
                probe.origin = Vector2i(x, y);
                probe.padded_origin = probe.origin;
                v5_build_bed_cumulative(probe);
                v5_prepare_lakes(probe);
                v5_fill_column(probe, column, x, y);
            }
            const V5Climate climate = climate_at_v5(x);

            switch (field_id) {
                case 1: {
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    const int32_t *colour = BIOME_COLOURS[std::clamp(column.biome, 0, 4)];
                    const int32_t shade = std::clamp(depth / 6, 0, 40);
                    write_rgb(pixel, colour[0] - shade, colour[1] - shade, colour[2] - shade);
                    break;
                }
                case 2: {
                    const double t = std::clamp((climate.temperature + 1.0) * 0.5, 0.0, 1.0);
                    write_rgb(pixel, static_cast<int32_t>(30 + t * 220), static_cast<int32_t>(60 + (1.0 - std::abs(t - 0.5) * 2.0) * 120),
                              static_cast<int32_t>(230 - t * 200));
                    break;
                }
                case 3: {
                    const double m = std::clamp((climate.moisture + 1.0) * 0.5, 0.0, 1.0);
                    write_rgb(pixel, static_cast<int32_t>(210 - m * 180), static_cast<int32_t>(150 + m * 60),
                              static_cast<int32_t>(70 + m * 180));
                    break;
                }
                case 4: {
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    const int32_t *colour = PROVINCE_COLOURS[std::clamp(column.province, 0, 4)];
                    write_rgb(pixel, colour[0], colour[1], colour[2]);
                    break;
                }
                case 5: {
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    if (depth < column.weathered) {
                        const int32_t tone = depth < column.soil ? 0 : depth < column.sediment ? 1 : 2;
                        write_rgb(pixel, 96 + tone * 30, 74 + tone * 24, 48 + tone * 18);
                        break;
                    }
                    int32_t bed = column.bed_first + column.bed_stored;
                    for (int32_t offset = 0; offset < column.bed_stored; ++offset) {
                        if (y < column.bed_y[offset]) { bed = column.bed_first + offset; break; }
                    }
                    const int32_t rock = v5_bed_rock_at(geology_province_at_v5(x, y), bed, y);
                    write_rgb(pixel, 52 + (rock * 47) % 190, 60 + (rock * 89) % 170, 74 + (rock * 131) % 160);
                    break;
                }
                case 8: {
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    if (depth < column.sand_depth) { write_rgb(pixel, 236, 206, 120); break; }
                    if (depth < column.weathered) {
                        const int32_t thickness = std::clamp(column.weathered * 4, 0, 200);
                        write_rgb(pixel, 60 + thickness / 2, 90 + thickness / 3, 60);
                        break;
                    }
                    write_rgb(pixel, 34, 36, 40);
                    break;
                }
                case 9: {
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    const V5ProvinceProfile &province = v5_province_profile(column.province);
                    const uint16_t profile = v5_stone_profile(0, x, y, std::max(0, depth), column.province);
                    const int32_t iron = (profile >> 5) & 31;
                    const int32_t gold = (profile >> 13) & 7;
                    write_rgb(pixel, 30 + iron * 7, 26 + static_cast<int32_t>(province.coal_richness * 40.0), 30 + gold * 30);
                    break;
                }
                case 10: {
                    const int32_t distance = std::abs(x);
                    if (depth < 0) { write_rgb(pixel, 16, 24, 34); break; }
                    if (distance < 108 && depth < 210) { write_rgb(pixel, 220, 90, 70); break; }
                    if (distance < 288) { write_rgb(pixel, 200, 170, 70); break; }
                    if (distance < 640) { write_rgb(pixel, 80, 150, 100); break; }
                    write_rgb(pixel, 40, 44, 50);
                    break;
                }
                default:
                    write_rgb(pixel, 0, 0, 0);
                    break;
            }
        }
    }

    result["width"] = width;
    result["height"] = height;
    result["stride"] = stride;
    result["field_id"] = field_id;
    result["pixels"] = pixels;
    return result;
}

// ---------------------------------------------------------------------------------------
// Start-region report
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_worldgen_v5_start_report() const {
    Dictionary result;
    int32_t buildable = 0;
    int32_t longest_buildable = 0;
    int32_t sand_columns = 0;
    int32_t minimum_surface = std::numeric_limits<int32_t>::max();
    int32_t maximum_surface = std::numeric_limits<int32_t>::min();
    V5Context probe;
    probe.origin = Vector2i(0, 0);
    probe.padded_origin = probe.origin;
    v5_build_bed_cumulative(probe);
    v5_prepare_lakes(probe);
    for (int32_t x = -260; x <= 260; ++x) {
        V5Column column;
        v5_fill_column(probe, column, x, surface_height_at_v5(x) + 200);
        minimum_surface = std::min(minimum_surface, column.surface);
        maximum_surface = std::max(maximum_surface, column.surface);
        if (column.slope <= 2) { ++buildable; longest_buildable = std::max(longest_buildable, buildable); }
        else buildable = 0;
        if (column.sand_depth > 0) ++sand_columns;
    }

    const int32_t seam_x = 54 + static_cast<int32_t>(v5_hash(seed_, 0xa1u, 0, 20, 0xe1) % 34u);
    const int32_t seam_y = surface_height_at_v5(seam_x) + 36 + static_cast<int32_t>(v5_hash(seed_, 0xa1u, 0, 21, 0xe3) % 12u);
    const int32_t mouth_x = 168 + static_cast<int32_t>(v5_hash(seed_, 0xa1u, 0, 0, 0xc1) % 92u);

    int32_t nearest_water = -1;
    for (int32_t x = 0; x <= 1600 && nearest_water < 0; x += 8) {
        for (const int32_t sign : {1, -1}) {
            const int32_t probe_x = x * sign;
            int32_t local = 0;
            const int32_t region = v5_table_region(probe_x, surface_height_at_v5(probe_x) + 240, local);
            if (v5_region_table_mu(region) < (1 << 28)) { nearest_water = x; break; }
        }
    }

    result["longest_buildable_run"] = longest_buildable;
    result["surface_relief"] = maximum_surface - minimum_surface;
    result["sand_columns"] = sand_columns;
    result["coal_seam_cell"] = Vector2i(seam_x, seam_y);
    result["coal_seam_depth"] = seam_y - surface_height_at_v5(seam_x);
    result["cave_route_mouth"] = Vector2i(mouth_x, surface_height_at_v5(mouth_x) - 1);
    result["nearest_wet_table_distance"] = nearest_water;
    result["protected_core_radius"] = 108;
    result["spawn_surface_y"] = surface_height_at_v5(0);
    return result;
}

// ---------------------------------------------------------------------------------------
// New World preview summary.
//
// Deliberately narrow: what a player could see by standing at the spawn and looking around.
// No cave, ore or aquifer information leaves this call.
// ---------------------------------------------------------------------------------------
// What one specific chunk believes about one world cell.
//
// Cross-chunk feature agreement cannot be checked with a content hash, because a chunk that
// silently omits a feature still agrees with itself. This asks two neighbours the same
// question directly, and is what located the entrance-row gather asymmetry.
Dictionary NativeSandWorld::get_worldgen_debug_chunk_view(Vector2i chunk_coordinate, Vector2i world_cell) const {
    Dictionary result;
    V5Context context;
    v5_debug_carve_chunk(chunk_coordinate, context);
    result["rooms"] = static_cast<int32_t>(context.rooms.size());
    result["capsules"] = static_cast<int32_t>(context.capsules.size());
    const int32_t lx = world_cell.x - context.padded_origin.x;
    const int32_t ly = world_cell.y - context.padded_origin.y;
    result["in_padded"] = lx >= 0 && ly >= 0 && lx < V5_PADDED && ly < V5_PADDED;
    result["carve"] = (lx >= 0 && ly >= 0 && lx < V5_PADDED && ly < V5_PADDED)
        ? static_cast<int32_t>(context.carve[ly * V5_PADDED + lx]) : -1;
    result["surface_min"] = context.surface_min;
    result["surface_max"] = context.surface_max;
    return result;
}

Dictionary NativeSandWorld::get_world_preview_summary() const {
    Dictionary result;
    result["generation_version"] = world_settings_.generation_version;
    if (world_settings_.generation_version < 5) {
        result["supported"] = false;
        return result;
    }
    result["supported"] = true;

    static const char *BIOME_LABEL[5] = {"Temperate plains", "Arid dunes", "Rocky highlands",
                                         "Wetland basin", "Banded badlands"};
    static const char *PROVINCE_LABEL[5] = {"Layered sedimentary shelf", "Cavernous limestone",
                                            "Granite massif", "Mineralised belt", "Volcanic terrane"};

    std::array<int32_t, 8> biome_hits{};
    int32_t samples = 0;
    int32_t minimum = std::numeric_limits<int32_t>::max();
    int32_t maximum = std::numeric_limits<int32_t>::min();
    bool surface_water = false;
    V5Context probe;
    probe.origin = Vector2i(0, 0);
    probe.padded_origin = probe.origin;
    v5_build_bed_cumulative(probe);
    v5_prepare_lakes(probe);
    for (int32_t x = -900; x <= 900; x += 12) {
        const int32_t surface = surface_height_at_v5(x);
        minimum = std::min(minimum, surface);
        maximum = std::max(maximum, surface);
        V5Column column;
        v5_fill_column(probe, column, x, surface + 260);
        biome_hits[std::clamp(column.biome, 0, 7)] += 1;
        ++samples;
        if (column.lake_mass > 0) surface_water = true;
    }
    int32_t dominant = 0;
    for (int32_t index = 1; index < v5_biome_count(); ++index)
        if (biome_hits[index] > biome_hits[dominant]) dominant = index;

    const int32_t spawn_surface = surface_height_at_v5(0);
    const int32_t province = geology_province_at_v5(0, spawn_surface + 520);
    const int32_t relief = maximum - minimum;

    result["biome"] = String(BIOME_LABEL[std::clamp(dominant, 0, 4)]);
    result["province"] = String(PROVINCE_LABEL[std::clamp(province, 0, 4)]);
    result["terrain"] = String(relief < 55 ? "Gentle terrain" : relief < 130 ? "Rolling terrain" : "Rugged terrain");
    result["surface_water"] = surface_water;
    result["relief_cells"] = relief;
    result["biome_variety"] = static_cast<int32_t>(std::count_if(biome_hits.begin(), biome_hits.end(),
        [samples](int32_t hits) { return hits * 40 >= samples; }));
    return result;
}

// ---------------------------------------------------------------------------------------
// Cross-seed statistical sampling. Analytic only: no chunk is materialised, so a thousand
// seeds stay affordable.
// ---------------------------------------------------------------------------------------
Dictionary NativeSandWorld::get_worldgen_v5_statistics(int64_t first_seed, int32_t count) {
    const auto started = std::chrono::steady_clock::now();
    count = std::clamp(count, 1, 20000);
    const int64_t restore = seed_;

    std::vector<double> relief, slope, flat_run, biome_runs, lake_count, wet_fraction, table_depth;
    std::vector<double> cave_systems, coal_fields, buildable, water_distance, coal_depth;
    // Relief measured at the scale a player actually sees. The 4096-cell figure can look
    // healthy while a single screen still reads as flat ground.
    std::vector<double> local_relief, province_runs, entrance_count, coal_clump;
    std::vector<double> field_temperature, field_moisture, field_ruggedness, field_basinness;
    std::array<int64_t, 8> biome_hits{};
    std::array<int64_t, 8> province_hits{};
    int64_t biome_samples = 0;
    int64_t province_samples = 0;
    int32_t seeds_without_water = 0;
    int32_t seeds_without_sand = 0;
    int32_t seeds_without_caves = 0;

    for (int32_t index = 0; index < count; ++index) {
        seed_ = first_seed + index;
        V5Context probe;
        probe.origin = Vector2i(0, 0);
        probe.padded_origin = probe.origin;
        v5_build_bed_cumulative(probe);
        v5_prepare_lakes(probe);

        int32_t minimum = std::numeric_limits<int32_t>::max();
        int32_t maximum = std::numeric_limits<int32_t>::min();
        int64_t slope_total = 0;
        int32_t slope_samples = 0;
        int32_t run = 0;
        int32_t longest = 0;
        int32_t previous_biome = -1;
        int32_t biome_run = 0;
        int32_t lakes = 0;
        int32_t sand_columns = 0;
        int32_t previous_surface = surface_height_at_v5(-2048);

        int32_t window_low = std::numeric_limits<int32_t>::max();
        int32_t window_high = std::numeric_limits<int32_t>::min();
        int32_t window_edge = -2048;
        int32_t previous_province = -1;
        int32_t province_run = 0;
        for (int32_t x = -2048; x <= 2048; x += 4) {
            const int32_t surface = surface_height_at_v5(x);
            window_low = std::min(window_low, surface);
            window_high = std::max(window_high, surface);
            if (x - window_edge >= 256) {
                local_relief.push_back(static_cast<double>(window_high - window_low));
                window_edge = x;
                window_low = surface;
                window_high = surface;
            }
            const int32_t province_here = geology_province_at_v5(x, surface + 420);
            if (province_here != previous_province) {
                if (previous_province >= 0) province_runs.push_back(static_cast<double>(province_run) * 4.0);
                previous_province = province_here;
                province_run = 0;
            }
            ++province_run;
            minimum = std::min(minimum, surface);
            maximum = std::max(maximum, surface);
            const int32_t step = std::abs(surface - previous_surface);
            slope_total += step;
            ++slope_samples;
            previous_surface = surface;
            if (step <= 1) { ++run; longest = std::max(longest, run); } else run = 0;

            V5Column column;
            v5_fill_column(probe, column, x, surface + 260);
            if ((x & 63) == 0) {
                const V5Climate climate = climate_at_v5(x);
                field_temperature.push_back(climate.temperature);
                field_moisture.push_back(climate.moisture);
                field_ruggedness.push_back(climate.ruggedness);
                field_basinness.push_back(climate.basinness);
            }
            ++biome_samples;
            biome_hits[std::clamp(column.biome, 0, 7)] += 1;
            if (column.sand_depth > 0) ++sand_columns;
            if (column.lake_mass > 0) ++lakes;
            if (column.biome != previous_biome) {
                if (previous_biome >= 0) biome_runs.push_back(static_cast<double>(biome_run) * 4.0);
                previous_biome = column.biome;
                biome_run = 0;
            }
            ++biome_run;
            ++province_samples;
            province_hits[std::clamp(column.province, 0, 7)] += 1;
        }

        int32_t wet_regions = 0;
        int32_t total_regions = 0;
        double depth_total = 0.0;
        int32_t nearest_wet = -1;
        for (int32_t region = -3; region <= 3; ++region) {
            ++total_regions;
            const int32_t table = v5_region_table_mu(region);
            if (table >= (1 << 28)) continue;
            ++wet_regions;
            const int32_t centre = region * 1408 + 704;
            depth_total += table / 255.0 - surface_height_at_v5(centre);
            const int32_t distance = std::abs(centre);
            if (nearest_wet < 0 || distance < nearest_wet) nearest_wet = distance;
        }

        relief.push_back(static_cast<double>(maximum - minimum));
        slope.push_back(slope_samples == 0 ? 0.0 : static_cast<double>(slope_total) / slope_samples);
        flat_run.push_back(static_cast<double>(longest) * 4.0);
        lake_count.push_back(static_cast<double>(lakes));
        buildable.push_back(static_cast<double>(sand_columns));
        wet_fraction.push_back(total_regions == 0 ? 0.0 : static_cast<double>(wet_regions) / total_regions);
        if (wet_regions > 0) table_depth.push_back(depth_total / wet_regions);
        water_distance.push_back(nearest_wet < 0 ? 99999.0 : static_cast<double>(nearest_wet));

        // Descriptor counts over a fixed window, using the same acceptance rules the
        // generator uses, so this measures the real feature population.
        int32_t systems = 0;
        for (int32_t gy = 0; gy <= 5; ++gy) {
            for (int32_t gx = -4; gx <= 4; ++gx) {
                if (v5_unit(seed_, 0x41u, gx, gy, 0x01) > 0.62) continue;
                const int32_t anchor_x = gx * 448 + static_cast<int32_t>(v5_hash(seed_, 0x41u, gx, gy, 0x03) % 448u);
                const int32_t anchor_depth = 40 + gy * 352 + static_cast<int32_t>(v5_hash(seed_, 0x41u, gx, gy, 0x05) % 352u);
                const V5ProvinceProfile &province = v5_province_profile(geology_province_at_v5(anchor_x, anchor_depth));
                const double gate = std::clamp((anchor_depth - 20.0) / 110.0, 0.0, 1.0);
                if (v5_unit(seed_, 0x41u, gx, gy, 0x07) > 0.52 * province.cave_density * gate) continue;
                ++systems;
            }
        }
        cave_systems.push_back(static_cast<double>(systems));
        if (systems == 0) ++seeds_without_caves;

        // Surface entrances: how many descriptors in the window pass the breach gate at all.
        int32_t entrances = 0;
        for (int32_t gy = 0; gy <= 3; ++gy) {
            for (int32_t gx = -8; gx <= 8; ++gx) {
                for (int32_t layer = 0; layer < 2; ++layer) {
                    const uint32_t domain = layer == 0 ? 0x41u : 0x42u;
                    const int32_t grid_x = layer == 0 ? 224 : 112;
                    const int32_t grid_y = layer == 0 ? 176 : 96;
                    const int32_t anchor_x = gx * grid_x + static_cast<int32_t>(v5_hash(seed_, domain, gx, gy, 0x03) % static_cast<uint32_t>(grid_x));
                    const int32_t anchor_depth = 40 + gy * grid_y +
                        static_cast<int32_t>(v5_hash(seed_, domain, gx, gy, 0x05) % static_cast<uint32_t>(grid_y));
                    const V5ProvinceProfile &province = v5_province_profile(geology_province_at_v5(anchor_x, surface_height_at_v5(anchor_x) + anchor_depth));
                    const double gate = std::clamp((anchor_depth - 20.0) / 110.0, 0.0, 1.0);
                    if (v5_unit(seed_, domain, gx, gy, 0x07) > (layer == 0 ? 0.58 : 0.54) * province.cave_density * gate) continue;
                    const int32_t gap = anchor_depth - 60;
                    if (gap <= 18 || gap >= 268) continue;
                    const V5Climate climate = climate_at_v5(anchor_x);
                    if (v5_unit(seed_, 0x47u, gx, gy, 0xb1) >= 0.66 * v5_biome_profile(climate.biome).cave_entrance_bias) continue;
                    ++entrances;
                }
            }
        }
        entrance_count.push_back(static_cast<double>(entrances));

        int32_t fields = 0;
        int32_t clump = 0;
        std::array<bool, 13 * 8> accepted{};
        int32_t shallowest_coal = -1;
        for (int32_t gy = 0; gy <= 6; ++gy) {
            for (int32_t gx = -6; gx <= 6; ++gx) {
                const int32_t anchor_x = gx * 236 + static_cast<int32_t>(v5_hash(seed_, 0x71u, gx, gy, 0x01) % 236u);
                const int32_t anchor_depth = 46 + gy * 188 + static_cast<int32_t>(v5_hash(seed_, 0x71u, gx, gy, 0x03) % 188u);
                const V5ProvinceProfile &province = v5_province_profile(geology_province_at_v5(anchor_x, anchor_depth));
                const double fertility = 0.5 + 0.5 * v5_fbm2(0x71u, anchor_x, anchor_depth, 3072, 3, 0x05);
                const double curve = std::clamp((anchor_depth - 38.0) / 92.0, 0.0, 1.0) *
                                     (1.0 - std::clamp((anchor_depth - 900.0) / 1500.0, 0.0, 1.0));
                const double rank = v5_unit(seed_, 0x71u, gx, gy, 0x11);
                int32_t beaten = 0;
                for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
                    if (ox == 0 && oy == 0) continue;
                    if (rank > v5_unit(seed_, 0x71u, gx + ox, gy + oy, 0x11)) ++beaten;
                }
                if (beaten < 3) continue;
                if (v5_unit(seed_, 0x71u, gx, gy, 0x07) > fertility * province.coal_richness * curve * 1.30) continue;
                ++fields;
                accepted[static_cast<size_t>(gy) * 13 + (gx + 6)] = true;
                if (shallowest_coal < 0 || anchor_depth < shallowest_coal) shallowest_coal = anchor_depth;
            }
        }
        coal_fields.push_back(static_cast<double>(fields));
        clump = 0;
        for (int32_t gy = 0; gy <= 5; ++gy) {
            for (int32_t gx = -5; gx <= 5; ++gx) {
                int32_t local = 0;
                for (int32_t oy = 0; oy <= 1; ++oy) for (int32_t ox = 0; ox <= 1; ++ox)
                    local += accepted[static_cast<size_t>(gy + oy) * 13 + (gx + ox + 6)] ? 1 : 0;
                clump = std::max(clump, local);
            }
        }
        coal_clump.push_back(static_cast<double>(clump));
        coal_depth.push_back(shallowest_coal < 0 ? 9999.0 : static_cast<double>(shallowest_coal));
        if (sand_columns == 0) ++seeds_without_sand;
        if (wet_regions == 0 && lakes == 0) ++seeds_without_water;
    }
    seed_ = restore;

    Dictionary result;
    result["first_seed"] = first_seed;
    result["seed_count"] = count;
    result["seeds_without_water"] = seeds_without_water;
    result["seeds_without_sand"] = seeds_without_sand;
    result["seeds_without_caves"] = seeds_without_caves;

    Dictionary metrics;
    metrics["surface_relief"] = v5_distribution(std::move(relief));
    metrics["surface_slope"] = v5_distribution(std::move(slope));
    metrics["longest_flat_run"] = v5_distribution(std::move(flat_run));
    metrics["biome_region_width"] = v5_distribution(std::move(biome_runs));
    metrics["surface_lake_columns"] = v5_distribution(std::move(lake_count));
    metrics["sand_columns"] = v5_distribution(std::move(buildable));
    metrics["wet_table_fraction"] = v5_distribution(std::move(wet_fraction));
    metrics["water_table_depth"] = v5_distribution(std::move(table_depth));
    metrics["nearest_wet_region_distance"] = v5_distribution(std::move(water_distance));
    metrics["cave_systems_in_window"] = v5_distribution(std::move(cave_systems));
    metrics["coal_fields_in_window"] = v5_distribution(std::move(coal_fields));
    metrics["shallowest_coal_depth"] = v5_distribution(std::move(coal_depth));
    metrics["local_relief_256"] = v5_distribution(std::move(local_relief));
    metrics["province_run_width"] = v5_distribution(std::move(province_runs));
    metrics["surface_entrances_in_window"] = v5_distribution(std::move(entrance_count));
    metrics["coal_field_clumping"] = v5_distribution(std::move(coal_clump));
    Dictionary fields_distribution;
    fields_distribution["temperature"] = v5_distribution(std::move(field_temperature));
    fields_distribution["moisture"] = v5_distribution(std::move(field_moisture));
    fields_distribution["ruggedness"] = v5_distribution(std::move(field_ruggedness));
    fields_distribution["basinness"] = v5_distribution(std::move(field_basinness));
    result["climate_field_distribution"] = fields_distribution;
    result["metrics"] = metrics;

    Dictionary biome_coverage;
    for (int32_t index = 0; index < v5_biome_count(); ++index) {
        biome_coverage[String(v5_biome_profile(index).name)] =
            biome_samples == 0 ? 0.0 : 100.0 * static_cast<double>(biome_hits[index]) / static_cast<double>(biome_samples);
    }
    Dictionary province_coverage;
    for (int32_t index = 0; index < v5_province_count(); ++index) {
        province_coverage[String(v5_province_profile(index).name)] =
            province_samples == 0 ? 0.0 : 100.0 * static_cast<double>(province_hits[index]) / static_cast<double>(province_samples);
    }
    result["biome_coverage_percentage"] = biome_coverage;
    result["province_coverage_percentage"] = province_coverage;
    const int64_t elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - started).count();
    result["elapsed_ms"] = static_cast<double>(elapsed) / 1000.0;
    return result;
}
} // namespace godot
