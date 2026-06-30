#include <array>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <span>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "visual_relay/protocol.hpp"
#include "visual_relay/rik_asio.hpp"
#include "visual_relay/service.hpp"

using namespace visual_relay;

namespace
{

struct SimObject
{
    std::uint64_t track_id;
    std::string label;
    std::string material;
    float spawn_offset_m;
    float lane_offset_m;
    float velocity_scale;
};

constexpr float kBeltLengthM = 6.0F;
constexpr float kTunnelStartM = 2.4F;
constexpr float kTunnelEndM = 3.6F;
constexpr float kFrameDtS = 0.05F;
constexpr float kBaseVelocityMps = 0.62F;

const std::vector<SimObject>& scene_objects() {
    static const std::vector<SimObject> objects{
        {7001, "red-crate", "painted-aluminum", 0.10F, -0.18F, 1.00F},
        {7002, "blue-cylinder", "brushed-metal", 1.12F, 0.23F, 0.96F},
        {7003, "yellow-wedge", "rubberized", 2.26F, 0.02F, 1.05F},
        {7004, "green-gear", "worn-polymer", 3.42F, -0.27F, 0.98F},
        {7005, "white-tag", "matte-ceramic", 4.78F, 0.29F, 1.02F},
    };
    return objects;
}

float wrap_belt(float position_m) {
    auto wrapped = std::fmod(position_m, kBeltLengthM);
    if (wrapped < 0.0F) {
        wrapped += kBeltLengthM;
    }
    return wrapped;
}

std::string handoff_stage(std::uint64_t frame) {
    switch ((frame / 45U) % 5U) {
        case 0:
            return "detecting";
        case 1:
            return "prepare";
        case 2:
            return "descriptor";
        case 3:
            return "commit";
        default:
            return "accepted";
    }
}

std::string encode_camera_frame(std::string_view view, std::uint64_t frame) {
    const float time_s = static_cast<float>(frame) * kFrameDtS;
    const bool catcher = view == "catcher";
    std::ostringstream out;
    out << std::fixed << std::setprecision(2);
    out << "VRFRAME|view=" << view << "|frame=" << frame
        << "|phase=" << std::fmod(time_s, 1.0F) << "|fps=20|latency_ms="
        << (catcher ? 34.0F + std::sin(time_s) * 4.0F
                    : 27.0F + std::cos(time_s) * 3.0F)
        << "|eta=" << std::max(0.0F, (kTunnelEndM - 2.12F) / kBaseVelocityMps)
        << "|descriptor=" << (catcher ? 0.74F : 0.88F) << "|tcp="
        << (frame > 55 ? "connected" : "connecting") << "|udp="
        << (frame > 12 ? "fresh" : "waiting") << "|handoff="
        << handoff_stage(frame);

    const float arm_a = 0.72F + std::sin(time_s * 0.7F) * 0.28F;
    const float arm_b = -1.18F + std::cos(time_s * 0.6F) * 0.22F;
    out << "|arm=" << arm_a << "," << arm_b << "|objects=";

    bool first = true;
    for (const auto& object : scene_objects()) {
        float position = wrap_belt(object.spawn_offset_m +
                                   time_s * kBaseVelocityMps *
                                       object.velocity_scale);
        float lane = object.lane_offset_m;
        float rotation = time_s * (1.2F + object.velocity_scale);
        if (position >= kTunnelStartM && position <= kTunnelEndM) {
            const float tunnel_u =
                (position - kTunnelStartM) / (kTunnelEndM - kTunnelStartM);
            lane += std::sin(tunnel_u * 7.1F + object.spawn_offset_m) * 0.14F;
            rotation += tunnel_u * 2.4F;
        }

        const bool visible_to_scout = position < kTunnelStartM + 0.12F;
        const bool visible_to_catcher = position > kTunnelEndM - 0.12F;
        if ((!catcher && !visible_to_scout) ||
            (catcher && !visible_to_catcher)) {
            continue;
        }

        const bool target = object.track_id == 7001;
        const float confidence =
            std::clamp(0.92F - std::abs(lane) * 0.21F +
                           std::sin(time_s + object.spawn_offset_m) * 0.04F,
                       0.45F, 0.98F);
        const float match =
            target ? std::clamp(0.86F + std::sin(time_s * 1.6F) * 0.08F,
                                0.72F, 0.97F)
                   : std::clamp(0.36F + std::cos(time_s + object.spawn_offset_m) *
                                           0.12F,
                                0.12F, 0.58F);

        if (!first) {
            out << ";";
        }
        first = false;
        out << object.track_id << "," << object.label << "," << object.material
            << "," << position << "," << lane << "," << rotation << ","
            << confidence << "," << match << "," << (target ? 1 : 0);
    }
    return out.str();
}

void control_server(ReadyState& ready, StopState& stop) {
    try {
        auto acceptor =
            rik_asio::tcp_acceptor::bind_any(env_port("CONTROL_PORT", 6300));
        acceptor.set_non_blocking(true);
        ready.mark("control_endpoint");
        while (!stop.stop_requested()) {
            auto accepted = acceptor.accept();
            if (accepted.would_block()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
                continue;
            }
            if (!accepted.ok()) {
                continue;
            }
            auto socket = std::move(accepted.socket);
            socket.set_non_blocking(true);
            const auto lease_start = monotonic_time_ns();
            std::array<char, 256> buf{};
            while (!stop.stop_requested() &&
                   monotonic_time_ns() - lease_start < 5'000'000'000ULL) {
                const auto result =
                    socket.read_some(std::span<char>(buf.data(), buf.size()));
                if (result.ok() && result.bytes > 0) {
                    log_line("relay-simulator",
                             "control lease heartbeat received");
                    break;
                }
                if (!result.would_block()) {
                    break;
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("relay-simulator",
                 std::string("control server failed: ") + ex.what());
        stop.request_stop();
    }
}

void camera_sender(ReadyState& ready, StopState& stop) {
    try {
        auto socket = rik_asio::udp_socket::open();
        rik_asio::endpoint scout;
        rik_asio::endpoint catcher;
        while (!stop.stop_requested()) {
            try {
                scout =
                    rik_asio::resolve_udp(env_or("SCOUT_HOST", "scout-station"),
                                          env_or("SCOUT_CAMERA_PORT", "5000"));
                catcher = rik_asio::resolve_udp(
                    env_or("CATCHER_HOST", "catcher-station"),
                    env_or("CATCHER_CAMERA_PORT", "5002"));
                break;
            }
            catch (const std::exception& ex) {
                log_line("relay-simulator",
                         std::string("camera endpoint discovery pending: ") +
                             ex.what());
                std::this_thread::sleep_for(std::chrono::milliseconds(500));
            }
        }
        if (stop.stop_requested()) {
            return;
        }
        ready.mark("rtp_sender");

        std::uint64_t frame = 0;
        while (!stop.stop_requested()) {
            const auto scout_payload = encode_camera_frame("scout", frame);
            const auto catcher_payload = encode_camera_frame("catcher", frame);

            socket.send_to(scout_payload, scout);
            if (!ready.has("scout_frame")) {
                ready.mark("scout_frame");
            }
            socket.send_to(catcher_payload, catcher);
            if (!ready.has("catcher_frame")) {
                ready.mark("catcher_frame");
            }
            ++frame;
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
    }
    catch (const std::exception& ex) {
        log_line("relay-simulator",
                 std::string("camera sender failed: ") + ex.what());
        stop.request_stop();
    }
}

}  // namespace

int main() {
    StopState stop;
    ReadyState ready;
    install_signal_handlers(stop);

    log_line("relay-simulator", "starting deterministic offscreen world");
    ready.mark("assets");
    ready.mark("renderer");

    ReadyHttpServer health("relay-simulator", ready, stop,
                           {"assets", "renderer", "control_endpoint",
                            "rtp_sender", "scout_frame", "catcher_frame"},
                           env_port("READY_PORT", 9000));
    health.start();

    std::thread control([&] { control_server(ready, stop); });
    std::thread cameras([&] { camera_sender(ready, stop); });

    while (!stop.stop_requested()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    if (control.joinable()) {
        control.join();
    }
    if (cameras.joinable()) {
        cameras.join();
    }
    health.join();
    log_line("relay-simulator", "stopped");
    return 0;
}
