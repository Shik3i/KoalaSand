#include "physical_traits.hpp"

#include <algorithm>

namespace koalasand_core {

std::uint32_t mix_u32(std::uint32_t hash, std::int32_t component) noexcept {
    return (hash ^ static_cast<std::uint32_t>(component)) * 16777619u;
}

Constituent hidden_constituent(std::uint16_t profile, std::uint16_t signature) noexcept {
    if (profile == 0) return Constituent::Other;
    const std::int32_t q_silica = profile & 31u;
    const std::int32_t q_iron = (profile >> 5u) & 31u;
    const std::int32_t q_heavy = (profile >> 10u) & 7u;
    const std::int32_t q_gold = (profile >> 13u) & 7u;
    std::int32_t silica = 680000 + (280000 * q_silica) / 31;
    std::int32_t iron = 10000 + (130000 * q_iron) / 31;
    std::int32_t heavy = 2000 + (55000 * q_heavy) / 7;
    const std::int32_t primary = silica + iron + heavy;
    if (primary > 985000) {
        silica = static_cast<std::int32_t>((static_cast<std::int64_t>(silica) * 985000) / primary);
        iron = static_cast<std::int32_t>((static_cast<std::int64_t>(iron) * 985000) / primary);
        heavy = static_cast<std::int32_t>((static_cast<std::int64_t>(heavy) * 985000) / primary);
    }
    const std::int32_t sample = static_cast<std::int32_t>((static_cast<std::int64_t>(signature) * 1000000 + 32768) / 65536);
    if (sample < silica) return Constituent::Silica;
    if (sample < silica + iron) return Constituent::IronBearing;
    if (sample < silica + iron + heavy) {
        if (q_gold > 0) {
            const std::int32_t gold_share = std::min(180000, 8000 * (1 << q_gold));
            const std::int32_t within_heavy = heavy > 0 ? static_cast<std::int32_t>((static_cast<std::int64_t>(sample - silica - iron) * 1000000) / heavy) : 1000000;
            if (within_heavy < gold_share) return Constituent::GoldBearing;
        }
        return Constituent::HeavyMineral;
    }
    return Constituent::Other;
}

std::int32_t grain_size_class(std::int32_t material_id, std::uint16_t profile, std::uint16_t signature) noexcept {
    if (material_id == 6) return 0;
    if (material_id >= 8) return 1;
    std::uint32_t stable = mix_u32(0x53495a45u, signature);
    stable = mix_u32(stable, profile);
    std::int32_t grain = static_cast<std::int32_t>(stable % 3u);
    if (hidden_constituent(profile, signature) == Constituent::HeavyMineral && grain == 0) grain = 1;
    return grain;
}

std::int32_t magnetic_susceptibility(std::int32_t material_id, std::uint16_t profile, std::uint16_t signature) noexcept {
    if (material_id == 8 || material_id == 11) return 1000;
    const Constituent constituent = hidden_constituent(profile, signature);
    if (constituent == Constituent::IronBearing) return 920;
    if (constituent == Constituent::HeavyMineral) return 180;
    return 0;
}

} // namespace koalasand_core
