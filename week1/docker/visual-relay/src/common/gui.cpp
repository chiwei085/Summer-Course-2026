#include "visual_relay/gui.hpp"

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <numbers>
#include <span>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>
#include <thread>

#include "visual_relay/rik_asio.hpp"

#if VISUAL_RELAY_HAS_SDL3
#include <SDL3/SDL.h>
#endif

namespace visual_relay
{
namespace
{

constexpr float kPi = std::numbers::pi_v<float>;
constexpr float kStatusPanelHeight = 116.0F;

std::vector<std::string_view> split(std::string_view text, char separator) {
    std::vector<std::string_view> parts;
    while (true) {
        const auto pos = text.find(separator);
        parts.push_back(text.substr(0, pos));
        if (pos == std::string_view::npos) {
            break;
        }
        text.remove_prefix(pos + 1);
    }
    return parts;
}

std::string_view value_after(std::string_view token, std::string_view key) {
    if (token.starts_with(key) && token.size() > key.size() &&
        token[key.size()] == '=') {
        return token.substr(key.size() + 1);
    }
    return {};
}

float parse_float(std::string_view value, float fallback = 0.0F) {
    float out = fallback;
    const auto* begin = value.data();
    const auto* end = value.data() + value.size();
    const auto result = std::from_chars(begin, end, out);
    return result.ec == std::errc{} ? out : fallback;
}

std::uint64_t parse_u64(std::string_view value, std::uint64_t fallback = 0) {
    std::uint64_t out = fallback;
    const auto* begin = value.data();
    const auto* end = value.data() + value.size();
    const auto result = std::from_chars(begin, end, out);
    return result.ec == std::errc{} ? out : fallback;
}

ProjectedObject parse_projection(std::string_view encoded) {
    const auto fields = split(encoded, ',');
    ProjectedObject projection;
    if (fields.size() < 9) {
        return projection;
    }
    projection.track_id = parse_u64(fields[0]);
    projection.center_x_px = parse_float(fields[1]);
    projection.center_y_px = parse_float(fields[2]);
    projection.width_px = parse_float(fields[3]);
    projection.height_px = parse_float(fields[4]);
    projection.depth = parse_float(fields[5]);
    projection.score = parse_float(fields[6]);
    projection.target = parse_u64(fields[7]) != 0;
    projection.visible = parse_u64(fields[8], 1) != 0;
    return projection;
}

#if VISUAL_RELAY_HAS_SDL3
struct Color
{
    Uint8 r;
    Uint8 g;
    Uint8 b;
    Uint8 a = 255;
};

void set_color(SDL_Renderer* renderer, Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
}

void fill_rect(SDL_Renderer* renderer, float x, float y, float w, float h,
               Color color) {
    set_color(renderer, color);
    SDL_FRect rect{x, y, w, h};
    SDL_RenderFillRect(renderer, &rect);
}

void stroke_rect(SDL_Renderer* renderer, float x, float y, float w, float h,
                 Color color) {
    set_color(renderer, color);
    SDL_FRect rect{x, y, w, h};
    SDL_RenderRect(renderer, &rect);
}

void line(SDL_Renderer* renderer, float x1, float y1, float x2, float y2,
          Color color) {
    set_color(renderer, color);
    SDL_RenderLine(renderer, x1, y1, x2, y2);
}

void debug_text(SDL_Renderer* renderer, float x, float y, std::string text,
                Color color = {226, 232, 240, 255}) {
    set_color(renderer, color);
    SDL_RenderDebugText(renderer, x, y, text.c_str());
}

void fill_circle(SDL_Renderer* renderer, float cx, float cy, float radius,
                 Color color) {
    set_color(renderer, color);
    const int r = static_cast<int>(std::ceil(radius));
    for (int y = -r; y <= r; ++y) {
        const float width =
            std::sqrt(std::max(0.0F, radius * radius - float(y * y)));
        SDL_RenderLine(renderer, cx - width, cy + float(y), cx + width,
                       cy + float(y));
    }
}

void draw_gauge(SDL_Renderer* renderer, float x, float y, float w, float value,
                Color color) {
    fill_rect(renderer, x, y, w, 7.0F, {31, 41, 55, 255});
    fill_rect(renderer, x, y, w * std::clamp(value, 0.0F, 1.0F), 7.0F, color);
    stroke_rect(renderer, x, y, w, 7.0F, {100, 116, 139, 255});
}

Color object_color(std::string_view label, bool secondary = false) {
    if (label.find("red") != std::string_view::npos ||
        label.find("crate") != std::string_view::npos) {
        return secondary ? Color{251, 191, 36, 255} : Color{220, 65, 55, 255};
    }
    if (label.find("blue") != std::string_view::npos ||
        label.find("cylinder") != std::string_view::npos) {
        return secondary ? Color{125, 211, 252, 255} : Color{37, 99, 235, 255};
    }
    if (label.find("yellow") != std::string_view::npos ||
        label.find("wedge") != std::string_view::npos) {
        return secondary ? Color{250, 250, 250, 255} : Color{234, 179, 8, 255};
    }
    if (label.find("green") != std::string_view::npos ||
        label.find("gear") != std::string_view::npos) {
        return secondary ? Color{20, 184, 166, 255} : Color{34, 197, 94, 255};
    }
    if (label.find("white") != std::string_view::npos ||
        label.find("tag") != std::string_view::npos) {
        return secondary ? Color{59, 130, 246, 255} : Color{226, 232, 240, 255};
    }
    return secondary ? Color{251, 146, 60, 255} : Color{168, 85, 247, 255};
}

float world_to_screen_x(float belt_position_m, float world_min, float world_max,
                        float left, float width) {
    const float u = std::clamp(
        (belt_position_m - world_min) / (world_max - world_min), 0.0F, 1.0F);
    return left + u * width;
}

void draw_belt(SDL_Renderer* renderer, float x, float y, float w, float h,
               float phase) {
    fill_rect(renderer, x, y, w, h, {68, 76, 89, 255});
    fill_rect(renderer, x, y + 12.0F, w, h - 24.0F, {50, 57, 68, 255});
    for (int i = -2; i < 24; ++i) {
        const float stripe =
            x + std::fmod(phase * 42.0F, 42.0F) + static_cast<float>(i) * 42.0F;
        line(renderer, stripe, y + 5.0F, stripe + 32.0F, y + h - 5.0F,
             {94, 108, 126, 255});
    }
    fill_rect(renderer, x, y - 18.0F, w, 8.0F, {148, 163, 184, 255});
    fill_rect(renderer, x, y + h + 10.0F, w, 8.0F, {148, 163, 184, 255});
    for (int i = 0; i <= 12; ++i) {
        const float rx = x + static_cast<float>(i) * w / 12.0F;
        fill_rect(renderer, rx - 3.0F, y - 28.0F, 6.0F, 20.0F,
                  {71, 85, 105, 255});
        fill_rect(renderer, rx - 3.0F, y + h + 18.0F, 6.0F, 20.0F,
                  {71, 85, 105, 255});
    }
}

void draw_tunnel(SDL_Renderer* renderer, float x, float y, float w, float h) {
    fill_rect(renderer, x - 16.0F, y + 10.0F, 16.0F, h - 20.0F,
              {31, 41, 55, 255});
    fill_rect(renderer, x + w, y + 10.0F, 16.0F, h - 20.0F, {31, 41, 55, 255});
    fill_rect(renderer, x - 18.0F, y - 8.0F, w + 36.0F, 34.0F,
              {55, 65, 81, 255});
    fill_rect(renderer, x, y + 26.0F, w, h - 52.0F, {15, 23, 42, 255});
    stroke_rect(renderer, x - 18.0F, y - 8.0F, w + 36.0F, h + 16.0F,
                {148, 163, 184, 255});
    fill_rect(renderer, x + 14.0F, y + 42.0F, w - 28.0F, 8.0F,
              {248, 113, 113, 255});
    fill_circle(renderer, x + w - 28.0F, y + 8.0F, 7.0F, {248, 113, 113, 255});
    fill_circle(renderer, x + w - 48.0F, y + 8.0F, 7.0F, {250, 204, 21, 255});
}

void draw_object(SDL_Renderer* renderer, const SceneObject& obj, float sx,
                 float sy, float scale, bool catcher_view) {
    const auto primary = object_color(obj.label);
    const auto secondary = object_color(obj.label, true);
    const float wobble = std::sin(obj.rotation_rad) * 4.0F;
    const float size = obj.target ? 42.0F * scale : 36.0F * scale;
    const float x = sx - size * 0.5F;
    const float y = sy - size * 0.5F + wobble;

    fill_rect(renderer, x + 4.0F, y + size - 3.0F, size, 6.0F,
              {15, 23, 42, 110});
    if (obj.label.find("cylinder") != std::string::npos) {
        fill_circle(renderer, sx, sy, size * 0.48F, primary);
        fill_circle(renderer, sx - size * 0.10F, sy - size * 0.10F,
                    size * 0.22F, secondary);
    }
    else if (obj.label.find("gear") != std::string::npos) {
        fill_circle(renderer, sx, sy, size * 0.50F, primary);
        for (int i = 0; i < 8; ++i) {
            const float a = obj.rotation_rad + float(i) * kPi / 4.0F;
            fill_rect(renderer, sx + std::cos(a) * size * 0.48F - 3.0F,
                      sy + std::sin(a) * size * 0.48F - 3.0F, 6.0F, 6.0F,
                      secondary);
        }
        fill_circle(renderer, sx, sy, size * 0.18F, {15, 23, 42, 255});
    }
    else if (obj.label.find("wedge") != std::string::npos) {
        const SDL_FColor primary_color{primary.r / 255.0F, primary.g / 255.0F,
                                       primary.b / 255.0F, primary.a / 255.0F};
        const SDL_FColor secondary_color{
            secondary.r / 255.0F, secondary.g / 255.0F, secondary.b / 255.0F,
            secondary.a / 255.0F};
        std::array<SDL_Vertex, 3> verts{
            SDL_Vertex{
                {sx - size * 0.50F, sy + size * 0.40F}, primary_color, {0, 0}},
            SDL_Vertex{
                {sx + size * 0.48F, sy + size * 0.36F}, primary_color, {0, 0}},
            SDL_Vertex{{sx + size * 0.12F, sy - size * 0.46F},
                       secondary_color,
                       {0, 0}},
        };
        SDL_RenderGeometry(renderer, nullptr, verts.data(),
                           static_cast<int>(verts.size()), nullptr, 0);
    }
    else {
        fill_rect(renderer, x, y, size, size, primary);
        fill_rect(renderer, x + 8.0F * scale, y + 7.0F * scale,
                  size - 16.0F * scale, 6.0F * scale, secondary);
        fill_rect(renderer, x + size * 0.58F, y + size * 0.35F, 8.0F * scale,
                  size * 0.46F, secondary);
    }

    const Color box =
        obj.target ? Color{34, 211, 238, 255} : Color{226, 232, 240, 255};
    stroke_rect(renderer, x - 5.0F, y - 5.0F, size + 10.0F, size + 10.0F, box);
    debug_text(renderer, x - 5.0F, y - 21.0F,
               (obj.target ? "T" : "C") + std::to_string(obj.track_id), box);
    const float score = catcher_view ? obj.match_score : obj.confidence;
    draw_gauge(renderer, x - 5.0F, y + size + 9.0F, size + 10.0F, score, box);
}

void draw_camera_rig(SDL_Renderer* renderer, float x, float y, bool scout) {
    fill_rect(renderer, x - 12.0F, y, 24.0F, 88.0F, {71, 85, 105, 255});
    fill_rect(renderer, x - 28.0F, y + 84.0F, 56.0F, 10.0F,
              {100, 116, 139, 255});
    fill_circle(renderer, x, y - 10.0F, 19.0F, {30, 41, 59, 255});
    fill_rect(renderer, x + (scout ? 8.0F : -48.0F), y - 20.0F, 40.0F, 22.0F,
              {14, 165, 233, 255});
    line(renderer, x, y - 10.0F, scout ? x + 160.0F : x - 160.0F, y + 74.0F,
         {56, 189, 248, 150});
    line(renderer, x, y - 10.0F, scout ? x + 160.0F : x - 160.0F, y - 80.0F,
         {56, 189, 248, 150});
}

void draw_arm(SDL_Renderer* renderer, float base_x, float base_y, float joint_a,
              float joint_b) {
    const float l1 = 104.0F;
    const float l2 = 78.0F;
    const float elbow_x = base_x + std::cos(joint_a) * l1;
    const float elbow_y = base_y - std::sin(joint_a) * l1;
    const float wrist_x = elbow_x + std::cos(joint_a + joint_b) * l2;
    const float wrist_y = elbow_y - std::sin(joint_a + joint_b) * l2;
    fill_circle(renderer, base_x, base_y, 24.0F, {100, 116, 139, 255});
    line(renderer, base_x, base_y, elbow_x, elbow_y, {248, 250, 252, 255});
    line(renderer, base_x + 1.0F, base_y + 1.0F, elbow_x + 1.0F, elbow_y + 1.0F,
         {248, 250, 252, 255});
    fill_circle(renderer, elbow_x, elbow_y, 14.0F, {14, 165, 233, 255});
    line(renderer, elbow_x, elbow_y, wrist_x, wrist_y, {250, 204, 21, 255});
    line(renderer, elbow_x + 1.0F, elbow_y + 1.0F, wrist_x + 1.0F,
         wrist_y + 1.0F, {250, 204, 21, 255});
    fill_circle(renderer, wrist_x, wrist_y, 10.0F, {248, 113, 113, 255});
    line(renderer, wrist_x - 14.0F, wrist_y - 7.0F, wrist_x + 14.0F,
         wrist_y + 7.0F, {248, 113, 113, 255});
}

void draw_status_panel(SDL_Renderer* renderer, const CameraFrame& frame,
                       float x, float y, float w) {
    fill_rect(renderer, x, y, w, kStatusPanelHeight, {17, 24, 39, 235});
    stroke_rect(renderer, x, y, w, kStatusPanelHeight, {71, 85, 105, 255});
    std::string title = "SIMULATOR WORLD";
    if (frame.view == StationView::scout) {
        title = "SCOUT CAMERA";
    }
    else if (frame.view == StationView::catcher) {
        title = "CATCHER CAMERA";
    }
    debug_text(renderer, x + 12.0F, y + 12.0F, title, {248, 250, 252, 255});
    debug_text(renderer, x + 12.0F, y + 31.0F,
               "TCP " + frame.tcp_state + "   UDP " + frame.udp_state,
               {125, 211, 252, 255});
    debug_text(renderer, x + 12.0F, y + 50.0F,
               "handoff " + frame.handoff_state + "   frame " +
                   std::to_string(frame.sequence),
               {250, 204, 21, 255});
    std::ostringstream metric;
    metric << "fps " << int(frame.fps) << "  latency " << int(frame.latency_ms)
           << "ms  eta " << frame.predicted_eta_s << "s";
    debug_text(renderer, x + 12.0F, y + 69.0F, metric.str(),
               {226, 232, 240, 255});
    debug_text(renderer, x + 12.0F, y + 88.0F, "descriptor");
    draw_gauge(renderer, x + 94.0F, y + 91.0F, w - 112.0F,
               frame.descriptor_quality, {34, 197, 94, 255});
}

void render_camera_pixels(SDL_Renderer* renderer, SDL_Texture*& texture,
                          int& texture_width, int& texture_height,
                          const CameraFrame& frame, int width, int height) {
    fill_rect(renderer, 0.0F, 0.0F, static_cast<float>(width),
              static_cast<float>(height), {8, 13, 24, 255});

    const float panel_h = kStatusPanelHeight + 10.0F;
    const float margin = 28.0F;
    const float available_w = static_cast<float>(width) - margin * 2.0F;
    const float available_h =
        static_cast<float>(height) - panel_h - margin * 2.0F;
    const float image_aspect = static_cast<float>(frame.image_width) /
                               static_cast<float>(frame.image_height);
    float draw_w = available_w;
    float draw_h = draw_w / image_aspect;
    if (draw_h > available_h) {
        draw_h = available_h;
        draw_w = draw_h * image_aspect;
    }
    const float draw_x = (static_cast<float>(width) - draw_w) * 0.5F;
    const float draw_y = margin + (available_h - draw_h) * 0.5F;

    if (texture != nullptr && (texture_width != frame.image_width ||
                               texture_height != frame.image_height)) {
        SDL_DestroyTexture(texture);
        texture = nullptr;
        texture_width = 0;
        texture_height = 0;
    }
    if (texture == nullptr) {
        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGB24,
                                    SDL_TEXTUREACCESS_STREAMING,
                                    frame.image_width, frame.image_height);
        if (texture != nullptr) {
            SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_LINEAR);
            texture_width = frame.image_width;
            texture_height = frame.image_height;
        }
    }
    if (texture != nullptr) {
        SDL_UpdateTexture(texture, nullptr, frame.rgb_pixels.data(),
                          frame.image_width * 3);
        const SDL_FRect dest{draw_x, draw_y, draw_w, draw_h};
        SDL_RenderTexture(renderer, texture, nullptr, &dest);
    }
    stroke_rect(renderer, draw_x, draw_y, draw_w, draw_h, {71, 85, 105, 255});

    for (const auto& obj : frame.projections) {
        if (!obj.visible) {
            continue;
        }
        const Color color =
            obj.target ? Color{34, 211, 238, 255} : Color{226, 232, 240, 255};
        const float sx =
            draw_x + (obj.center_x_px / float(frame.image_width)) * draw_w;
        const float sy =
            draw_y + (obj.center_y_px / float(frame.image_height)) * draw_h;
        const float box_w = (obj.width_px / float(frame.image_width)) * draw_w;
        const float box_h =
            (obj.height_px / float(frame.image_height)) * draw_h;
        stroke_rect(renderer, sx - box_w * 0.5F, sy - box_h * 0.5F, box_w,
                    box_h, color);
        debug_text(renderer, sx - box_w * 0.5F, sy - box_h * 0.5F - 16.0F,
                   (obj.target ? "T" : "C") + std::to_string(obj.track_id),
                   color);
    }

    draw_status_panel(
        renderer, frame, margin, static_cast<float>(height) - panel_h + 10.0F,
        std::min(560.0F, static_cast<float>(width) - margin * 2.0F));
}

void render_scene(SDL_Renderer* renderer, const CameraFrame& frame, int width,
                  int height) {
    fill_rect(renderer, 0.0F, 0.0F, static_cast<float>(width),
              static_cast<float>(height), {11, 18, 32, 255});
    fill_rect(renderer, 0.0F, 0.0F, static_cast<float>(width), 86.0F,
              {21, 31, 49, 255});
    fill_rect(renderer, 0.0F, static_cast<float>(height) - 92.0F,
              static_cast<float>(width), 92.0F, {30, 41, 59, 255});

    const float margin = 44.0F;
    const float belt_y = static_cast<float>(height) * 0.47F;
    const float belt_h = 94.0F;
    const float belt_w = static_cast<float>(width) - margin * 2.0F;
    draw_belt(renderer, margin, belt_y, belt_w, belt_h, frame.belt_phase);

    float world_min = 0.0F;
    float world_max = 6.0F;
    float tunnel_x = margin + belt_w * 0.40F;
    if (frame.view == StationView::scout) {
        world_max = 3.7F;
        tunnel_x = margin + belt_w * 0.66F;
    }
    else if (frame.view == StationView::catcher) {
        world_min = 3.4F;
        tunnel_x = margin + belt_w * 0.18F;
    }
    draw_tunnel(renderer, tunnel_x, belt_y - 54.0F, belt_w * 0.22F,
                belt_h + 108.0F);

    if (frame.view == StationView::simulator) {
        draw_camera_rig(renderer, margin + 76.0F, belt_y - 92.0F, true);
        draw_camera_rig(renderer, static_cast<float>(width) - margin - 78.0F,
                        belt_y - 92.0F, false);
        draw_arm(renderer, static_cast<float>(width) - 214.0F,
                 belt_y + belt_h + 76.0F, frame.arm_joint_a_rad,
                 frame.arm_joint_b_rad);
        debug_text(renderer, tunnel_x - 26.0F, belt_y - 78.0F, "HIDDEN TUNNEL",
                   {250, 204, 21, 255});
    }
    else if (frame.view == StationView::scout) {
        fill_rect(renderer, tunnel_x - 110.0F, belt_y + belt_h + 42.0F, 92.0F,
                  34.0F, {30, 64, 175, 255});
        debug_text(renderer, tunnel_x - 101.0F, belt_y + belt_h + 53.0F,
                   "ROI LOCK", {248, 250, 252, 255});
    }
    else {
        draw_arm(renderer, static_cast<float>(width) - 214.0F,
                 belt_y + belt_h + 76.0F, frame.arm_joint_a_rad,
                 frame.arm_joint_b_rad);
        fill_rect(renderer, margin + 40.0F, belt_y + belt_h + 38.0F, 120.0F,
                  46.0F, {21, 128, 61, 255});
        fill_rect(renderer, margin + 174.0F, belt_y + belt_h + 38.0F, 120.0F,
                  46.0F, {185, 28, 28, 255});
        debug_text(renderer, margin + 60.0F, belt_y + belt_h + 54.0F,
                   "ACCEPT BIN");
        debug_text(renderer, margin + 197.0F, belt_y + belt_h + 54.0F,
                   "REJECT BIN");
    }

    for (const auto& obj : frame.objects) {
        if (!obj.visible) {
            continue;
        }
        const float sx =
            world_to_screen_x(obj.belt_position_m, world_min, world_max,
                              margin + 20.0F, belt_w - 40.0F);
        const float sy = belt_y + belt_h * 0.52F + obj.lane_offset_m * 58.0F;
        draw_object(renderer, obj, sx, sy, 1.0F,
                    frame.view == StationView::catcher);
    }

    if (frame.view == StationView::catcher ||
        frame.view == StationView::simulator) {
        const float intercept_x = margin + belt_w * 0.63F;
        line(renderer, intercept_x - 18.0F, belt_y - 28.0F, intercept_x + 18.0F,
             belt_y + 8.0F, {34, 211, 238, 255});
        line(renderer, intercept_x + 18.0F, belt_y - 28.0F, intercept_x - 18.0F,
             belt_y + 8.0F, {34, 211, 238, 255});
        debug_text(renderer, intercept_x - 42.0F, belt_y - 48.0F, "INTERCEPT",
                   {34, 211, 238, 255});
    }

    if (frame.view != StationView::simulator) {
        draw_status_panel(renderer, frame, margin, 24.0F,
                          std::min(560.0F, static_cast<float>(width) - 88.0F));
    }
}
#endif

}  // namespace

CameraFrame parse_camera_frame(std::string_view payload, StationView fallback) {
    CameraFrame frame;
    frame.view = fallback;
    for (const auto token : split(payload, '|')) {
        if (const auto value = value_after(token, "view"); !value.empty()) {
            if (value == "simulator") {
                frame.view = StationView::simulator;
            }
            else if (value == "catcher") {
                frame.view = StationView::catcher;
            }
            else {
                frame.view = StationView::scout;
            }
        }
        else if (const auto value = value_after(token, "frame");
                 !value.empty()) {
            frame.sequence = parse_u64(value);
        }
        else if (const auto value = value_after(token, "phase");
                 !value.empty()) {
            frame.belt_phase = parse_float(value);
        }
        else if (const auto value = value_after(token, "fps"); !value.empty()) {
            frame.fps = parse_float(value, 20.0F);
        }
        else if (const auto value = value_after(token, "latency_ms");
                 !value.empty()) {
            frame.latency_ms = parse_float(value);
        }
        else if (const auto value = value_after(token, "eta"); !value.empty()) {
            frame.predicted_eta_s = parse_float(value);
        }
        else if (const auto value = value_after(token, "descriptor");
                 !value.empty()) {
            frame.descriptor_quality = parse_float(value);
        }
        else if (const auto value = value_after(token, "tcp"); !value.empty()) {
            frame.tcp_state = std::string(value);
        }
        else if (const auto value = value_after(token, "udp"); !value.empty()) {
            frame.udp_state = std::string(value);
        }
        else if (const auto value = value_after(token, "handoff");
                 !value.empty()) {
            frame.handoff_state = std::string(value);
        }
        else if (const auto value = value_after(token, "arm"); !value.empty()) {
            const auto parts = split(value, ',');
            if (parts.size() >= 2) {
                frame.arm_joint_a_rad = parse_float(parts[0]);
                frame.arm_joint_b_rad = parse_float(parts[1]);
            }
        }
        else if (const auto value = value_after(token, "objects");
                 !value.empty()) {
            for (const auto encoded_object : split(value, ';')) {
                if (encoded_object.empty()) {
                    continue;
                }
                const auto fields = split(encoded_object, ',');
                if (fields.size() < 9) {
                    continue;
                }
                SceneObject obj;
                obj.track_id = parse_u64(fields[0]);
                obj.label = std::string(fields[1]);
                obj.material = std::string(fields[2]);
                obj.belt_position_m = parse_float(fields[3]);
                obj.lane_offset_m = parse_float(fields[4]);
                obj.rotation_rad = parse_float(fields[5]);
                obj.confidence = parse_float(fields[6]);
                obj.match_score = parse_float(fields[7]);
                obj.target = parse_u64(fields[8]) != 0;
                frame.objects.push_back(std::move(obj));
            }
        }
        else if (const auto value = value_after(token, "projections");
                 !value.empty()) {
            for (const auto encoded_projection : split(value, ';')) {
                if (!encoded_projection.empty()) {
                    frame.projections.push_back(
                        parse_projection(encoded_projection));
                }
            }
        }
    }
    return frame;
}

namespace
{

// Copies everything except the receiver's accumulated pixel buffer, so a
// metadata-bearing chunk can refresh telemetry without disturbing rows that
// arrived in earlier (or haven't yet arrived in later) chunks.
void copy_metadata_fields(CameraFrame& dest, const CameraFrame& src) {
    dest.view = src.view;
    dest.sequence = src.sequence;
    dest.belt_phase = src.belt_phase;
    dest.fps = src.fps;
    dest.latency_ms = src.latency_ms;
    dest.predicted_eta_s = src.predicted_eta_s;
    dest.descriptor_quality = src.descriptor_quality;
    dest.arm_joint_a_rad = src.arm_joint_a_rad;
    dest.arm_joint_b_rad = src.arm_joint_b_rad;
    dest.tcp_state = src.tcp_state;
    dest.udp_state = src.udp_state;
    dest.handoff_state = src.handoff_state;
    dest.objects = src.objects;
    dest.projections = src.projections;
}

}  // namespace

CameraChunkReceiver::CameraChunkReceiver(CameraFrame initial)
    : frame_(std::move(initial)),
      sequence_(frame_.sequence),
      have_sequence_(frame_.sequence != 0) {
    if (frame_.image_height > 0) {
        received_rows_.assign(static_cast<std::size_t>(frame_.image_height),
                              false);
    }
}

const CameraFrame& CameraChunkReceiver::frame() const {
    return frame_;
}

bool CameraChunkReceiver::frame_complete() const {
    return !received_rows_.empty() &&
           std::all_of(received_rows_.begin(), received_rows_.end(),
                       [](bool row) { return row; });
}

bool CameraChunkReceiver::apply(std::span<const std::uint8_t> payload) {
    constexpr std::string_view magic = "VRRGBC\n";
    if (payload.size() < magic.size() ||
        std::memcmp(payload.data(), magic.data(), magic.size()) != 0) {
        const auto* text = reinterpret_cast<const char*>(payload.data());
        copy_metadata_fields(
            frame_, parse_camera_frame(std::string_view(text, payload.size()),
                                       frame_.view));
        return true;
    }

    std::size_t cursor = magic.size();
    auto read_line = [&]() -> std::string_view {
        const std::size_t begin = cursor;
        while (cursor < payload.size() && payload[cursor] != '\n') {
            ++cursor;
        }
        const std::size_t end = cursor;
        if (cursor < payload.size()) {
            ++cursor;
        }
        const auto* text =
            reinterpret_cast<const char*>(payload.data() + begin);
        return {text, end - begin};
    };

    const auto frame_seq = parse_u64(read_line(), 0);
    const int width = static_cast<int>(parse_u64(read_line(), 0));
    const int height = static_cast<int>(parse_u64(read_line(), 0));
    const auto row_start = static_cast<std::size_t>(parse_u64(read_line(), 0));
    const auto row_count = static_cast<std::size_t>(parse_u64(read_line(), 0));
    const auto metadata_size =
        static_cast<std::size_t>(parse_u64(read_line(), 0));

    if (width <= 0 || height <= 0 || row_count == 0) {
        return false;
    }
    if (have_sequence_ && frame_seq < sequence_) {
        return false;
    }
    if (!have_sequence_ || frame_seq > sequence_ ||
        frame_.image_width != width || frame_.image_height != height) {
        const bool dimensions_changed =
            frame_.image_width != width || frame_.image_height != height;
        have_sequence_ = true;
        sequence_ = frame_seq;
        frame_.image_width = width;
        frame_.image_height = height;
        if (dimensions_changed || frame_.rgb_pixels.empty()) {
            frame_.rgb_pixels.assign(static_cast<std::size_t>(width) *
                                         static_cast<std::size_t>(height) * 3U,
                                     0U);
        }
        received_rows_.assign(static_cast<std::size_t>(height), false);
    }

    if (cursor + metadata_size > payload.size()) {
        return false;
    }
    if (metadata_size > 0) {
        const auto* metadata =
            reinterpret_cast<const char*>(payload.data() + cursor);
        copy_metadata_fields(
            frame_,
            parse_camera_frame(std::string_view(metadata, metadata_size),
                               frame_.view));
    }
    cursor += metadata_size;

    const std::size_t row_bytes = static_cast<std::size_t>(width) * 3U;
    const std::size_t pixel_bytes = row_count * row_bytes;
    if (row_start + row_count > static_cast<std::size_t>(height) ||
        cursor + pixel_bytes > payload.size()) {
        return false;
    }
    const std::size_t dest_offset = row_start * row_bytes;
    std::copy(
        payload.begin() + static_cast<std::ptrdiff_t>(cursor),
        payload.begin() + static_cast<std::ptrdiff_t>(cursor + pixel_bytes),
        frame_.rgb_pixels.begin() + static_cast<std::ptrdiff_t>(dest_offset));
    for (std::size_t row = row_start; row < row_start + row_count; ++row) {
        received_rows_[row] = true;
    }
    frame_.sequence = frame_seq;
    return true;
}

void receive_camera_frames(ReadyState& ready, StopState& stop,
                           LatestValue<CameraFrame>& frame,
                           std::string_view service_name, int port,
                           CameraFrame initial) {
    try {
        auto socket = rik_asio::udp_socket::bind_any(port);
        socket.set_non_blocking(true);
        std::array<std::uint8_t, 32768> data{};
        rik_asio::endpoint sender;
        // Camera images arrive as a run of small row-band chunks; this
        // accumulates them across datagrams. A dropped chunk just leaves
        // stale pixels in those rows instead of losing the whole frame.
        CameraChunkReceiver camera_frames(std::move(initial));
        while (!stop.stop_requested()) {
            const auto result = socket.receive_from(
                std::span<std::uint8_t>(data.data(), data.size()), sender);
            if (result.ok() && result.bytes > 0) {
                if (camera_frames.apply(std::span<const std::uint8_t>(
                        data.data(), result.bytes)) &&
                    camera_frames.frame_complete()) {
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
        log_line(service_name,
                 std::string("camera receiver failed: ") + ex.what());
        stop.request_stop();
    }
}

GuiWindow::GuiWindow(std::string title) : title_(std::move(title)) {
#if VISUAL_RELAY_HAS_SDL3
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        log_line(title_, std::string("SDL init failed: ") + SDL_GetError());
        return;
    }
    int window_width = 900;
    int window_height = 500;
    int window_x = 64;
    int window_y = 80;
    if (title_.find("Scout") != std::string::npos) {
        window_height = 430;
        window_y = 610;
    }
    else if (title_.find("Catcher") != std::string::npos) {
        window_x = 980;
        window_height = 500;
    }
    window_ = SDL_CreateWindow(title_.c_str(), window_width, window_height,
                               SDL_WINDOW_RESIZABLE);
    if (window_ == nullptr) {
        log_line(title_,
                 std::string("window creation failed: ") + SDL_GetError());
        return;
    }
    SDL_SetWindowPosition(static_cast<SDL_Window*>(window_), window_x,
                          window_y);
    renderer_ = SDL_CreateRenderer(static_cast<SDL_Window*>(window_), nullptr);
    if (renderer_ == nullptr) {
        log_line(title_,
                 std::string("renderer creation failed: ") + SDL_GetError());
        return;
    }
    ok_ = true;
#else
    log_line(title_, "SDL3 support was not compiled in");
#endif
}

GuiWindow::~GuiWindow() {
#if VISUAL_RELAY_HAS_SDL3
    if (renderer_ != nullptr) {
        if (camera_texture_ != nullptr) {
            SDL_DestroyTexture(static_cast<SDL_Texture*>(camera_texture_));
        }
        SDL_DestroyRenderer(static_cast<SDL_Renderer*>(renderer_));
    }
    if (window_ != nullptr) {
        SDL_DestroyWindow(static_cast<SDL_Window*>(window_));
    }
    SDL_Quit();
#endif
}

bool GuiWindow::ok() const {
    return ok_;
}

bool GuiWindow::poll(StopState& stop, const CameraFrame& frame) {
#if VISUAL_RELAY_HAS_SDL3
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_EVENT_QUIT) {
            stop.request_stop();
        }
    }
    if (!ok_) {
        return false;
    }
    int width = 1120;
    int height = 680;
    auto* renderer = static_cast<SDL_Renderer*>(renderer_);
    SDL_GetRenderOutputSize(renderer, &width, &height);
    if (frame.view == StationView::simulator || frame.rgb_pixels.empty()) {
        render_scene(renderer, frame, width, height);
    }
    else {
        auto* texture = static_cast<SDL_Texture*>(camera_texture_);
        render_camera_pixels(renderer, texture, camera_texture_width_,
                             camera_texture_height_, frame, width, height);
        camera_texture_ = texture;
    }
    SDL_SetWindowTitle(static_cast<SDL_Window*>(window_), title_.c_str());
    SDL_RenderPresent(renderer);
    return !stop.stop_requested();
#else
    (void)frame;
    stop.request_stop();
    return false;
#endif
}

}  // namespace visual_relay
