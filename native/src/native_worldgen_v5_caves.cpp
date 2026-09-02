// KoalaSand world generation V5 - cave systems, ore, and chunk assembly.
//
// A cave is never generated as "cave pixels". Every void belongs to a deterministic system
// descriptor that is addressed in world coordinates, expanded into capsules and blobs, and
// then rasterised into a padded buffer. Because the descriptor set for a world position is
// identical no matter which chunk asks, a system crosses chunk boundaries intact - which is
// exactly what V4's per-chunk candidate culling destroyed.
#include "native_sand_world.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
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

enum V5Domain : uint32_t {
    D_TUNNEL = 0x43,
    D_CHAMBER = 0x44,
    D_FISSURE = 0x45,
    D_CAVERN = 0x46,
    D_ENTRANCE = 0x47,
    D_SEDIMENT = 0x61,
    D_ORE_COAL = 0x71,
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

inline double smooth5(double t) {
    t = std::clamp(t, 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

inline double smoothstep_between(double edge0, double edge1, double value) {
    if (edge0 == edge1) return value >= edge1 ? 1.0 : 0.0;
    return smooth5((value - edge0) / (edge1 - edge0));
}

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

constexpr uint8_t ARCH_TUNNEL = 1;
constexpr uint8_t ARCH_CHAMBER = 2;
constexpr uint8_t ARCH_FISSURE = 3;
constexpr uint8_t ARCH_CAVERN = 4;
constexpr uint8_t ARCH_ENTRANCE = 5;
constexpr uint8_t ARCH_SCENE = 6;

constexpr int32_t CAVE_COARSE_X = 224;
constexpr int32_t CAVE_COARSE_Y = 176;
constexpr int32_t CAVE_COARSE_REACH = 286;
constexpr int32_t CAVE_FINE_X = 112;
constexpr int32_t CAVE_FINE_Y = 96;
constexpr int32_t CAVE_FINE_REACH = 146;
constexpr int32_t CAVE_ANCHOR_ROOF = 40;
// Deepest anchor that can still breach: the entrance gate needs anchor_depth - 60 < 268.
constexpr int32_t ENTRANCE_MAX_ANCHOR_DEPTH = 328;
constexpr int32_t COAL_GRID_X = 236;
constexpr int32_t COAL_GRID_Y = 188;
constexpr int32_t COAL_REACH = 150;
constexpr int32_t DRY_TABLE = 1 << 28;
constexpr int32_t START_CORE_RADIUS = 96;
constexpr int32_t MAX_NODES = 20;
} // namespace

// ---------------------------------------------------------------------------------------
// Cave system descriptors
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_gather_cave_layer(V5Context &context, uint32_t domain, int32_t grid_x,
                                           int32_t grid_y, int32_t reach, bool allow_cavern) const {
    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;

    const int32_t depth_low = top - context.surface_max - CAVE_ANCHOR_ROOF;
    const int32_t depth_high = bottom - context.surface_min - CAVE_ANCHOR_ROOF;
    const int32_t gx_first = floor_div(left - reach, grid_x);
    const int32_t gx_last = floor_div(right + reach, grid_x);
    const int32_t gy_first = floor_div(depth_low - reach, grid_y);
    int32_t gy_last = floor_div(depth_high + reach, grid_y);
    // A surface entrance is the one shape that leaves its descriptor's reach box: it runs from
    // the system all the way up to the surface. A chunk that can contain the surface must
    // therefore scan every descriptor row deep enough to send one up to it, or the shaft
    // exists for the chunk below and not for the chunk above and is capped on the boundary.
    // The reach-based window alone is not enough, because reach does not bound an entrance.
    if (bottom >= context.surface_min - 8) {
        gy_last = std::max(gy_last, floor_div(ENTRANCE_MAX_ANCHOR_DEPTH, grid_y));
    }

    // Emitting geometry through small lambdas keeps every shape in one place and avoids any
    // per-cell allocation: the scratch node buffer is stack-resident and fixed size.
    double node_x[MAX_NODES];
    double node_y[MAX_NODES];
    double node_r[MAX_NODES];
    int32_t cached_column = std::numeric_limits<int32_t>::min();
    int32_t cached_surface = 0;

    const auto emit_chain = [&](int32_t count, int32_t system, uint8_t archetype) {
        for (int32_t index = 0; index + 1 < count; ++index) {
            V5Capsule capsule;
            capsule.x0 = node_x[index];
            capsule.y0 = node_y[index];
            capsule.x1 = node_x[index + 1];
            capsule.y1 = node_y[index + 1];
            capsule.r0 = node_r[index];
            capsule.r1 = node_r[index + 1];
            capsule.system = system;
            capsule.archetype = archetype;
            context.capsules.push_back(capsule);
        }
    };

    // gx outer so the per-column surface reference is actually reused. Shape geometry is a
    // pure function of (gx, gy), so iteration order cannot change what is generated.
    for (int32_t gx = gx_first; gx <= gx_last; ++gx) {
        for (int32_t gy = gy_first; gy <= gy_last; ++gy) {
            if (gy < 0) continue;
            const int32_t anchor_x = gx * grid_x + static_cast<int32_t>(v5_hash(seed_, domain, gx, gy, 0x03) % static_cast<uint32_t>(grid_x));
            if (anchor_x + reach < left || anchor_x - reach > right) continue;
            // One surface reference per grid *column*, reused by every row: descriptor
            // rejection must stay cheap because most candidates never touch this chunk.
            if (gx != cached_column) { cached_column = gx; cached_surface = surface_height_at_v5(gx * grid_x + grid_x / 2); }
            const int32_t surface_reference = cached_surface;
            const int32_t anchor_depth = CAVE_ANCHOR_ROOF + gy * grid_y +
                static_cast<int32_t>(v5_hash(seed_, domain, gx, gy, 0x05) % static_cast<uint32_t>(grid_y));
            const int32_t anchor_y = surface_reference + anchor_depth;
            // A surface entrance is the one shape not clamped into the reach box: it runs all
            // the way up to the surface. Rejecting a descriptor on the reach box alone would
            // therefore admit it for the chunk below and reject it for the chunk above, and the
            // shaft would be capped exactly at the chunk boundary - the precise failure mode
            // this generator exists to eliminate.
            const int32_t highest = std::min(anchor_y - reach, surface_reference - 6);
            if (anchor_y + reach < top || highest > bottom) continue;
            if (anchor_y >= world_settings_.depth - 40) continue;

            const int32_t province_id = geology_province_at_v5(anchor_x, anchor_y);
            const V5ProvinceProfile &province = v5_province_profile(province_id);

            // Density is controlled by construction, not by a per-chunk cull, so the same
            // system exists for every chunk that can see it.
            const double depth_gate = smoothstep_between(20.0, 130.0, static_cast<double>(anchor_depth)) *
                                      (1.0 - 0.55 * smoothstep_between(1500.0, 3300.0, static_cast<double>(anchor_depth)));
            const double base = allow_cavern ? 0.58 : 0.54;
            if (v5_unit(seed_, domain, gx, gy, 0x07) > base * province.cave_density * depth_gate) continue;

            const int32_t system = ++context.systems;

            double weights[4] = {province.tunnel_weight, province.chamber_weight, province.fissure_weight,
                                 allow_cavern ? province.cavern_weight : 0.0};
            double weight_total = weights[0] + weights[1] + weights[2] + weights[3];
            if (weight_total <= 0.0) continue;
            double pick = v5_unit(seed_, domain, gx, gy, 0x09) * weight_total;
            int32_t archetype_index = 0;
            for (; archetype_index < 3; ++archetype_index) {
                pick -= weights[archetype_index];
                if (pick <= 0.0) break;
            }

            const double reach_limit = static_cast<double>(reach) - 8.0;
            const double origin_x = static_cast<double>(anchor_x);
            const double origin_y = static_cast<double>(anchor_y);
            const auto clamp_reach = [&](double &x, double &y) {
                x = std::clamp(x, origin_x - reach_limit, origin_x + reach_limit);
                y = std::clamp(y, origin_y - reach_limit, origin_y + reach_limit);
            };

            if (archetype_index == 0) {
                // ------------------------------------------------------------------
                // Directional tunnel. A correlated heading walk with a restoring force
                // toward the regional trend produces a passage, not per-cell jitter.
                // ------------------------------------------------------------------
                const int32_t nodes = allow_cavern ? 8 + static_cast<int32_t>(v5_hash(seed_, D_TUNNEL, gx, gy, 0x11) % 7u)
                                                   : 5 + static_cast<int32_t>(v5_hash(seed_, D_TUNNEL, gx, gy, 0x11) % 4u);
                const double horizontal = province.horizontal_bias;
                double base_angle = v5_signed(seed_, D_TUNNEL, gx, gy, 0x13) * 3.14159265358979;
                // Bias the heading toward the horizontal in bedded rock, toward the dip in
                // massive rock, by squashing the vertical component of every step.
                const double squash = 0.30 + 0.85 * (1.0 - horizontal);
                const double radius_base = 3.2 + v5_unit(seed_, D_TUNNEL, gx, gy, 0x15) * 3.6;
                const double turn = 0.20 + 0.26 * (1.0 - horizontal);
                double x = origin_x;
                double y = origin_y;
                double angle = base_angle;
                for (int32_t index = 0; index < nodes; ++index) {
                    const double t = nodes <= 1 ? 0.0 : static_cast<double>(index) / (nodes - 1);
                    node_x[index] = x;
                    node_y[index] = y;
                    node_r[index] = std::clamp(radius_base *
                        (0.60 + 0.60 * (0.5 + 0.5 * v5_signed(seed_, D_TUNNEL, gx * 131 + index, gy, 0x17))) *
                        (0.55 + 0.45 * std::sin(3.14159265358979 * std::clamp(t * 1.12, 0.0, 1.0))), 2.0, 8.0);
                    angle += v5_signed(seed_, D_TUNNEL, gx * 97 + index, gy, 0x19) * turn + (base_angle - angle) * 0.16;
                    const double step = 22.0 + v5_unit(seed_, D_TUNNEL, gx * 53 + index, gy, 0x1b) * 15.0;
                    x += std::cos(angle) * step;
                    y += std::sin(angle) * step * squash;
                    clamp_reach(x, y);
                }
                emit_chain(nodes, system, ARCH_TUNNEL);

                // Branches keep the system connected instead of scattering separate voids.
                const int32_t branches = static_cast<int32_t>(v5_hash(seed_, D_TUNNEL, gx, gy, 0x1d) % 3u);
                for (int32_t branch = 0; branch < branches; ++branch) {
                    const int32_t from = 2 + static_cast<int32_t>(v5_hash(seed_, D_TUNNEL, gx * 17 + branch, gy, 0x1f) % static_cast<uint32_t>(std::max(1, nodes - 3)));
                    double bx = node_x[std::min(from, nodes - 1)];
                    double by = node_y[std::min(from, nodes - 1)];
                    double bangle = base_angle + (branch == 0 ? 0.85 : -0.95) +
                                    v5_signed(seed_, D_TUNNEL, gx * 23 + branch, gy, 0x21) * 0.4;
                    const int32_t child = 4 + static_cast<int32_t>(v5_hash(seed_, D_TUNNEL, gx * 29 + branch, gy, 0x23) % 4u);
                    for (int32_t index = 0; index < child; ++index) {
                        node_x[index] = bx;
                        node_y[index] = by;
                        const double t = child <= 1 ? 0.0 : static_cast<double>(index) / (child - 1);
                        node_r[index] = std::clamp(radius_base * 0.72 * (1.0 - 0.55 * t), 1.8, 6.0);
                        bangle += v5_signed(seed_, D_TUNNEL, gx * 37 + branch * 11 + index, gy, 0x25) * 0.32;
                        const double step = 18.0 + v5_unit(seed_, D_TUNNEL, gx * 41 + index, gy, 0x27) * 13.0;
                        bx += std::cos(bangle) * step;
                        by += std::sin(bangle) * step * squash;
                        clamp_reach(bx, by);
                    }
                    emit_chain(child, system, ARCH_TUNNEL);
                }
            } else if (archetype_index == 1) {
                // ------------------------------------------------------------------
                // Chamber cluster. Overlapping angularly-perturbed blobs, never circles.
                // ------------------------------------------------------------------
                const int32_t count = 3 + static_cast<int32_t>(v5_hash(seed_, D_CHAMBER, gx, gy, 0x31) % 4u);
                const double spread = 12.0 + v5_unit(seed_, D_CHAMBER, gx, gy, 0x33) * 22.0;
                for (int32_t index = 0; index < count; ++index) {
                    V5Blob blob;
                    blob.cx = origin_x + v5_signed(seed_, D_CHAMBER, gx * 61 + index, gy, 0x35) * spread;
                    blob.cy = origin_y + v5_signed(seed_, D_CHAMBER, gx * 67 + index, gy, 0x37) * spread * 0.62;
                    blob.rx = 9.0 + v5_unit(seed_, D_CHAMBER, gx * 71 + index, gy, 0x39) * 15.0;
                    blob.ry = 6.0 + v5_unit(seed_, D_CHAMBER, gx * 73 + index, gy, 0x3b) * 10.0;
                    const double phase_a = v5_unit(seed_, D_CHAMBER, gx * 79 + index, gy, 0x3d) * 6.2831853;
                    const double phase_b = v5_unit(seed_, D_CHAMBER, gx * 83 + index, gy, 0x3f) * 6.2831853;
                    const double phase_c = v5_unit(seed_, D_CHAMBER, gx * 89 + index, gy, 0x41) * 6.2831853;
                    blob.amp_a = 0.16 + 0.16 * v5_unit(seed_, D_CHAMBER, gx * 91 + index, gy, 0x43);
                    blob.amp_b = 0.08 + 0.12 * v5_unit(seed_, D_CHAMBER, gx * 97 + index, gy, 0x45);
                    blob.amp_c = 0.10 + 0.14 * v5_unit(seed_, D_CHAMBER, gx * 101 + index, gy, 0x47);
                    blob.cos_a = std::cos(phase_a); blob.sin_a = std::sin(phase_a);
                    blob.cos_b = std::cos(phase_b); blob.sin_b = std::sin(phase_b);
                    blob.cos_c = std::cos(phase_c); blob.sin_c = std::sin(phase_c);
                    blob.system = system;
                    blob.archetype = ARCH_CHAMBER;
                    context.blobs.push_back(blob);
                }
                // Exits so a chamber is part of a network rather than a sealed bubble.
                const int32_t exits = 1 + static_cast<int32_t>(v5_hash(seed_, D_CHAMBER, gx, gy, 0x49) % 3u);
                for (int32_t exit = 0; exit < exits; ++exit) {
                    double angle = v5_unit(seed_, D_CHAMBER, gx * 103 + exit, gy, 0x4b) * 6.2831853;
                    double x = origin_x;
                    double y = origin_y;
                    const int32_t child = 4 + static_cast<int32_t>(v5_hash(seed_, D_CHAMBER, gx * 107 + exit, gy, 0x4d) % 5u);
                    for (int32_t index = 0; index < child; ++index) {
                        node_x[index] = x;
                        node_y[index] = y;
                        node_r[index] = std::clamp(4.4 - 0.35 * index, 2.0, 5.0);
                        angle += v5_signed(seed_, D_CHAMBER, gx * 109 + exit * 13 + index, gy, 0x4f) * 0.34;
                        const double step = 20.0 + v5_unit(seed_, D_CHAMBER, gx * 113 + index, gy, 0x51) * 14.0;
                        x += std::cos(angle) * step;
                        y += std::sin(angle) * step * 0.55;
                        clamp_reach(x, y);
                    }
                    emit_chain(child, system, ARCH_TUNNEL);
                }
            } else if (archetype_index == 2) {
                // ------------------------------------------------------------------
                // Fracture. Directionally biased but stepped, curved, branching and
                // radius-tapered, so it terminates naturally instead of ending as a
                // straight bar the way the V4 two-segment fissure did.
                // ------------------------------------------------------------------
                const int32_t nodes = allow_cavern ? 7 + static_cast<int32_t>(v5_hash(seed_, D_FISSURE, gx, gy, 0x61) % 7u)
                                                   : 5 + static_cast<int32_t>(v5_hash(seed_, D_FISSURE, gx, gy, 0x61) % 4u);
                const double dip = 1.5707963 + v5_signed(seed_, D_FISSURE, gx, gy, 0x63) * 0.55;
                const double width = 2.4 + v5_unit(seed_, D_FISSURE, gx, gy, 0x65) * 2.6;
                double x = origin_x;
                double y = origin_y - 40.0;
                double angle = dip;
                for (int32_t index = 0; index < nodes; ++index) {
                    const double t = nodes <= 1 ? 0.0 : static_cast<double>(index) / (nodes - 1);
                    node_x[index] = x;
                    node_y[index] = y;
                    // Sine taper: zero width at both terminations.
                    node_r[index] = std::max(1.3, width * std::pow(std::sin(3.14159265358979 * (0.06 + 0.88 * t)), 0.55));
                    angle += v5_signed(seed_, D_FISSURE, gx * 127 + index, gy, 0x67) * 0.46 + (dip - angle) * 0.22;
                    double step = 16.0 + v5_unit(seed_, D_FISSURE, gx * 131 + index, gy, 0x69) * 13.0;
                    x += std::cos(angle) * step;
                    y += std::sin(angle) * step;
                    // Periodic lateral jog: fractures step across bedding, they do not run
                    // as one perfectly straight cut.
                    if (index % 3 == 2) x += v5_signed(seed_, D_FISSURE, gx * 137 + index, gy, 0x6b) * 11.0;
                    clamp_reach(x, y);
                }
                emit_chain(nodes, system, ARCH_FISSURE);
                if (v5_unit(seed_, D_FISSURE, gx, gy, 0x6d) > 0.55) {
                    const int32_t from = 2 + static_cast<int32_t>(v5_hash(seed_, D_FISSURE, gx, gy, 0x6f) % static_cast<uint32_t>(std::max(1, nodes - 3)));
                    double bx = node_x[std::min(from, nodes - 1)];
                    double by = node_y[std::min(from, nodes - 1)];
                    double bangle = dip + (v5_unit(seed_, D_FISSURE, gx, gy, 0x71) > 0.5 ? 0.7 : -0.7);
                    const int32_t child = 3 + static_cast<int32_t>(v5_hash(seed_, D_FISSURE, gx, gy, 0x73) % 4u);
                    for (int32_t index = 0; index < child; ++index) {
                        const double t = child <= 1 ? 0.0 : static_cast<double>(index) / (child - 1);
                        node_x[index] = bx;
                        node_y[index] = by;
                        node_r[index] = std::max(1.2, width * 0.7 * (1.0 - t));
                        bangle += v5_signed(seed_, D_FISSURE, gx * 139 + index, gy, 0x75) * 0.42;
                        const double step = 14.0 + v5_unit(seed_, D_FISSURE, gx * 149 + index, gy, 0x77) * 11.0;
                        bx += std::cos(bangle) * step;
                        by += std::sin(bangle) * step;
                        clamp_reach(bx, by);
                    }
                    emit_chain(child, system, ARCH_FISSURE);
                }
            } else {
                // ------------------------------------------------------------------
                // Rare large cavern. Big enough to feel like a discovery; the ledge pass
                // in the chunk assembler gives it a floor rather than a bare void.
                // ------------------------------------------------------------------
                if (v5_unit(seed_, D_CAVERN, gx, gy, 0x81) < 0.62 || anchor_depth < 260) continue;
                const int32_t count = 6 + static_cast<int32_t>(v5_hash(seed_, D_CAVERN, gx, gy, 0x83) % 4u);
                const double spread = 26.0 + v5_unit(seed_, D_CAVERN, gx, gy, 0x85) * 34.0;
                for (int32_t index = 0; index < count; ++index) {
                    V5Blob blob;
                    blob.cx = origin_x + v5_signed(seed_, D_CAVERN, gx * 151 + index, gy, 0x87) * spread;
                    blob.cy = origin_y + v5_signed(seed_, D_CAVERN, gx * 157 + index, gy, 0x89) * spread * 0.48;
                    blob.rx = 22.0 + v5_unit(seed_, D_CAVERN, gx * 163 + index, gy, 0x8b) * 26.0;
                    blob.ry = 13.0 + v5_unit(seed_, D_CAVERN, gx * 167 + index, gy, 0x8d) * 15.0;
                    const double phase_a = v5_unit(seed_, D_CAVERN, gx * 173 + index, gy, 0x8f) * 6.2831853;
                    const double phase_b = v5_unit(seed_, D_CAVERN, gx * 179 + index, gy, 0x91) * 6.2831853;
                    const double phase_c = v5_unit(seed_, D_CAVERN, gx * 181 + index, gy, 0x93) * 6.2831853;
                    blob.amp_a = 0.14 + 0.14 * v5_unit(seed_, D_CAVERN, gx * 191 + index, gy, 0x95);
                    blob.amp_b = 0.07 + 0.11 * v5_unit(seed_, D_CAVERN, gx * 193 + index, gy, 0x97);
                    blob.amp_c = 0.09 + 0.13 * v5_unit(seed_, D_CAVERN, gx * 197 + index, gy, 0x99);
                    blob.cos_a = std::cos(phase_a); blob.sin_a = std::sin(phase_a);
                    blob.cos_b = std::cos(phase_b); blob.sin_b = std::sin(phase_b);
                    blob.cos_c = std::cos(phase_c); blob.sin_c = std::sin(phase_c);
                    blob.system = system;
                    blob.archetype = ARCH_CAVERN;
                    context.blobs.push_back(blob);
                }
                const int32_t exits = 2 + static_cast<int32_t>(v5_hash(seed_, D_CAVERN, gx, gy, 0x9b) % 3u);
                for (int32_t exit = 0; exit < exits; ++exit) {
                    double angle = v5_unit(seed_, D_CAVERN, gx * 199 + exit, gy, 0x9d) * 6.2831853;
                    double x = origin_x;
                    double y = origin_y;
                    const int32_t child = 5 + static_cast<int32_t>(v5_hash(seed_, D_CAVERN, gx * 211 + exit, gy, 0x9f) % 4u);
                    for (int32_t index = 0; index < child; ++index) {
                        node_x[index] = x;
                        node_y[index] = y;
                        node_r[index] = std::clamp(5.5 - 0.42 * index, 2.2, 6.0);
                        angle += v5_signed(seed_, D_CAVERN, gx * 223 + exit * 7 + index, gy, 0xa1) * 0.30;
                        const double step = 22.0 + v5_unit(seed_, D_CAVERN, gx * 227 + index, gy, 0xa3) * 15.0;
                        x += std::cos(angle) * step;
                        y += std::sin(angle) * step * 0.55;
                        clamp_reach(x, y);
                    }
                    emit_chain(child, system, ARCH_TUNNEL);
                }
            }

            // --------------------------------------------------------------------------
            // Deliberate surface entrance. Only a system whose top already reaches into the
            // shallow zone can breach, and only where the local surface is not a cliff, so
            // an entrance is a designed feature rather than an accidental one-cell hole.
            // --------------------------------------------------------------------------
            const int32_t entrance_top = anchor_y - 60;
            const int32_t local_surface = surface_reference;
            const int32_t gap = entrance_top - local_surface;
            if (gap > 18 && gap < 268) {
                const V5Climate climate = climate_at_v5(anchor_x);
                const V5BiomeProfile &biome = v5_biome_profile(climate.biome);
                if (v5_unit(seed_, D_ENTRANCE, gx, gy, 0xb1) < 0.66 * biome.cave_entrance_bias) {
                    const int32_t steps = 5;
                    double x = static_cast<double>(anchor_x);
                    double y = static_cast<double>(entrance_top);
                    const double target_x = static_cast<double>(anchor_x) + v5_signed(seed_, D_ENTRANCE, gx, gy, 0xb3) * 26.0;
                    const double target_y = static_cast<double>(local_surface) - 2.0;
                    for (int32_t index = 0; index < steps; ++index) {
                        const double t = static_cast<double>(index) / (steps - 1);
                        node_x[index] = x + (target_x - x) * t + v5_signed(seed_, D_ENTRANCE, gx * 233 + index, gy, 0xb5) * 7.0;
                        node_y[index] = y + (target_y - y) * t;
                        node_r[index] = 4.6 - 2.6 * t;
                    }
                    emit_chain(steps, system, ARCH_ENTRANCE);
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------
// Guaranteed start-region features. These use the same descriptor machinery as the rest of
// the world; they only add candidates near the origin, so nothing outside the start radius
// is aware that a guarantee exists.
// ---------------------------------------------------------------------------------------
namespace {
constexpr int32_t START_ROUTE_MIN_X = -420;
constexpr int32_t START_ROUTE_MAX_X = 640;
}

void NativeSandWorld::v5_gather_features(V5Context &context) const {
    context.capsules.clear();
    context.blobs.clear();
    context.veins.clear();
    context.systems = 0;

    v5_gather_cave_layer(context, 0x41u, CAVE_COARSE_X, CAVE_COARSE_Y, CAVE_COARSE_REACH, true);
    v5_gather_cave_layer(context, 0x42u, CAVE_FINE_X, CAVE_FINE_Y, CAVE_FINE_REACH, false);

    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;

    // Early exploration route: one descending passage that starts outside the protected
    // build core and reaches the shallow cave band, plus its surface entrance.
    if (right >= START_ROUTE_MIN_X && left <= START_ROUTE_MAX_X) {
        const int32_t mouth_x = 168 + static_cast<int32_t>(v5_hash(seed_, D_START, 0, 0, 0xc1) % 92u);
        const int32_t mouth_y = surface_height_at_v5(mouth_x) - 1;
        if (bottom >= mouth_y - 8 && top <= mouth_y + 360) {
            const int32_t system = ++context.systems;
            double x = static_cast<double>(mouth_x);
            double y = static_cast<double>(mouth_y);
            double angle = 1.5707963 + v5_signed(seed_, D_START, 0, 1, 0xc3) * 0.34;
            double nx[12], ny[12], nr[12];
            for (int32_t index = 0; index < 12; ++index) {
                const double t = static_cast<double>(index) / 11.0;
                nx[index] = x;
                ny[index] = y;
                nr[index] = 2.6 + 3.0 * smooth5(std::min(1.0, t * 2.2));
                angle += v5_signed(seed_, D_START, index, 2, 0xc5) * 0.30 + (1.35 - angle) * 0.18;
                const double step = 24.0 + v5_unit(seed_, D_START, index, 3, 0xc7) * 12.0;
                x += std::cos(angle) * step;
                y += std::sin(angle) * step;
            }
            for (int32_t index = 0; index + 1 < 12; ++index) {
                V5Capsule capsule;
                capsule.x0 = nx[index]; capsule.y0 = ny[index];
                capsule.x1 = nx[index + 1]; capsule.y1 = ny[index + 1];
                capsule.r0 = nr[index]; capsule.r1 = nr[index + 1];
                capsule.system = system;
                capsule.archetype = index == 0 ? ARCH_ENTRANCE : ARCH_TUNNEL;
                context.capsules.push_back(capsule);
            }
            // A chamber at the bottom of the route: this is the reachable early water body
            // whenever the local table sits above it.
            for (int32_t index = 0; index < 4; ++index) {
                V5Blob blob;
                blob.cx = nx[11] + v5_signed(seed_, D_START, index, 4, 0xc9) * 20.0;
                blob.cy = ny[11] + v5_signed(seed_, D_START, index, 5, 0xcb) * 11.0;
                blob.rx = 13.0 + v5_unit(seed_, D_START, index, 6, 0xcd) * 12.0;
                blob.ry = 8.0 + v5_unit(seed_, D_START, index, 7, 0xcf) * 7.0;
                const double phase = v5_unit(seed_, D_START, index, 8, 0xd1) * 6.2831853;
                blob.amp_a = 0.20; blob.cos_a = std::cos(phase); blob.sin_a = std::sin(phase);
                blob.amp_b = 0.12; blob.cos_b = std::sin(phase); blob.sin_b = std::cos(phase);
                blob.amp_c = 0.14; blob.cos_c = std::cos(phase * 1.7); blob.sin_c = std::sin(phase * 1.7);
                blob.system = system;
                blob.archetype = ARCH_CHAMBER;
                context.blobs.push_back(blob);
            }
        }
    }

    v5_gather_ore(context);
    v5_gather_scenes(context);
    v5_gather_structures(context);
}

// ---------------------------------------------------------------------------------------
// Jigsaw structures.
//
// Reusable pieces carry connection ports; a seeded builder walks open ports and attaches a
// compatible piece, rejecting anything that overlaps what it has already placed. The whole
// assembly depends only on the candidate region coordinate, so it is identical for every
// chunk that can see it and needs no shared state or global list.
//
// Only the underground facility is stamped for now. Surface ruins resolve through the same
// assembler and are exposed via get_structure_candidates(), but placing visible buildings on
// the skyline is a content and balance decision, not a generator one.
// ---------------------------------------------------------------------------------------
namespace {
struct V5JigsawPiece {
    const char *name;
    int32_t width;
    int32_t height;
    uint8_t ports;     // 1 left, 2 right, 4 top, 8 bottom
};

constexpr uint8_t PORT_LEFT = 1;
constexpr uint8_t PORT_RIGHT = 2;
constexpr uint8_t PORT_TOP = 4;
constexpr uint8_t PORT_BOTTOM = 8;

const V5JigsawPiece V5_PIECES[5] = {
    {"hall",    26, 13, PORT_LEFT | PORT_RIGHT},
    {"chamber", 20, 17, PORT_LEFT | PORT_RIGHT | PORT_BOTTOM},
    {"shaft",   11, 27, PORT_TOP | PORT_BOTTOM},
    {"vault",   24, 19, PORT_TOP | PORT_LEFT},
    {"cell",    13, 11, PORT_RIGHT},
};

constexpr int32_t JIGSAW_MAX_ROOMS = 9;
constexpr int32_t JIGSAW_REACH = 104;
constexpr int32_t STRUCTURE_REGION = 1088;
constexpr uint32_t STRUCTURE_SALT = 0x1003u;

inline uint8_t opposite_port(uint8_t port) {
    switch (port) {
        case PORT_LEFT: return PORT_RIGHT;
        case PORT_RIGHT: return PORT_LEFT;
        case PORT_TOP: return PORT_BOTTOM;
        default: return PORT_TOP;
    }
}
} // namespace

int32_t NativeSandWorld::v5_assemble_jigsaw(int32_t seed_x, int32_t seed_y, int32_t anchor_x, int32_t anchor_y,
                                            V5Room *out_rooms, int32_t capacity) const {
    int32_t count = 0;
    const int32_t root = static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, seed_x, seed_y, 0x01) % 4u);
    const V5JigsawPiece &first = V5_PIECES[root];
    out_rooms[count++] = V5Room{anchor_x - first.width / 2, anchor_y - first.height / 2,
                                anchor_x - first.width / 2 + first.width - 1,
                                anchor_y - first.height / 2 + first.height - 1, first.ports,
                                static_cast<uint8_t>(root)};

    const int32_t target = 4 + static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, seed_x, seed_y, 0x03) % 5u);
    int32_t attempt = 0;
    for (int32_t cursor = 0; cursor < count && count < std::min(capacity, target); ++cursor) {
        for (const uint8_t port : {PORT_LEFT, PORT_RIGHT, PORT_TOP, PORT_BOTTOM}) {
            if (count >= std::min(capacity, target)) break;
            if ((out_rooms[cursor].ports & port) == 0) continue;
            ++attempt;
            if (v5_unit(seed_, D_STRUCTURE, seed_x * 31 + attempt, seed_y, 0x05) > 0.78) continue;

            // Pick a piece that offers the matching port.
            const uint8_t needed = opposite_port(port);
            int32_t choice = -1;
            const int32_t offset = static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, seed_x * 37 + attempt, seed_y, 0x07) % 5u);
            for (int32_t probe = 0; probe < 5; ++probe) {
                const int32_t index = (offset + probe) % 5;
                if ((V5_PIECES[index].ports & needed) != 0) { choice = index; break; }
            }
            if (choice < 0) continue;
            const V5JigsawPiece &piece = V5_PIECES[choice];

            const V5Room &host = out_rooms[cursor];
            V5Room room{};
            room.piece = static_cast<uint8_t>(choice);
            room.ports = piece.ports;
            if (port == PORT_LEFT) {
                room.x1 = host.x0 - 1; room.x0 = room.x1 - piece.width + 1;
                room.y0 = host.y0 + (host.y1 - host.y0) / 2 - piece.height / 2;
            } else if (port == PORT_RIGHT) {
                room.x0 = host.x1 + 1; room.x1 = room.x0 + piece.width - 1;
                room.y0 = host.y0 + (host.y1 - host.y0) / 2 - piece.height / 2;
            } else if (port == PORT_TOP) {
                room.y1 = host.y0 - 1; room.y0 = room.y1 - piece.height + 1;
                room.x0 = host.x0 + (host.x1 - host.x0) / 2 - piece.width / 2;
            } else {
                room.y0 = host.y1 + 1; room.y1 = room.y0 + piece.height - 1;
                room.x0 = host.x0 + (host.x1 - host.x0) / 2 - piece.width / 2;
            }
            if (port == PORT_LEFT || port == PORT_RIGHT) room.y1 = room.y0 + piece.height - 1;
            else room.x1 = room.x0 + piece.width - 1;

            if (std::abs(room.x0 - anchor_x) > JIGSAW_REACH || std::abs(room.x1 - anchor_x) > JIGSAW_REACH) continue;
            if (std::abs(room.y0 - anchor_y) > JIGSAW_REACH || std::abs(room.y1 - anchor_y) > JIGSAW_REACH) continue;
            bool overlaps = false;
            for (int32_t other = 0; other < count && !overlaps; ++other) {
                overlaps = room.x0 <= out_rooms[other].x1 && room.x1 >= out_rooms[other].x0 &&
                           room.y0 <= out_rooms[other].y1 && room.y1 >= out_rooms[other].y0;
            }
            if (overlaps) continue;
            out_rooms[count++] = room;
        }
    }
    return count;
}

// Surface ruins use the same assembler. They are placed only on ground flat enough to have
// stood on, and sunk so that a few courses of masonry break the surface rather than a whole
// building being dropped on the skyline.
void NativeSandWorld::v5_gather_surface_ruins(V5Context &context) const {
    constexpr int32_t RUIN_REGION = 768;
    constexpr uint32_t RUIN_SALT = 0x1001u;
    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;
    const int32_t reach = JIGSAW_REACH + 32;
    if (bottom < context.surface_min - reach || top > context.surface_max + reach) return;

    V5Room rooms[JIGSAW_MAX_ROOMS];
    for (int32_t rx = floor_div(left - reach, RUIN_REGION); rx <= floor_div(right + reach, RUIN_REGION); ++rx) {
        if (v5_unit(seed_, D_STRUCTURE, rx, 0, RUIN_SALT) > 0.30) continue;
        const int32_t span = RUIN_REGION - 96 * 2;
        const int32_t x = rx * RUIN_REGION + 96 +
            static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, rx, 0, 0x1002u) % static_cast<uint32_t>(span));
        if (x + reach < left || x - reach > right) continue;
        if (std::abs(x) < 620) continue;   // the start region stays unbuilt

        // Flat enough to have been built on, sampled across the footprint.
        const int32_t centre = surface_height_at_v5(x);
        int32_t lowest = centre;
        int32_t highest = centre;
        for (int32_t offset = -56; offset <= 56; offset += 14) {
            const int32_t sample = surface_height_at_v5(x + offset);
            lowest = std::max(lowest, sample);
            highest = std::min(highest, sample);
        }
        if (lowest - highest > 7) continue;

        const int32_t y = centre + 26 + static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, rx, 0, 0x1003u) % 14u);
        if (y + JIGSAW_REACH < top || y - JIGSAW_REACH > bottom) continue;
        const int32_t count = v5_assemble_jigsaw(rx, 4093, x, y, rooms, JIGSAW_MAX_ROOMS);
        for (int32_t index = 0; index < count; ++index) {
            // Never leave masonry hanging in the air above the local surface.
            const int32_t midpoint = (rooms[index].x0 + rooms[index].x1) / 2;
            if (rooms[index].y0 < surface_height_at_v5(midpoint) + 2) continue;
            context.rooms.push_back(rooms[index]);
        }
    }
}

void NativeSandWorld::v5_gather_structures(V5Context &context) const {
    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;
    const int32_t reach = JIGSAW_REACH + 32;

    const int32_t rx_first = floor_div(left - reach, STRUCTURE_REGION);
    const int32_t rx_last = floor_div(right + reach, STRUCTURE_REGION);
    const int32_t ry_first = floor_div(top - reach, STRUCTURE_REGION);
    const int32_t ry_last = floor_div(bottom + reach, STRUCTURE_REGION);

    V5Room rooms[JIGSAW_MAX_ROOMS];
    for (int32_t ry = ry_first; ry <= ry_last; ++ry) {
        for (int32_t rx = rx_first; rx <= rx_last; ++rx) {
            if (v5_unit(seed_, D_STRUCTURE, rx, ry, STRUCTURE_SALT) > 0.34) continue;
            const int32_t span = STRUCTURE_REGION - 128 * 2;
            const int32_t x = rx * STRUCTURE_REGION + 128 +
                static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, rx, ry, STRUCTURE_SALT + 1u) % static_cast<uint32_t>(span));
            const int32_t y = ry * STRUCTURE_REGION + 128 +
                static_cast<int32_t>(v5_hash(seed_, D_STRUCTURE, rx, ry, STRUCTURE_SALT + 2u) % static_cast<uint32_t>(span));
            if (x + reach < left || x - reach > right || y + reach < top || y - reach > bottom) continue;
            const int32_t depth = y - surface_height_at_v5(x);
            if (depth < 180 || depth > 1400) continue;
            if (std::abs(x) < 140 && depth < 220) continue;
            if (y + JIGSAW_REACH >= world_settings_.depth - 40) continue;

            const int32_t count = v5_assemble_jigsaw(rx, ry, x, y, rooms, JIGSAW_MAX_ROOMS);
            for (int32_t index = 0; index < count; ++index) context.rooms.push_back(rooms[index]);
        }
    }
    v5_gather_surface_ruins(context);
}

// ---------------------------------------------------------------------------------------
// Natural feature scenes.
//
// Noita stamps hand-authored Pixel Scenes into procedural terrain. The same idea applies
// here as an extension point: a scene is a small authored arrangement of the primitives the
// generator already rasterises, placed deterministically against host constraints. Because
// it emits nothing but ordinary blobs and veins, a scene automatically inherits conservation,
// stability and chunk-order independence rather than needing its own guarantees.
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_gather_scenes(V5Context &context) const {
    constexpr int32_t SCENE_X = 1216;
    constexpr int32_t SCENE_Y = 704;
    constexpr int32_t SCENE_REACH = 64;
    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;

    const int32_t gx_first = floor_div(left - SCENE_REACH, SCENE_X);
    const int32_t gx_last = floor_div(right + SCENE_REACH, SCENE_X);
    const int32_t gy_first = floor_div(top - SCENE_REACH, SCENE_Y);
    const int32_t gy_last = floor_div(bottom + SCENE_REACH, SCENE_Y);

    for (int32_t gx = gx_first; gx <= gx_last; ++gx) {
        for (int32_t gy = gy_first; gy <= gy_last; ++gy) {
            if (v5_unit(seed_, D_SCENE, gx, gy, 0x11) > 0.46) continue;
            const int32_t x = gx * SCENE_X + static_cast<int32_t>(v5_hash(seed_, D_SCENE, gx, gy, 0x13) % static_cast<uint32_t>(SCENE_X));
            const int32_t y = gy * SCENE_Y + static_cast<int32_t>(v5_hash(seed_, D_SCENE, gx, gy, 0x15) % static_cast<uint32_t>(SCENE_Y));
            if (x + SCENE_REACH < left || x - SCENE_REACH > right) continue;
            if (y + SCENE_REACH < top || y - SCENE_REACH > bottom) continue;
            const int32_t depth = y - surface_height_at_v5(x);
            if (depth < 180 || y >= world_settings_.depth - 80) continue;

            const double weights[3] = {1.00, 0.80, 0.90};
            double total = weights[0] + weights[1] + weights[2];
            double pick = v5_unit(seed_, D_SCENE, gx, gy, 0x17) * total;
            int32_t kind = 0;
            for (; kind < 2; ++kind) { pick -= weights[kind]; if (pick <= 0.0) break; }
            const double mirror = (v5_hash(seed_, D_SCENE, gx, gy, 0x19) & 1u) != 0u ? -1.0 : 1.0;
            const int32_t system = ++context.systems;

            if (kind == 0 && depth >= 320) {
                // Geode pocket: a sealed cavity with a mineralised lining.
                V5Blob blob;
                blob.cx = x; blob.cy = y;
                blob.rx = 7.0 + v5_unit(seed_, D_SCENE, gx, gy, 0x21) * 5.0;
                blob.ry = 5.5 + v5_unit(seed_, D_SCENE, gx, gy, 0x23) * 4.0;
                const double phase = v5_unit(seed_, D_SCENE, gx, gy, 0x25) * 6.2831853;
                blob.amp_a = 0.18; blob.cos_a = std::cos(phase); blob.sin_a = std::sin(phase);
                blob.amp_b = 0.10; blob.cos_b = std::cos(phase * 2.1); blob.sin_b = std::sin(phase * 2.1);
                blob.amp_c = 0.12; blob.cos_c = std::cos(phase * 0.7); blob.sin_c = std::sin(phase * 0.7);
                blob.system = system;
                blob.archetype = ARCH_CHAMBER;
                context.blobs.push_back(blob);
                V5Vein lining;
                lining.x0 = x - blob.rx * 0.6; lining.y0 = y;
                lining.x1 = x + blob.rx * 0.6; lining.y1 = y;
                lining.r0 = blob.ry + 4.0; lining.r1 = blob.ry + 4.0;
                lining.kind = 1;
                context.veins.push_back(lining);
            } else if (kind == 1 && depth >= 260) {
                // Collapsed arch: a wide low chamber left spanned by two rock pillars.
                for (int32_t index = 0; index < 3; ++index) {
                    V5Blob blob;
                    blob.cx = x + mirror * (index - 1) * 17.0;
                    blob.cy = y + (index == 1 ? -4.0 : 0.0);
                    blob.rx = 17.0 + v5_unit(seed_, D_SCENE, gx * 31 + index, gy, 0x31) * 9.0;
                    blob.ry = 8.0 + v5_unit(seed_, D_SCENE, gx * 37 + index, gy, 0x33) * 5.0;
                    const double phase = v5_unit(seed_, D_SCENE, gx * 41 + index, gy, 0x35) * 6.2831853;
                    blob.amp_a = 0.16; blob.cos_a = std::cos(phase); blob.sin_a = std::sin(phase);
                    blob.amp_b = 0.09; blob.cos_b = std::cos(phase * 1.9); blob.sin_b = std::sin(phase * 1.9);
                    blob.amp_c = 0.11; blob.cos_c = std::cos(phase * 0.6); blob.sin_c = std::sin(phase * 0.6);
                    blob.system = system;
                    blob.archetype = ARCH_CHAMBER;
                    context.blobs.push_back(blob);
                }
                for (int32_t pillar = 0; pillar < 2; ++pillar) {
                    V5Vein column;
                    const double offset = mirror * (pillar == 0 ? -9.0 : 11.0);
                    column.x0 = x + offset; column.y0 = y - 9.0;
                    column.x1 = x + offset * 1.15; column.y1 = y + 11.0;
                    column.r0 = 2.0 + v5_unit(seed_, D_SCENE, gx * 43 + pillar, gy, 0x37) * 1.6;
                    column.r1 = column.r0 + 1.4;
                    column.kind = 2;
                    context.veins.push_back(column);
                }
            } else {
                // Mineral exposure: a bedding-parallel lens of altered, ore-bearing rock.
                const double length = 26.0 + v5_unit(seed_, D_SCENE, gx, gy, 0x41) * 30.0;
                V5Vein lens;
                lens.x0 = x - length * 0.5; lens.y0 = y + mirror * 3.0;
                lens.x1 = x + length * 0.5; lens.y1 = y - mirror * 3.0;
                lens.r0 = 3.0; lens.r1 = 5.0 + v5_unit(seed_, D_SCENE, gx, gy, 0x43) * 3.0;
                lens.kind = 1;
                context.veins.push_back(lens);
            }
        }
    }
}

// ---------------------------------------------------------------------------------------
// Resource fields.
//
// Availability is hierarchical: a regional fertility field, then host-geology suitability,
// then a depth curve, then a candidate deposit, then vein geometry that follows bedding.
// Nothing is decided by "this cell rolled under one percent".
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_gather_ore(V5Context &context) const {
    const int32_t left = context.padded_origin.x;
    const int32_t right = context.padded_origin.x + V5_PADDED - 1;
    const int32_t top = context.padded_origin.y;
    const int32_t bottom = context.padded_origin.y + V5_PADDED - 1;

    const int32_t depth_low = top - context.surface_max;
    const int32_t depth_high = bottom - context.surface_min;
    const int32_t gx_first = floor_div(left - COAL_REACH, COAL_GRID_X);
    const int32_t gx_last = floor_div(right + COAL_REACH, COAL_GRID_X);
    const int32_t gy_first = floor_div(depth_low - COAL_REACH, COAL_GRID_Y);
    const int32_t gy_last = floor_div(depth_high + COAL_REACH, COAL_GRID_Y);

    for (int32_t gy = gy_first; gy <= gy_last; ++gy) {
        if (gy < 0) continue;
        for (int32_t gx = gx_first; gx <= gx_last; ++gx) {
            const int32_t anchor_x = gx * COAL_GRID_X + static_cast<int32_t>(v5_hash(seed_, D_ORE_COAL, gx, gy, 0x01) % static_cast<uint32_t>(COAL_GRID_X));
            if (anchor_x + COAL_REACH < left || anchor_x - COAL_REACH > right) continue;
            const int32_t surface_reference = surface_height_at_v5(anchor_x);
            const int32_t anchor_depth = 46 + gy * COAL_GRID_Y +
                static_cast<int32_t>(v5_hash(seed_, D_ORE_COAL, gx, gy, 0x03) % static_cast<uint32_t>(COAL_GRID_Y));
            const int32_t anchor_y = surface_reference + anchor_depth;
            if (anchor_y + COAL_REACH < top || anchor_y - COAL_REACH > bottom) continue;

            // Regional fertility: broad rich and poor belts, not a uniform speckle.
            const double fertility = 0.5 + 0.5 * v5_fbm2(D_ORE_COAL, anchor_x, anchor_depth, 3072, 3, 0x05);
            const V5ProvinceProfile &province = v5_province_profile(geology_province_at_v5(anchor_x, anchor_depth));
            const double depth_curve = smoothstep_between(38.0, 130.0, static_cast<double>(anchor_depth)) *
                                       (1.0 - smoothstep_between(900.0, 2400.0, static_cast<double>(anchor_depth)));
            const double suitability = fertility * province.coal_richness * depth_curve;
            const double rank = v5_unit(seed_, D_ORE_COAL, gx, gy, 0x11);
            int32_t beaten = 0;
            for (int32_t oy = -1; oy <= 1; ++oy) for (int32_t ox = -1; ox <= 1; ++ox) {
                if (ox == 0 && oy == 0) continue;
                if (rank > v5_unit(seed_, D_ORE_COAL, gx + ox, gy + oy, 0x11)) ++beaten;
            }
            const double richness = fertility * province.coal_richness;
            const int32_t required = richness > 1.05 ? 6 : richness > 0.80 ? 4 : 3;
            if (beaten < required) continue;
            if (v5_unit(seed_, D_ORE_COAL, gx, gy, 0x07) > suitability * 1.30) continue;

            // Bedding-parallel lens with a shallow dip, plus one branch.
            const double dip = v5_signed(seed_, D_ORE_COAL, gx, gy, 0x09) * 0.24;
            const double bulk = 1.0 + 0.55 * std::clamp(richness - 0.80, 0.0, 1.2);
            const double length = (52.0 + v5_unit(seed_, D_ORE_COAL, gx, gy, 0x0b) * 96.0) * bulk;
            const int32_t segments = 5;
            double x = static_cast<double>(anchor_x) - length * 0.5;
            double y = static_cast<double>(anchor_y);
            for (int32_t index = 0; index < segments; ++index) {
                const double t = static_cast<double>(index) / (segments - 1);
                const double nx = static_cast<double>(anchor_x) - length * 0.5 + length * t;
                const double ny = static_cast<double>(anchor_y) + dip * (nx - anchor_x) +
                                  v5_signed(seed_, D_ORE_COAL, gx * 31 + index, gy, 0x0d) * 6.0;
                if (index > 0) {
                    V5Vein vein;
                    vein.x0 = x; vein.y0 = y; vein.x1 = nx; vein.y1 = ny;
                    const double thickness = (1.8 + 3.2 * std::sin(3.14159265358979 * std::clamp(t, 0.05, 0.95))) * bulk;
                    vein.r0 = std::max(1.2, thickness * (0.7 + 0.5 * v5_unit(seed_, D_ORE_COAL, gx * 37 + index, gy, 0x0f)));
                    vein.r1 = std::max(1.2, thickness);
                    vein.kind = 0;
                    context.veins.push_back(vein);
                }
                x = nx;
                y = ny;
            }
        }
    }

    // Guaranteed shallow starting fuel, expressed as a normal vein so it is indistinguishable
    // in kind from the rest of the world.
    if (right >= 20 && left <= 150) {
        const int32_t seam_x = 54 + static_cast<int32_t>(v5_hash(seed_, D_START, 0, 20, 0xe1) % 34u);
        const int32_t seam_y = surface_height_at_v5(seam_x) + 36 + static_cast<int32_t>(v5_hash(seed_, D_START, 0, 21, 0xe3) % 12u);
        if (bottom >= seam_y - 30 && top <= seam_y + 30) {
            V5Vein vein;
            vein.x0 = seam_x - 32; vein.y0 = static_cast<double>(seam_y) + 2.0;
            vein.x1 = seam_x + 34; vein.y1 = static_cast<double>(seam_y) - 1.0;
            vein.r0 = 3.0; vein.r1 = 3.6;
            vein.kind = 0;
            context.veins.push_back(vein);
        }
    }
}

// ---------------------------------------------------------------------------------------
// Rasterisation into the padded buffer.
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_rasterize_caves(V5Context &context) const {
    const int32_t px = context.padded_origin.x;
    const int32_t py = context.padded_origin.y;
    const int32_t floor_limit = world_settings_.depth - 14;

    const auto mark = [&](int32_t lx, int32_t ly, uint8_t archetype, int32_t system) {
        const V5Column &column = context.columns[lx];
        const int32_t world_y = py + ly;
        const int32_t depth = world_y - column.surface;
        if (depth < 0 || world_y >= floor_limit) return;
        if (archetype != ARCH_ENTRANCE && depth < v5_cave_roof(column)) return;
        // Only an entrance is allowed through the roof, and it may not open a lake basin.
        if (archetype == ARCH_ENTRANCE && column.lake_guard != 0 && world_y >= column.lake_guard - 2) return;
        const int32_t world_x = px + lx;
        // Protected build core: no ordinary void under the immediate factory start.
        if (std::abs(world_x) < START_CORE_RADIUS + 12 && depth < 210) return;
        if (v5_aquifer_barrier(context, world_x, world_y)) return;
        const int32_t index = ly * V5_PADDED + lx;
        if (context.carve[index] != 0 && context.carve[index] <= archetype) return;
        context.carve[index] = archetype;
        context.carve_system[index] = static_cast<uint16_t>(std::min(system, 65535));
    };

    for (const V5Capsule &capsule : context.capsules) {
        const double radius = std::max(capsule.r0, capsule.r1) + 1.0;
        const int32_t x0 = std::max(0, static_cast<int32_t>(std::floor(std::min(capsule.x0, capsule.x1) - radius)) - px);
        const int32_t x1 = std::min(V5_PADDED - 1, static_cast<int32_t>(std::ceil(std::max(capsule.x0, capsule.x1) + radius)) - px);
        const int32_t y0 = std::max(0, static_cast<int32_t>(std::floor(std::min(capsule.y0, capsule.y1) - radius)) - py);
        const int32_t y1 = std::min(V5_PADDED - 1, static_cast<int32_t>(std::ceil(std::max(capsule.y0, capsule.y1) + radius)) - py);
        if (x0 > x1 || y0 > y1) continue;
        for (int32_t ly = y0; ly <= y1; ++ly) {
            const double world_y = static_cast<double>(py + ly);
            for (int32_t lx = x0; lx <= x1; ++lx) {
                double t = 0.0;
                const double distance = segment_distance_squared_d(static_cast<double>(px + lx), world_y,
                                                                   capsule.x0, capsule.y0, capsule.x1, capsule.y1, t);
                const double local_radius = capsule.r0 + (capsule.r1 - capsule.r0) * t;
                if (distance <= local_radius * local_radius) mark(lx, ly, capsule.archetype, capsule.system);
            }
        }
    }

    for (const V5Blob &blob : context.blobs) {
        const double margin = 1.0 + blob.amp_a + blob.amp_b + blob.amp_c;
        const int32_t x0 = std::max(0, static_cast<int32_t>(std::floor(blob.cx - blob.rx * margin)) - px);
        const int32_t x1 = std::min(V5_PADDED - 1, static_cast<int32_t>(std::ceil(blob.cx + blob.rx * margin)) - px);
        const int32_t y0 = std::max(0, static_cast<int32_t>(std::floor(blob.cy - blob.ry * margin)) - py);
        const int32_t y1 = std::min(V5_PADDED - 1, static_cast<int32_t>(std::ceil(blob.cy + blob.ry * margin)) - py);
        if (x0 > x1 || y0 > y1) continue;
        for (int32_t ly = y0; ly <= y1; ++ly) {
            const double dy = (static_cast<double>(py + ly) - blob.cy) / blob.ry;
            for (int32_t lx = x0; lx <= x1; ++lx) {
                const double dx = (static_cast<double>(px + lx) - blob.cx) / blob.rx;
                const double length = std::sqrt(dx * dx + dy * dy);
                if (length > margin) continue;
                double boundary = 1.0;
                if (length > 1e-9) {
                    // Angular harmonics via Chebyshev recurrence: an irregular outline with
                    // no trigonometric call in the inner loop.
                    const double c = dx / length;
                    const double s = dy / length;
                    const double c2 = c * c - s * s;
                    const double s2 = 2.0 * c * s;
                    const double c3 = c * c2 - s * s2;
                    const double s3 = s * c2 + c * s2;
                    const double c5 = c3 * c2 - s3 * s2;
                    const double s5 = s3 * c2 + c3 * s2;
                    boundary += blob.amp_a * (c3 * blob.cos_a - s3 * blob.sin_a);
                    boundary += blob.amp_b * (c5 * blob.cos_b - s5 * blob.sin_b);
                    boundary += blob.amp_c * (c2 * blob.cos_c - s2 * blob.sin_c);
                }
                if (length <= boundary) mark(lx, ly, blob.archetype, blob.system);
            }
        }
    }

    // Jigsaw rooms: the interior joins the carve buffer so sediment and Sand rules see it,
    // and the masonry shell is recorded separately so a cave crossing the structure cannot
    // eat its walls.
    context.wall.assign(V5_PADDED_CELLS, 0);
    for (const V5Room &room : context.rooms) {
        const int32_t x0 = std::max(0, room.x0 - px);
        const int32_t x1 = std::min(V5_PADDED - 1, room.x1 - px);
        const int32_t y0 = std::max(0, room.y0 - py);
        const int32_t y1 = std::min(V5_PADDED - 1, room.y1 - py);
        if (x0 > x1 || y0 > y1) continue;
        for (int32_t ly = y0; ly <= y1; ++ly) {
            const int32_t world_y = py + ly;
            for (int32_t lx = x0; lx <= x1; ++lx) {
                const int32_t world_x = px + lx;
                const bool shell = world_x <= room.x0 + 1 || world_x >= room.x1 - 1 ||
                                   world_y <= room.y0 + 1 || world_y >= room.y1 - 1;
                const int32_t index = ly * V5_PADDED + lx;
                if (!shell) { context.carve[index] = ARCH_SCENE; context.wall[index] = 0; continue; }
                // Doorways: a two-cell gap centred on each declared port.
                const int32_t mid_y = (room.y0 + room.y1) / 2;
                const int32_t mid_x = (room.x0 + room.x1) / 2;
                const bool doorway =
                    ((room.ports & 1u) != 0 && world_x <= room.x0 + 1 && std::abs(world_y - mid_y) <= 2) ||
                    ((room.ports & 2u) != 0 && world_x >= room.x1 - 1 && std::abs(world_y - mid_y) <= 2) ||
                    ((room.ports & 4u) != 0 && world_y <= room.y0 + 1 && std::abs(world_x - mid_x) <= 2) ||
                    ((room.ports & 8u) != 0 && world_y >= room.y1 - 1 && std::abs(world_x - mid_x) <= 2);
                if (doorway) { context.carve[index] = ARCH_SCENE; context.wall[index] = 0; continue; }
                context.wall[index] = 1;
                context.carve[index] = 0;
            }
        }
    }

    // Two exact cleanup passes. The padding makes the neighbourhood test position-pure, so
    // the result does not depend on which chunk performed it.
    for (int32_t pass = 0; pass < 2; ++pass) {
        std::vector<uint8_t> next = context.carve;
        for (int32_t ly = 1; ly < V5_PADDED - 1; ++ly) {
            for (int32_t lx = 1; lx < V5_PADDED - 1; ++lx) {
                const int32_t index = ly * V5_PADDED + lx;
                if (context.carve[index] == 0) continue;
                if (context.carve[index] == ARCH_SCENE) continue;   // authored geometry is deliberate
                const bool connected = context.carve[index - 1] != 0 || context.carve[index + 1] != 0 ||
                                       context.carve[index - V5_PADDED] != 0 || context.carve[index + V5_PADDED] != 0;
                if (!connected) next[index] = 0;
            }
        }
        context.carve.swap(next);
    }
}

// ---------------------------------------------------------------------------------------
// Vegetation. Driven by the V5 surface and biome; the legacy organic pass still uses the V2
// surface and would float or bury every tree in a V5 world.
// ---------------------------------------------------------------------------------------
void NativeSandWorld::v5_apply_vegetation(GeneratedChunk &generated, const V5Context &context) const {
    constexpr int32_t BIN_WIDTH = 26;
    const Vector2i origin = context.origin;
    const int32_t first_bin = floor_div(origin.x - 30, BIN_WIDTH);
    const int32_t last_bin = floor_div(origin.x + CHUNK_SIZE + 30, BIN_WIDTH);
    for (int32_t bin = first_bin; bin <= last_bin; ++bin) {
        const int32_t anchor_x = bin * BIN_WIDTH + 4 + static_cast<int32_t>(v5_hash(seed_, D_VEGETATION, bin, 0, 0x11) % 18u);
        const int32_t local_anchor = anchor_x - context.padded_origin.x;
        if (local_anchor < 0 || local_anchor >= V5_PADDED) continue;
        const V5Column &column = context.columns[local_anchor];
        const V5BiomeProfile &biome = v5_biome_profile(column.biome);
        if (column.slope > 3 || column.lake_mass > 0) continue;
        if (v5_unit(seed_, D_VEGETATION, bin, 1, 0x13) > biome.vegetation * 0.72) continue;
        if (column.sand_depth > 3) continue;

        const uint32_t shape = v5_hash(seed_, D_VEGETATION, bin, 2, 0x15);
        const int32_t surface = column.surface;
        const int32_t height = 11 + static_cast<int32_t>(shape % 11u);
        const int32_t thickness = height >= 18 && ((shape >> 8u) & 1u) != 0u ? 2 : 1;
        const int32_t canopy_radius = 4 + static_cast<int32_t>((shape >> 10u) % 3u);
        const int32_t moisture = 26 + static_cast<int32_t>((shape >> 14u) % 62u);
        const int32_t branch_y = surface - height / 2;
        const Vector2i canopy_center{anchor_x + thickness / 2, surface - height + 2};

        for (int32_t ly = 0; ly < CHUNK_SIZE; ++ly) {
            for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
                const Vector2i cell = origin + Vector2i(lx, ly);
                bool wood = cell.y >= surface - height && cell.y < surface && cell.x >= anchor_x && cell.x < anchor_x + thickness;
                const Vector2i delta = cell - canopy_center;
                const bool leaves = delta.x * delta.x * 3 + delta.y * delta.y * 4 <= canopy_radius * canopy_radius * 4;
                if (cell.y == branch_y && std::abs(cell.x - anchor_x) <= 3 + static_cast<int32_t>((shape >> 18u) & 3u)) wood = true;
                if (!wood && !leaves) continue;
                const int32_t index = ly * CHUNK_SIZE + lx;
                if (generated.material[index] != EMPTY) continue;
                generated.material[index] = static_cast<uint16_t>(wood ? WOOD : LEAVES);
                if (generated.organic_moisture == nullptr) {
                    generated.organic_moisture = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
                    generated.organic_moisture->fill(0);
                }
                (*generated.organic_moisture)[index] = static_cast<uint8_t>(wood ? moisture : moisture / 2);
            }
        }
    }

    // Sparse physical food specimens on cave and surface floors. The support has to be
    // ground: scanning for "first empty cell above anything" put specimens on top of tree
    // canopies, where they read as floating dots in the sky.
    for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
        const int32_t world_x = origin.x + lx;
        if ((v5_hash(seed_, D_VEGETATION, world_x, context.origin.y, 0x17) % 233u) != 0u) continue;
        for (int32_t ly = 1; ly < CHUNK_SIZE - 1; ++ly) {
            const int32_t index = ly * CHUNK_SIZE + lx;
            if (generated.material[index] != EMPTY) continue;
            const int32_t below = generated.material[index + CHUNK_SIZE];
            if (below != STONE && below != SAND && below != COAL) continue;
            generated.material[index] = RAW_FOOD;
            break;
        }
    }
}

void NativeSandWorld::v5_debug_carve_chunk(Vector2i coordinate, V5Context &context) const {
    const Vector2i origin = coordinate * CHUNK_SIZE;
    context.origin = origin;
    context.padded_origin = origin - Vector2i(V5_PAD, V5_PAD);
    context.columns.assign(V5_PADDED, V5Column());
    context.carve.assign(V5_PADDED_CELLS, 0);
    context.carve_system.assign(V5_PADDED_CELLS, 0);
    v5_build_bed_cumulative(context);
    v5_prepare_lakes(context);
    const int32_t probe_y = origin.y + CHUNK_SIZE / 2;
    context.surface_min = std::numeric_limits<int32_t>::max();
    context.surface_max = std::numeric_limits<int32_t>::min();
    for (int32_t index = 0; index < V5_PADDED; ++index) {
        v5_fill_column(context, context.columns[index], context.padded_origin.x + index, probe_y);
        context.surface_min = std::min(context.surface_min, context.columns[index].surface);
        context.surface_max = std::max(context.surface_max, context.columns[index].surface);
    }
    v5_prepare_tables(context);
    v5_gather_features(context);
    v5_rasterize_caves(context);
}

// ---------------------------------------------------------------------------------------
// Chunk assembly
// ---------------------------------------------------------------------------------------
std::unique_ptr<NativeSandWorld::GeneratedChunk> NativeSandWorld::generate_chunk_data_v5(Vector2i coordinate) const {
    const auto started = std::chrono::steady_clock::now();
    auto generated = std::make_unique<GeneratedChunk>();
    generated->coordinate = coordinate;
    generated->temperature.fill(TEMPERATURE_AMBIENT);
    const Vector2i origin = coordinate * CHUNK_SIZE;

    V5Context context;
    context.origin = origin;
    context.padded_origin = origin - Vector2i(V5_PAD, V5_PAD);
    context.columns.resize(V5_PADDED);
    context.carve.assign(V5_PADDED_CELLS, 0);
    context.carve_system.assign(V5_PADDED_CELLS, 0);
    context.capsules.reserve(192);
    context.blobs.reserve(96);
    context.veins.reserve(48);
    context.rooms.reserve(16);

    v5_build_bed_cumulative(context);
    v5_prepare_lakes(context);
    const int32_t probe_y = origin.y + CHUNK_SIZE / 2;
    context.surface_min = std::numeric_limits<int32_t>::max();
    context.surface_max = std::numeric_limits<int32_t>::min();
    for (int32_t index = 0; index < V5_PADDED; ++index) {
        v5_fill_column(context, context.columns[index], context.padded_origin.x + index, probe_y);
        context.surface_min = std::min(context.surface_min, context.columns[index].surface);
        context.surface_max = std::max(context.surface_max, context.columns[index].surface);
    }

    v5_prepare_tables(context);
    v5_gather_features(context);
    v5_rasterize_caves(context);

    // A surface entrance is allowed to breach the roof, so it can pass straight through a
    // loose deposit. Drop the deposit wherever the carve buffer undercuts it: generated Sand
    // has to be settled on publication, and the player is the one who gets to destabilise it.
    for (int32_t index = 0; index < V5_PADDED; ++index) {
        V5Column &column = context.columns[index];
        if (column.sand_depth <= 0) continue;
        const int32_t top = column.surface - context.padded_origin.y - 3;
        const int32_t bottom = top + column.sand_depth + 9;
        bool undercut = false;
        for (int32_t ly = std::max(0, top); ly <= std::min(V5_PADDED - 1, bottom) && !undercut; ++ly) {
            for (int32_t offset = -2; offset <= 2; ++offset) {
                const int32_t lx = index + offset;
                if (lx < 0 || lx >= V5_PADDED) continue;
                if (context.carve[ly * V5_PADDED + lx] != 0) { undercut = true; break; }
            }
        }
        if (undercut) column.sand_depth = 0;
    }

    // Partial cells are recorded and applied after the material pass: the amount plane has to
    // be initialised from the *finished* materials, or every full cell would read as mass 0.
    std::vector<std::pair<int32_t, uint8_t>> partial_cells;
    const auto carved_at = [&](int32_t lx, int32_t ly) {
        const int32_t x = lx + V5_PAD;
        const int32_t y = ly + V5_PAD;
        if (x < 0 || y < 0 || x >= V5_PADDED || y >= V5_PADDED) return false;
        return context.carve[y * V5_PADDED + x] != 0;
    };

    // ---- base material -------------------------------------------------------------
    // Column-major so the bedding walk and the mineralisation cache stay coherent.
    for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
        const V5Column &column = context.columns[lx + V5_PAD];
        const int32_t world_x = origin.x + lx;
        int32_t cached_block = std::numeric_limits<int32_t>::min();
        int32_t cached_rock = -1;
        uint16_t cached_profile = 1;
        // Province is a coarse crustal field. Sampling it once per four rows keeps the
        // Voronoi cost negligible; the per-column phase offset breaks the sampling lattice so
        // a province contact reads as an irregular geological boundary rather than a
        // staircase locked to the sampling grid.
        const int32_t province_phase = static_cast<int32_t>((static_cast<uint32_t>(world_x) * 2654435761u) >> 30u);
        int32_t province_block = std::numeric_limits<int32_t>::min();
        int32_t cell_province = column.province;

        for (int32_t ly = 0; ly < CHUNK_SIZE; ++ly) {
            const int32_t index = ly * CHUNK_SIZE + lx;
            const Vector2i cell{world_x, origin.y + ly};
            if (!is_inside_virtual_world(cell)) {
                generated->material[index] = static_cast<uint16_t>(cell.y < -world_settings_.sky ? EMPTY : BEDROCK);
                continue;
            }
            if (cell.y >= world_settings_.depth - 10) {
                generated->material[index] = BEDROCK;
                continue;
            }
            const int32_t depth = cell.y - column.surface;
            if (depth < 0) {
                // Sky, or a surface lake filled to its analytic spill level.
                if (column.lake_mass > 0 && cell.y >= column.lake_level) {
                    generated->material[index] = WATER;
                    if (cell.y == column.lake_level && column.lake_mass < 255) {
                        partial_cells.emplace_back(index, static_cast<uint8_t>(column.lake_mass));
                    }
                } else {
                    generated->material[index] = EMPTY;
                }
                continue;
            }

            if (!context.wall.empty() && context.wall[(ly + V5_PAD) * V5_PADDED + (lx + V5_PAD)] != 0) {
                // Masonry: a ruin wall keeps its cell even where a cave system runs through it.
                generated->material[index] = STONE;
                generated->provenance[index] = v5_stone_profile(0, cell.x, cell.y, depth, column.province);
                generated->mineral_signature[index] = static_cast<uint16_t>(
                    v5_hash(seed_, D_SEDIMENT, cell.x, cell.y, 0x61) & 0xffffu);
                continue;
            }
            if (carved_at(lx, ly)) {
                // Local water table decides whether the void is dry, flooded, or holds the
                // waterline row. The shape comes from geology and cave geometry.
                int32_t local = 0;
                const int32_t region = v5_table_region(cell.x, cell.y, local);
                const int32_t table = v5_context_table_mu(context, region);
                if (table < DRY_TABLE) {
                    const int32_t level_row = table / 255;
                    if (cell.y > level_row) {
                        generated->material[index] = WATER;
                        continue;
                    }
                    if (cell.y == level_row) {
                        const int32_t mass = 255 * (level_row + 1) - table;
                        if (mass >= 24) {
                            generated->material[index] = WATER;
                            if (mass < 255) partial_cells.emplace_back(index, static_cast<uint8_t>(mass));
                            continue;
                        }
                    }
                }
                generated->material[index] = EMPTY;
                continue;
            }

            // Solid column: loose Sand, then the three surface horizons, then bedding.
            int32_t rock = 0;
            if (depth < column.sand_depth) {
                generated->material[index] = SAND;
                generated->provenance[index] = v5_stone_profile(8, cell.x, cell.y, depth, column.province);
                generated->mineral_signature[index] = mineral_signature_for(cell);
                continue;
            }
            if (depth < column.soil) rock = 8;
            else if (depth < column.sediment) rock = 9;
            else if (depth < column.weathered) rock = 10;
            else {
                const int32_t block4 = (cell.y + province_phase) >> 2;
                if (block4 != province_block) {
                    province_block = block4;
                    cell_province = geology_province_at_v5(cell.x, (block4 << 2) - province_phase);
                }
                int32_t bed = column.bed_first + column.bed_stored;
                for (int32_t offset = 0; offset < column.bed_stored; ++offset) {
                    if (cell.y < column.bed_y[offset]) { bed = column.bed_first + offset; break; }
                }
                rock = v5_bed_rock_at(cell_province, bed, cell.y);
            }

            const int32_t block = cell.y >> 3;
            if (block != cached_block || rock != cached_rock) {
                cached_block = block;
                cached_rock = rock;
                cached_profile = v5_stone_profile(rock, cell.x & ~7, block << 3, depth, cell_province);
            }
            generated->material[index] = STONE;
            generated->provenance[index] = cached_profile;
            generated->mineral_signature[index] = static_cast<uint16_t>(
                v5_hash(seed_, D_SEDIMENT, cell.x >> 2, cell.y >> 2, 0x21) & 0xffffu);
        }
    }

    // ---- ore veins -----------------------------------------------------------------
    for (const V5Vein &vein : context.veins) {
        const double radius = std::max(vein.r0, vein.r1) + 1.0;
        const int32_t x0 = std::max(0, static_cast<int32_t>(std::floor(std::min(vein.x0, vein.x1) - radius)) - origin.x);
        const int32_t x1 = std::min(CHUNK_SIZE - 1, static_cast<int32_t>(std::ceil(std::max(vein.x0, vein.x1) + radius)) - origin.x);
        const int32_t y0 = std::max(0, static_cast<int32_t>(std::floor(std::min(vein.y0, vein.y1) - radius)) - origin.y);
        const int32_t y1 = std::min(CHUNK_SIZE - 1, static_cast<int32_t>(std::ceil(std::max(vein.y0, vein.y1) + radius)) - origin.y);
        for (int32_t ly = y0; ly <= y1; ++ly) {
            for (int32_t lx = x0; lx <= x1; ++lx) {
                const int32_t index = ly * CHUNK_SIZE + lx;
                const int32_t material = generated->material[index];
                // Solid fill may only close an air cell. Overwriting Water would destroy mass.
                if (vein.kind == 2 ? material != EMPTY : material != STONE) continue;
                double t = 0.0;
                const double distance = segment_distance_squared_d(static_cast<double>(origin.x + lx),
                                                                   static_cast<double>(origin.y + ly),
                                                                   vein.x0, vein.y0, vein.x1, vein.y1, t);
                const double local_radius = vein.r0 + (vein.r1 - vein.r0) * t;
                if (distance > local_radius * local_radius) continue;
                const V5Column &vein_column = context.columns[lx + V5_PAD];
                if (vein.kind == 0) {
                    generated->material[index] = COAL;
                } else if (vein.kind == 1) {
                    // Alteration raises the ore-bearing constituents of the host rock without
                    // inventing a new material, so the mass stays exactly what geology holds.
                    const uint16_t host = generated->provenance[index];
                    const int32_t iron = std::min(31, static_cast<int32_t>((host >> 5u) & 31u) + 9);
                    const int32_t heavy = std::min(7, static_cast<int32_t>((host >> 10u) & 7u) + 2);
                    const int32_t gold = std::min(7, static_cast<int32_t>((host >> 13u) & 7u) + 3);
                    generated->provenance[index] = static_cast<uint16_t>((host & 31u) |
                        (static_cast<uint32_t>(iron) << 5u) | (static_cast<uint32_t>(heavy) << 10u) |
                        (static_cast<uint32_t>(gold) << 13u));
                } else {
                    generated->material[index] = STONE;
                    generated->provenance[index] = v5_stone_profile(4, origin.x + lx, origin.y + ly,
                        std::max(0, origin.y + ly - vein_column.surface), vein_column.province);
                    generated->mineral_signature[index] = static_cast<uint16_t>(
                        v5_hash(seed_, D_SEDIMENT, origin.x + lx, origin.y + ly, 0x51) & 0xffffu);
                }
            }
        }
    }

    // ---- cave-floor sediment -------------------------------------------------------
    // Deposits follow geometry: a void cell becomes Sand only when the three cells beneath
    // it are solid, which is exactly the condition the sand simulation uses to stay asleep.
    for (int32_t ly = CHUNK_SIZE - 1; ly >= 0; --ly) {
        for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
            const int32_t index = ly * CHUNK_SIZE + lx;
            if (generated->material[index] != EMPTY) continue;
            if (!carved_at(lx, ly)) continue;
            const V5Column &column = context.columns[lx + V5_PAD];
            const int32_t depth = origin.y + ly - column.surface;
            if (depth < 0) continue;
            const bool supported = !carved_at(lx, ly + 1) && !carved_at(lx - 1, ly + 1) && !carved_at(lx + 1, ly + 1);
            if (!supported) continue;
            const uint32_t roll = v5_hash(seed_, D_SEDIMENT, origin.x + lx, origin.y + ly, 0x31) % 100u;
            const V5ProvinceProfile &province = v5_province_profile(column.province);
            const uint32_t chance = static_cast<uint32_t>(std::clamp(30.0 + 34.0 * province.permeability, 5.0, 92.0));
            if (roll >= chance) continue;
            generated->material[index] = SAND;
            generated->provenance[index] = v5_stone_profile(9, origin.x + lx, origin.y + ly, depth, column.province);
            generated->mineral_signature[index] = mineral_signature_for(Vector2i(origin.x + lx, origin.y + ly));
        }
    }

    // Final Sand support backstop.
    //
    // Every pass that can place Sand has its own support rule, and each one reasons about the
    // world from a slightly different angle: surface deposits about neighbouring columns, cave
    // floors about the carve buffer, authored rooms about neither. One of them will eventually
    // be wrong. This sweep is the invariant itself rather than another approximation of it: a
    // generated Sand cell with an open cell beneath it becomes host rock instead. It reads the
    // finished materials, so it cannot disagree with what was actually emitted.
    for (int32_t ly = CHUNK_SIZE - 1; ly >= 0; --ly) {
        for (int32_t lx = 0; lx < CHUNK_SIZE; ++lx) {
            const int32_t index = ly * CHUNK_SIZE + lx;
            if (generated->material[index] != SAND) continue;
            bool undermined = false;
            for (int32_t offset = -1; offset <= 1 && !undermined; ++offset) {
                const int32_t nx = lx + offset;
                const int32_t ny = ly + 1;
                if (nx < 0 || nx >= CHUNK_SIZE) {
                    // Outside the chunk: the padded carve buffer is the only view available,
                    // so treat anything hollow there as unsupported.
                    undermined = carved_at(nx, ny);
                } else if (ny < CHUNK_SIZE) {
                    undermined = generated->material[ny * CHUNK_SIZE + nx] == EMPTY;
                } else {
                    undermined = carved_at(nx, ny);
                }
            }
            if (!undermined) continue;
            const V5Column &column = context.columns[lx + V5_PAD];
            const int32_t depth = origin.y + ly - column.surface;
            generated->material[index] = STONE;
            generated->provenance[index] = v5_stone_profile(10, origin.x + lx, origin.y + ly,
                                                            std::max(0, depth), column.province);
            generated->mineral_signature[index] = static_cast<uint16_t>(
                v5_hash(seed_, D_SEDIMENT, origin.x + lx, origin.y + ly, 0x71) & 0xffffu);
        }
    }

    v5_apply_vegetation(*generated, context);

    if (!partial_cells.empty()) {
        generated->material_amount = std::make_unique<std::array<uint8_t, CELLS_PER_CHUNK>>();
        for (int32_t index = 0; index < CELLS_PER_CHUNK; ++index)
            (*generated->material_amount)[index] = generated->material[index] == EMPTY ? 0 : 255;
        for (const auto &[index, mass] : partial_cells)
            if (generated->material[index] == WATER) (*generated->material_amount)[index] = mass;
    }

    generated->generation_usec = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - started).count();
    return generated;
}
} // namespace godot
