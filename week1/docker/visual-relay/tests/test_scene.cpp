#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "visual_relay/gui.hpp"
#include "visual_relay/scene.hpp"

using namespace visual_relay;

namespace
{

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        std::exit(1);
    }
}

std::vector<std::uint8_t> make_chunk(std::uint64_t sequence, int width,
                                     int height, int row, std::string metadata,
                                     std::uint8_t value) {
    std::string header = "VRRGBC\n" + std::to_string(sequence) + "\n" +
                         std::to_string(width) + "\n" + std::to_string(height) +
                         "\n" + std::to_string(row) + "\n1\n" +
                         std::to_string(metadata.size()) + "\n";
    std::vector<std::uint8_t> packet(header.begin(), header.end());
    packet.insert(packet.end(), metadata.begin(), metadata.end());
    packet.insert(packet.end(), static_cast<std::size_t>(width) * 3U, value);
    return packet;
}

}  // namespace

int main() {
    const auto scene = load_scene_config();
    expect(scene.camera_width == 640, "scene camera width");
    expect(scene.camera_height == 360, "scene camera height");
    const auto* red = find_appearance(scene, "red-crate");
    expect(red != nullptr, "red crate appearance loaded");
    expect(red->primary.r == 0xdc && red->secondary.g == 0xbf,
           "scene colors parsed");
    expect(!scene.belt_texture.empty(), "belt texture loaded");
    expect(red->texture.empty() || red->texture.width > 0,
           "optional red texture is well-formed");

    CameraFrame initial;
    initial.view = StationView::scout;
    CameraChunkReceiver receiver(initial);
    const std::string metadata =
        "VRFRAME|view=scout|frame=2|objects=7001,red-crate,painted,1,0,0,0.9,0."
        "8,1|"
        "projections=7001,2,1,2,2,0.5,0.9,1,1";
    const auto newest = make_chunk(2, 4, 2, 0, metadata, 42);
    expect(receiver.apply(newest), "new frame chunk accepted");
    expect(receiver.frame().sequence == 2, "new frame sequence stored");
    expect(receiver.frame().projections.size() == 1, "projection parsed");

    const auto stale = make_chunk(1, 4, 2, 1, {}, 99);
    expect(!receiver.apply(stale), "stale chunk rejected");
    expect(receiver.frame().rgb_pixels[0] == 42, "new pixel retained");

    const auto second_row = make_chunk(2, 4, 2, 1, {}, 43);
    expect(receiver.apply(second_row), "same-frame row accepted");
    expect(receiver.frame_complete(), "row coverage complete");

    std::cout << "scene tests passed\n";
    return 0;
}
