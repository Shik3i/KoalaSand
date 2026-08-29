#pragma once

#include <cstdint>
#include <functional>

namespace koalasand_core {

enum class WorkerBackend : std::uint8_t { SingleThread = 0, NativeThreads = 1, WebThreads = 2 };

struct WorkerPolicy {
    WorkerBackend backend = WorkerBackend::SingleThread;
    std::int32_t worker_count = 1;
};

inline void deterministic_single_thread(std::int32_t jobs, const std::function<void(std::int32_t)> &run) {
    for (std::int32_t index = 0; index < jobs; ++index) run(index);
}

} // namespace koalasand_core
