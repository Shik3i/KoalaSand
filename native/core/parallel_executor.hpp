#pragma once

#include "worker_backend.hpp"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace koalasand_core {

class ParallelExecutor {
public:
    explicit ParallelExecutor(std::int32_t requested_workers = 1);
    ~ParallelExecutor();
    ParallelExecutor(const ParallelExecutor &) = delete;
    ParallelExecutor &operator=(const ParallelExecutor &) = delete;

    void run(std::int32_t jobs, const std::function<void(std::int32_t, std::int32_t)> &job);
    std::int32_t worker_count() const { return worker_count_; }
    WorkerBackend backend() const { return worker_count_ == 1 ? WorkerBackend::SingleThread : WorkerBackend::NativeThreads; }
    std::int32_t workers_used_last_run() const { return workers_used_last_run_; }
    std::uint64_t wait_ns_last_run() const { return wait_ns_last_run_; }

private:
    void worker_loop(std::int32_t worker_index);
    void consume(std::int32_t worker_index);

    std::int32_t worker_count_ = 1;
    std::vector<std::thread> workers_;
    std::mutex mutex_;
    std::condition_variable start_;
    std::condition_variable done_;
    std::condition_variable ready_;
    std::function<void(std::int32_t, std::int32_t)> job_;
    std::atomic<std::int32_t> next_job_{0};
    std::atomic<std::int32_t> workers_used_{0};
    std::int32_t job_count_ = 0;
    std::int32_t pending_ = 0;
    std::int32_t ready_count_ = 0;
    std::int32_t workers_used_last_run_ = 0;
    std::uint64_t wait_ns_last_run_ = 0;
    std::uint64_t generation_ = 0;
    bool stop_ = false;
};

} // namespace koalasand_core
