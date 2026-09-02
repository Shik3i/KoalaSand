// KoalaSand world generation V5.
//
// V5 keeps every V4 architectural guarantee (native flat arrays, coordinate-addressable
// deterministic fields, order-independent chunk generation, equilibrium on publication)
// and replaces the *content* model:
//
//   * per-subsystem seed domains, so adding a rule to one system cannot move another,
//   * regionally differentiated terrain character instead of one global amplitude stack,
//   * climate-space biome selection instead of a single threshold field,
//   * warped-Voronoi geological provinces with real bedding planes that truncate against a
//     weathering unconformity instead of running parallel to the surface forever,
//   * cave *systems* expanded into capsules and blobs and rasterised through a padded
//     buffer, instead of a per-cell descriptor test plus per-chunk culling that fragmented
//     every feature at the chunk edges,
//   * water tables with irregular impermeable barriers instead of drawn ellipses,
//   * fractional top-row liquid mass so an analytic waterline between rows stays exact.
#include "native_sand_world.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <limits>
#include <vector>

namespace godot {
namespace {
constexpr int32_t EMPTY = 0;
constexpr int32_t STONE = 1;
constexpr int32_t SAND = 2;
constexpr int32_t WATER = 3;
constexpr int32_t COAL = 4;
constexpr int32_t BEDROCK = 5;
constexpr int32_t WOOD = 21;
constexpr int32_t LEAVES = 22;
constexpr int32_t RAW_FOOD = 25;

// ---------------------------------------------------------------------------------------
// Seed domains. Every subsystem hashes through its own domain constant, so the order and
// number of calls inside one system can never perturb another system's values.
// ---------------------------------------------------------------------------------------
enum V5Domain : uint32_t {
    D_WARP = 0x11,
    D_TERRAIN = 0x12,
    D_TERRACE = 0x13,
    D_CLIMATE = 0x21,
    D_BIOME_DITHER = 0x22,
    D_PROVINCE = 0x31,
    D_STRATA = 0x32,
    D_UNCONFORMITY = 0x33,
    D_CAVE_COARSE = 0x41,
    D_CAVE_FINE = 0x42,
    D_TUNNEL = 0x43,
    D_CHAMBER = 0x44,
    D_FISSURE = 0x45,
    D_CAVERN = 0x46,
    D_ENTRANCE = 0x47,
    D_LAKE = 0x51,
    D_AQUIFER = 0x52,
    D_TABLE_WARP = 0x53,
    D_SEDIMENT = 0x61,
    D_ORE_COAL = 0x71,
    D_ORE_IRON = 0x72,
    D_ORE_GOLD = 0x73,
    D_STRUCTURE = 0x81,
    D_SCENE = 0x82,
    D_VEGETATION = 0x91,
    D_START = 0xa1,
};

constexpr uint64_t V5_TAG = 0x0000563500000000ull;

inline uint64_t v5_mix(uint64_t value) {
    value += 0x9e3779b97f4a7c15ull;
    value = (value ^ (value >> 30u)) * 0xbf58476d1ce4e5b9ull;
    value = (value ^ (value >> 27u)) * 0x94d049bb133111ebull;
    return value ^ (value >> 31u);
}

// Platform-independent fixed-width hash. Negative coordinates widen through an explicit
// two's-complement cast, never through a sign-dependent shift.
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

inline double v5_signed(int64_t seed, uint32_t domain, int32_t x, int32_t y, uint32_t salt) {
    return v5_unit(seed, domain, x, y, salt) * 2.0 - 1.0;
}

// C2-continuous interpolant. A plain smoothstep leaves faint banding at low frequencies,
// part of what made the V4 surface read as one repeated wave.
inline double smooth5(double t) {
    t = std::clamp(t, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

inline double smoothstep_between(double edge0, double edge1, double value) {
    if (edge0 == edge1) return value >= edge1 ? 1.0 : 0.0;
    return smooth5((value - edge0) / (edge1 - edge0));
}

inline double lerp_double(double a, double b, double t) { return a + (b - a) * t; }

inline double segment_distance_squared_d(double px, double py, double x0, double y0,
                                         double x1, double y1, double &t_out) {
    const double vx = x1 - x0;
    const double vy = y1 - y0;
    const double length_squared = vx * vx + vy * vy;
    double t = 0.0;
    if (length_squared > 0.0) t = std::clamp(((px - x0) * vx + (py - y0) * vy) / length_squared, 0.0, 1.0);
    t_out = t;
    const double dx = px - (x0 + vx * t);
    const double dy = py - (y0 + vy * t);
    return dx * dx + dy * dy;
}

// ---------------------------------------------------------------------------------------
// Data-driven profiles. Balancing changes stay inside these tables.
// ---------------------------------------------------------------------------------------
constexpr int32_t V5_BIOME_COUNT = 5;
constexpr int32_t V5_PROVINCE_COUNT = 5;
constexpr int32_t V5_ROCK_COUNT = 11;

constexpr uint8_t R_SANDSTONE = 0;
constexpr uint8_t R_SHALE = 1;
constexpr uint8_t R_LIMESTONE = 2;
constexpr uint8_t R_MUDSTONE = 3;
constexpr uint8_t R_GRANITE = 4;
constexpr uint8_t R_GNEISS = 5;
constexpr uint8_t R_IRONSTONE = 6;
constexpr uint8_t R_BASALT = 7;

constexpr uint8_t ARCH_TUNNEL = 1;
constexpr uint8_t ARCH_CHAMBER = 2;
constexpr uint8_t ARCH_FISSURE = 3;
constexpr uint8_t ARCH_CAVERN = 4;
constexpr uint8_t ARCH_ENTRANCE = 5;

const NativeSandWorld::V5BiomeProfile V5_BIOMES[V5_BIOME_COUNT] = {
    //  name                  t      m      r      b     wt    wm    wr    wb  soil    sediment  sand  lake   veg  entrance
    {"temperate_plain",     0.02,  0.26, -0.50,  0.10, 0.95, 1.00, 0.90, 0.65,  3,  8,  10, 26, 0.38, 0.55, 0.82, 0.55},
    {"arid_dunes",          0.76, -0.80, -0.40, -0.20, 1.20, 1.40, 0.75, 0.55,  1,  3,   6, 18, 1.00, 0.06, 0.05, 0.45},
    {"rocky_highland",     -0.30, -0.16,  0.74, -0.55, 0.78, 0.72, 1.15, 0.80,  1,  3,   2,  9, 0.12, 0.18, 0.30, 0.95},
    {"wet_lowland",         0.24,  0.80, -0.66,  0.72, 0.90, 1.25, 0.95, 1.15,  4, 11,  18, 42, 0.34, 1.00, 0.95, 0.35},
    {"badlands",            0.60, -0.40,  0.34, -0.34, 1.05, 1.00, 1.05, 0.80,  1,  4,   8, 22, 0.62, 0.12, 0.16, 0.75},
};

const NativeSandWorld::V5ProvinceProfile V5_PROVINCES[V5_PROVINCE_COUNT] = {
    // name              weight cave  horiz tunnel chamb  fiss  cav   perm  coal  iron  gold period thick
    {"sedimentary_basin", 1.35, 1.00, 0.84,  1.40, 0.85,  0.55, 0.35, 0.72, 1.30, 0.55, 0.20, 7, 1.00,
        {R_SANDSTONE, R_SHALE, R_SANDSTONE, R_MUDSTONE, R_LIMESTONE, R_SHALE, R_SANDSTONE, R_MUDSTONE}},
    {"karst_platform",    0.70, 1.55, 0.66,  1.20, 1.70, 0.45,  0.60, 1.00, 0.45, 0.45, 0.25, 6, 1.30,
        {R_LIMESTONE, R_LIMESTONE, R_MUDSTONE, R_LIMESTONE, R_SHALE, R_LIMESTONE, R_LIMESTONE, R_LIMESTONE}},
    {"granite_massif",    1.05, 0.50, 0.26,  0.45, 0.30, 1.60,  0.20, 0.26, 0.30, 0.55, 1.05, 4, 2.15,
        {R_GNEISS, R_GRANITE, R_GRANITE, R_GNEISS, R_GRANITE, R_GRANITE, R_GRANITE, R_GRANITE}},
    {"mineralised_belt",  0.55, 0.88, 0.44,  0.85, 0.70, 1.20,  0.45, 0.52, 0.85, 1.85, 1.65, 6, 1.20,
        {R_IRONSTONE, R_SHALE, R_GNEISS, R_IRONSTONE, R_MUDSTONE, R_GNEISS, R_IRONSTONE, R_SHALE}},
    {"volcanic_terrane",  0.75, 0.66, 0.38,  0.55, 0.40, 1.35,  0.55, 0.30, 0.35, 1.15, 0.45, 5, 1.60,
        {R_BASALT, R_MUDSTONE, R_BASALT, R_GNEISS, R_BASALT, R_SHALE, R_BASALT, R_BASALT}},
};

// Composition seeds use the existing 16-bit provenance packing so downstream separation and
// exact conservation keep working unchanged. The quantised silica field doubles as the rock
// family identifier: (q_silica >> 1) is unique per rock, which is what lets the renderer
// colour a cell straight from its stored composition with no extra per-cell state and no
// per-cell field evaluation during rendering.
const NativeSandWorld::V5RockProfile V5_ROCKS[V5_ROCK_COUNT] = {
    {"sandstone", 29,  4, 1, 0},
    {"shale",     10, 17, 3, 0},
    {"limestone",  8,  3, 1, 0},
    {"mudstone",  13, 11, 2, 0},
    {"granite",   23,  7, 2, 1},
    {"gneiss",    20, 12, 4, 1},
    {"ironstone", 17, 29, 6, 0},
    {"basalt",    15, 22, 5, 0},
    {"topsoil",    2, 21, 0, 0},
    {"subsoil",    4, 24, 0, 0},
    {"regolith",   6, 26, 0, 0},
};

// Feature grids. None is chunk-aligned, so a chunk boundary never becomes a feature boundary.
constexpr int32_t CAVE_COARSE_X = 448;
constexpr int32_t CAVE_COARSE_Y = 352;
constexpr int32_t CAVE_COARSE_REACH = 290;
constexpr int32_t CAVE_FINE_X = 206;
constexpr int32_t CAVE_FINE_Y = 166;
constexpr int32_t CAVE_FINE_REACH = 148;
constexpr int32_t CAVE_ANCHOR_ROOF = 40;
constexpr int32_t COAL_GRID_X = 236;
constexpr int32_t COAL_GRID_Y = 188;
constexpr int32_t COAL_REACH = 150;
constexpr int32_t AQUIFER_REGION = 1408;
constexpr int32_t AQUIFER_PLUG = 11;
constexpr int32_t LAKE_REGION = 704;
constexpr int32_t PROVINCE_SITE_X = 968;
constexpr int32_t PROVINCE_SITE_Y = 616;
constexpr int32_t DRY_TABLE = 1 << 28;

constexpr int32_t START_CALM_RADIUS = 288;
constexpr int32_t START_CORE_RADIUS = 96;
constexpr int32_t BED_MIN = 68;
constexpr int32_t BED_SPAN = 104;
constexpr double BED_NOISE_AMPLITUDE = 12.0;

// A capsule/blob may never carve above this many cells below the local surface, except for
// deliberate surface entrances. Keeps a solid roof over the whole world.
inline int32_t v5_roof_for(int32_t weathered) { return std::max(34, weathered + 14); }
} // namespace

const NativeSandWorld::V5BiomeProfile &NativeSandWorld::v5_biome_profile(int32_t index) {
    return V5_BIOMES[std::clamp(index, 0, V5_BIOME_COUNT - 1)];
}
const NativeSandWorld::V5ProvinceProfile &NativeSandWorld::v5_province_profile(int32_t index) {
    return V5_PROVINCES[std::clamp(index, 0, V5_PROVINCE_COUNT - 1)];
}
const NativeSandWorld::V5RockProfile &NativeSandWorld::v5_rock_profile(int32_t index) {
    return V5_ROCKS[std::clamp(index, 0, V5_ROCK_COUNT - 1)];
}
// Rock family palette. The family index is (q_silica >> 1), which the rock table assigns
// uniquely, so this is a direct read of stored composition rather than a second source of
// truth about where a cell sits.
void NativeSandWorld::v5_profile_colour(uint16_t profile, float *rgb) {
    static const float FAMILY[16][3] = {
        {0.34f, 0.30f, 0.26f},  // 0  unused
        {0.26f, 0.19f, 0.12f},  // 1  topsoil    dark humic brown
        {0.42f, 0.30f, 0.19f},  // 2  subsoil    clay brown
        {0.56f, 0.48f, 0.38f},  // 3  regolith   pale weathered grit
        {0.80f, 0.79f, 0.73f},  // 4  limestone  near-white carbonate
        {0.24f, 0.27f, 0.32f},  // 5  shale      dark blue-grey
        {0.46f, 0.42f, 0.32f},  // 6  mudstone   olive
        {0.19f, 0.20f, 0.23f},  // 7  basalt     near-black
        {0.52f, 0.26f, 0.17f},  // 8  ironstone  rust
        {0.40f, 0.42f, 0.44f},  // 9  unused
        {0.47f, 0.45f, 0.54f},  // 10 gneiss     grey-violet
        {0.72f, 0.64f, 0.62f},  // 11 granite    pink-grey
        {0.44f, 0.44f, 0.46f},  // 12 unused
        {0.52f, 0.50f, 0.46f},  // 13 unused
        {0.82f, 0.70f, 0.44f},  // 14 sandstone  warm buff
        {0.46f, 0.46f, 0.46f},  // 15 unused
    };
    const int32_t family = (profile & 31u) >> 1u;
    const float iron = static_cast<float>((profile >> 5u) & 31u) / 31.0f;
    const float heavy = static_cast<float>((profile >> 10u) & 7u) / 7.0f;
    const float gold = static_cast<float>((profile >> 13u) & 7u) / 7.0f;
    const float *base = FAMILY[family];
    // Iron oxide reddens and slightly darkens; heavy minerals darken; gold warms.
    const float darken = 1.0f - 0.20f * heavy - 0.10f * iron;
    rgb[0] = std::clamp(base[0] * darken + 0.19f * iron + 0.13f * gold, 0.0f, 1.0f);
    rgb[1] = std::clamp(base[1] * darken + 0.04f * iron + 0.09f * gold, 0.0f, 1.0f);
    rgb[2] = std::clamp(base[2] * darken - 0.04f * iron - 0.02f * gold, 0.0f, 1.0f);
}

// Decodes the stored 5/5/3/3 packing into six mass fractions that sum to exactly 1.
// V4 and earlier read *different, overlapping* bit windows in composition_for() than
// get_geology_profile() reported, so the number a player was shown and the number the
// conservation ledger used were not the same quantity. V5 has one decoder.
void NativeSandWorld::v5_profile_fractions(uint16_t profile, uint16_t signature, double *out_six) {
    const double q_silica = static_cast<double>(profile & 31u) / 31.0;
    const double q_iron = static_cast<double>((profile >> 5u) & 31u) / 31.0;
    const double q_heavy = static_cast<double>((profile >> 10u) & 7u) / 7.0;
    const int32_t q_gold = static_cast<int32_t>((profile >> 13u) & 7u);

    // A power response widens the low end so a carbonate can actually read as quartz-poor;
    // a linear map over this five-bit field cannot express the range real rock covers.
    double silica = 0.04 + 0.92 * std::pow(q_silica, 1.55);
    double iron = 0.004 + 0.30 * std::pow(q_iron, 1.30);
    double heavy = 0.001 + 0.062 * q_heavy;
    double gold = q_gold == 0 ? 0.0 : 0.0000001 * static_cast<double>(1 << q_gold);
    double clay = 0.015 + 0.130 * (static_cast<double>(signature & 63u) / 63.0);

    const double reserved = iron + heavy + gold + clay;
    if (silica + reserved > 0.995) silica = 0.995 - reserved;
    if (silica < 0.01) {
        const double scale = (0.985 - 0.01) / std::max(1e-9, reserved);
        iron *= scale; heavy *= scale; gold *= scale; clay *= scale;
        silica = 0.01;
    }
    out_six[0] = silica;
    out_six[1] = iron;
    out_six[2] = heavy;
    out_six[3] = gold;
    out_six[4] = clay;
    out_six[5] = std::max(0.0, 1.0 - silica - iron - heavy - gold - clay);
}

int32_t NativeSandWorld::v5_biome_count() { return V5_BIOME_COUNT; }
int32_t NativeSandWorld::v5_province_count() { return V5_PROVINCE_COUNT; }
int32_t NativeSandWorld::v5_rock_count() { return V5_ROCK_COUNT; }

// ---------------------------------------------------------------------------------------
// Noise primitives
// ---------------------------------------------------------------------------------------
double NativeSandWorld::v5_value1(uint32_t domain, int32_t x, int32_t scale, uint32_t salt) const {
    const int32_t anchor = floor_div(x, scale);
    const double local = static_cast<double>(x - anchor * scale) / static_cast<double>(scale);
    const double left = v5_signed(seed_, domain, anchor, 0, salt);
    const double right = v5_signed(seed_, domain, anchor + 1, 0, salt);
    return lerp_double(left, right, smooth5(local));
}

double NativeSandWorld::v5_fbm1(uint32_t domain, int32_t x, int32_t scale, int32_t octaves, uint32_t salt) const {
    double total = 0.0;
    double amplitude = 1.0;
    double normal = 0.0;
    int32_t step = scale;
    for (int32_t octave = 0; octave < octaves; ++octave) {
        total += v5_value1(domain, x, std::max(2, step), salt + static_cast<uint32_t>(octave) * 0x9e37u) * amplitude;
        normal += amplitude;
        amplitude *= 0.5;
        step /= 2;
    }
    return normal > 0.0 ? total / normal : 0.0;
}

double NativeSandWorld::v5_ridged1(uint32_t domain, int32_t x, int32_t scale, int32_t octaves, uint32_t salt) const {
    double total = 0.0;
    double amplitude = 1.0;
    double normal = 0.0;
    int32_t step = scale;
    for (int32_t octave = 0; octave < octaves; ++octave) {
        const double value = 1.0 - std::abs(v5_value1(domain, x, std::max(2, step), salt + static_cast<uint32_t>(octave) * 0x85ebu));
        total += value * value * amplitude;
        normal += amplitude;
        amplitude *= 0.5;
        step /= 2;
    }
    return normal > 0.0 ? total / normal : 0.0;
}

double NativeSandWorld::v5_value2(uint32_t domain, int32_t x, int32_t y, int32_t scale_x, int32_t scale_y, uint32_t salt) const {
    const int32_t ax = floor_div(x, scale_x);
    const int32_t ay = floor_div(y, scale_y);
    const double tx = smooth5(static_cast<double>(x - ax * scale_x) / static_cast<double>(scale_x));
    const double ty = smooth5(static_cast<double>(y - ay * scale_y) / static_cast<double>(scale_y));
    const double v00 = v5_signed(seed_, domain, ax, ay, salt);
    const double v10 = v5_signed(seed_, domain, ax + 1, ay, salt);
    const double v01 = v5_signed(seed_, domain, ax, ay + 1, salt);
    const double v11 = v5_signed(seed_, domain, ax + 1, ay + 1, salt);
    return lerp_double(lerp_double(v00, v10, tx), lerp_double(v01, v11, tx), ty);
}

double NativeSandWorld::v5_fbm2(uint32_t domain, int32_t x, int32_t y, int32_t scale, int32_t octaves, uint32_t salt) const {
    double total = 0.0;
    double amplitude = 1.0;
    double normal = 0.0;
    int32_t step = scale;
    for (int32_t octave = 0; octave < octaves; ++octave) {
        const int32_t clamped = std::max(2, step);
        total += v5_value2(domain, x, y, clamped, clamped, salt + static_cast<uint32_t>(octave) * 0xc2b2u) * amplitude;
        normal += amplitude;
        amplitude *= 0.5;
        step /= 2;
    }
    return normal > 0.0 ? total / normal : 0.0;
}

// ---------------------------------------------------------------------------------------
// Surface terrain.
//
// V4 applied one amplitude stack uniformly, so every region shared the same statistical
// silhouette. V5 solves regional character weights first and lets them select *which*
// landform operators run, so a highland is not a scaled plain and a mesa is not a hill.
// The same weights feed the climate fields, which is why a rugged biome lands on rugged
// ground instead of being decided by an unrelated noise channel.
// ---------------------------------------------------------------------------------------
namespace {
// Soft saturation. Plain fBm of value noise clusters hard around zero, which is what left V4
// with a single terrain character and the first V5 draft with a single dominant biome. This
// spreads the distribution toward its extremes without the flat tops a hard clamp produces.
inline double v5_expand(double value, double gain) {
    const double scaled = value * gain;
    return scaled / std::sqrt(1.0 + scaled * scaled);
}
} // namespace

NativeSandWorld::V5Terrain NativeSandWorld::v5_terrain_fields(int32_t world_x) const {
    V5Terrain terrain;
    const int32_t warped = world_x + static_cast<int32_t>(std::lround(v5_fbm1(D_WARP, world_x, 2560, 3, 0x01) * 430.0));

    terrain.continental = v5_expand(v5_fbm1(D_TERRAIN, warped, 4096, 3, 0x11), 2.35);
    terrain.uplift = v5_expand(v5_fbm1(D_TERRAIN, warped, 1792, 3, 0x13), 2.20);
    terrain.roughness = std::clamp(0.5 + 0.60 * v5_expand(v5_fbm1(D_TERRAIN, warped, 2304, 2, 0x15), 1.90), 0.0, 1.0);

    terrain.highland = smoothstep_between(-0.08, 0.66, terrain.uplift);
    terrain.basin = smoothstep_between(0.05, -0.72, terrain.continental);
    terrain.terrace = smoothstep_between(0.28, 0.86, terrain.uplift * (1.20 - terrain.roughness));

    // Start-region shaping biases the *fields*, not the height, so it blends into the
    // surrounding world instead of stamping a circular plateau.
    const int32_t distance = std::abs(world_x);
    if (distance < START_CALM_RADIUS) terrain.calm = 1.0 - smooth5(static_cast<double>(distance) / START_CALM_RADIUS);
    terrain.roughness *= 1.0 - 0.80 * terrain.calm;
    terrain.highland *= 1.0 - 0.85 * terrain.calm;
    terrain.terrace *= 1.0 - 0.95 * terrain.calm;
    terrain.basin *= 1.0 - 0.55 * terrain.calm;
    return terrain;
}

int32_t NativeSandWorld::v5_surface_from(const V5Terrain &terrain, int32_t world_x) const {
    const double amplitude = static_cast<double>(world_settings_.surface_amplitude);
    const int32_t warped = world_x + static_cast<int32_t>(std::lround(v5_fbm1(D_WARP, world_x, 2560, 3, 0x01) * 430.0));

    // Negative y is up, so uplift subtracts. Every band is expanded before it is scaled:
    // an fBm average sits close to zero, so an unexpanded meso band contributes a few cells
    // and the silhouette reads as one slow wave no matter what the region is supposed to be.
    double height = -(terrain.continental * 0.66 + terrain.uplift * 0.98) * amplitude * (1.0 - 0.50 * terrain.calm);
    height += -v5_ridged1(D_TERRAIN, warped, 448, 3, 0x17) * amplitude * 1.70 * terrain.highland * terrain.roughness;
    height += -v5_expand(v5_fbm1(D_TERRAIN, warped, 704, 3, 0x18), 2.05) * amplitude * 1.30 *
              (0.14 + 0.86 * terrain.roughness) * (1.0 - 0.55 * terrain.basin);
    height += -v5_expand(v5_fbm1(D_TERRAIN, warped, 320, 3, 0x1c), 2.05) * amplitude * 0.80 *
              (0.12 + 0.88 * terrain.roughness) * (1.0 - 0.60 * terrain.basin);
    height += -v5_expand(v5_fbm1(D_TERRAIN, warped, 176, 3, 0x19), 2.10) * amplitude * 0.52 *
              (0.14 + 0.86 * terrain.roughness) * (1.0 - 0.65 * terrain.basin);
    height += -v5_expand(v5_fbm1(D_TERRAIN, world_x, 52, 2, 0x1b), 1.70) * amplitude * 0.13 *
              (0.35 + 0.65 * terrain.roughness);
    height += terrain.basin * amplitude * 0.52;

    if (terrain.terrace > 0.14) {
        // Mesa and escarpment operator: flat treads separated by short steep risers.
        const double step = 10.0 + 11.0 * (0.5 + 0.5 * v5_value1(D_TERRACE, warped, 1536, 0x21));
        const double scaled = height / step;
        const double base = std::floor(scaled);
        const double shaped = base + smooth5((scaled - base - 0.28) / 0.42);
        height = lerp_double(height, shaped * step, terrain.terrace);
    }
    return world_settings_.surface_baseline + static_cast<int32_t>(std::lround(height));
}

int32_t NativeSandWorld::surface_height_at_v5(int32_t world_x) const {
    return v5_surface_from(v5_terrain_fields(world_x), world_x);
}

// ---------------------------------------------------------------------------------------
// Climate fields and biome selection.
// ---------------------------------------------------------------------------------------
NativeSandWorld::V5Climate NativeSandWorld::climate_at_v5(int32_t world_x) const {
    V5Climate climate;
    const double amplitude = std::max(1.0, static_cast<double>(world_settings_.surface_amplitude));
    const V5Terrain terrain = v5_terrain_fields(world_x);
    const int32_t surface = v5_surface_from(terrain, world_x);

    // Independent warps, so climate boundaries do not lock onto terrain boundaries.
    const int32_t warp_t = world_x + static_cast<int32_t>(std::lround(v5_fbm1(D_WARP, world_x, 1792, 2, 0x31) * 340.0));
    const int32_t warp_m = world_x + static_cast<int32_t>(std::lround(v5_fbm1(D_WARP, world_x, 2176, 2, 0x33) * 390.0));
    const double altitude = std::clamp(static_cast<double>(world_settings_.surface_baseline - surface) / (amplitude * 1.7), -1.0, 1.0);

    double temperature = v5_expand(v5_fbm1(D_CLIMATE, warp_t, 3584, 3, 0x41), 2.45) - 0.46 * altitude;
    double moisture = v5_expand(v5_fbm1(D_CLIMATE, warp_m, 2432, 3, 0x43), 2.35);

    // Ruggedness and basinness come from the landform weights themselves.
    const double ruggedness = std::clamp(-0.88 + 1.30 * terrain.roughness + 1.05 * terrain.highland, -1.0, 1.0);
    const double basinness = std::clamp(-1.15 * terrain.continental + 0.45 * terrain.basin - 0.08, -1.0, 1.0);

    // Rain shadow: highlands dry the leeward side, basins collect moisture.
    moisture -= 0.42 * terrain.highland;
    moisture += 0.36 * std::max(0.0, basinness);

    // Start region drifts toward habitable climate without a hard boundary.
    const int32_t distance = std::abs(world_x);
    if (distance < START_CALM_RADIUS * 2) {
        const double calm = 1.0 - smooth5(static_cast<double>(distance) / (START_CALM_RADIUS * 2.0));
        temperature = lerp_double(temperature, 0.12, 0.60 * calm);
        moisture = lerp_double(moisture, 0.26, 0.60 * calm);
    }

    climate.temperature = std::clamp(temperature, -1.2, 1.2);
    climate.moisture = std::clamp(moisture, -1.2, 1.2);
    climate.ruggedness = ruggedness;
    climate.basinness = basinness;

    // Climate-space nearest-profile selection with a deterministic patch dither, so borders
    // interfinger over tens of cells instead of forming a vertical chunk-aligned wall.
    double best = std::numeric_limits<double>::max();
    double second = std::numeric_limits<double>::max();
    int32_t chosen = 0;
    for (int32_t index = 0; index < V5_BIOME_COUNT; ++index) {
        const V5BiomeProfile &profile = V5_BIOMES[index];
        const double dt = climate.temperature - profile.temperature;
        const double dm = climate.moisture - profile.moisture;
        const double dr = climate.ruggedness - profile.ruggedness;
        const double db = climate.basinness - profile.basinness;
        double score = profile.weight_temperature * dt * dt + profile.weight_moisture * dm * dm +
                       profile.weight_ruggedness * dr * dr + profile.weight_basinness * db * db;
        const uint32_t salt = 0x51u + static_cast<uint32_t>(index) * 0x2ba3u;
        const double dither = v5_value1(D_BIOME_DITHER, world_x, 53, salt) * 0.40 +
                              v5_value1(D_BIOME_DITHER, world_x, 197, salt + 7u) * 0.60;
        score *= 1.0 + 0.13 * dither;
        if (score < best) { second = best; best = score; chosen = index; }
        else if (score < second) { second = score; }
    }
    climate.biome = chosen;
    climate.biome_margin = second <= 0.0 || second >= std::numeric_limits<double>::max() * 0.5
                               ? 1.0 : std::clamp(1.0 - best / second, 0.0, 1.0);
    return climate;
}

// ---------------------------------------------------------------------------------------
// Geological provinces: warped Voronoi cells rather than a floor-divided grid, so province
// boundaries are irregular and never coincide with a chunk edge.
// ---------------------------------------------------------------------------------------
// world_y is absolute, not depth below the surface: provinces are deep crustal bodies and
// must not staircase with the terrain (or, worse, with the chunk that happened to sample them).
int32_t NativeSandWorld::geology_province_at_v5(int32_t world_x, int32_t world_y) const {
    const double px = static_cast<double>(world_x) + v5_fbm2(D_PROVINCE, world_x, world_y, 1024, 2, 0x61) * 240.0;
    const double py = static_cast<double>(world_y) + v5_fbm2(D_PROVINCE, world_x, world_y, 768, 2, 0x63) * 180.0;
    const int32_t gx = floor_div(static_cast<int32_t>(std::lround(px)), PROVINCE_SITE_X);
    const int32_t gy = floor_div(static_cast<int32_t>(std::lround(py)), PROVINCE_SITE_Y);

    double total_weight = 0.0;
    for (const V5ProvinceProfile &profile : V5_PROVINCES) total_weight += profile.weight;

    // Perturbing each candidate distance by a shared fine-scale field times a per-site sign
    // only changes the outcome where two sites are nearly equidistant, so a contact
    // interleaves over tens of cells while the interior of a province stays untouched.
    const double contact = v5_value2(D_PROVINCE, world_x, world_y, 43, 33, 0x6b);

    double best = std::numeric_limits<double>::max();
    int32_t chosen = 0;
    for (int32_t oy = -1; oy <= 1; ++oy) {
        for (int32_t ox = -1; ox <= 1; ++ox) {
            const int32_t sx = gx + ox;
            const int32_t sy = gy + oy;
            const double site_x = (static_cast<double>(sx) + v5_unit(seed_, D_PROVINCE, sx, sy, 0x65)) * PROVINCE_SITE_X;
            const double site_y = (static_cast<double>(sy) + v5_unit(seed_, D_PROVINCE, sx, sy, 0x67)) * PROVINCE_SITE_Y;
            const double dx = (px - site_x) / PROVINCE_SITE_X;
            const double dy = (py - site_y) / PROVINCE_SITE_Y;
            double distance = dx * dx + dy * dy;
            distance *= 1.0 + 0.075 * contact * (v5_unit(seed_, D_PROVINCE, sx, sy, 0x6d) * 2.0 - 1.0);
            if (distance >= best) continue;
            best = distance;
            double pick = v5_unit(seed_, D_PROVINCE, sx, sy, 0x69) * total_weight;
            int32_t index = 0;
            for (; index < V5_PROVINCE_COUNT - 1; ++index) {
                pick -= V5_PROVINCES[index].weight;
                if (pick <= 0.0) break;
            }
            chosen = index;
        }
    }
    return chosen;
}

// ---------------------------------------------------------------------------------------
// Composition provenance.
//
// V4 tagged stone with 0x8000|layer|province, which collides with the gold field of the
// profile packing and made every stone cell claim gold. V5 stores a real geology profile id
// derived from the rock type and the local mineralisation, so composition is meaningful,
// exactly conserved, and is also what the renderer colours from.
// ---------------------------------------------------------------------------------------
uint16_t NativeSandWorld::v5_stone_profile(int32_t rock, int32_t world_x, int32_t world_y, int32_t depth, int32_t province) const {
    const V5RockProfile &base = v5_rock_profile(rock);
    const V5ProvinceProfile &host = v5_province_profile(province);

    const double depth_gain = smoothstep_between(60.0, 900.0, static_cast<double>(depth));
    const double iron_field = (0.5 + 0.5 * v5_fbm2(D_ORE_IRON, world_x, world_y, 768, 2, 0x71)) * host.iron_richness;
    const double gold_field = v5_ridged1(D_ORE_GOLD, world_x + world_y * 3, 320, 2, 0x73) *
                              (0.40 + 0.60 * (0.5 + 0.5 * v5_value2(D_ORE_GOLD, world_x, world_y, 1536, 1536, 0x75))) *
                              host.gold_richness * depth_gain;

    // The silica field carries the rock family and must stay exact; local variation goes
    // into the iron and heavy channels, which is also where real alteration shows up.
    const int32_t jitter = static_cast<int32_t>(v5_hash(seed_, D_STRATA, world_x >> 4, world_y >> 4, 0x77) % 3u) - 1;
    const int32_t silica = std::clamp(base.silica, 0, 31);
    const int32_t iron = std::clamp(base.iron + jitter + static_cast<int32_t>(std::lround(iron_field * 8.0)), 0, 31);
    const int32_t heavy = std::clamp(base.heavy + static_cast<int32_t>(std::lround(iron_field * 1.6)), 0, 7);
    const int32_t gold = gold_field < 0.74 ? base.gold
        : std::clamp(base.gold + 1 + static_cast<int32_t>(std::lround((gold_field - 0.74) / 0.26 * 5.0)), 0, 7);

    uint16_t packed = static_cast<uint16_t>((silica & 31) | ((iron & 31) << 5u) | ((heavy & 7) << 10u) | ((gold & 7) << 13u));
    if (packed == 0) packed = 1;
    return packed;
}

// ---------------------------------------------------------------------------------------
// Stratigraphy.
//
// Shallow horizons (soil, sediment, weathering) follow the surface because they are surface
// processes. Bedding planes below the weathering front are absolute-y surfaces built from a
// shared regional fold plus an *independent* irregularity per bed, and they are truncated by
// the weathering front. That unconformity, and the subcrop pattern it produces along x, is
// what makes a section read as geology instead of as a stack of parallel sine waves.
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_build_bed_cumulative(V5Context &context) const {
    int32_t cumulative = world_settings_.surface_baseline - world_settings_.surface_amplitude - 40;
    for (int32_t index = 0; index < 64; ++index) {
        context.bed_cumulative[index] = cumulative;
        const int32_t base = BED_MIN + static_cast<int32_t>(v5_hash(seed_, D_STRATA, index, 0, 0xa1) % static_cast<uint32_t>(BED_SPAN));
        // Deeper packages are thicker: compaction and metamorphism destroy fine bedding.
        cumulative += base + base * index / 14;
    }
}

// Depth grade: 0 at the top of the bedded cover, 1 in the igneous basement.
int32_t NativeSandWorld::v5_deep_facies(int32_t rock, int32_t world_y) const {
    const int32_t datum = world_settings_.surface_baseline - world_settings_.surface_amplitude;
    const double grade = smoothstep_between(1100.0, 2700.0, static_cast<double>(world_y - datum));
    if (grade <= 0.0) return rock;
    // Sedimentary cover grades into gneiss, then into granite at the deepest levels.
    const double basement = smoothstep_between(2200.0, 3400.0, static_cast<double>(world_y - datum));
    const int32_t metamorphic = rock == 0 || rock == 1 || rock == 2 || rock == 3 ? 5 : rock;
    if (basement > 0.55) return rock == 7 ? 7 : 4;
    return grade > 0.5 ? metamorphic : rock;
}

int32_t NativeSandWorld::v5_bed_rock(int32_t province_index, int32_t bed_index) const {
    const V5ProvinceProfile &province = v5_province_profile(province_index);
    const int32_t period = std::clamp(province.bed_period, 3, 8);
    const int32_t wrapped = ((bed_index % period) + period) % period;
    return province.rock_sequence[wrapped];
}

int32_t NativeSandWorld::v5_bed_rock_at(int32_t province_index, int32_t bed_index, int32_t world_y) const {
    return v5_deep_facies(v5_bed_rock(province_index, bed_index), world_y);
}

int32_t NativeSandWorld::v5_cave_roof(const V5Column &column) const {
    return v5_roof_for(column.weathered);
}

void NativeSandWorld::v5_fill_column(V5Context &context, V5Column &column, int32_t world_x, int32_t probe_y) const {
    const int32_t surface = surface_height_at_v5(world_x);
    const V5Climate climate = climate_at_v5(world_x);
    const V5BiomeProfile &biome = v5_biome_profile(climate.biome);

    column.surface = surface;
    column.biome = climate.biome;

    const int32_t left = surface_height_at_v5(world_x - 4);
    const int32_t right = surface_height_at_v5(world_x + 4);
    column.slope = std::abs(right - left);
    column.curvature = surface_height_at_v5(world_x - 28) + surface_height_at_v5(world_x + 28) - surface * 2;

    const double valley = std::clamp(static_cast<double>(column.curvature) / 46.0, 0.0, 1.0);
    const double flat = 1.0 - std::clamp(static_cast<double>(column.slope) / 9.0, 0.0, 1.0);
    const double jitter = 0.5 + 0.5 * v5_fbm1(D_SEDIMENT, world_x, 176, 2, 0x81);

    column.soil = std::clamp(biome.soil_min + static_cast<int32_t>(std::lround(
        (biome.soil_max - biome.soil_min) * (0.35 * jitter + 0.35 * flat + 0.30 * valley))), 0, 24);
    column.sediment = column.soil + std::clamp(biome.sediment_min + static_cast<int32_t>(std::lround(
        (biome.sediment_max - biome.sediment_min) * (0.30 * jitter + 0.30 * flat + 0.40 * valley))), 1, 60);
    column.weathered = column.sediment + 6 + static_cast<int32_t>(std::lround(
        24.0 * (0.45 + 0.55 * (0.5 + 0.5 * v5_fbm1(D_UNCONFORMITY, world_x, 512, 3, 0x83)))));

    // Loose surface Sand is a *deposit*, not a painted threshold: it needs a locally flat and
    // laterally supported surface, so it is already settled the instant it is published.
    const double dune = 0.5 + 0.5 * v5_fbm1(D_SEDIMENT, world_x, 232, 3, 0x85);
    const double patch = 0.5 + 0.5 * v5_fbm1(D_SEDIMENT, world_x, 61, 2, 0x87);
    const double drive = biome.surface_sand * (0.55 * dune + 0.45 * patch) + 0.34 * valley * biome.surface_sand;
    // A deposit may only rest where both neighbouring columns stand at or above its base,
    // which is exactly the condition the falling-sand solver uses to stay asleep.
    const bool supported = surface_height_at_v5(world_x - 1) <= surface + 1 &&
                           surface_height_at_v5(world_x + 1) <= surface + 1;
    int32_t sand_depth = 0;
    if (supported && column.slope <= 2 && drive > 0.24) {
        sand_depth = 2 + static_cast<int32_t>(std::lround((drive - 0.24) * 20.0 * (0.6 + 0.8 * dune)));
        sand_depth = std::clamp(sand_depth, 2, std::min(12, std::max(2, column.sediment - 1)));
    }
    if (supported && std::abs(world_x) < START_CORE_RADIUS && column.slope <= 2) {
        sand_depth = std::max(sand_depth, 4 + static_cast<int32_t>(v5_hash(seed_, D_START, floor_div(world_x, 24), 0, 0x89) % 4u));
    }
    column.sand_depth = sand_depth;

    column.province = geology_province_at_v5(world_x, probe_y);

    // Bedding planes: shared regional fold + per-bed irregularity + per-bed local thinning.
    const double fold = v5_fbm1(D_STRATA, world_x, 2560, 3, 0x8b) * 118.0 +
                        v5_fbm1(D_STRATA, world_x, 928, 2, 0x8d) * 34.0;
    const int32_t unconformity = surface + column.weathered;

    // Only the bedding boundaries that can reach this chunk are evaluated.
    const int32_t window_low = probe_y - CHUNK_SIZE - 200;
    const int32_t window_high = probe_y + CHUNK_SIZE + 200;
    int32_t first = 0;
    while (first < 62 && static_cast<double>(context.bed_cumulative[first + 1]) + fold < window_low) ++first;
    column.bed_first = first;
    column.bed_stored = 0;
    for (int32_t offset = 0; offset < V5_BEDS_STORED; ++offset) {
        const int32_t index = first + offset;
        if (index >= 64) break;
        const uint32_t salt = 0x91u + static_cast<uint32_t>(index) * 0x1f3bu;
        const int32_t control = 720 + (index % 7) * 421 + static_cast<int32_t>(v5_hash(seed_, D_STRATA, index, 1, 0x93) % 397u);
        const double thin = 0.42 + 0.58 * (0.5 + 0.5 * v5_fbm1(D_STRATA, world_x + index * 811, 1664, 2, salt + 3u));
        double boundary = static_cast<double>(context.bed_cumulative[index]) + fold;
        boundary += v5_fbm1(D_STRATA, world_x, control, 3, salt) * BED_NOISE_AMPLITUDE;
        // Local thinning pulls a bed toward its upper neighbour without ever inverting it.
        boundary -= (1.0 - thin) * static_cast<double>(context.bed_cumulative[index] - context.bed_cumulative[std::max(0, index - 1)]) * 0.45;
        int32_t value = static_cast<int32_t>(std::lround(boundary));
        // Truncation against the weathering front: beds above it subcrop out entirely.
        value = std::max(value, unconformity);
        if (offset > 0) value = std::max(value, column.bed_y[offset - 1]);
        column.bed_y[offset] = value;
        column.bed_stored = offset + 1;
        if (value > window_high) break;
    }

    const int32_t lake_slot = floor_div(world_x, LAKE_REGION) - context.lake_region_first;
    column.lake_level = 0;
    column.lake_mass = 0;
    column.lake_guard = 0;
    if (lake_slot >= 0 && lake_slot < 3 && context.lake_mass[lake_slot] > 0) {
        if (world_x >= context.lake_left[lake_slot] && world_x <= context.lake_right[lake_slot])
            column.lake_guard = context.lake_waterline[lake_slot];
        if (column.surface > context.lake_waterline[lake_slot]) {
            column.lake_level = context.lake_waterline[lake_slot];
            column.lake_mass = context.lake_mass[lake_slot];
        }
    }
}

// ---------------------------------------------------------------------------------------
// Surface lakes.
//
// A 2D side view makes basin detection tractable. The whole lake is resolved once per
// candidate region, never per column: every column inside a region uses the *same* analytic
// waterline and the *same* fractional top-row mass, and a region only carries a lake when
// both of its edge columns stand above that waterline. Those two properties together mean a
// generated lake can never sit beside a lower one, so it is settled the moment it publishes.
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_prepare_lakes(V5Context &context) const {
    context.lake_region_first = floor_div(context.padded_origin.x, LAKE_REGION) - 1;
    for (int32_t slot = 0; slot < 3; ++slot) {
        context.lake_waterline[slot] = 0;
        context.lake_mass[slot] = 0;
        context.lake_left[slot] = 0;
        context.lake_right[slot] = 0;
    }
    // Surface water only exists within reach of the surface band; deep chunks skip the work.
    const int32_t band = world_settings_.surface_amplitude * 2 + 80;
    if (context.padded_origin.y > band || context.padded_origin.y + V5_PADDED < -band) return;

    for (int32_t slot = 0; slot < 3; ++slot) {
        const int32_t region = context.lake_region_first + slot;
        const int32_t start = region * LAKE_REGION;
        const int32_t centre_biome = climate_at_v5(start + LAKE_REGION / 2).biome;
        const V5BiomeProfile &biome = v5_biome_profile(centre_biome);
        if (v5_unit(seed_, D_LAKE, region, 0, 0xc1) > 0.30 + 0.46 * biome.lake_bias) continue;

        constexpr int32_t SAMPLES = 32;
        int32_t floor_y = std::numeric_limits<int32_t>::min();
        int32_t left_rim = std::numeric_limits<int32_t>::max();
        int32_t right_rim = std::numeric_limits<int32_t>::max();
        for (int32_t index = 0; index < SAMPLES; ++index) {
            const int32_t x = start + index * (LAKE_REGION / SAMPLES);
            const int32_t y = surface_height_at_v5(x);
            floor_y = std::max(floor_y, y);
            if (index < SAMPLES / 3) left_rim = std::min(left_rim, y);
            else if (index >= SAMPLES * 2 / 3) right_rim = std::min(right_rim, y);
        }
        // Water escapes over the lower of the two confining rims.
        const int32_t spill = std::max(left_rim, right_rim);
        if (floor_y - spill < 6) continue;
        const int32_t waterline = spill + 1;
        // Containment at both region edges is what keeps neighbouring waterlines apart.
        if (surface_height_at_v5(start) > waterline) continue;
        if (surface_height_at_v5(start + LAKE_REGION - 1) > waterline) continue;
        context.lake_waterline[slot] = waterline;
        context.lake_mass[slot] = 46 + static_cast<int32_t>(v5_hash(seed_, D_LAKE, region, 1, 0xc3) % 172u);

        // Basin extent, used to keep a surface entrance from cutting the lake bed or its rim.
        // A breached basin would drain sideways on the first tick, which is precisely the
        // "generated terrain must publish settled" invariant this pass has to protect.
        int32_t inner_left = start + LAKE_REGION;
        int32_t inner_right = start;
        for (int32_t index = 0; index < SAMPLES; ++index) {
            const int32_t x = start + index * (LAKE_REGION / SAMPLES);
            if (surface_height_at_v5(x) <= waterline) continue;
            inner_left = std::min(inner_left, x);
            inner_right = std::max(inner_right, x);
        }
        if (inner_left > inner_right) { context.lake_mass[slot] = 0; continue; }
        for (int32_t step = 1; step <= 96 && surface_height_at_v5(inner_left - 1) > waterline; ++step) --inner_left;
        for (int32_t step = 1; step <= 96 && surface_height_at_v5(inner_right + 1) > waterline; ++step) ++inner_right;
        context.lake_left[slot] = inner_left - 44;
        context.lake_right[slot] = inner_right + 44;
    }
}

// ---------------------------------------------------------------------------------------
// Hydrology: local water tables.
//
// Water shape comes from geology plus cave geometry plus a local water table, never from a
// drawn ellipse. Regions are separated by warped impermeable barriers, the same device
// Minecraft uses, so two neighbouring tables at different levels can never leak into each
// other and every generated reservoir is settled by construction.
// ---------------------------------------------------------------------------------------
int32_t NativeSandWorld::v5_table_region(int32_t world_x, int32_t world_y, int32_t &local) const {
    const int32_t warp = static_cast<int32_t>(std::lround(v5_fbm1(D_TABLE_WARP, world_y, 384, 2, 0xb1) * 54.0));
    const int32_t shifted = world_x + warp;
    const int32_t region = floor_div(shifted, AQUIFER_REGION);
    local = shifted - region * AQUIFER_REGION;
    return region;
}

int32_t NativeSandWorld::v5_region_table_mu(int32_t region) const {
    if (v5_unit(seed_, D_AQUIFER, region, 0, 0xb3) < 0.36) return DRY_TABLE;
    const int32_t center = region * AQUIFER_REGION + AQUIFER_REGION / 2;
    const int32_t surface = surface_height_at_v5(center);
    const V5ProvinceProfile &province = v5_province_profile(geology_province_at_v5(center, surface + 320));
    const V5Climate climate = climate_at_v5(center);
    double depth = 330.0 - 175.0 * province.permeability - 95.0 * climate.moisture +
                   270.0 * v5_unit(seed_, D_AQUIFER, region, 1, 0xb5);
    depth = std::clamp(depth, 74.0, 660.0);
    const int32_t level = surface + static_cast<int32_t>(std::lround(depth));
    const int32_t fraction = static_cast<int32_t>(v5_hash(seed_, D_AQUIFER, region, 2, 0xb7) % 200u);
    return level * 255 + fraction;
}

void NativeSandWorld::v5_prepare_tables(V5Context &context) const {
    // The warp is bounded, so a chunk can only ever touch a handful of table regions.
    const int32_t low = context.padded_origin.x - 64;
    const int32_t high = context.padded_origin.x + V5_PADDED + 64;
    context.table_region_first = floor_div(low, AQUIFER_REGION) - 1;
    for (int32_t index = 0; index < V5_TABLE_REGIONS; ++index) {
        context.table_mu[index] = v5_region_table_mu(context.table_region_first + index);
    }
    (void)high;
}

int32_t NativeSandWorld::v5_context_table_mu(const V5Context &context, int32_t region) const {
    const int32_t offset = region - context.table_region_first;
    if (offset >= 0 && offset < V5_TABLE_REGIONS) return context.table_mu[offset];
    return v5_region_table_mu(region);
}

bool NativeSandWorld::v5_aquifer_barrier(const V5Context &context, int32_t world_x, int32_t world_y) const {
    int32_t local = 0;
    const int32_t region = v5_table_region(world_x, world_y, local);
    int32_t neighbour = region;
    if (local < AQUIFER_PLUG) neighbour = region - 1;
    else if (local >= AQUIFER_REGION - AQUIFER_PLUG) neighbour = region + 1;
    else return false;
    const int32_t here = v5_context_table_mu(context, region);
    const int32_t there = v5_context_table_mu(context, neighbour);
    if (here == there) return false;      // identical waterline, nothing to separate
    const int32_t lower = std::min(here, there);
    if (lower >= DRY_TABLE) return false;
    return static_cast<int64_t>(world_y) * 255 >= static_cast<int64_t>(lower) - 255 * 5;
}
} // namespace godot
