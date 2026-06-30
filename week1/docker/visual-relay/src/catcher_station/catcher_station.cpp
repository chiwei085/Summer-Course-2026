#include <array>
#include <chrono>
#include <cstring>
#include <mutex>
#include <set>
#include <span>
#include <string>
#include <thread>

#include "visual_relay/gui.hpp"
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

struct SharedFrame
{
    std::mutex mutex;
    CameraFrame latest = parse_camera_frame(
        "VRFRAME|view=catcher|frame=0|phase=0|fps=0|latency_ms=0|eta=0|"
        "descriptor=0|tcp=connecting|udp=waiting|handoff=waiting|"
        "arm=0.7,-1.1|objects=",
        StationView::catcher);
};

void receive_camera(ReadyState& ready, StopState& stop, SharedFrame& frame) {
    try {
        auto socket =
            rik_asio::udp_socket::bind_any(env_port("CAMERA_PORT", 5002));
        socket.set_non_blocking(true);
        std::array<char, 2048> data{};
        rik_asio::endpoint sender;
        while (!stop.stop_requested()) {
            const auto result = socket.receive_from(
                std::span<char>(data.data(), data.size()), sender);
            if (result.ok() && result.bytes > 0) {
                const std::string payload(data.data(), result.bytes);
                auto parsed = parse_camera_frame(payload, StationView::catcher);
                {
                    std::scoped_lock lock(frame.mutex);
                    frame.latest = std::move(parsed);
                }
                ready.mark("camera_frame");
            }
            else {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("catcher-station",
                 std::string("camera receiver failed: ") + ex.what());
        stop.request_stop();
    }
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

MessageFrame read_frame(rik_asio::tcp_socket& socket) {
    std::array<std::uint8_t, 36> header{};
    socket.read_exact(std::span<std::uint8_t>(header.data(), header.size()));
    std::uint32_t payload_size = 0;
    std::memcpy(&payload_size, header.data() + 8, sizeof(payload_size));
    if (payload_size > kMaxMessagePayloadSize) {
        throw ProtocolError("message payload too large");
    }
    std::vector<std::uint8_t> bytes(header.begin(), header.end());
    bytes.resize(header.size() + payload_size);
    if (payload_size > 0) {
        socket.read_exact(std::span<std::uint8_t>(bytes.data() + header.size(),
                                                  payload_size));
    }
    return parse_message(bytes);
}

void write_frame(rik_asio::tcp_socket& socket, const MessageFrame& frame) {
    const auto bytes = serialize_message(frame);
    socket.write_all(std::span<const std::uint8_t>(bytes.data(), bytes.size()));
}

void handoff_server(ReadyState& ready, StopState& stop) {
    try {
        auto acceptor =
            rik_asio::tcp_acceptor::bind_any(env_port("HANDOFF_PORT", 6200));
        acceptor.set_non_blocking(true);
        HandoffBook book;
        ready.mark("handoff_server");
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
            while (!stop.stop_requested()) {
                try {
                    const auto frame = read_frame(socket);
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
                            write_frame(socket, make_text_message(
                                                    MessageType::handoff_accept,
                                                    frame.header.session_id,
                                                    id + 1, id, "accepted"));
                        }
                        else if (book.committed.contains(id)) {
                            write_frame(socket,
                                        make_text_message(
                                            MessageType::handoff_accept,
                                            frame.header.session_id, id + 1, id,
                                            "duplicate-accepted"));
                        }
                        else {
                            write_frame(socket, make_text_message(
                                                    MessageType::handoff_reject,
                                                    frame.header.session_id,
                                                    id + 1, id, "incomplete"));
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
    SharedFrame shared_frame;

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
    std::thread camera([&] { receive_camera(ready, stop, shared_frame); });
    std::thread udp_receiver([&] { receive_track_updates(ready, stop); });
    std::thread handoff([&] { handoff_server(ready, stop); });
    std::thread arm([&] { arm_control_client(ready, stop); });

    while (!stop.stop_requested()) {
        CameraFrame frame;
        {
            std::scoped_lock lock(shared_frame.mutex);
            frame = shared_frame.latest;
            frame.tcp_state = ready.has("handoff_server") ? "listening"
                                                          : frame.tcp_state;
            frame.udp_state = ready.has("fresh_track_update")
                                  ? "fresh"
                                  : (ready.has("udp_receiver") ? "waiting"
                                                               : frame.udp_state);
            if (ready.has("handoff_commit")) {
                frame.handoff_state = "accepted";
            }
        }
        gui.poll(stop, frame, ready.summary());
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
