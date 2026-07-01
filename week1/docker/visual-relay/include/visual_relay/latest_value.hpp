#pragma once

#include <chrono>
#include <semaphore>
#include <utility>

namespace visual_relay
{

// Single-producer/single-consumer "latest value" slot. Synchronization is
// done purely with a pair of C++20 counting semaphores: `free_` lets the
// producer know the slot isn't being read right now, `ready_` lets the consumer
// know a fresh value is waiting. Their acquire()/release() pairing establishes
// the happens-before edges that make the plain copies of `slot_` race-free.
template <typename T>
class LatestValue
{
public:
    explicit LatestValue(T initial) : slot_(std::move(initial)) {}

    // Blocks only as long as the consumer is mid-take(); bounded by
    // `wait_timeout` so callers can stay responsive to shutdown requests.
    // Returns false on timeout (caller should retry).
    template <typename Rep, typename Period>
    bool publish(T value,
                 const std::chrono::duration<Rep, Period>& wait_timeout) {
        if (!free_.try_acquire_for(wait_timeout)) {
            return false;
        }
        slot_ = std::move(value);
        ready_.release();
        return true;
    }

    // Non-blocking. Returns true and overwrites `out` if a new value has
    // been published since the last successful take(); otherwise leaves
    // `out` untouched so the caller keeps showing the last known frame.
    bool take(T& out) {
        if (!ready_.try_acquire()) {
            return false;
        }
        out = slot_;
        free_.release();
        return true;
    }

private:
    T slot_;
    std::binary_semaphore free_{1};
    std::binary_semaphore ready_{0};
};

}  // namespace visual_relay
