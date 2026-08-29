#include "physical_traits.hpp"
#include "fluid_prototype.hpp"
#include "worker_backend.hpp"

#include <cstdint>

int main() {
    std::uint32_t hash = 2166136261u;
    koalasand_core::deterministic_single_thread(256, [&](std::int32_t index) {
        hash = koalasand_core::mix_u32(hash, koalasand_core::grain_size_class(2, 2386, static_cast<std::uint16_t>(index)));
        hash = koalasand_core::mix_u32(hash, koalasand_core::magnetic_susceptibility(7, 2386, static_cast<std::uint16_t>(index)));
    });
    koalasand_core::FluidPrototype fluid(8, 8, koalasand_core::FluidCandidate::FixedMass8, 1);
    fluid.set_water(4, 2, 255);
    fluid.wake_all();
    fluid.step();
    hash = koalasand_core::mix_u32(hash, static_cast<std::uint32_t>(fluid.state_hash()));
    return hash == 0 ? 1 : 0;
}
