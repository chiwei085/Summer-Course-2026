#include "week3/local_geometry/edges.hpp"

#include <algorithm>
#include <cmath>
#include <deque>
#include <numbers>

namespace week3::local_geometry
{
namespace
{

constexpr std::uint8_t kEdge = 255;
constexpr std::uint8_t kNoEdge = 0;

// Quantizes a gradient direction (radians) onto one of the four principal
// compass directions a 3x3 neighborhood can express: 0 deg (east/west),
// 45 deg, 90 deg (north/south), 135 deg. Non-max suppression then only has
// to compare a pixel against the two neighbors that direction picks out.
int quantize_direction(double theta_rad) {
    double deg = theta_rad * 180.0 / std::numbers::pi;
    if (deg < 0.0) deg += 180.0;  // gradient direction is symmetric mod 180
    if (deg >= 157.5 || deg < 22.5) return 0;  // east-west
    if (deg < 67.5) return 1;                  // northeast-southwest
    if (deg < 112.5) return 2;                 // north-south
    return 3;                                  // northwest-southeast
}

}  // namespace

GrayImage non_max_suppression(const Gradients& gradients) {
    const ImageSize size = gradients.magnitude.size;
    GrayImage out = make_gray_image(size);

    static constexpr int kOffsets[4][2][2] = {
        {{-1, 0}, {1, 0}},   // 0 deg: compare east/west
        {{-1, -1}, {1, 1}},  // 45 deg: compare NE/SW diagonal
        {{0, -1}, {0, 1}},   // 90 deg: compare north/south
        {{1, -1}, {-1, 1}},  // 135 deg: compare NW/SE diagonal
    };

    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const double mag = gradients.magnitude.at(x, y);
            const int dir = quantize_direction(gradients.orientation.at(x, y));

            // Clamp-to-edge, matching the border handling `sobel_gradients`
            // already uses: a border pixel compares against the nearest
            // in-bounds neighbor rather than a phantom magnitude-0 pixel,
            // so it isn't trivially kept just because one side is missing.
            const int ax = std::clamp(x + kOffsets[dir][0][0], 0, size.width - 1);
            const int ay = std::clamp(y + kOffsets[dir][0][1], 0, size.height - 1);
            const int bx = std::clamp(x + kOffsets[dir][1][0], 0, size.width - 1);
            const int by = std::clamp(y + kOffsets[dir][1][1], 0, size.height - 1);
            const double neighbor_a = gradients.magnitude.at(ax, ay);
            const double neighbor_b = gradients.magnitude.at(bx, by);

            out.at(x, y) = (mag >= neighbor_a && mag >= neighbor_b) ? mag : 0.0;
        }
    }
    return out;
}

EdgeMap canny(const GrayImage& gray, CannyParams params) {
    const Gradients gradients = sobel_gradients(gray);
    const GrayImage suppressed = non_max_suppression(gradients);
    const ImageSize size = gray.size;

    // Double threshold: classify every surviving ridge pixel as strong,
    // weak, or discarded.
    enum class Strength : std::uint8_t
    {
        None,
        Weak,
        Strong
    };
    std::vector<Strength> classification(size.pixel_count(), Strength::None);
    for (std::size_t i = 0; i < suppressed.pixels.size(); ++i) {
        const double v = suppressed.pixels[i];
        if (v >= params.high_threshold) {
            classification[i] = Strength::Strong;
        }
        else if (v >= params.low_threshold) {
            classification[i] = Strength::Weak;
        }
    }

    // Hysteresis: a weak pixel survives only if it is 8-connected (directly
    // or transitively through other weak pixels) to a strong pixel. Flood
    // fill outward from every strong pixel.
    EdgeMap edges{.size = size,
                  .pixels = std::vector<std::uint8_t>(size.pixel_count(), 0)};
    std::deque<std::pair<int, int>> queue;
    auto index_of = [&](int x, int y) {
        return static_cast<std::size_t>(y) * size.width + x;
    };
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            if (classification[index_of(x, y)] == Strength::Strong) {
                edges.pixels[index_of(x, y)] = kEdge;
                queue.emplace_back(x, y);
            }
        }
    }
    while (!queue.empty()) {
        const auto [cx, cy] = queue.front();
        queue.pop_front();
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                if (dx == 0 && dy == 0) continue;
                const int nx = cx + dx;
                const int ny = cy + dy;
                if (nx < 0 || nx >= size.width || ny < 0 || ny >= size.height)
                    continue;
                const std::size_t ni = index_of(nx, ny);
                if (classification[ni] == Strength::Weak &&
                    edges.pixels[ni] == kNoEdge) {
                    edges.pixels[ni] = kEdge;
                    queue.emplace_back(nx, ny);
                }
            }
        }
    }
    return edges;
}

Image edge_map_to_image(const EdgeMap& edges) {
    std::vector<Rgb8> pixels(edges.pixels.size());
    std::ranges::transform(edges.pixels, pixels.begin(), [](std::uint8_t v) {
        return Rgb8{.r = v, .g = v, .b = v};
    });
    return Image{edges.size, std::move(pixels)};
}

}  // namespace week3::local_geometry
