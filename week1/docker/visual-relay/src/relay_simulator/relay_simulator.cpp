#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <span>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "visual_relay/gui.hpp"
#include "visual_relay/latest_value.hpp"
#include "visual_relay/rik_asio.hpp"
#include "visual_relay/scene.hpp"
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
constexpr float kFrameDtS = 0.08F;
// Stations only ever see what was true a tick ago: this is what actually
// gives the UDP camera link a (small) transit delay instead of stations
// observing the exact same instant the simulator renders locally.
constexpr std::uint64_t kStationLatencyTicks = 1;
constexpr float kBaseVelocityMps = 0.62F;
constexpr float kScoutCameraMinM = 0.0F;
constexpr float kScoutCameraMaxM = kTunnelStartM + 0.12F;
constexpr float kCatcherCameraMinM = kTunnelEndM - 0.12F;
constexpr float kCatcherCameraMaxM = kBeltLengthM;

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

ProjectedObject project_object_for_camera(const SceneObject& object,
                                          StationView view, int width,
                                          int height) {
    const bool catcher = view == StationView::catcher;
    const float min_m = catcher ? kCatcherCameraMinM : kScoutCameraMinM;
    const float max_m = catcher ? kCatcherCameraMaxM : kScoutCameraMaxM;
    const float world_u = std::clamp(
        (object.belt_position_m - min_m) / (max_m - min_m), 0.0F, 1.0F);
    const float u = 1.0F - world_u;
    const float lane_y = 0.58F + object.lane_offset_m * 0.34F;
    const float perspective = std::clamp(0.78F + lane_y * 0.34F, 0.62F, 1.08F);
    const float base = object.target ? 0.18F : 0.145F;

    ProjectedObject projection;
    projection.track_id = object.track_id;
    projection.center_x_px = u * static_cast<float>(width - 1);
    projection.center_y_px = lane_y * static_cast<float>(height);
    projection.width_px = base * static_cast<float>(height) * perspective;
    projection.height_px = projection.width_px * 0.82F;
    projection.depth = lane_y;
    projection.score = catcher ? object.match_score : object.confidence;
    projection.target = object.target;
    projection.visible = object.visible;
    return projection;
}

std::string encode_projection(const ProjectedObject& projection) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(1) << projection.track_id << ","
        << projection.center_x_px << "," << projection.center_y_px << ","
        << projection.width_px << "," << projection.height_px << ","
        << projection.depth << "," << projection.score << ","
        << (projection.target ? 1 : 0) << "," << (projection.visible ? 1 : 0);
    return out.str();
}

std::string encode_camera_frame(std::string_view view, std::uint64_t frame,
                                const SceneConfig& scene) {
    const float time_s = static_cast<float>(frame) * kFrameDtS;
    const bool catcher = view == "catcher";
    const bool simulator = view == "simulator";
    const StationView station_view =
        catcher ? StationView::catcher
                : (simulator ? StationView::simulator : StationView::scout);
    std::ostringstream out;
    out << std::fixed << std::setprecision(2);
    out << "VRFRAME|view=" << view << "|frame=" << frame
        << "|phase=" << std::fmod(time_s, 1.0F) << "|fps=12.5|latency_ms="
        << (catcher ? 34.0F + std::sin(time_s) * 4.0F
                    : 27.0F + std::cos(time_s) * 3.0F)
        << "|eta=" << std::max(0.0F, (kTunnelEndM - 2.12F) / kBaseVelocityMps)
        << "|descriptor=" << (catcher ? 0.74F : 0.88F)
        << "|tcp=" << (frame > 55 ? "connected" : "connecting")
        << "|udp=" << (frame > 12 ? "fresh" : "waiting")
        << "|handoff=" << handoff_stage(frame);

    const float arm_a = 0.72F + std::sin(time_s * 0.7F) * 0.28F;
    const float arm_b = -1.18F + std::cos(time_s * 0.6F) * 0.22F;
    out << "|arm=" << arm_a << "," << arm_b << "|objects=";

    std::vector<SceneObject> visible_objects;
    bool first = true;
    for (const auto& object : scene_objects()) {
        float position =
            wrap_belt(object.spawn_offset_m +
                      time_s * kBaseVelocityMps * object.velocity_scale);
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
        if (!simulator && ((!catcher && !visible_to_scout) ||
                           (catcher && !visible_to_catcher))) {
            continue;
        }

        const bool target = object.track_id == 7001;
        const float confidence =
            std::clamp(0.92F - std::abs(lane) * 0.21F +
                           std::sin(time_s + object.spawn_offset_m) * 0.04F,
                       0.45F, 0.98F);
        const float match =
            target
                ? std::clamp(0.86F + std::sin(time_s * 1.6F) * 0.08F, 0.72F,
                             0.97F)
                : std::clamp(
                      0.36F + std::cos(time_s + object.spawn_offset_m) * 0.12F,
                      0.12F, 0.58F);

        SceneObject scene_object;
        scene_object.track_id = object.track_id;
        scene_object.label = object.label;
        scene_object.material = object.material;
        scene_object.belt_position_m = position;
        scene_object.lane_offset_m = lane;
        scene_object.rotation_rad = rotation;
        scene_object.confidence = confidence;
        scene_object.match_score = match;
        scene_object.target = target;
        scene_object.visible = true;
        visible_objects.push_back(scene_object);

        if (!first) {
            out << ";";
        }
        first = false;
        out << object.track_id << "," << object.label << "," << object.material
            << "," << position << "," << lane << "," << rotation << ","
            << confidence << "," << match << "," << (target ? 1 : 0);
    }

    out << "|projections=";
    first = true;
    for (const auto& object : visible_objects) {
        if (!first) {
            out << ";";
        }
        first = false;
        out << encode_projection(project_object_for_camera(
            object, station_view, scene.camera_width, scene.camera_height));
    }
    return out.str();
}

struct RgbImage
{
    RgbImage(int image_width, int image_height)
        : width(image_width),
          height(image_height),
          pixels(static_cast<std::size_t>(image_width) *
                 static_cast<std::size_t>(image_height) * 3U) {}

    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> pixels;
};

void put_pixel(RgbImage& image, int x, int y, std::uint8_t r, std::uint8_t g,
               std::uint8_t b) {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
        return;
    }
    const auto offset =
        (static_cast<std::size_t>(y) * static_cast<std::size_t>(image.width) +
         static_cast<std::size_t>(x)) *
        3U;
    image.pixels[offset] = r;
    image.pixels[offset + 1U] = g;
    image.pixels[offset + 2U] = b;
}

void fill_rect(RgbImage& image, int x, int y, int w, int h, std::uint8_t r,
               std::uint8_t g, std::uint8_t b) {
    for (int yy = y; yy < y + h; ++yy) {
        for (int xx = x; xx < x + w; ++xx) {
            put_pixel(image, xx, yy, r, g, b);
        }
    }
}

void fill_circle(RgbImage& image, int cx, int cy, int radius, std::uint8_t r,
                 std::uint8_t g, std::uint8_t b) {
    for (int yy = cy - radius; yy <= cy + radius; ++yy) {
        for (int xx = cx - radius; xx <= cx + radius; ++xx) {
            const int dx = xx - cx;
            const int dy = yy - cy;
            if (dx * dx + dy * dy <= radius * radius) {
                put_pixel(image, xx, yy, r, g, b);
            }
        }
    }
}

RgbColor sample_texture(const TextureImage& texture, float u, float v,
                        RgbColor fallback) {
    if (texture.empty()) {
        return fallback;
    }
    const int x = std::clamp(static_cast<int>(u * float(texture.width)), 0,
                             texture.width - 1);
    const int y = std::clamp(static_cast<int>(v * float(texture.height)), 0,
                             texture.height - 1);
    const auto offset =
        (static_cast<std::size_t>(y) * static_cast<std::size_t>(texture.width) +
         static_cast<std::size_t>(x)) *
        3U;
    return {texture.rgb_pixels[offset], texture.rgb_pixels[offset + 1U],
            texture.rgb_pixels[offset + 2U]};
}

void draw_rear_face(RgbImage& image, const SceneObject& object,
                    const SceneConfig& scene,
                    const ProjectedObject& projection) {
    const auto* appearance = find_appearance(scene, object.track_id);
    const RgbColor primary =
        appearance == nullptr ? RgbColor{} : appearance->primary;
    const RgbColor secondary =
        appearance == nullptr ? RgbColor{251, 191, 36} : appearance->secondary;
    const float material_boost =
        object.material.find("metal") != std::string::npos ? 1.10F : 0.92F;
    const float light =
        std::clamp(0.38F + scene.lighting.directional_intensity * 0.42F +
                       std::sin(object.rotation_rad) * 0.08F,
                   0.35F, 1.15F);
    const auto shaded = scaled(primary, light * material_boost);
    const auto highlight = scaled(secondary, std::min(1.25F, light + 0.20F));
    const int cx = static_cast<int>(projection.center_x_px);
    const int cy = static_cast<int>(projection.center_y_px);
    const int size = static_cast<int>(projection.width_px);
    const std::uint8_t r = shaded.r;
    const std::uint8_t g = shaded.g;
    const std::uint8_t b = shaded.b;
    const std::uint8_t seam_r = highlight.r;
    const std::uint8_t seam_g = highlight.g;
    const std::uint8_t seam_b = highlight.b;

    fill_circle(image, cx + size / 8, cy + size / 3, size / 2, 11, 18, 32);
    if (object.label.find("cylinder") != std::string_view::npos ||
        object.label.find("gear") != std::string_view::npos) {
        fill_circle(image, cx, cy, size / 2, r, g, b);
        fill_circle(image, cx + size / 6, cy - size / 8, size / 5, seam_r,
                    seam_g, seam_b);
        if (object.label.find("gear") != std::string_view::npos) {
            fill_circle(image, cx, cy, std::max(2, size / 7), 15, 23, 42);
        }
    }
    else {
        fill_rect(image, cx - size / 2, cy - size / 2, size, size, r, g, b);
        fill_rect(image, cx + size / 2 - 4, cy - size / 2 + 2, 2, size - 4,
                  seam_r, seam_g, seam_b);
        fill_rect(image, cx - size / 2 + 3, cy + size / 2 - 4, size - 6, 2,
                  seam_r, seam_g, seam_b);
        if (appearance != nullptr && !appearance->texture.empty()) {
            for (int yy = -size / 3; yy < size / 3; ++yy) {
                for (int xx = -size / 3; xx < size / 3; ++xx) {
                    const auto tex = sample_texture(
                        appearance->texture, (float(xx) / float(size) + 0.5F),
                        (float(yy) / float(size) + 0.5F), highlight);
                    put_pixel(image, cx + xx, cy + yy, tex.r, tex.g, tex.b);
                }
            }
        }
    }
}

RgbImage render_camera_image(const CameraFrame& frame,
                             const SceneConfig& scene) {
    RgbImage image(scene.camera_width, scene.camera_height);
    for (int y = 0; y < image.height; ++y) {
        const float v =
            static_cast<float>(y) / static_cast<float>(image.height - 1);
        for (int x = 0; x < image.width; ++x) {
            const float u =
                static_cast<float>(x) / static_cast<float>(image.width - 1);
            const float vignette = std::clamp(
                1.15F - std::hypot(u - 0.5F, v - 0.52F) * 0.85F, 0.55F, 1.0F);
            std::uint8_t r =
                static_cast<std::uint8_t>((18.0F + v * 18.0F) * vignette);
            std::uint8_t g =
                static_cast<std::uint8_t>((27.0F + v * 22.0F) * vignette);
            std::uint8_t b =
                static_cast<std::uint8_t>((43.0F + v * 18.0F) * vignette);
            if (y > 34) {
                const float lane = std::abs(u - 0.5F);
                const float belt = std::clamp(1.0F - lane * 1.35F, 0.0F, 1.0F);
                const auto tex = sample_texture(
                    scene.belt_texture, u + frame.belt_phase, v, {54, 62, 74});
                r = static_cast<std::uint8_t>(
                    (float(tex.r) * 0.55F + belt * 28.0F) * vignette);
                g = static_cast<std::uint8_t>(
                    (float(tex.g) * 0.55F + belt * 28.0F) * vignette);
                b = static_cast<std::uint8_t>(
                    (float(tex.b) * 0.55F + belt * 31.0F) * vignette);
            }
            put_pixel(image, x, y, r, g, b);
        }
    }

    for (int stripe = -4; stripe < 12; ++stripe) {
        const int base =
            static_cast<int>(std::fmod(frame.belt_phase * 28.0F, 28.0F)) +
            stripe * 28;
        for (int y = 38; y < image.height; ++y) {
            const int x = base + (y - 38) / 2;
            put_pixel(image, x, y, 98, 112, 130);
            put_pixel(image, x + 1, y, 98, 112, 130);
        }
    }

    for (const auto& object : frame.objects) {
        draw_rear_face(image, object, scene,
                       project_object_for_camera(object, frame.view,
                                                 image.width, image.height));
    }

    return image;
}

// Keep the RGB stream in row bands instead of one huge datagram. A 240x135
// frame at 15 rows per chunk stays readable without flooding the UDP bridge.
constexpr std::size_t kCameraChunkRows = 15;

std::vector<std::uint8_t> encode_camera_chunk(std::uint64_t frame_seq,
                                              const RgbImage& image,
                                              std::size_t row_start,
                                              std::size_t row_count,
                                              std::string_view metadata) {
    std::ostringstream header;
    header << "VRRGBC\n"
           << frame_seq << "\n"
           << image.width << "\n"
           << image.height << "\n"
           << row_start << "\n"
           << row_count << "\n"
           << metadata.size() << "\n";
    const std::string header_text = header.str();
    const std::size_t row_bytes = static_cast<std::size_t>(image.width) * 3U;
    const std::size_t pixel_offset = row_start * row_bytes;
    const std::size_t pixel_bytes = row_count * row_bytes;

    std::vector<std::uint8_t> packet;
    packet.reserve(header_text.size() + metadata.size() + pixel_bytes);
    packet.insert(packet.end(), header_text.begin(), header_text.end());
    packet.insert(packet.end(), metadata.begin(), metadata.end());
    packet.insert(packet.end(), image.pixels.begin() + pixel_offset,
                  image.pixels.begin() + pixel_offset + pixel_bytes);
    return packet;
}

// Sends one camera image as a sequence of row-band datagrams. The first chunk
// carries the frame's text metadata; every send_to() result is checked because
// a silently dropped send is indistinguishable from a healthy link.
void send_camera_image(rik_asio::udp_socket& socket,
                       const rik_asio::endpoint& target,
                       std::string_view station_name, std::uint64_t frame_seq,
                       const RgbImage& image, std::string_view metadata) {
    std::size_t row_start = 0;
    bool first = true;
    while (row_start < static_cast<std::size_t>(image.height)) {
        const std::size_t rows =
            std::min(kCameraChunkRows,
                     static_cast<std::size_t>(image.height) - row_start);
        const auto packet =
            encode_camera_chunk(frame_seq, image, row_start, rows,
                                first ? metadata : std::string_view{});
        const auto result = socket.send_to(
            std::span<const std::uint8_t>(packet.data(), packet.size()),
            target);
        if (!result.ok()) {
            log_line("relay-simulator", std::string("camera chunk send to ") +
                                            std::string(station_name) +
                                            " failed");
        }
        row_start += rows;
        first = false;
    }
}

void control_server(ReadyState& ready, StopState& stop) {
    try {
        auto acceptor =
            rik_asio::tcp_acceptor::bind_any(env_port("CONTROL_PORT", 6300));
        acceptor.set_non_blocking(true);
        ready.mark("control_endpoint");
        while (!stop.stop_requested()) {
            auto accepted = acceptor.accept_for(std::chrono::milliseconds(50));
            if (accepted.would_block()) continue;
            if (!accepted.ok()) {
                continue;
            }
            auto socket = std::move(accepted.socket);
            socket.set_non_blocking(true);
            const auto lease_start = monotonic_time_ns();
            std::array<char, 256> buf{};
            while (!stop.stop_requested() &&
                   monotonic_time_ns() - lease_start < 5'000'000'000ULL) {
                const auto result = socket.read_some_for(
                    std::span<char>(buf.data(), buf.size()),
                    std::chrono::milliseconds(250));
                if (result.ok() && result.bytes > 0) {
                    log_line("relay-simulator",
                             "control lease heartbeat received");
                    break;
                }
                if (!result.would_block()) {
                    break;
                }
            }
        }
    }
    catch (const std::exception& ex) {
        log_line("relay-simulator",
                 std::string("control server failed: ") + ex.what());
        stop.request_stop();
    }
}

void camera_sender(ReadyState& ready, StopState& stop, const SceneConfig& scene,
                   LatestValue<CameraFrame>& simulator_frame) {
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
        ready.mark("camera_sender");

        std::uint64_t frame = 0;
        while (!stop.stop_requested()) {
            // Stations transmit/receive over UDP, so they must always lag
            // the simulator's own live frame by at least one tick.
            const std::uint64_t station_frame =
                frame >= kStationLatencyTicks ? frame - kStationLatencyTicks
                                              : 0;
            const auto scout_payload =
                encode_camera_frame("scout", station_frame, scene);
            const auto catcher_payload =
                encode_camera_frame("catcher", station_frame, scene);
            const auto scout_frame =
                parse_camera_frame(scout_payload, StationView::scout);
            const auto catcher_frame =
                parse_camera_frame(catcher_payload, StationView::catcher);
            const auto scout_image = render_camera_image(scout_frame, scene);
            const auto catcher_image =
                render_camera_image(catcher_frame, scene);

            auto live_frame = parse_camera_frame(
                encode_camera_frame("simulator", frame, scene),
                StationView::simulator);
            while (!stop.stop_requested() &&
                   !simulator_frame.publish(live_frame,
                                            std::chrono::milliseconds(50))) {
            }

            send_camera_image(socket, scout, "scout", station_frame,
                              scout_image, scout_payload);
            if (!ready.has("scout_frame")) {
                ready.mark("scout_frame");
            }
            send_camera_image(socket, catcher, "catcher", station_frame,
                              catcher_image, catcher_payload);
            if (!ready.has("catcher_frame")) {
                ready.mark("catcher_frame");
            }
            ++frame;
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
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

    log_line("relay-simulator", "starting deterministic world display");
    const auto scene = load_scene_config();
    ready.mark("assets");

    GuiWindow gui("Visual Relay Simulator");
    if (!gui.ok()) {
        log_line("relay-simulator", "GUI backend is required");
        return 2;
    }
    ready.mark("renderer");
    LatestValue<CameraFrame> simulator_frame{parse_camera_frame(
        encode_camera_frame("simulator", 0, scene), StationView::simulator)};

    ReadyHttpServer health("relay-simulator", ready, stop,
                           {"assets", "renderer", "control_endpoint",
                            "camera_sender", "scout_frame", "catcher_frame"},
                           env_port("READY_PORT", 9000));
    health.start();

    std::thread control([&] { control_server(ready, stop); });
    std::thread cameras(
        [&] { camera_sender(ready, stop, scene, simulator_frame); });

    CameraFrame frame = parse_camera_frame(
        encode_camera_frame("simulator", 0, scene), StationView::simulator);
    while (!stop.stop_requested()) {
        simulator_frame.take(frame);
        gui.poll(stop, frame, ready.summary());
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
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
