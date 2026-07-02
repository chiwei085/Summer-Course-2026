#pragma once

#include <cstdint>
#include <vector>

#include "week3/local_geometry/gradient.hpp"
#include "week3/local_geometry/image.hpp"

namespace week3::local_geometry
{

// A binary edge map: one byte per pixel, 0 (not an edge) or 255 (edge),
// row-major. Kept as its own type (rather than reusing `GrayImage`) so
// "this is a mask" is visible at every call site and in every signature.
struct EdgeMap
{
    ImageSize size{};
    std::vector<std::uint8_t> pixels;

    [[nodiscard]] std::uint8_t at(int x, int y) const {
        return pixels[static_cast<std::size_t>(y) * size.width + x];
    }
    [[nodiscard]] bool is_edge(int x, int y) const { return at(x, y) != 0; }
};

// Thins the gradient magnitude down to single-pixel-wide ridges by keeping
// only local maxima along the gradient direction (the direction gradient
// magnitude changes fastest, i.e. perpendicular to the edge itself).
[[nodiscard]] GrayImage non_max_suppression(const Gradients& gradients);

struct CannyParams
{
    double low_threshold{30.0};
    double high_threshold{90.0};
};

// Canny edge detector: Sobel gradients -> non-max suppression along the
// gradient direction -> double threshold -> hysteresis (a weak edge survives
// only if it is 8-connected to a strong edge).
[[nodiscard]] EdgeMap canny(const GrayImage& gray, CannyParams params);

[[nodiscard]] Image edge_map_to_image(const EdgeMap& edges);

}  // namespace week3::local_geometry
