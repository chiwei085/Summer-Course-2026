#include <array>
#include <chrono>
#include <cstring>
#include <optional>
#include <set>
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

struct HandoffBook
{
    std::set<std::uint64_t> prepared;
    std::set<std::uint64_t> described;
    std::set<std::uint64_t> thumbnails;
    std::set<std::uint64_t> committed;
};

CameraFrame initial_catcher_frame() {
    return parse_camera_frame(
        "VRFRAME|view=catcher|frame=0|phase=0|fps=0|latency_ms=0|eta=0|"
        "descriptor=0|tcp=connecting|udp=waiting|handoff=waiting|"
        "arm=0.7,-1.1|objects=",
        StationView::catcher);
}

void receive_track_updates(ReadyState& ready, StopState& stop) {
    try {
        auto socket =
            rik_asio::udp_socket::bind_any(env_port("TRACK_UPDATE_PORT", 6100));
        socket.set_non_blocking(true);
        std::array<std::uint8_t, kTrackUpdateWireSize> packet{};
        rik_asio::endpoint sender;
        std::uint64_t expected_session = 0;
        std::uint64_t last_sequence = 0;
        ready.mark("udp_receiver");
        while (!stop.stop_requested()) {
            const auto result = socket.receive_from(
                std::span<std::uint8_t>(packet.data(), packet.size()), sender);
            if (result.ok() && result.bytes == packet.size()) {
                try {
                    const auto update = parse_track_update(packet);
                    if (expected_session == 0) {
                        expected_session = update.session_id;
                    }
                    if (is_fresh_track_update(
                            update, expected_session, last_sequence,
                            monotonic_time_ns(), 750'000'000ULL)) {
                        last_sequence = update.sequence;
                        ready.mark("fresh_track_update");
                    }
                }
                catch (const ProtocolError& ex) {
                    log_line("catcher-station",
                             std::string("dropped UDP update: ") + ex.what());
                }
            }
            else {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("catcher-station",
                 std::string("UDP receiver failed: ") + ex.what());
        stop.request_stop();
    }
}

std::optional<MessageFrame> read_frame_for(rik_asio::tcp_socket& socket,
                                           std::chrono::milliseconds timeout) {
    std::array<std::uint8_t, kMessageHeaderWireSize> header{};
    if (!socket.read_exact_for(
            std::span<std::uint8_t>(header.data(), header.size()), timeout)) {
        return std::nullopt;
    }
    std::uint32_t payload_size = 0;
    std::memcpy(&payload_size, header.data() + 8, sizeof(payload_size));
    if (payload_size > kMaxMessagePayloadSize) {
        throw ProtocolError("message payload too large");
    }
    std::vector<std::uint8_t> bytes(header.begin(), header.end());
    bytes.resize(header.size() + payload_size);
    if (payload_size > 0 &&
        !socket.read_exact_for(
            std::span<std::uint8_t>(bytes.data() + header.size(), payload_size),
            timeout)) {
        return std::nullopt;
    }
    return parse_message(bytes);
}

void send_handoff_reply(rik_asio::tcp_socket& socket, MessageType type,
                        std::uint64_t session_id, std::uint64_t correlation_id,
                        std::string_view text) {
    const auto response = serialize_message(make_text_message(
        type, session_id, correlation_id + 1, correlation_id, text));
    (void)socket.write_all_for(
        std::span<const std::uint8_t>(response.data(), response.size()),
        std::chrono::milliseconds(500));
}

void handoff_server(ReadyState& ready, StopState& stop) {
    try {
        auto acceptor =
            rik_asio::tcp_acceptor::bind_any(env_port("HANDOFF_PORT", 6200));
        acceptor.set_non_blocking(true);
        HandoffBook book;
        ready.mark("handoff_server");
        while (!stop.stop_requested()) {
            auto accepted = acceptor.accept_for(std::chrono::milliseconds(50));
            if (accepted.would_block()) continue;
            if (!accepted.ok()) {
                continue;
            }
            auto socket = std::move(accepted.socket);
            while (!stop.stop_requested()) {
                try {
                    const auto maybe_frame =
                        read_frame_for(socket, std::chrono::milliseconds(750));
                    if (!maybe_frame.has_value()) {
                        break;
                    }
                    const auto& frame = *maybe_frame;
                    const auto type =
                        static_cast<MessageType>(frame.header.message_type);
                    const auto id = frame.header.correlation_id == 0
                                        ? frame.header.message_id
                                        : frame.header.correlation_id;
                    if (type == MessageType::handoff_prepare) {
                        book.prepared.insert(id);
                    }
                    else if (type == MessageType::handoff_descriptor &&
                             book.prepared.contains(id)) {
                        book.described.insert(id);
                    }
                    else if (type == MessageType::handoff_thumbnail &&
                             book.prepared.contains(id)) {
                        book.thumbnails.insert(id);
                    }
                    else if (type == MessageType::handoff_commit) {
                        const bool complete = book.prepared.contains(id) &&
                                              book.described.contains(id);
                        if (complete && !book.committed.contains(id)) {
                            book.committed.insert(id);
                            ready.mark("handoff_commit");
                            send_handoff_reply(socket, MessageType::handoff_accept,
                                              frame.header.session_id, id,
                                              "accepted");
                        }
                        else if (book.committed.contains(id)) {
                            send_handoff_reply(socket, MessageType::handoff_accept,
                                              frame.header.session_id, id,
                                              "duplicate-accepted");
                        }
                        else {
                            send_handoff_reply(socket, MessageType::handoff_reject,
                                              frame.header.session_id, id,
                                              "incomplete");
                        }
                    }
                }
                catch (const std::exception&) {
                    break;
                }
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("catcher-station",
                 std::string("handoff server failed: ") + ex.what());
        stop.request_stop();
    }
}

void arm_control_client(ReadyState& ready, StopState& stop) {
    while (!stop.stop_requested()) {
        try {
            auto socket = rik_asio::tcp_socket::connect(
                env_or("SIMULATOR_HOST", "relay-simulator"),
                env_or("CONTROL_PORT", "6300"));
            socket.write_all("catcher-arm-heartbeat\n");
            ready.mark("arm_control");
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
        catch (const std::exception& ex) {
            log_line(
                "catcher-station",
                std::string("arm control reconnect pending: ") + ex.what());
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    }
}

}  // namespace

int main() {
    StopState stop;
    ReadyState ready;
    install_signal_handlers(stop);
    LatestValue<CameraFrame> shared_frame{initial_catcher_frame()};

    GuiWindow gui("Visual Relay Catcher");
    if (!gui.ok()) {
        log_line("catcher-station", "GUI backend is required");
        return 2;
    }
    ready.mark("gui");

    ReadyHttpServer health("catcher-station", ready, stop,
                           {"gui", "camera_frame", "udp_receiver",
                            "handoff_server", "arm_control"},
                           env_port("READY_PORT", 9002));
    health.start();
    std::thread camera([&] {
        receive_camera_frames(ready, stop, shared_frame, "catcher-station",
                              env_port("CAMERA_PORT", 5002),
                              initial_catcher_frame());
    });
    std::thread udp_receiver([&] { receive_track_updates(ready, stop); });
    std::thread handoff([&] { handoff_server(ready, stop); });
    std::thread arm([&] { arm_control_client(ready, stop); });

    CameraFrame frame = initial_catcher_frame();
    while (!stop.stop_requested()) {
        shared_frame.take(frame);
        frame.tcp_state =
            ready.has("handoff_server") ? "listening" : frame.tcp_state;
        frame.udp_state =
            ready.has("fresh_track_update")
                ? "fresh"
                : (ready.has("udp_receiver") ? "waiting" : frame.udp_state);
        if (ready.has("handoff_commit")) {
            frame.handoff_state = "accepted";
        }
        gui.poll(stop, frame);
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }

    if (camera.joinable()) camera.join();
    if (udp_receiver.joinable()) udp_receiver.join();
    if (handoff.joinable()) handoff.join();
    if (arm.joinable()) arm.join();
    health.join();
    log_line("catcher-station", "stopped");
    return 0;
}
