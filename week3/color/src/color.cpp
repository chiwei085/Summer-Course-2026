#include "week3/color/color.hpp"

#include <algorithm>
#include <cmath>

namespace week3::color
{
namespace
{

double clamp01(double v) {
    return std::clamp(v, 0.0, 1.0);
}

std::uint8_t to_u8(double normalized) {
    return static_cast<std::uint8_t>(std::lround(clamp01(normalized) * 255.0));
}

}  // namespace

std::uint8_t rgb_to_intensity(Rgb8 pixel, IntensityMethod method) {
    const double r = pixel.r;
    const double g = pixel.g;
    const double b = pixel.b;
    switch (method) {
        case IntensityMethod::Average:
            return static_cast<std::uint8_t>(std::lround((r + g + b) / 3.0));
        case IntensityMethod::Lightness:
            return static_cast<std::uint8_t>(
                std::lround((std::max({r, g, b}) + std::min({r, g, b})) / 2.0));
        case IntensityMethod::Luminosity:
            // ITU-R BT.601 luma weights.
            return static_cast<std::uint8_t>(
                std::lround(0.299 * r + 0.587 * g + 0.114 * b));
    }
    return 0;
}

Image rgb_to_intensity_image(const Image& image, IntensityMethod method) {
    std::vector<Rgb8> out(image.pixels().size());
    std::ranges::transform(image.pixels(), out.begin(), [method](Rgb8 p) {
        const std::uint8_t i = rgb_to_intensity(p, method);
        return Rgb8{.r = i, .g = i, .b = i};
    });
    return Image{image.size(), std::move(out)};
}

double normalize_hue(double h) {
    double wrapped = std::fmod(h, 360.0);
    if (wrapped < 0.0) wrapped += 360.0;
    return wrapped;
}

double hue_delta(double from, double to) {
    const double raw = normalize_hue(to) - normalize_hue(from);
    if (raw > 180.0) return raw - 360.0;
    if (raw < -180.0) return raw + 360.0;
    return raw;
}

Hsv rgb_to_hsv(Rgb8 pixel) {
    const double r = pixel.r / 255.0;
    const double g = pixel.g / 255.0;
    const double b = pixel.b / 255.0;

    const double max_c = std::max({r, g, b});
    const double min_c = std::min({r, g, b});
    const double delta = max_c - min_c;

    double hue = 0.0;
    if (delta > 1e-9) {
        if (max_c == r) {
            // (g - b) / delta can land outside [-6, 6] to [0, 6) once we
            // add 6 below; fmod folds every branch back onto the same
            // 0-360 wheel so red at hue 0 and hue 360 are the same point.
            hue = std::fmod(((g - b) / delta), 6.0);
        }
        else if (max_c == g) {
            hue = ((b - r) / delta) + 2.0;
        }
        else {
            hue = ((r - g) / delta) + 4.0;
        }
        hue = normalize_hue(hue * 60.0);
    }

    const double value = max_c;
    const double saturation = value <= 1e-9 ? 0.0 : delta / value;

    return Hsv{.h = hue, .s = clamp01(saturation), .v = clamp01(value)};
}

Rgb8 hsv_to_rgb(Hsv hsv) {
    const double h = normalize_hue(hsv.h);
    const double s = clamp01(hsv.s);
    const double v = clamp01(hsv.v);

    const double c = v * s;
    const double h_prime = h / 60.0;
    const double x = c * (1.0 - std::fabs(std::fmod(h_prime, 2.0) - 1.0));
    const double m = v - c;

    double r1 = 0.0, g1 = 0.0, b1 = 0.0;
    if (h_prime < 1.0) {
        r1 = c;
        g1 = x;
        b1 = 0.0;
    }
    else if (h_prime < 2.0) {
        r1 = x;
        g1 = c;
        b1 = 0.0;
    }
    else if (h_prime < 3.0) {
        r1 = 0.0;
        g1 = c;
        b1 = x;
    }
    else if (h_prime < 4.0) {
        r1 = 0.0;
        g1 = x;
        b1 = c;
    }
    else if (h_prime < 5.0) {
        r1 = x;
        g1 = 0.0;
        b1 = c;
    }
    else {
        r1 = c;
        g1 = 0.0;
        b1 = x;
    }

    return Rgb8{.r = to_u8(r1 + m), .g = to_u8(g1 + m), .b = to_u8(b1 + m)};
}

}  // namespace week3::color
