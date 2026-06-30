#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace visual_relay
{

std::uint64_t monotonic_time_ns();
std::uint64_t stable_session_id(std::string_view name);
std::string env_or(std::string_view name, std::string fallback);
int env_port(std::string_view name, int fallback);
void log_line(std::string_view service, std::string_view message);

class StopState
{
public:
    void request_stop();
    bool stop_requested() const;

private:
    std::atomic_bool stop_{false};
};

class ReadyState
{
public:
    void mark(std::string name);
    bool has(std::string_view name) const;
    bool has_all(const std::vector<std::string>& names) const;
    std::string summary() const;

private:
    mutable std::mutex mutex_;
    std::vector<std::string> marks_;
};

class ReadyHttpServer
{
public:
    ReadyHttpServer(std::string service_name, ReadyState& ready,
                    StopState& stop, std::vector<std::string> required_marks,
                    int port);
    ReadyHttpServer(const ReadyHttpServer&) = delete;
    ReadyHttpServer& operator=(const ReadyHttpServer&) = delete;
    ~ReadyHttpServer();

    void start();
    void join();

private:
    void run();

    std::string service_name_;
    ReadyState& ready_;
    StopState& stop_;
    std::vector<std::string> required_marks_;
    int port_;
    std::thread thread_;
};

void install_signal_handlers(StopState& stop);

}  // namespace visual_relay
