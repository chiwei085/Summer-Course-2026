#pragma once

#include <cstdint>

#include "week3/color/image.hpp"

namespace week3::color
{

// The three classic ways to collapse RGB into a single intensity channel.
// `Luminosity` (ITU-R BT.601 luma) is what the eye perceives as brightness;
// `Average` and `Lightness` are the naive alternatives usually taught
// alongside it so the difference is visible.
enum class IntensityMethod
{
    Average,
    Lightness,
    Luminosity,
};

[[nodiscard]] std::uint8_t rgb_to_intensity(Rgb8 pixel, IntensityMethod method);

[[nodiscard]] Image rgb_to_intensity_image(const Image& image,
                                           IntensityMethod method);

// HSV with H in [0, 360), S and V in [0, 1]. Kept as floats rather than the
// source RGB's 8-bit ints so the cube/cone visualizers can round-trip
// without banding.
struct Hsv
{
    double h{0.0};
    double s{0.0};
    double v{0.0};
};

[[nodiscard]] Hsv rgb_to_hsv(Rgb8 pixel);
[[nodiscard]] Rgb8 hsv_to_rgb(Hsv hsv);

// Shortest signed distance from `from` to `to` around the 360-degree hue
// wheel, e.g. hue_delta(350, 10) == 20, not -340. Exists because red sits
// at the 0/360 seam and naive subtraction breaks exactly there.
[[nodiscard]] double hue_delta(double from, double to);

// Wraps an arbitrary hue value into [0, 360).
[[nodiscard]] double normalize_hue(double h);

}  // namespace week3::color
