#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace visual_relay
{

struct RgbColor
{
    std::uint8_t r = 226;
    std::uint8_t g = 232;
    std::uint8_t b = 240;
};

struct TextureImage
{
    int width = 0;
    int height = 0;
    std::vector<std::uint8_t> rgb_pixels;

    [[nodiscard]] bool empty() const { return rgb_pixels.empty(); }
};

struct SceneObjectAppearance
{
    std::uint64_t track_seed = 0;
    std::string name;
    std::string material;
    RgbColor primary;
    RgbColor secondary;
    std::string texture_path;
    TextureImage texture;
    std::vector<std::string> features;
};

struct SceneLighting
{
    float directional_intensity = 0.78F;
    float scout_point_intensity = 0.65F;
    float catcher_point_intensity = 0.92F;
};

struct SceneConfig
{
    std::string asset_root = "assets";
    int camera_width = 640;
    int camera_height = 360;
    float belt_length_m = 6.0F;
    float belt_width_m = 0.82F;
    float nominal_velocity_mps = 0.62F;
    float tunnel_start_m = 2.4F;
    float tunnel_end_m = 3.6F;
    float tunnel_width_m = 1.08F;
    float tunnel_height_m = 1.15F;
    SceneLighting lighting;
    TextureImage belt_texture;
    std::vector<SceneObjectAppearance> objects;
};

SceneConfig load_scene_config();

const SceneObjectAppearance* find_appearance(const SceneConfig& scene,
                                             std::string_view label);
const SceneObjectAppearance* find_appearance(const SceneConfig& scene,
                                             std::uint64_t track_seed);

RgbColor scaled(RgbColor color, float amount);

}  // namespace visual_relay
