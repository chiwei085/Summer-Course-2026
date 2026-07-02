#pragma once

#include <cstdint>
#include <vector>

#include "week3/local_geometry/image.hpp"

namespace week3::local_geometry
{

// A single-channel floating-point image: the shared representation for
// grayscale intensity, gradients, and every derived buffer (Harris
// response, non-max-suppressed edge strength, ...) downstream of it. Kept
// distinct from `Image` (which is always 8-bit RGB) because gradients are
// signed and Harris responses can be far outside [0, 255].
struct GrayImage
{
    ImageSize size{};
    std::vector<double> pixels;  // row-major, size.pixel_count() entries

    [[nodiscard]] double at(int x, int y) const {
        return pixels[static_cast<std::size_t>(y) * size.width + x];
    }
    [[nodiscard]] double& at(int x, int y) {
        return pixels[static_cast<std::size_t>(y) * size.width + x];
    }
};

[[nodiscard]] GrayImage make_gray_image(ImageSize size, double fill = 0.0);

// ITU-R BT.601 luma, matching week3::color's `IntensityMethod::Luminosity`.
[[nodiscard]] GrayImage to_grayscale(const Image& image);

// Renders a `GrayImage` back to a displayable 8-bit RGB image. Values are
// linearly rescaled from [min, max] over the image (not assumed to already
// be in [0, 255]) so gradients, magnitudes, and Harris responses all render
// sensibly without every call site repeating the same normalization.
[[nodiscard]] Image visualize_gray(const GrayImage& gray);

// Sobel 3x3 kernels, applied with replicated (clamp-to-edge) borders so the
// output has the same size as the input.
struct Gradients
{
    GrayImage gx;
    GrayImage gy;
    GrayImage magnitude;    // sqrt(gx^2 + gy^2)
    GrayImage orientation;  // atan2(gy, gx), radians in (-pi, pi]
};

[[nodiscard]] Gradients sobel_gradients(const GrayImage& gray);

}  // namespace week3::local_geometry
