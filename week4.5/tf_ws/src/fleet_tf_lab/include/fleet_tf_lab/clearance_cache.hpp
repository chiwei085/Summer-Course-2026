#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <thread>

namespace fleet_tf_lab
{

// Snapshot of the AMR's clearance to the nearest obstacle, as computed by
// the lidar driver thread from the front laser. Several independent consumer
// threads (the safety supervisor, the fleet telemetry uplink, the dock
// approach checker, a local dashboard feed) each poll this at their own rate.
struct ClearanceState
{
    double min_clearance_m = 2.0;
    bool slow_zone = false;
    std::uint64_t sequence = 0;
};

// A hand-rolled reader-writer lock: any number of readers may hold it at
// once, a writer needs exclusive access. Every thread blocks properly on a
// condition variable -- nobody spins, nobody burns CPU. Admission policy: a
// new reader may join the readers already inside whenever no writer is
// currently writing; the writer proceeds once nobody else is inside.
class NaiveReaderPreferringLock
{
public:
    void lockRead() {
        std::unique_lock<std::mutex> lock(mutex_);
        readers_cv_.wait(lock, [this] { return !writer_active_; });
        ++active_readers_;
    }

    void unlockRead() {
        std::unique_lock<std::mutex> lock(mutex_);
        if (--active_readers_ == 0) {
            writer_cv_.notify_one();
        }
    }

    void lockWrite() {
        std::unique_lock<std::mutex> lock(mutex_);
        writer_cv_.wait(
            lock, [this] { return !writer_active_ && active_readers_ == 0; });
        writer_active_ = true;
    }

    void unlockWrite() {
        std::unique_lock<std::mutex> lock(mutex_);
        writer_active_ = false;
        lock.unlock();
        writer_cv_.notify_one();
        readers_cv_.notify_all();
    }

private:
    std::mutex mutex_;
    std::condition_variable readers_cv_;
    std::condition_variable writer_cv_;
    int active_readers_ = 0;
    bool writer_active_ = false;
};

// Thread-safe holder for the latest ClearanceState, guarded by the lock
// above. `writes_committed` is a mutex-guarded counter incremented by the
// writer after it releases the lock, used only for grading -- it does not
// participate in the reader/writer contention being studied here.
class ClearanceCache
{
public:
    ClearanceState read() {
        lock_.lockRead();
        ClearanceState copy = state_;
        lock_.unlockRead();
        return copy;
    }

    // Consumers that process the snapshot in place (instead of copying it
    // out immediately) hold the read lock for the duration of `work_time` --
    // a realistic reason a "read" can take long enough for a batch of
    // overlapping readers to keep the resource permanently busy.
    ClearanceState readWithSimulatedWork(std::chrono::microseconds work_time) {
        lock_.lockRead();
        std::this_thread::sleep_for(work_time);
        ClearanceState copy = state_;
        lock_.unlockRead();
        return copy;
    }

    void write(const ClearanceState& state) {
        lock_.lockWrite();
        state_ = state;
        lock_.unlockWrite();
        std::lock_guard<std::mutex> guard(counter_mutex_);
        ++writes_committed_;
    }

    std::uint64_t writesCommitted() {
        std::lock_guard<std::mutex> guard(counter_mutex_);
        return writes_committed_;
    }

private:
    NaiveReaderPreferringLock lock_;
    ClearanceState state_{};
    std::mutex counter_mutex_;
    std::uint64_t writes_committed_ = 0;
};

}  // namespace fleet_tf_lab
