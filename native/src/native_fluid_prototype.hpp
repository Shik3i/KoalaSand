#pragma once

#include "fluid_prototype.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

namespace godot {

class NativeFluidPrototype : public RefCounted {
    GDCLASS(NativeFluidPrototype, RefCounted)

public:
    void configure_representative(int32_t requested_workers = 4);
    Dictionary step_representative();
    Dictionary get_memory_statistics() const;
    String state_hash() const;

protected:
    static void _bind_methods();

private:
    std::unique_ptr<koalasand_core::FluidPrototype> prototype_;
    int64_t tick_ = 0;
    int64_t last_step_usec_ = 0;
    koalasand_core::FluidTelemetry last_;
};

} // namespace godot
