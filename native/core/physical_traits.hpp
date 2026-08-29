#pragma once

#include <cstdint>

namespace koalasand_core {

enum class Constituent : std::int32_t { Silica = 0, IronBearing = 1, HeavyMineral = 2, GoldBearing = 3, Other = 4 };

std::uint32_t mix_u32(std::uint32_t hash, std::int32_t component) noexcept;
Constituent hidden_constituent(std::uint16_t profile, std::uint16_t signature) noexcept;
std::int32_t grain_size_class(std::int32_t material_id, std::uint16_t profile, std::uint16_t signature) noexcept;
std::int32_t magnetic_susceptibility(std::int32_t material_id, std::uint16_t profile, std::uint16_t signature) noexcept;

} // namespace koalasand_core
