#pragma once

#include <string>
#include <string_view>
#include <cstdint>
#include <vector>

#include "visual_relay/service.hpp"

namespace visual_relay
{

enum class StationView
{
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
};

CameraFrame parse_camera_frame(std::string_view payload, StationView fallback);

class GuiWindow
{
public:
    explicit GuiWindow(std::string title);
    GuiWindow(const GuiWindow&) = delete;
    GuiWindow& operator=(const GuiWindow&) = delete;
    ~GuiWindow();

    bool ok() const;
    bool poll(StopState& stop, const CameraFrame& frame,
              const std::string& status);

private:
    std::string title_;
    bool ok_{false};
    void* window_{nullptr};
    void* renderer_{nullptr};
};

}  // namespace visual_relay
