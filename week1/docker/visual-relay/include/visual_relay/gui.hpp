#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "visual_relay/latest_value.hpp"
#include "visual_relay/service.hpp"

namespace visual_relay
{

enum class StationView
{
    simulator,
    scout,
    catcher,
};

struct SceneObject
{
    std::uint64_t track_id = 0;
    std::string label = "unknown";
    std::string material = "matte";
    float belt_position_m = 0.0F;
    float lane_offset_m = 0.0F;
    float rotation_rad = 0.0F;
    float confidence = 0.0F;
    float match_score = 0.0F;
    bool target = false;
    bool visible = true;
};

struct ProjectedObject
{
    std::uint64_t track_id = 0;
    float center_x_px = 0.0F;
    float center_y_px = 0.0F;
    float width_px = 0.0F;
    float height_px = 0.0F;
    float depth = 0.0F;
    float score = 0.0F;
    bool target = false;
    bool visible = true;
};

struct CameraFrame
{
    StationView view = StationView::scout;
    std::uint64_t sequence = 0;
    float belt_phase = 0.0F;
    float fps = 20.0F;
    float latency_ms = 0.0F;
    float predicted_eta_s = 0.0F;
    float descriptor_quality = 0.0F;
    float arm_joint_a_rad = 0.0F;
    float arm_joint_b_rad = 0.0F;
    std::string tcp_state = "connecting";
    std::string udp_state = "waiting";
    std::string handoff_state = "pending";
    std::vector<SceneObject> objects;
    std::vector<ProjectedObject> projections;
    int image_width = 0;
    int image_height = 0;
    std::vector<std::uint8_t> rgb_pixels;
};

CameraFrame parse_camera_frame(std::string_view payload, StationView fallback);

// Stateful receiver for the simulator's row-band camera datagrams. It rejects
// stale chunks and tracks per-row coverage for the current frame so delayed
// packets from older frames cannot overwrite newer pixels.
class CameraChunkReceiver
{
public:
    explicit CameraChunkReceiver(CameraFrame initial);

    bool apply(std::span<const std::uint8_t> payload);
    const CameraFrame& frame() const;
    bool frame_complete() const;

private:
    CameraFrame frame_;
    std::uint64_t sequence_ = 0;
    bool have_sequence_ = false;
    std::vector<bool> received_rows_;
};

// Reads row-band UDP camera datagrams for one station, publishing each
// completed frame into `frame` and marking `ready` once a full frame has
// arrived. Runs until `stop` is requested.
void receive_camera_frames(ReadyState& ready, StopState& stop,
                           LatestValue<CameraFrame>& frame,
                           std::string_view service_name, int port,
                           CameraFrame initial);

class GuiWindow
{
public:
    explicit GuiWindow(std::string title);
    GuiWindow(const GuiWindow&) = delete;
    GuiWindow& operator=(const GuiWindow&) = delete;
    ~GuiWindow();

    bool ok() const;
    bool poll(StopState& stop, const CameraFrame& frame);

private:
    std::string title_;
    bool ok_{false};
    void* window_{nullptr};
    void* renderer_{nullptr};
    void* camera_texture_{nullptr};
    int camera_texture_width_{0};
    int camera_texture_height_{0};
};

}  // namespace visual_relay
