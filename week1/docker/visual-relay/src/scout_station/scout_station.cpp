#include <array>
#include <chrono>
#include <span>
#include <string>
#include <thread>

#include "visual_relay/gui.hpp"
#include "visual_relay/latest_value.hpp"
#include "visual_relay/protocol.hpp"
#include "visual_relay/rik_asio.hpp"
#include "visual_relay/service.hpp"

using namespace visual_relay;

namespace
{

CameraFrame initial_scout_frame() {
    return parse_camera_frame(
        "VRFRAME|view=scout|frame=0|phase=0|fps=0|latency_ms=0|eta=0|"
        "descriptor=0|tcp=connecting|udp=waiting|handoff=waiting|objects=",
        StationView::scout);
}

void receive_camera(ReadyState& ready, StopState& stop,
                    LatestValue<CameraFrame>& frame) {
    try {
        auto socket =
            rik_asio::udp_socket::bind_any(env_port("CAMERA_PORT", 5000));
        socket.set_non_blocking(true);
        std::array<std::uint8_t, 32768> data{};
        rik_asio::endpoint sender;
        // Camera images arrive as a run of small row-band chunks; this
        // accumulates them across datagrams. A dropped chunk just leaves
        // stale pixels in those rows instead of losing the whole frame.
        CameraChunkReceiver camera_frames(initial_scout_frame());
        while (!stop.stop_requested()) {
            const auto result = socket.receive_from(
                std::span<std::uint8_t>(data.data(), data.size()), sender);
            if (result.ok() && result.bytes > 0) {
                if (camera_frames.apply(std::span<const std::uint8_t>(
                        data.data(), result.bytes))) {
                    while (!stop.stop_requested() &&
                           !frame.publish(camera_frames.frame(),
                                          std::chrono::milliseconds(50))) {
                    }
                    ready.mark("camera_frame");
                }
            }
            else {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("scout-station",
                 std::string("camera receiver failed: ") + ex.what());
        stop.request_stop();
    }
}

void send_track_updates(ReadyState& ready, StopState& stop,
                        std::uint64_t session_id) {
    try {
        auto socket = rik_asio::udp_socket::open();
        const auto catcher =
            rik_asio::resolve_udp(env_or("CATCHER_HOST", "catcher-station"),
                                  env_or("TRACK_UPDATE_PORT", "6100"));
        ready.mark("udp_sender");
        std::uint64_t sequence = 0;
        while (!stop.stop_requested()) {
            TrackUpdate update;
            update.session_id = session_id;
            update.track_id = 7001;
            update.sequence = ++sequence;
            update.capture_time_ns = monotonic_time_ns();
            update.belt_position_m =
                0.25F + static_cast<float>(sequence % 100) * 0.012F;
            update.velocity_mps = 0.62F;
            update.predicted_exit_time_s = 1.8F;
            update.confidence = 0.88F;
            const auto packet = serialize_track_update(update);
            const auto sent = socket.send_to(
                std::span<const std::uint8_t>(packet.data(), packet.size()),
                catcher);
            if (!sent.ok()) {
                log_line("scout-station", "UDP track update send failed");
                ready.mark("udp_degraded");
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(40));
        }
    }
    catch (const std::exception& ex) {
        log_line("scout-station",
                 std::string("UDP sender failed: ") + ex.what());
        stop.request_stop();
    }
}

void write_frame(rik_asio::tcp_socket& socket, const MessageFrame& frame) {
    const auto bytes = serialize_message(frame);
    socket.write_all(std::span<const std::uint8_t>(bytes.data(), bytes.size()));
}

void handoff_client(ReadyState& ready, StopState& stop,
                    std::uint64_t session_id) {
    std::uint64_t message_id = 9001;
    while (!stop.stop_requested()) {
        try {
            auto socket = rik_asio::tcp_socket::connect(
                env_or("CATCHER_HOST", "catcher-station"),
                env_or("HANDOFF_PORT", "6200"));
            ready.mark("handoff_client");
            log_line("scout-station", "handoff TCP connected");

            write_frame(socket,
                        make_text_message(MessageType::hello, session_id,
                                          message_id++, 0, "scout-station"));
            write_frame(socket, make_text_message(MessageType::handoff_prepare,
                                                  session_id, message_id,
                                                  message_id, "track=7001"));
            write_frame(
                socket,
                make_text_message(
                    MessageType::handoff_descriptor, session_id, message_id,
                    message_id,
                    "track=7001;class=red-crate;material=painted-aluminum;"
                    "marks=yellow-stripe,right-side-scuff;quality=0.88;"
                    "eta=2.39"));
            write_frame(socket,
                        make_text_message(MessageType::handoff_thumbnail,
                                          session_id, message_id, message_id,
                                          "thumbnail=inline-demo-64x64"));
            write_frame(
                socket,
                make_text_message(MessageType::handoff_commit, session_id,
                                  message_id, message_id, "commit=track-7001"));

            std::array<std::uint8_t, 256> response{};
            const auto result = socket.read_some(
                std::span<std::uint8_t>(response.data(), response.size()));
            if (result.ok() && result.bytes > 0) {
                log_line("scout-station", "handoff response received");
                ready.mark("handoff_accept");
            }
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        catch (const std::exception& ex) {
            log_line("scout-station",
                     std::string("handoff reconnect pending: ") + ex.what());
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    }
}

}  // namespace

int main() {
    StopState stop;
    ReadyState ready;
    install_signal_handlers(stop);
    const auto session_id = stable_session_id("scout-station");
    LatestValue<CameraFrame> shared_frame{initial_scout_frame()};

    GuiWindow gui("Visual Relay Scout");
    if (!gui.ok()) {
        log_line("scout-station", "GUI backend is required");
        return 2;
    }
    ready.mark("gui");

    ReadyHttpServer health(
        "scout-station", ready, stop,
        {"gui", "camera_frame", "udp_sender", "handoff_client"},
        env_port("READY_PORT", 9001));
    health.start();
    std::thread camera([&] { receive_camera(ready, stop, shared_frame); });
    std::thread udp_sender(
        [&] { send_track_updates(ready, stop, session_id); });
    std::thread handoff([&] { handoff_client(ready, stop, session_id); });

    CameraFrame frame = initial_scout_frame();
    while (!stop.stop_requested()) {
        shared_frame.take(frame);
        frame.tcp_state =
            ready.has("handoff_client") ? "connected" : frame.tcp_state;
        frame.udp_state =
            ready.has("udp_degraded")
                ? "degraded"
                : (ready.has("udp_sender") ? "fresh" : frame.udp_state);
        if (ready.has("handoff_accept")) {
            frame.handoff_state = "accepted";
        }
        gui.poll(stop, frame, ready.summary());
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }

    if (camera.joinable()) camera.join();
    if (udp_sender.joinable()) udp_sender.join();
    if (handoff.joinable()) handoff.join();
    health.join();
    log_line("scout-station", "stopped");
    return 0;
}
