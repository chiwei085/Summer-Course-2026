#include "visual_relay/scene.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <charconv>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>

namespace visual_relay
{
namespace
{

namespace fs = std::filesystem;
using json = nlohmann::json;

std::string asset_root() {
    if (const char* env = std::getenv("VISUAL_RELAY_ASSET_DIR");
        env != nullptr && env[0] != '\0') {
        return env;
    }
    if (fs::exists("assets/scene/scene.json")) {
        return "assets";
    }
    return "/opt/visual-relay/share/visual-relay/assets";
}

RgbColor parse_hex_color(const std::string& text, RgbColor fallback) {
    if (text.size() != 7 || text[0] != '#') {
        return fallback;
    }
    auto read = [&](std::size_t offset) -> std::uint8_t {
        unsigned value = 0;
        const auto* begin = text.data() + static_cast<std::ptrdiff_t>(offset);
        const auto* end = begin + 2;
        const auto result = std::from_chars(begin, end, value, 16);
        if (result.ec != std::errc{}) {
            return 0;
        }
        return static_cast<std::uint8_t>(value);
    };
    return {read(1), read(3), read(5)};
}

TextureImage load_ppm(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return {};
    }

    auto next_token = [&]() -> std::string {
        std::string token;
        while (input >> token) {
            if (!token.empty() && token[0] == '#') {
                std::string ignored;
                std::getline(input, ignored);
                continue;
            }
            return token;
        }
        return {};
    };

    const std::string magic = next_token();
    int width = 0;
    int height = 0;
    int max_value = 0;
    width = std::atoi(next_token().c_str());
    height = std::atoi(next_token().c_str());
    max_value = std::atoi(next_token().c_str());
    if ((magic != "P6" && magic != "P3") || width <= 0 || height <= 0 ||
        max_value != 255) {
        return {};
    }

    TextureImage image;
    image.width = width;
    image.height = height;
    image.rgb_pixels.resize(static_cast<std::size_t>(width) *
                            static_cast<std::size_t>(height) * 3U);
    if (magic == "P6") {
        input.get();
        input.read(reinterpret_cast<char*>(image.rgb_pixels.data()),
                   static_cast<std::streamsize>(image.rgb_pixels.size()));
        if (input.gcount() !=
            static_cast<std::streamsize>(image.rgb_pixels.size())) {
            return {};
        }
    }
    else {
        for (auto& byte : image.rgb_pixels) {
            byte = static_cast<std::uint8_t>(
                std::clamp(std::atoi(next_token().c_str()), 0, 255));
        }
    }
    return image;
}

template <typename T>
T json_value(const json& object, std::string_view key, T fallback) {
    const auto it = object.find(std::string(key));
    return it == object.end() ? fallback : it->get<T>();
}

}  // namespace

SceneConfig load_scene_config() {
    SceneConfig scene;
    scene.asset_root = asset_root();
    const fs::path root(scene.asset_root);
    std::ifstream input(root / "scene" / "scene.json");
    if (!input) {
        return scene;
    }

    const auto data = json::parse(input, nullptr, false);
    if (data.is_discarded()) {
        return scene;
    }

    if (const auto it = data.find("camera_resolution");
        it != data.end() && it->is_array() && it->size() >= 2) {
        scene.camera_width = std::max(1, (*it)[0].get<int>());
        scene.camera_height = std::max(1, (*it)[1].get<int>());
    }

    if (const auto it = data.find("belt"); it != data.end()) {
        scene.belt_length_m = json_value(*it, "length_m", scene.belt_length_m);
        scene.belt_width_m = json_value(*it, "width_m", scene.belt_width_m);
        scene.nominal_velocity_mps =
            json_value(*it, "nominal_velocity_mps", scene.nominal_velocity_mps);
        const auto texture_path = json_value(*it, "texture", std::string{});
        if (!texture_path.empty()) {
            scene.belt_texture = load_ppm(root / texture_path);
        }
    }

    if (const auto it = data.find("tunnel"); it != data.end()) {
        scene.tunnel_start_m = json_value(*it, "start_m", scene.tunnel_start_m);
        scene.tunnel_end_m = json_value(*it, "end_m", scene.tunnel_end_m);
        scene.tunnel_width_m = json_value(*it, "width_m", scene.tunnel_width_m);
        scene.tunnel_height_m =
            json_value(*it, "height_m", scene.tunnel_height_m);
    }

    if (const auto it = data.find("lighting"); it != data.end()) {
        if (const auto directional = it->find("directional");
            directional != it->end()) {
            scene.lighting.directional_intensity =
                json_value(*directional, "intensity",
                           scene.lighting.directional_intensity);
        }
        if (const auto scout = it->find("scout_point"); scout != it->end()) {
            scene.lighting.scout_point_intensity = json_value(
                *scout, "intensity", scene.lighting.scout_point_intensity);
        }
        if (const auto catcher = it->find("catcher_point");
            catcher != it->end()) {
            scene.lighting.catcher_point_intensity = json_value(
                *catcher, "intensity", scene.lighting.catcher_point_intensity);
        }
    }

    if (const auto it = data.find("objects");
        it != data.end() && it->is_array()) {
        scene.objects.clear();
        for (const auto& item : *it) {
            SceneObjectAppearance appearance;
            appearance.track_seed = json_value(item, "track_seed", 0ULL);
            appearance.name = json_value(item, "name", std::string{"unknown"});
            appearance.material =
                json_value(item, "material", std::string{"matte"});
            appearance.primary = parse_hex_color(
                json_value(item, "primary_color", std::string{}),
                appearance.primary);
            appearance.secondary = parse_hex_color(
                json_value(item, "secondary_color", std::string{}),
                appearance.secondary);
            appearance.texture_path =
                json_value(item, "texture", std::string{});
            if (!appearance.texture_path.empty()) {
                appearance.texture = load_ppm(root / appearance.texture_path);
            }
            if (const auto features = item.find("features");
                features != item.end() && features->is_array()) {
                for (const auto& feature : *features) {
                    appearance.features.push_back(feature.get<std::string>());
                }
            }
            scene.objects.push_back(std::move(appearance));
        }
    }

    return scene;
}

const SceneObjectAppearance* find_appearance(const SceneConfig& scene,
                                             std::string_view label) {
    const auto found =
        std::find_if(scene.objects.begin(), scene.objects.end(),
                     [&](const auto& object) { return object.name == label; });
    return found == scene.objects.end() ? nullptr : &*found;
}

const SceneObjectAppearance* find_appearance(const SceneConfig& scene,
                                             std::uint64_t track_seed) {
    const auto found = std::find_if(
        scene.objects.begin(), scene.objects.end(),
        [&](const auto& object) { return object.track_seed == track_seed; });
    return found == scene.objects.end() ? nullptr : &*found;
}

RgbColor scaled(RgbColor color, float amount) {
    auto scale = [amount](std::uint8_t value) {
        return static_cast<std::uint8_t>(std::clamp(
            static_cast<int>(static_cast<float>(value) * amount), 0, 255));
    };
    return {scale(color.r), scale(color.g), scale(color.b)};
}

}  // namespace visual_relay
