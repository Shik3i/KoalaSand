#include "parallel_executor.hpp"

#include <algorithm>
#include <chrono>

namespace koalasand_core {

ParallelExecutor::ParallelExecutor(std::int32_t requested_workers) {
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
    requested_workers = 1;
#endif
    const auto hardware = static_cast<std::int32_t>(std::max(1u, std::thread::hardware_concurrency()));
    worker_count_ = std::clamp(requested_workers, 1, hardware);
    for (std::int32_t index = 1; index < worker_count_; ++index) workers_.emplace_back(&ParallelExecutor::worker_loop, this, index);
    std::unique_lock<std::mutex> lock(mutex_);
    ready_.wait(lock, [this] { return ready_count_ == static_cast<std::int32_t>(workers_.size()); });
}

ParallelExecutor::~ParallelExecutor() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        stop_ = true;
        ++generation_;
    }
    start_.notify_all();
    for (auto &worker : workers_) if (worker.joinable()) worker.join();
}

void ParallelExecutor::consume(std::int32_t worker_index) {
    bool used = false;
    for (;;) {
        const std::int32_t index = next_job_.fetch_add(1, std::memory_order_relaxed);
        if (index >= job_count_) break;
        used = true;
        job_(index, worker_index);
    }
    if (used) workers_used_.fetch_add(1, std::memory_order_relaxed);
}

void ParallelExecutor::run(std::int32_t jobs, const std::function<void(std::int32_t, std::int32_t)> &job) {
    if (jobs <= 0) { workers_used_last_run_ = 0; wait_ns_last_run_ = 0; return; }
    if (worker_count_ == 1 || jobs == 1) {
        for (std::int32_t index = 0; index < jobs; ++index) job(index, 0);
        workers_used_last_run_ = 1;
        wait_ns_last_run_ = 0;
        return;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        job_ = job;
        job_count_ = jobs;
        next_job_.store(0, std::memory_order_relaxed);
        workers_used_.store(0, std::memory_order_relaxed);
        pending_ = static_cast<std::int32_t>(workers_.size());
        ++generation_;
    }
    start_.notify_all();
    consume(0);
    const auto wait_started = std::chrono::steady_clock::now();
    std::unique_lock<std::mutex> lock(mutex_);
    done_.wait(lock, [this] { return pending_ == 0; });
    wait_ns_last_run_ = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now() - wait_started).count());
    workers_used_last_run_ = workers_used_.load(std::memory_order_relaxed);
    job_ = {};
}

void ParallelExecutor::worker_loop(std::int32_t worker_index) {
    std::uint64_t observed;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        observed = generation_;
        ++ready_count_;
        ready_.notify_one();
    }
    for (;;) {
        {
            std::unique_lock<std::mutex> lock(mutex_);
            start_.wait(lock, [this, &observed] { return stop_ || generation_ != observed; });
            if (stop_) return;
            observed = generation_;
        }
        consume(worker_index);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (--pending_ == 0) done_.notify_one();
        }
    }
}

} // namespace koalasand_core
