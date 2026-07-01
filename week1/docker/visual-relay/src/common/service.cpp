#include "visual_relay/service.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <span>
#include <sstream>
#include <string>
#include <utility>

#include "visual_relay/rik_asio.hpp"

namespace visual_relay
{
namespace
{

StopState* g_stop_state = nullptr;

void handle_signal(int) {
    if (g_stop_state != nullptr) {
        g_stop_state->request_stop();
    }
}

}  // namespace

std::uint64_t monotonic_time_ns() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(now).count());
}

std::uint64_t stable_session_id(std::string_view name) {
    std::uint64_t hash = 1469598103934665603ULL;
    for (const auto ch : name) {
        hash ^= static_cast<unsigned char>(ch);
        hash *= 1099511628211ULL;
    }
    hash ^= monotonic_time_ns();
    return hash == 0 ? 1 : hash;
}

std::string env_or(std::string_view name, std::string fallback) {
    if (const char* value = std::getenv(std::string(name).c_str());
        value != nullptr && value[0] != '\0') {
        return value;
    }
    return fallback;
}

int env_port(std::string_view name, int fallback) {
    if (const char* value = std::getenv(std::string(name).c_str());
        value != nullptr && value[0] != '\0') {
        return std::max(1, std::atoi(value));
    }
    return fallback;
}

void log_line(std::string_view service, std::string_view message) {
    std::cout << "[" << service << "] " << message << std::endl;
}

void StopState::request_stop() {
    stop_.store(true);
}

bool StopState::stop_requested() const {
    return stop_.load();
}

void ReadyState::mark(std::string name) {
    std::scoped_lock lock(mutex_);
    if (std::find(marks_.begin(), marks_.end(), name) == marks_.end()) {
        marks_.push_back(std::move(name));
    }
}

bool ReadyState::has(std::string_view name) const {
    std::scoped_lock lock(mutex_);
    return std::find(marks_.begin(), marks_.end(), name) != marks_.end();
}

bool ReadyState::has_all(const std::vector<std::string>& names) const {
    std::scoped_lock lock(mutex_);
    return std::all_of(names.begin(), names.end(), [&](const auto& name) {
        return std::find(marks_.begin(), marks_.end(), name) != marks_.end();
    });
}

std::string ReadyState::summary() const {
    std::scoped_lock lock(mutex_);
    std::ostringstream out;
    for (std::size_t i = 0; i < marks_.size(); ++i) {
        if (i != 0) {
            out << ",";
        }
        out << marks_[i];
    }
    return out.str();
}

ReadyHttpServer::ReadyHttpServer(std::string service_name, ReadyState& ready,
                                 StopState& stop,
                                 std::vector<std::string> required_marks,
                                 int port)
    : service_name_(std::move(service_name)),
      ready_(ready),
      stop_(stop),
      required_marks_(std::move(required_marks)),
      port_(port) {}

ReadyHttpServer::~ReadyHttpServer() {
    join();
}

void ReadyHttpServer::start() {
    thread_ = std::thread([this] { run(); });
}

void ReadyHttpServer::join() {
    if (thread_.joinable()) {
        thread_.join();
    }
}

void ReadyHttpServer::run() {
    try {
        auto acceptor = rik_asio::tcp_acceptor::bind_any(port_);
        acceptor.set_non_blocking(true);
        while (!stop_.stop_requested()) {
            auto accepted = acceptor.accept_for(std::chrono::milliseconds(50));
            if (accepted.would_block()) continue;
            if (!accepted.ok()) {
                continue;
            }
            std::array<char, 512> request{};
            (void)accepted.socket.read_some_for(
                std::span<char>(request.data(), request.size()),
                std::chrono::milliseconds(250));
            const bool ready = ready_.has_all(required_marks_);
            const auto body = service_name_ +
                              " ready=" + (ready ? "true " : "false ") +
                              ready_.summary() + "\n";
            const std::string response =
                std::string("HTTP/1.1 ") +
                (ready ? "200 OK" : "503 Service Unavailable") +
                "\r\nContent-Type: text/plain\r\nContent-Length: " +
                std::to_string(body.size()) + "\r\n\r\n" + body;
            (void)accepted.socket.write_all_for(response,
                                                std::chrono::milliseconds(250));
        }
    }
    catch (const std::exception& ex) {
        log_line(service_name_,
                 std::string("readiness server failed: ") + ex.what());
        stop_.request_stop();
    }
}

void install_signal_handlers(StopState& stop) {
    g_stop_state = &stop;
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);
}

}  // namespace visual_relay
