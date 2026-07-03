#pragma once

#include <cstdint>
#include <vector>

#include "week3/snake/image.hpp"

namespace week3::snake
{

// A single-channel floating-point image: the shared representation for
// grayscale intensity, blurred intensity, and gradients. Kept distinct from
// `Image` (always 8-bit RGB) because gradients are signed and blurred
// intensity is a `double` average, not a rounded byte.
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

// ITU-R BT.601 luma.
[[nodiscard]] GrayImage to_grayscale(const Image& image);

// Renders a `GrayImage` back to a displayable 8-bit RGB image. Values are
// linearly rescaled from [min, max] over the image so gradients and other
// signed/unbounded fields render sensibly.
[[nodiscard]] Image visualize_gray(const GrayImage& gray);

// Separable Gaussian blur (1D horizontal pass, then 1D vertical pass) with a
// kernel built from the continuous Gaussian and truncated at
// `radius = ceil(3 * sigma)`, clamp-to-edge borders. `sigma <= 0` returns a
// copy of `gray` unchanged.
[[nodiscard]] GrayImage gaussian_blur(const GrayImage& gray, double sigma);

// Sobel 3x3 kernels, applied with clamp-to-edge borders so the output has
// the same size as the input.
struct Gradients
{
    GrayImage gx;
    GrayImage gy;
    GrayImage magnitude;  // sqrt(gx^2 + gy^2)
};

[[nodiscard]] Gradients sobel_gradients(const GrayImage& gray);

// Canny edge detector: Sobel gradients -> non-maximum suppression along the
// gradient direction (so edges come out as thin, single-pixel lines instead
// of a blob of every pixel above a magnitude cutoff) -> double-threshold
// hysteresis linking. This is the difference from thresholding raw gradient
// magnitude directly: a stretch of diffuse, low-but-nonzero gradient from
// background texture (wood grain, cloth weave) rarely survives NMS or
// clears the low threshold on its own, whereas a true object edge -- a
// narrow ridge of high magnitude -- does, and hysteresis lets it recruit
// only the weak edge pixels actually connected to it. `high_threshold` is
// chosen by Otsu's method on the (NMS'd) gradient-magnitude histogram, same
// as the plain-threshold approach, so there's still no manual per-image
// cutoff; `low_ratio` sets the hysteresis low threshold as a fraction of
// that.
[[nodiscard]] std::vector<std::uint8_t> canny_edges(const GrayImage& gray,
                                                     double low_ratio = 0.4);

}  // namespace week3::snake
