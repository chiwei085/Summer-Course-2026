#include "week3/local_geometry/gradient.hpp"

#include <algorithm>
#include <cmath>

namespace week3::local_geometry
{
namespace
{

int clamp_coord(int v, int lo, int hi) {
    return std::clamp(v, lo, hi);
}

// Applies a 3x3 kernel at (x, y) with clamp-to-edge borders.
double apply_kernel_3x3(const GrayImage& gray, int x, int y,
                        const double (&kernel)[3][3]) {
    double sum = 0.0;
    for (int ky = -1; ky <= 1; ++ky) {
        const int sy = clamp_coord(y + ky, 0, gray.size.height - 1);
        for (int kx = -1; kx <= 1; ++kx) {
            const int sx = clamp_coord(x + kx, 0, gray.size.width - 1);
            sum += kernel[ky + 1][kx + 1] * gray.at(sx, sy);
        }
    }
    return sum;
}

}  // namespace

GrayImage make_gray_image(ImageSize size, double fill) {
    GrayImage gray;
    gray.size = size;
    gray.pixels.assign(size.pixel_count(), fill);
    return gray;
}

GrayImage to_grayscale(const Image& image) {
    GrayImage gray = make_gray_image(image.size());
    const ImageSize size = image.size();
    for (int y = 0; y < size.height; ++y) {
        for (int x = 0; x < size.width; ++x) {
            const Rgb8 p = image.at(x, y);
            gray.at(x, y) =
                0.299 * p.r + 0.587 * p.g + 0.114 * p.b;  // BT.601 luma
        }
    }
    return gray;
}

Image visualize_gray(const GrayImage& gray) {
    double min_v = gray.pixels.empty() ? 0.0 : gray.pixels.front();
    double max_v = min_v;
    for (const double v : gray.pixels) {
        min_v = std::min(min_v, v);
        max_v = std::max(max_v, v);
    }
    const double range = max_v - min_v;

    std::vector<Rgb8> pixels(gray.pixels.size());
    for (std::size_t i = 0; i < pixels.size(); ++i) {
        const double normalized =
            range > 1e-9 ? (gray.pixels[i] - min_v) / range : 0.0;
        const auto byte =
            static_cast<std::uint8_t>(std::lround(normalized * 255.0));
        pixels[i] = Rgb8{.r = byte, .g = byte, .b = byte};
    }
    return Image{gray.size, std::move(pixels)};
}

Gradients sobel_gradients(const GrayImage& gray) {
    static constexpr double kSobelX[3][3] = {
        {-1.0, 0.0, 1.0}, {-2.0, 0.0, 2.0}, {-1.0, 0.0, 1.0}};
    static constexpr double kSobelY[3][3] = {
        {-1.0, -2.0, -1.0}, {0.0, 0.0, 0.0}, {1.0, 2.0, 1.0}};

    Gradients out{
        .gx = make_gray_image(gray.size),
        .gy = make_gray_image(gray.size),
        .magnitude = make_gray_image(gray.size),
        .orientation = make_gray_image(gray.size),
    };

    for (int y = 0; y < gray.size.height; ++y) {
        for (int x = 0; x < gray.size.width; ++x) {
            const double gx = apply_kernel_3x3(gray, x, y, kSobelX);
            const double gy = apply_kernel_3x3(gray, x, y, kSobelY);
            out.gx.at(x, y) = gx;
            out.gy.at(x, y) = gy;
            out.magnitude.at(x, y) = std::hypot(gx, gy);
            out.orientation.at(x, y) = std::atan2(gy, gx);
        }
    }
    return out;
}

}  // namespace week3::local_geometry
